"""Shared helpers and layout numbers for the workshop kit generators (tools/blender/WORKSHOP_KIT.md).

Run the asset scripts headless from the repo root, e.g.:
    blender -b --factory-startup -P tools/blender/scripts/workshop/make_rack.py
Previews go to tools/blender/previews/workshop/<asset>/ unless `-- --previews <dir>` or `-- --no-previews`.

Kit coordinates (WORKSHOP_KIT.md 3.1): metres, origin in the middle of the footprint on the floor
top, the bay door in the +Y wall. Every number of the layout lives here, nowhere else.
"""

import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

sys.path.append(os.path.join(os.path.dirname(__file__), ".."))
import rover_kit_common as rk  # noqa: E402

REPO_ROOT = rk.REPO_ROOT
PARTS_DIR = os.path.join(REPO_ROOT, "tools", "blender", "parts", "workshop")
EXPORT_DIR = os.path.join(REPO_ROOT, "game", "res", "models", "workshop_kit")
PREVIEWS_DIR = os.path.join(REPO_ROOT, "tools", "blender", "previews", "workshop")
ROVER_PARTS_DIR = rk.PARTS_DIR
# Godot post-import script for the workshop GLBs (moving pieces' colliders become AnimatableBody3D)
GODOT_IMPORT_SCRIPT = "res://src/workshop/workshop_kit_import.gd"

# --- Layout (WORKSHOP_KIT.md 4, 5) ----------------------------------------------------------
HALF_X, HALF_Y = 5.0, 4.0              # outer footprint 10 x 8
WALL = 0.20
INNER_X, INNER_Y = HALF_X - WALL, HALF_Y - WALL
WALL_HEIGHT = 3.45                     # 5 cm parapet over the 3.4 m roof
CEILING = 3.0
ROOF_TOP = 3.4
PLINTH_DEPTH = 0.30

DOOR_X = (-3.0, 1.0)                   # bay door opening in the +Y wall
DOOR_HEIGHT = 2.5
DOOR_LEAF_THICKNESS = 0.08
DOOR_LEAF_GAP = 0.025                  # each side, to the jamb plates (>= 20 mm)
DOOR_HINGE = Vector((-1.0, HALF_Y - DOOR_LEAF_THICKNESS, 0.0))

PARTITION_X = 2.10                     # centre plane; faces at 2.05 (bay) and 2.15 (operator)
PARTITION_THICKNESS = 0.10
PARTITION_HEIGHT = CEILING
PERSONNEL_OPENING = (-2.5, -1.5)       # y range, 2.1 m tall
PERSONNEL_HEIGHT = 2.1
PERSONNEL_SLIDE = 1.0
WINDOW_SILL, WINDOW_HEAD = 1.0, 2.4
# Partition modules south to north: (part, centre y, length)
PARTITION_MODULES = [("ws_partition_solid", -3.2, 1.2), ("ws_partition_door", -2.0, 1.2),
                     ("ws_partition_window", -0.4, 2.0), ("ws_partition_window", 1.6, 2.0),
                     ("ws_partition_solid", 3.2, 1.2)]

DOCK = Vector((-0.1, -0.3, 0.0))       # dock point on the floor; the rover's origin rides 0.10 above
DOCK_ZONE = 0.40
ROVER_RIDE = 0.10
ROVER_BELLY = 0.30                     # chassis bottom above the floor at rest
PROBE_RISE = 0.28
PAD_SIZE = (3.0, 4.0)
CONTACT_PLATE = 1.0

RACK_ORIGIN = Vector((-0.1, -INNER_Y, 0.0))   # middle of its back edge on the floor
RACK_SIZE = (2.5, 0.5, 1.8)
SHELF_TOPS = [0.16, 0.68, 1.20, 1.62]
# Stepped: each level is shallower than the one below, so its parts stand in front of the shelf
# above them and are seen from the walkway at any distance (WORKSHOP_KIT.md 6.3)
SHELF_DEPTHS = [0.48, 0.40, 0.28, 0.18]
LABEL_RAIL = 0.14
CHARGER_ORIGIN = Vector((PARTITION_X - PARTITION_THICKNESS / 2.0, 3.1, 0.0))
CONSOLE_ORIGIN = Vector((PARTITION_X + PARTITION_THICKNESS / 2.0, -0.3, 0.0))
SPAWN = Vector((3.8, 2.0, 0.0))

