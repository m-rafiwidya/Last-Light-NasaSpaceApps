"""Shared helpers for the astronaut generator (tools/blender/ASTRONAUT_KIT.md): materials, the
skeleton table and a mesh builder that tags every vertex with its bone weights and every face
with its region.

Character space (ASTRONAUT_KIT.md 3.1): metres, origin on the ground between the feet, the
character faces -Y, its left is +X. The workshop's numbers (seat, stand, console) come from
workshop_kit_common.py, never from here.
"""

import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.append(os.path.join(os.path.dirname(__file__), ".."))
sys.path.append(os.path.join(os.path.dirname(__file__), "..", "workshop"))
import rover_kit_common as rk  # noqa: E402
import workshop_kit_common as ws  # noqa: E402

REPO_ROOT = rk.REPO_ROOT
PARTS_DIR = os.path.join(REPO_ROOT, "tools", "blender", "parts", "astronaut")
EXPORT_DIR = os.path.join(REPO_ROOT, "game", "res", "models", "astronaut_kit")
PREVIEWS_DIR = os.path.join(REPO_ROOT, "tools", "blender", "previews", "astronaut")

# --- Materials (ASTRONAUT_KIT.md 5.1), in material-index order ------------------------------
MATERIALS = ["suit_shell", "suit_fabric", "suit_metal", "suit_dark", "suit_visor", "suit_accent", "suit_lamp"]
SHELL, FABRIC, METAL, DARK, VISOR, ACCENT, LAMP = range(len(MATERIALS))
PALETTE = {
    "suit_shell": "F1EFE9",
    "suit_fabric": "E6E2D8",
    "suit_metal": "4A4D52",
    "suit_dark": "1C1D20",
    "suit_visor": "0B0E10",
    "suit_accent": "E0A030",
    "suit_lamp": "FFB347",
}
# (metallic, roughness)
MATERIAL_SETTINGS = {
    "suit_shell": (0.0, 0.45), "suit_fabric": (0.0, 0.85), "suit_metal": (0.6, 0.45), "suit_dark": (0.0, 0.8),
    "suit_visor": (0.9, 0.12), "suit_accent": (0.0, 0.6), "suit_lamp": (0.0, 0.5),
}
EMISSIVE = {"suit_lamp": 1.5}
# Lighter stand-ins for the Workbench previews, so dark parts show their shape
PREVIEW_COLORS = {"suit_metal": "8A9099", "suit_dark": "5A5D63", "suit_visor": "2E3A46", "suit_fabric": "D8D3C7"}


def get_material(name: str) -> bpy.types.Material:
    if name not in PALETTE:
        raise ValueError("Not an astronaut kit material: " + name)
    material = bpy.data.materials.get(name)
    if material:
        return material
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    color = rk.srgb_to_linear(PALETTE[name])
    metallic, roughness = MATERIAL_SETTINGS[name]
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if name in EMISSIVE:
        bsdf.inputs["Emission Color"].default_value = color
        bsdf.inputs["Emission Strength"].default_value = EMISSIVE[name]
    material.diffuse_color = color
    material.metallic = metallic
    material.roughness = roughness
    return material


def set_preview_colors(enabled: bool) -> None:
    for name, hex_color in PALETTE.items():
        material = bpy.data.materials.get(name)
        if material:
            material.diffuse_color = rk.srgb_to_linear(PREVIEW_COLORS.get(name, hex_color) if enabled else hex_color)


# --- Skeleton (ASTRONAUT_KIT.md 6.1): Godot SkeletonProfileHumanoid names ---------------------
# name: (parent, head, tail) in the T-pose. Left = +X; the right side mirrors x.
HIP = Vector((0.115, 0.0, 0.90))
KNEE = Vector((0.115, 0.0, 0.52))
ANKLE = Vector((0.125, 0.0, 0.11))
SHOULDER = Vector((0.225, 0.0, 1.415))
ELBOW = Vector((0.50, 0.0, 1.415))
WRIST = Vector((0.765, 0.0, 1.415))
KNUCKLE_X = 0.88
FINGER_JOINT_X = 0.916
FINGERTIP_X = 0.95
FINGER_Y = {"Index": -0.0435, "Middle": -0.0145, "Ring": 0.0145, "Little": 0.0435}
THUMB_ROOT = Vector((0.785, -0.03, 1.412))
THUMB_BASE = Vector((0.812, -0.058, 1.406))
THUMB_DIR = Vector((0.55, -0.82, -0.12)).normalized()
THUMB_LENGTHS = (0.036, 0.030)


