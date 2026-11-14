"""Shared helpers for the rover kit part generators (see tools/blender/ROVER_KIT.md).

Run part scripts headless from the repo root, e.g.:
    blender -b --factory-startup -P tools/blender/scripts/make_wheel.py
Previews go to tools/blender/previews/<part>/ unless `-- --previews <dir>` or `-- --no-previews`.
"""

import math
import os
import re
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
PARTS_DIR = os.path.join(REPO_ROOT, "tools", "blender", "parts")
EXPORT_DIR = os.path.join(REPO_ROOT, "game", "res", "models", "rover_kit")
# Preview renders, one folder per part (git-ignored)
PREVIEWS_DIR = os.path.join(REPO_ROOT, "tools", "blender", "previews")

# ROVER_KIT.md 6.3. The only four materials allowed in the kit.
PALETTE = {
    "rover_body": "E6E2D8",
    "rover_metal": "4A4D52",
    "rover_dark": "1C1D20",
    "rover_gold": "C9A227",
}
# Lighter stand-ins used only while rendering previews, so dark parts show their shape.
PREVIEW_COLORS = {
    "rover_body": "F2F0EA",
    "rover_metal": "9DA3AB",
    "rover_dark": "5A5D63",
    "rover_gold": "E0B83A",
}
MATERIAL_SETTINGS = {
    "rover_body": (0.0, 0.6),
    "rover_metal": (0.6, 0.45),
    "rover_dark": (0.0, 0.8),
    "rover_gold": (0.9, 0.35),
}


def script_args() -> list:
    """Arguments after `--` on the Blender command line."""
    return sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def preview_dir(part: str):
    """Preview folder from the command line: default tools/blender/previews/<part>/,
    `--previews DIR` to override, `--no-previews` to skip (returns None)."""
    args = script_args()
    if "--no-previews" in args:
        return None
    path = args[args.index("--previews") + 1] if "--previews" in args else os.path.join(PREVIEWS_DIR, part)
    os.makedirs(path, exist_ok=True)
    return path