# Rover (WORKSHOP_KIT.md 2.1), origin at its physics origin, facing +Y
ROVER_HALF_WIDTH = 0.628
ROVER_FRONT, ROVER_REAR = 0.65, -0.896
ROVER_HEIGHT = 1.22
TURN_RADIUS = 1.07
# Player (2.2)
PLAYER_RADIUS, PLAYER_HEIGHT, PLAYER_EYE, PLAYER_REACH = 0.25, 2.0, 1.5, 3.0

# --- Materials (WORKSHOP_KIT.md 7.2) --------------------------------------------------------
PALETTE = {
    "ws_panel": "CFCBC2",
    "ws_frame": "3A3D42",
    "ws_floor": "6B6E72",
    "ws_accent": "E0A030",
    "ws_dark": "1C1D20",
    "ws_label": "EDEBE4",
    "ws_glass": "9FB4C0",
    "ws_screen": "0B0E10",
    "ws_lamp": "FFB347",
    "ws_status": "FFFFFF",
}
# (metallic, roughness)
MATERIAL_SETTINGS = {
    "ws_panel": (0.0, 0.7), "ws_frame": (0.5, 0.5), "ws_floor": (0.1, 0.8), "ws_accent": (0.0, 0.6),
    "ws_dark": (0.0, 0.8), "ws_label": (0.0, 0.9), "ws_glass": (0.0, 0.1), "ws_screen": (0.0, 0.3),
    "ws_lamp": (0.0, 0.5), "ws_status": (0.0, 0.5),
}
EMISSIVE = {"ws_lamp": 4.0, "ws_status": 2.0}
GLASS_ALPHA = 0.25
# Lighter stand-ins for previews, so dark parts show their shape
PREVIEW_COLORS = {"ws_frame": "8A9099", "ws_dark": "5A5D63", "ws_screen": "34404A", "ws_floor": "9A9DA2"}


def get_material(name: str) -> bpy.types.Material:
    if name not in PALETTE:
        raise ValueError("Not a workshop kit material: " + name)
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
    if name == "ws_glass":
        bsdf.inputs["Alpha"].default_value = GLASS_ALPHA
        material.surface_render_method = "BLENDED"
    material.diffuse_color = color
    material.metallic = metallic
    material.roughness = roughness
    return material


def materials(*names) -> list:
    return [get_material(n) for n in names]


def set_preview_colors(enabled: bool) -> None:
    for name, hex_color in PALETTE.items():
        material = bpy.data.materials.get(name)
        if material:
            source = PREVIEW_COLORS.get(name, hex_color) if enabled else hex_color
            material.diffuse_color = rk.srgb_to_linear(source)


# --- Geometry helpers ----------------------------------------------------------------------
# Every helper takes a material index into the object's material list.

def box(bm, x: tuple, y: tuple, z: tuple, mat: int = 0) -> list:
    """Closed axis-aligned box, normals outward."""
    return rk.box(bm, x, y, z, mat)


def trim(bm, x: tuple, y: tuple, z: tuple, mat: int, open_side: str) -> list:
    """Box without the face against the surface it sits on (`open_side` "-x", "+y", ...): a trim
    strip, frame member or plate on a wall. Normals outward."""
    faces = box(bm, x, y, z, mat)
    axis = "xyz".index(open_side[1])
    sign = 1.0 if open_side[0] == "+" else -1.0
    for f in faces:
        if f.normal[axis] * sign > 0.9:
            bm.faces.remove(f)
            faces.remove(f)
            break
    return faces


def quad(bm, corners: list, mat: int, normal: Vector) -> bmesh.types.BMFace:
    """One face from four corners, turned to face `normal`."""
    face = bm.faces.new([bm.verts.new(c) for c in corners])
    face.material_index = mat
    bm.normal_update()
    if face.normal.dot(Vector(normal)) < 0.0:
        face.normal_flip()
    return face


def floor_quad(bm, x: tuple, y: tuple, z: float, mat: int) -> bmesh.types.BMFace:
    """A decal on the floor: an upward-facing rectangle at height z."""
    return quad(bm, [(x[0], y[0], z), (x[1], y[0], z), (x[1], y[1], z), (x[0], y[1], z)], mat, (0, 0, 1))