def _side_bones(side: str, s: float) -> dict:
    def m(v):
        return Vector((s * v.x, v.y, v.z))
    b = {}
    b[side + "Shoulder"] = ("UpperChest", m(Vector((0.04, 0.0, 1.405))), m(SHOULDER))
    b[side + "UpperArm"] = (side + "Shoulder", m(SHOULDER), m(ELBOW))
    b[side + "LowerArm"] = (side + "UpperArm", m(ELBOW), m(WRIST))
    b[side + "Hand"] = (side + "LowerArm", m(WRIST), m(Vector((KNUCKLE_X, 0.0, WRIST.z))))
    p1 = THUMB_BASE + THUMB_DIR * THUMB_LENGTHS[0]
    p2 = p1 + THUMB_DIR * THUMB_LENGTHS[1]
    b[side + "ThumbMetacarpal"] = (side + "Hand", m(THUMB_ROOT), m(THUMB_BASE))
    b[side + "ThumbProximal"] = (side + "ThumbMetacarpal", m(THUMB_BASE), m(p1))
    b[side + "ThumbDistal"] = (side + "ThumbProximal", m(p1), m(p2))
    for finger, y in FINGER_Y.items():
        b[side + finger + "Proximal"] = (side + "Hand", m(Vector((KNUCKLE_X, y, WRIST.z))),
                                         m(Vector((FINGER_JOINT_X, y, WRIST.z))))
        b[side + finger + "Intermediate"] = (side + finger + "Proximal", m(Vector((FINGER_JOINT_X, y, WRIST.z))),
                                             m(Vector((FINGERTIP_X, y, WRIST.z))))
    b[side + "UpperLeg"] = ("Hips", m(HIP), m(KNEE))
    b[side + "LowerLeg"] = (side + "UpperLeg", m(KNEE), m(ANKLE))
    b[side + "Foot"] = (side + "LowerLeg", m(ANKLE), m(Vector((ANKLE.x, -0.13, 0.035))))
    b[side + "Toes"] = (side + "Foot", m(Vector((ANKLE.x, -0.13, 0.035))), m(Vector((ANKLE.x, -0.22, 0.035))))
    return b


BONES = {
    "Root": (None, Vector((0.0, 0.0, 0.0)), Vector((0.0, 0.0, 0.10))),
    "Hips": ("Root", Vector((0.0, 0.0, 0.93)), Vector((0.0, 0.0, 1.04))),
    "Spine": ("Hips", Vector((0.0, 0.0, 1.04)), Vector((0.0, 0.0, 1.18))),
    "Chest": ("Spine", Vector((0.0, 0.0, 1.18)), Vector((0.0, 0.0, 1.32))),
    "UpperChest": ("Chest", Vector((0.0, 0.0, 1.32)), Vector((0.0, 0.0, 1.49))),
    "Neck": ("UpperChest", Vector((0.0, 0.0, 1.49)), Vector((0.0, 0.0, 1.56))),
    "Head": ("Neck", Vector((0.0, 0.0, 1.56)), Vector((0.0, 0.0, 1.72))),
}
BONES.update(_side_bones("Left", 1.0))
BONES.update(_side_bones("Right", -1.0))
BONE_NAMES = list(BONES)
BONE_INDEX = {n: i for i, n in enumerate(BONE_NAMES)}


def side_name(side: str, name: str) -> str:
    """'Left' + 'UpperArm' -> 'LeftUpperArm'; names without a side pass through."""
    return name if name in BONES else side + name


# --- Mesh builder ---------------------------------------------------------------------------