def srgb_to_linear(hex_color: str) -> tuple:
    def channel(c: float) -> float:
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    rgb = [int(hex_color[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    return tuple(channel(c) for c in rgb) + (1.0,)


def reset_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.unit_settings.system = "METRIC"
    bpy.context.scene.unit_settings.scale_length = 1.0


def get_material(name: str) -> bpy.types.Material:
    """Creates (or returns) one of the four kit materials."""
    if name not in PALETTE:
        raise ValueError("Not a rover kit material: " + name)
    material = bpy.data.materials.get(name)
    if material:
        return material
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    color = srgb_to_linear(PALETTE[name])
    metallic, roughness = MATERIAL_SETTINGS[name]
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    material.diffuse_color = color  # viewport / workbench colour
    material.metallic = metallic
    material.roughness = roughness
    return material


def set_preview_colors(enabled: bool) -> None:
    source = PREVIEW_COLORS if enabled else PALETTE
    for name in PALETTE:
        material = bpy.data.materials.get(name)
        if material:
            material.diffuse_color = srgb_to_linear(source[name])


def mesh_object(name: str, bm: bmesh.types.BMesh, materials: list) -> bpy.types.Object:
    """Creates a flat-shaded mesh object from a bmesh (which is freed)."""
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    for polygon in mesh.polygons:
        polygon.use_smooth = False
    for material in materials:
        mesh.materials.append(material)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def triangle_count(obj: bpy.types.Object) -> int:
    mesh = obj.data
    mesh.calc_loop_triangles()
    return len(mesh.loop_triangles)


def mirror_bmesh_x(bm: bmesh.types.BMesh) -> None:
    """Mirrors geometry across the YZ plane in place (for _L from _R) and fixes the winding."""
    bmesh.ops.scale(bm, vec=(-1.0, 1.0, 1.0), verts=bm.verts)
    bmesh.ops.reverse_faces(bm, faces=bm.faces)


def make_collision_child(parent: bpy.types.Object, bm: bmesh.types.BMesh) -> bpy.types.Object:
    """Adds the `<part>-convcolonly` collision mesh (ROVER_KIT.md 7) as a child of the part root."""
    obj = mesh_object(parent.name + "-convcolonly", bm, [])
    obj.parent = parent
    obj.display_type = "WIRE"
    obj.hide_render = True
    return obj


# Godot turns nodes whose names end in these words (after "-", "_" or "$") into special
# nodes on import, e.g. "socket_wheel" becomes a VehicleWheel3D. Only the intended collision
# suffix "-convcolonly" may appear in the kit (ROVER_KIT.md 2.2).
GODOT_IMPORT_HINT = re.compile(
    r"[-_$](noimp|col|convcol|colonly|convcolonly|navmesh|occ|occonly|rigid|rigidonly|vehicle|wheel|loop|cycle)$",
    re.IGNORECASE,
)


def check_export_name(name: str) -> None:
    if name.endswith("-convcolonly"):
        return
    if GODOT_IMPORT_HINT.search(name):
        raise ValueError('"%s" ends in a Godot import hint and would change node type on import' % name)
    if re.search(r"\.\d{3}$", name):
        raise ValueError('"%s" has a Blender duplicate suffix' % name)


def side_of(root: bpy.types.Object):
    """'L' / 'R' for a mirrored part root (wheel_L, rocker_R, ...), else None."""
    match = re.search(r"_([LR])$", root.name)
    return match.group(1) if match else None


def export_part(root: bpy.types.Object, path: str) -> None:
    """Exports the part root and its children as GLB with the root at the origin, as
    parts are instanced on their own (ROVER_KIT.md 8).

    In an _L / _R file the two roots' empties need unique Blender names, so they carry the
    side suffix (socket_wheel_hub_R). It is stripped while exporting, so both GLBs get the
    same socket names."""
    saved_location = root.location.copy()
    root.location = (0.0, 0.0, 0.0)
    bpy.context.view_layer.update()

    side = side_of(root)
    renamed = {}
    if side:
        for child in root.children_recursive:
            if child.type == "EMPTY" and child.name.endswith("_" + side):
                renamed[child] = child.name
                child.name = child.name[:-2]
                if child.name != renamed[child][:-2]:
                    raise ValueError("Could not strip the side from %s (name taken)" % renamed[child])
    for obj in [root] + list(root.children_recursive):
        check_export_name(obj.name)

    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    for child in root.children_recursive:
        child.select_set(True)
    bpy.context.view_layer.objects.active = root

    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=True,
        export_animations=False,
        export_materials="EXPORT",
    )
    for child, name in renamed.items():
        child.name = name
    root.location = saved_location
    bpy.context.view_layer.update()


def save_blend(path: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=path, compress=True)


def render_view(target: bpy.types.Object, path: str, direction: tuple, ortho_scale: float,
                perspective: bool = False, distance: float = 1.0, focus: tuple = (0.0, 0.0, 0.0),
                size: int = 640) -> None:
    """Renders `target` alone with Workbench from `direction` (a vector from the target
    toward the camera). Orthographic views fit `ortho_scale` metres; perspective views sit
    `distance` metres away, aimed at `focus` (an offset from the target's origin).
    World +Z is up in the image (+Y for straight-down views).
    Backface culling is on, so flipped normals show as holes."""
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.resolution_x = size
    scene.render.resolution_y = size
    scene.render.film_transparent = False
    shading = scene.display.shading
    shading.light = "STUDIO"
    shading.color_type = "MATERIAL"
    shading.show_backface_culling = True
    shading.show_cavity = True
    shading.cavity_type = "WORLD"
    shading.show_object_outline = True
    shading.show_specular_highlight = True
    shading.background_type = "VIEWPORT"
    shading.background_color = (0.82, 0.84, 0.88)

    others = [o for o in scene.objects if o.type == "MESH" and o != target and o.parent != target]
    saved = {o: o.hide_render for o in others}
    for o in others:
        o.hide_render = True

    camera_data = bpy.data.cameras.new("preview_camera")
    camera = bpy.data.objects.new("preview_camera", camera_data)
    scene.collection.objects.link(camera)
    center = target.matrix_world.translation + Vector(focus)
    view = Vector(direction).normalized()
    location = center + view * (distance if perspective else 2.0)
    # The camera looks down its -Z with +Y as image up: aim it at the target, world +Z up
    forward = -view
    up_hint = Vector((0.0, 0.0, 1.0)) if abs(view.z) < 0.99 else Vector((0.0, 1.0, 0.0))
    right = forward.cross(up_hint).normalized()
    up = right.cross(forward)
    camera.matrix_world = Matrix((
        (right.x, up.x, -forward.x, location.x),
        (right.y, up.y, -forward.y, location.y),
        (right.z, up.z, -forward.z, location.z),
        (0.0, 0.0, 0.0, 1.0),
    ))
    if perspective:
        camera_data.type = "PERSP"
        camera_data.lens = 85.0
    else:
        camera_data.type = "ORTHO"
        camera_data.ortho_scale = ortho_scale
    scene.camera = camera

    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)

    bpy.data.objects.remove(camera)
    bpy.data.cameras.remove(camera_data)
    for o, hidden in saved.items():
        o.hide_render = hidden


def polar(r: float, phi: float) -> tuple:
    """(y, z) on a circle around the X axis. phi = 90 degrees is the top (+Z)."""
    return (r * math.cos(phi), r * math.sin(phi))


# --- Standard connector (ROVER_KIT.md 2.5) ---------------------------------------------------
# Child: plug of PLUG_RADIUS sticking CONNECTOR_DEPTH out of its mating face. Parent: collar of
# COLLAR_RADIUS with a recess the plug fills; the recess opening is flush with the mating plane.
COLLAR_RADIUS = 0.030
PLUG_RADIUS = 0.022
CONNECTOR_DEPTH = 0.008
KEY_HALF_WIDTH = 0.004
KEY_DEPTH = 0.004


def plug_outline() -> list:
    """(u, v) outline of the keyed plug: 8 points on a circle with the key notch cut at +v.
    The parent's recess uses the same outline, so the notch becomes the key tab there."""
    top_angle = math.asin(KEY_HALF_WIDTH / PLUG_RADIUS)
    top_v = PLUG_RADIUS * math.cos(top_angle)
    start = math.pi / 2.0 + top_angle
    arc = 2.0 * math.pi - 2.0 * top_angle
    outline = [polar(PLUG_RADIUS, start + arc * k / 7.0) for k in range(8)]
    outline += [(KEY_HALF_WIDTH, top_v - KEY_DEPTH), (-KEY_HALF_WIDTH, top_v - KEY_DEPTH)]
    return outline


def circle_outline(radius: float, sides: int, phase: float = 0.0) -> list:
    return [polar(radius, phase + k * 2.0 * math.pi / sides) for k in range(sides)]


def prism(bm, outline: list, place, w0: float, w1: float, cap0: bool = True, cap1: bool = True) -> list:
    """Extrudes a 2D outline between w0 and w1. `place(u, v, w)` maps to 3D. Returns the
    faces; their winding is not fixed (see `orient` / recalc_face_normals)."""
    a = [bm.verts.new(place(u, v, w0)) for u, v in outline]
    b = [bm.verts.new(place(u, v, w1)) for u, v in outline]
    faces = []
    if cap0:
        faces.append(bm.faces.new(a))
    if cap1:
        faces.append(bm.faces.new(b))
    for k in range(len(outline)):
        n = (k + 1) % len(outline)
        faces.append(bm.faces.new((a[k], a[n], b[n], b[k])))
    return faces


def orient(bm, faces: list, outward) -> int:
    """Flips faces whose normal disagrees with `outward(face)` (a vector pointing away from
    the inside of the part). Returns how many were flipped."""
    bm.normal_update()
    flipped = [f for f in faces if f.normal.dot(outward(f)) < 0.0]
    bmesh.ops.reverse_faces(bm, faces=flipped)
    return len(flipped)


def axis_outward(axis: int, w_min: float, w_max: float, center_uv=(0.0, 0.0)):
    """`outward` for a prism along a world axis (0 = X, 1 = Y, 2 = Z) spanning w_min..w_max:
    caps point along the axis away from the middle, sides point away from the axis line."""
    others = [i for i in range(3) if i != axis]

    def out(f):
        c = f.calc_center_median()
        if abs(f.normal[axis]) > 0.9:
            v = Vector((0.0, 0.0, 0.0))
            v[axis] = c[axis] - (w_min + w_max) / 2.0
            return v
        v = Vector(c)
        v[axis] = 0.0
        v[others[0]] -= center_uv[0]
        v[others[1]] -= center_uv[1]
        return v
    return out


def add_socket(parent: bpy.types.Object, name: str, world_location) -> bpy.types.Object:
    """Adds a zero-rotation `socket_*` / `pivot_*` empty under a part root (ROVER_KIT.md 2.3).
    Under an _L / _R root the side suffix is added to keep Blender names unique; export_part
    strips it again."""
    side = side_of(parent)
    if side:
        name += "_" + side
    empty = bpy.data.objects.new(name, None)
    if empty.name != name:
        raise ValueError("Empty name %s is already taken (got %s)" % (name, empty.name))
    empty.empty_display_type = "PLAIN_AXES"
    empty.empty_display_size = 0.05
    bpy.context.scene.collection.objects.link(empty)
    empty.parent = parent
    empty.location = Vector(world_location) - parent.location
    return empty


def append_objects(blend_path: str, names: list) -> list:
    """Appends objects (with their children) from another part's .blend, e.g. to preview a
    part assembled with its neighbours."""
    with bpy.data.libraries.load(blend_path, link=False) as (source, target):
        target.objects = [n for n in source.objects]
    wanted = []
    for obj in target.objects:
        if obj is None:
            continue
        root = obj
        while root.parent:
            root = root.parent
        if root.name.split(".")[0] in names:
            bpy.context.scene.collection.objects.link(obj)
            # Use this file's kit materials instead of appended ".001" copies
            for slot in obj.material_slots:
                if slot.material and "." in slot.material.name:
                    existing = bpy.data.materials.get(slot.material.name.split(".")[0])
                    if existing:
                        slot.material = existing
            if obj.parent is None:
                wanted.append(obj)
        else:
            bpy.data.objects.remove(obj)
    return wanted


def parent_keep_transform(child: bpy.types.Object, parent: bpy.types.Object) -> None:
    world = child.matrix_world.copy()
    child.parent = parent
    child.matrix_parent_inverse = parent.matrix_world.inverted()
    child.matrix_world = world


def world_vertices(obj: bpy.types.Object) -> list:
    bpy.context.view_layer.update()
    m = obj.matrix_world
    return [m @ v.co for v in obj.data.vertices]