def floor_polygon(bm, points: list, z: float, mat: int) -> bmesh.types.BMFace:
    face = bm.faces.new([bm.verts.new((p[0], p[1], z)) for p in points])
    face.material_index = mat
    bm.normal_update()
    if face.normal.z < 0.0:
        face.normal_flip()
    return face


def stud(bm, center, normal_axis: str, mat: int, size: float = 0.024, height: float = 0.008) -> list:
    """A fastener head: a low four-sided pyramid (4 triangles) on a surface whose outward normal
    is `normal_axis` ("+y", "-x", ...)."""
    axis = "xyz".index(normal_axis[1])
    sign = 1.0 if normal_axis[0] == "+" else -1.0
    u, v = [i for i in range(3) if i != axis]
    c = Vector(center)
    base = []
    for du, dv in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
        p = c.copy()
        p[u] += du * size / 2.0
        p[v] += dv * size / 2.0
        base.append(bm.verts.new(p))
    tip = c.copy()
    tip[axis] += sign * height
    apex = bm.verts.new(tip)
    faces = []
    for k in range(4):
        f = bm.faces.new((base[k], base[(k + 1) % 4], apex))
        f.material_index = mat
        faces.append(f)
    out = Vector((0.0, 0.0, 0.0))
    out[axis] = sign
    rk.orient(bm, faces, lambda f: (f.calc_center_median() - c) + out * 0.001)
    return faces


def cylinder(bm, center, axis: str, radius: float, w0: float, w1: float, mat: int, sides: int = 8,
             caps: tuple = (True, True)) -> list:
    """Round prism along a world axis ("x", "y", "z") through `center`, from w0 to w1 along it
    (offsets from the centre). Normals outward."""
    a = "xyz".index(axis)
    u, v = [i for i in range(3) if i != a]
    c = Vector(center)

    def place(pu, pv, w):
        p = c.copy()
        p[u] += pu
        p[v] += pv
        p[a] += w
        return tuple(p)
    faces = rk.prism(bm, rk.circle_outline(radius, sides, math.pi / sides), place, w0, w1, *caps)
    for f in faces:
        f.material_index = mat
    lo, hi = c[a] + w0, c[a] + w1
    rk.orient(bm, faces, rk.axis_outward(a, lo, hi, (c[u], c[v])))
    return faces


def dome(bm, center, radius: float, mat: int, sides: int = 8) -> list:
    """Half dome on a flat base (open at the bottom): a ring and a top fan, 3 * sides triangles."""
    c = Vector(center)
    ring0 = [bm.verts.new(c + Vector((radius * math.cos(2 * math.pi * k / sides),
                                      radius * math.sin(2 * math.pi * k / sides), 0.0))) for k in range(sides)]
    r1 = radius * 0.7
    ring1 = [bm.verts.new(c + Vector((r1 * math.cos(2 * math.pi * k / sides),
                                      r1 * math.sin(2 * math.pi * k / sides), radius * 0.7))) for k in range(sides)]
    top = bm.verts.new(c + Vector((0.0, 0.0, radius)))
    faces = []
    for k in range(sides):
        n = (k + 1) % sides
        faces.append(bm.faces.new((ring0[k], ring0[n], ring1[n], ring1[k])))
        faces.append(bm.faces.new((ring1[k], ring1[n], top)))
    for f in faces:
        f.material_index = mat
    rk.orient(bm, faces, lambda f: f.calc_center_median() - c)
    return faces


def prism_xy(bm, outline: list, z0: float, z1: float, mat: int) -> list:
    """Closed prism of a 2D outline (x, y) between heights z0 and z1, normals outward."""
    faces = rk.prism(bm, outline, lambda u, v, w: (u, v, w), z0, z1)
    for f in faces:
        f.material_index = mat
    bmesh.ops.recalc_face_normals(bm, faces=faces)
    return faces


def ring(bm, center, r_in: float, r_out: float, z: float, mat: int, sides: int = 24) -> list:
    """Flat ring on the floor (a painted circle), facing up."""
    c = Vector(center)
    faces = []
    for k in range(sides):
        a0, a1 = 2 * math.pi * k / sides, 2 * math.pi * (k + 1) / sides
        pts = [(c.x + r * math.cos(a), c.y + r * math.sin(a), z) for r, a in
               ((r_in, a0), (r_out, a0), (r_out, a1), (r_in, a1))]
        faces.append(quad(bm, pts, mat, (0, 0, 1)))
    return faces