class Builder:
    """One bmesh for the whole suit. Every vertex carries its bone weights (a deform layer with
    the BONE_NAMES order); every face carries its region (a face int layer, REGIONS order) and a
    material index (MATERIALS order)."""

    def __init__(self, regions: list):
        self.bm = bmesh.new()
        self.deform = self.bm.verts.layers.deform.verify()
        self.region_layer = self.bm.faces.layers.int.new("region")
        self.part_layer = self.bm.faces.layers.int.new("part")
        self.regions = regions
        self.region = 0
        # Parts for the pose checks: (name, main bone); a rigid part's every vertex is on its bone
        self.parts = []
        self.mirror = 1.0          # -1 while building the right side (x mirrored)
        self.side = "Left"

    def set_region(self, name: str) -> None:
        self.region = self.regions.index(name)

    def begin(self, name: str, bone: str, sided: bool = True) -> None:
        """Starts a part (a piece the pose checks treat as one solid). A sided part's name gets
        the current side, e.g. "Left knee cap", and its bone the side prefix."""
        self.parts.append(("%s %s" % (self.side, name) if sided else name, side_name(self.side, bone)))

    def set_side(self, side: str) -> None:
        self.side = side
        self.mirror = 1.0 if side == "Left" else -1.0

    def weights(self, w) -> dict:
        """A bone name or {bone: weight}; side-less names get the current side."""
        if isinstance(w, str):
            w = {w: 1.0}
        return {side_name(self.side, k): v for k, v in w.items() if v > 0.0}

    def vert(self, co, w) -> bmesh.types.BMVert:
        v = self.bm.verts.new((co[0] * self.mirror, co[1], co[2]))
        for bone, weight in self.weights(w).items():
            v[self.deform][BONE_INDEX[bone]] = weight
        return v

    def face(self, verts: list, mat: int, outward=None) -> bmesh.types.BMFace:
        f = self.bm.faces.new(verts)
        f.material_index = mat
        f[self.region_layer] = self.region
        f[self.part_layer] = len(self.parts) - 1
        if outward is not None:
            f.normal_update()
            if f.normal.dot(outward) < 0.0:
                f.normal_flip()
        return f

    # --- Primitives (coordinates are left-side; the builder mirrors them on the right) -------

    def loft(self, sections: list, mats, caps=(True, True)) -> list:
        """Rings of the same point count joined by quads. Each section is (centre, u, v, points,
        weights): points are (pu, pv) offsets along the u and v vectors. `mats` is one material
        or a list with one per band. Normals point away from the loft's axis (caps along it)."""
        rings = []
        for c, u, v, pts, w in sections:
            c, u, v = Vector(c), Vector(u), Vector(v)
            rings.append([self.vert(c + u * pu + v * pv, w) for pu, pv in pts])
        centres = [self.m(Vector(s[0])) for s in sections]
        faces = []
        n = len(rings[0])
        for i in range(len(rings) - 1):
            mat = mats[i] if isinstance(mats, (list, tuple)) else mats
            axis = centres[i + 1] - centres[i]
            mid = (centres[i] + centres[i + 1]) / 2.0
            for k in range(n):
                q = (rings[i][k], rings[i][(k + 1) % n], rings[i + 1][(k + 1) % n], rings[i + 1][k])
                fc = sum((x.co for x in q), Vector()) / 4.0
                out = fc - mid
                if axis.length > 1e-9:
                    a = axis.normalized()
                    out = out - a * out.dot(a)
                faces.append(self.face(q, mat, out))
        cap_mats = (mats[0], mats[-1]) if isinstance(mats, (list, tuple)) else (mats, mats)
        if caps[0]:
            faces.append(self.face(rings[0][::-1], cap_mats[0], centres[0] - centres[1]))
        if caps[1]:
            faces.append(self.face(rings[-1], cap_mats[1], centres[-1] - centres[-2]))
        return faces

    def m(self, p: Vector) -> Vector:
        return Vector((p.x * self.mirror, p.y, p.z))

    def tube(self, points: list, radii: list, sides: int, mats, w, caps=(True, True), up=(0.0, 0.0, 1.0),
             aspect: float = 1.0, phase: float = 0.0) -> list:
        """A loft of circles (or ellipses, `aspect` = v / u) along a polyline. `w` is one weight
        spec for all sections or a list per section."""
        sections = []
        for i, (p, r) in enumerate(zip(points, radii)):
            p = Vector(p)
            if i == 0:
                d = Vector(points[1]) - p
            elif i == len(points) - 1:
                d = p - Vector(points[i - 1])
            else:
                d = Vector(points[i + 1]) - Vector(points[i - 1])
            u, v = frame(d, up)
            pts = [(r * math.cos(phase + 2 * math.pi * k / sides), aspect * r * math.sin(phase + 2 * math.pi * k / sides))
                   for k in range(sides)]
            sections.append((p, u, v, pts, w[i] if isinstance(w, list) else w))
        return self.loft(sections, mats, caps)

    def cbox(self, center, size, chamfer: float, mat, w, axis: str = "z") -> list:
        """Chamfered box: an octagon (a rectangle with cut corners) lofted along `axis`, its two
        ends inset by the chamfer. `mat` may be a function of the face normal."""
        a = "xyz".index(axis)
        iu, iv = [i for i in range(3) if i != a]
        c = Vector(center)
        half = [s / 2.0 for s in size]

        def octagon(hu, hv, ch):
            ch = min(ch, hu * 0.9, hv * 0.9)
            return [(hu, -hv + ch), (hu, hv - ch), (hu - ch, hv), (-hu + ch, hv), (-hu, hv - ch), (-hu, -hv + ch),
                    (-hu + ch, -hv), (hu - ch, -hv)]
        u = Vector((0.0, 0.0, 0.0))
        v = Vector((0.0, 0.0, 0.0))
        d = Vector((0.0, 0.0, 0.0))
        u[iu], v[iv], d[a] = 1.0, 1.0, 1.0
        full = octagon(half[iu], half[iv], chamfer)
        inset = octagon(half[iu] - chamfer, half[iv] - chamfer, chamfer * 0.5)
        sections = [(c - d * half[a], u, v, inset, w), (c - d * (half[a] - chamfer), u, v, full, w),
                    (c + d * (half[a] - chamfer), u, v, full, w), (c + d * half[a], u, v, inset, w)]
        faces = self.loft(sections, mat if not callable(mat) else 0)
        if callable(mat):
            self.bm.normal_update()
            for f in faces:
                f.material_index = mat(Vector((f.normal.x * self.mirror, f.normal.y, f.normal.z)))
        return faces

    def box(self, lo, hi, mat, w) -> list:
        """Axis-aligned box (left-side coordinates)."""
        lo, hi = Vector(lo), Vector(hi)
        c = (lo + hi) / 2.0
        h = (hi - lo) / 2.0
        pts = [(h.x, -h.y), (h.x, h.y), (-h.x, h.y), (-h.x, -h.y)]
        return self.loft([(c - Vector((0, 0, h.z)), (1, 0, 0), (0, 1, 0), pts, w),
                          (c + Vector((0, 0, h.z)), (1, 0, 0), (0, 1, 0), pts, w)], mat)

    def beam(self, a, b, width: float, height: float, mat, w, up=(0.0, 0.0, 1.0), mats=None) -> list:
        """A box of the given cross-section from a to b; `up` orients its height."""
        u, v = frame(Vector(b) - Vector(a), up)
        pts = [(width / 2, -height / 2), (width / 2, height / 2), (-width / 2, height / 2), (-width / 2, -height / 2)]
        return self.loft([(a, u, v, pts, w), (b, u, v, pts, w)], mats or mat)