def new_bmesh() -> bmesh.types.BMesh:
    return bmesh.new()


def make_object(name: str, bm, material_names: list, origin=(0.0, 0.0, 0.0), parent=None) -> bpy.types.Object:
    """Mesh object from a bmesh built in kit coordinates. Its origin goes to `origin` (kit
    coordinates) and the geometry is shifted to keep its place."""
    origin = Vector(origin)
    bmesh.ops.translate(bm, vec=-origin, verts=bm.verts)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    obj = rk.mesh_object(name, bm, materials(*material_names))
    obj.location = origin
    if parent is not None:
        bpy.context.view_layer.update()
        rk.parent_keep_transform(obj, parent)
    return obj


def collision_box(parent: bpy.types.Object, name: str, x: tuple, y: tuple, z: tuple) -> bpy.types.Object:
    """A `<name>-convcolonly` box child (kit coordinates), WORKSHOP_KIT.md 9.1."""
    bm = bmesh.new()
    rk.box(bm, x, y, z, 0)
    obj = rk.mesh_object(name + "-convcolonly", bm, [])
    obj.display_type = "WIRE"
    obj.hide_render = True
    bpy.context.view_layer.update()
    rk.parent_keep_transform(obj, parent)
    return obj


def collision_mesh(parent: bpy.types.Object, name: str, bm) -> bpy.types.Object:
    """A convex `<name>-convcolonly` child from a bmesh in kit coordinates."""
    obj = rk.mesh_object(name + "-convcolonly", bm, [])
    obj.display_type = "WIRE"
    obj.hide_render = True
    bpy.context.view_layer.update()
    rk.parent_keep_transform(obj, parent)
    return obj


def add_empty(parent: bpy.types.Object, name: str, location, rotation_z_degrees: float = 0.0) -> bpy.types.Object:
    """Zero-rotation empty (kit coordinates) under `parent`; only `place_*` empties turn. When the
    name is already taken in this file (several parts with a `label_sign`), the Blender name gets
    `__<part>` appended, and `export` strips it again."""
    if rotation_z_degrees and not name.startswith("place_"):
        raise ValueError("Only place_* empties may turn: " + name)
    if name in bpy.data.objects:
        root = parent
        while root.parent:
            root = root.parent
        name = name + "__" + root.name
    empty = bpy.data.objects.new(name, None)
    if empty.name != name:
        raise ValueError("Empty name %s is already taken (got %s)" % (name, empty.name))
    empty.empty_display_type = "PLAIN_AXES"
    empty.empty_display_size = 0.1
    bpy.context.scene.collection.objects.link(empty)
    empty.location = Vector(location)
    empty.rotation_euler = (0.0, 0.0, math.radians(rotation_z_degrees))
    bpy.context.view_layer.update()
    rk.parent_keep_transform(empty, parent)
    return empty


def root_empty(name: str, location=(0.0, 0.0, 0.0)) -> bpy.types.Object:
    """A part root that has no mesh of its own (ws_layout)."""
    empty = bpy.data.objects.new(name, None)
    empty.empty_display_type = "ARROWS"
    bpy.context.scene.collection.objects.link(empty)
    empty.location = Vector(location)
    return empty


# --- Reference objects (WORKSHOP_KIT.md 3.1; never exported) --------------------------------

def add_references() -> list:
    refs = []
    bm = bmesh.new()
    rk.box(bm, (-0.5, 0.5), (-0.5, 0.5), (0.0, 1.0), 0)
    cube = rk.mesh_object("ref_cube", bm, [])
    cube.location = (-6.5, -5.5, 0.0)
    refs.append(cube)
    bm = bmesh.new()
    cylinder(bm, (0.0, 0.0, 0.0), "z", PLAYER_RADIUS, 0.0, PLAYER_HEIGHT, 0, 12)
    refs.append(rk.mesh_object("ref_player", bm, []))
    refs[-1].location = SPAWN
    bm = bmesh.new()
    rk.box(bm, (-ROVER_HALF_WIDTH, ROVER_HALF_WIDTH), (ROVER_REAR, ROVER_FRONT), (0.0, ROVER_HEIGHT), 0)
    rover = rk.mesh_object("ref_rover", bm, [])
    rover.location = (DOCK.x, DOCK.y, 0.0)
    refs.append(rover)
    for r in refs:
        r.display_type = "WIRE"
        r.hide_render = True
    return refs