def frame(direction, up=(0.0, 0.0, 1.0)) -> tuple:
    """(u, v) perpendicular to `direction`: v as close to `up` as possible, u = v x direction."""
    d = Vector(direction).normalized()
    up = Vector(up)
    if abs(d.dot(up.normalized())) > 0.99:
        up = Vector((0.0, -1.0, 0.0)) if abs(d.y) < 0.9 else Vector((1.0, 0.0, 0.0))
    v = (up - d * up.dot(d)).normalized()
    u = v.cross(d).normalized()
    return u, v


def superellipse(a: float, b: float, n: int, p: float = 2.0, phase: float = 0.0) -> list:
    pts = []
    for k in range(n):
        t = phase + 2.0 * math.pi * k / n
        c, s = math.cos(t), math.sin(t)
        pts.append((a * math.copysign(abs(c) ** (2.0 / p), c), b * math.copysign(abs(s) ** (2.0 / p), s)))
    return pts


def blend(a: str, b: str, t: float) -> dict:
    """Weights moving from bone a (t = 0) to bone b (t = 1)."""
    return {a: 1.0 - t, b: t} if 0.0 < t < 1.0 else ({a: 1.0} if t <= 0.0 else {b: 1.0})


# --- Objects, export, previews --------------------------------------------------------------

def mesh_from_builder(name: str, builder: Builder) -> bpy.types.Object:
    mesh = bpy.data.meshes.new(name)
    builder.bm.to_mesh(mesh)
    builder.bm.free()
    for polygon in mesh.polygons:
        polygon.use_smooth = False
    for material in MATERIALS:
        mesh.materials.append(get_material(material))
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    for bone in BONE_NAMES:
        obj.vertex_groups.new(name=bone)
    return obj


def export_glb(root: bpy.types.Object, path: str, skins: bool = False) -> None:
    """Exports `root` and its children (glTF binary, +Y up, ASTRONAUT_KIT.md 9). No Godot import
    script: the astronaut has no colliders."""
    for obj in [root] + list(root.children_recursive):
        rk.check_export_name(obj.name)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in [root] + list(root.children_recursive):
        obj.select_set(True)
    bpy.context.view_layer.objects.active = root
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=True,
        export_animations=False,
        export_skins=skins,
        export_materials="EXPORT",
    )


def preview_dir(name: str):
    args = rk.script_args()
    if "--no-previews" in args:
        return None
    path = args[args.index("--previews") + 1] if "--previews" in args else os.path.join(PREVIEWS_DIR, name)
    os.makedirs(path, exist_ok=True)
    return path


def render(target, path: str, direction: tuple, scale: float, perspective: bool = False, distance: float = 4.0,
           focus: tuple = (0.0, 0.0, 0.0), keep_visible: tuple = (), size: int = 800) -> None:
    rk.render_view(target, path, direction, scale, perspective, distance, focus, size, keep_visible)


def rotation_z(degrees: float) -> Matrix:
    return Matrix.Rotation(math.radians(degrees), 4, "Z")