# --- Export and checks ---------------------------------------------------------------------

def export(root: bpy.types.Object) -> str:
    """Exports a part root and its children to game/res/models/workshop_kit/<root>.glb with the
    workshop post-import script."""
    rk.GODOT_IMPORT_SCRIPT = GODOT_IMPORT_SCRIPT
    path = os.path.join(EXPORT_DIR, root.name + ".glb")
    # Strip the `__<part>` suffixes (add_empty), moving any other holder of the plain name aside
    renamed, moved = {}, {}
    for child in root.children_recursive:
        if "__" in child.name:
            plain = child.name.split("__")[0]
            holder = bpy.data.objects.get(plain)
            if holder is not None:
                moved[holder] = plain
                holder.name = plain + "__moved"
            renamed[child] = child.name
            child.name = plain
    rk.export_part(root, path)
    for child, name in renamed.items():
        child.name = name
    for holder, name in moved.items():
        holder.name = name
    return path


def save(asset: str) -> None:
    rk.save_blend(os.path.join(PARTS_DIR, asset + ".blend"))


def visible_triangles(root: bpy.types.Object) -> int:
    return sum(rk.triangle_count(o) for o in [root] + list(root.children_recursive)
               if o.type == "MESH" and "-convcolonly" not in o.name)


def check_part(root: bpy.types.Object, budget: int, size: tuple = None, rows: list = None) -> int:
    """Checks a part (WORKSHOP_KIT.md 12): names, empties unrotated, only kit materials, the
    triangle budget and (optionally) its bounding size in metres to 1 mm. Appends report lines,
    returns the number of failures."""
    rows = rows if rows is not None else []
    failures = 0
    objects = [root] + list(root.children_recursive)
    for o in objects:
        rk.check_export_name(o.name)
        if o.type == "EMPTY" and not o.name.startswith("place_") and o is not root:
            if any(abs(a) > 1e-6 for a in o.matrix_world.to_euler()):
                rows.append("FAIL %s: empty %s is rotated" % (root.name, o.name))
                failures += 1
        if o.type == "MESH":
            for slot in o.material_slots:
                if slot.material and slot.material.name not in PALETTE:
                    rows.append("FAIL %s: material %s is not in the kit" % (o.name, slot.material.name))
                    failures += 1
    tris = visible_triangles(root)
    ok = tris <= budget
    failures += 0 if ok else 1
    line = "%s: %d triangles (budget %d)%s" % (root.name, tris, budget, "" if ok else "  FAIL")
    if size is not None:
        lo, hi = bounds([o for o in objects if o.type == "MESH" and "-convcolonly" not in o.name])
        measured = tuple(hi[i] - lo[i] for i in range(3))
        size_ok = all(abs(measured[i] - size[i]) <= 0.001 for i in range(3) if size[i] is not None)
        failures += 0 if size_ok else 1
        line += ", size %.3f x %.3f x %.3f m%s" % (measured + ("" if size_ok else "  FAIL (spec %s)" % (size,),))
    rows.append(line)
    return failures


def bounds(objects: list) -> tuple:
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for o in objects:
        for p in rk.world_vertices(o):
            for i in range(3):
                lo[i] = min(lo[i], p[i])
                hi[i] = max(hi[i], p[i])
    return lo, hi


def check_closed(obj: bpy.types.Object) -> bool:
    """True when every edge of the mesh joins exactly two faces (a closed solid that casts a
    clean shadow)."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    closed = all(len(e.link_faces) == 2 for e in bm.edges)
    bm.free()
    return closed


def preview_dir(asset: str):
    args = rk.script_args()
    if "--no-previews" in args:
        return None
    path = args[args.index("--previews") + 1] if "--previews" in args else os.path.join(PREVIEWS_DIR, asset)
    os.makedirs(path, exist_ok=True)
    return path


def render(target, path: str, direction: tuple, scale: float, perspective: bool = False, distance: float = 6.0,
           focus: tuple = (0.0, 0.0, 0.0), keep_visible: tuple = (), size: int = 800) -> None:
    rk.render_view(target, path, direction, scale, perspective, distance, focus, size, keep_visible)


def report(asset: str, rows: list) -> None:
    print("\n".join("WORKSHOP_KIT %s " % asset + line for line in rows))
