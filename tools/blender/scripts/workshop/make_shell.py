"""Generates the workshop shell modules (A01, WORKSHOP_KIT.md 5.1, 5.3, 5.4), checks them and
renders previews.

    blender -b --factory-startup -P tools/blender/scripts/workshop/make_shell.py [-- --previews DIR | --no-previews]

Writes tools/blender/parts/workshop/shell.blend, one GLB per module in game/res/models/workshop_kit/
and previews in tools/blender/previews/workshop/shell/.

Modules are modelled in module coordinates (origin as in WORKSHOP_KIT.md 5.1) and laid out in a
row for the .blend; ws_layout (make_layout.py) places them in the kit.
    wall modules   origin: middle of the exterior face's bottom edge; exterior face toward +Y
                   (the north wall's pose), the wall from y 0 to -0.20
    partition      origin: middle of the bottom edge on its centre plane; runs along Y, the bay
                   face toward -X, the operator face toward +X
    floor / roof   origin: tile centre on the floor (z 0)
    corner         origin: the footprint's outer corner (posed as the north-east corner)
    lamp / panel   origin: the middle of the back face, facing +Y
"""

import math
import os
import sys

import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

sys.path.append(os.path.dirname(__file__))
import workshop_kit_common as ws  # noqa: E402

BUDGETS = {
    "ws_wall_panel": 300, "ws_wall_window": 400, "ws_wall_bay_door": 940, "ws_corner": 60,
    "ws_floor_tile": 30, "ws_plinth": 24, "ws_roof_tile": 120, "ws_partition_solid": 150,
    "ws_partition_door": 440, "ws_partition_window": 250, "ws_work_lamp": 120, "ws_door_panel": 120,
}
HALF_W = 1.0                     # half of a 2 m wall module
FRAME_W = 0.06                   # frame member width at each module edge
PROUD = 0.03                     # how far frames stand off a wall face
STUD_STEP = 0.5
MIN_GAP = 0.020


def wall_faces(bm, x0: float, x1: float, height: float, studs_inside: bool = True, mid_rail: bool = True) -> None:
    """Frames, bands and fastener heads on both faces of a wall module spanning x0..x1
    (exterior face y 0, interior y -WALL). Material 1 = ws_frame."""
    t = ws.WALL
    for x in ((x0, x0 + FRAME_W), (x1 - FRAME_W, x1)):
        ws.trim(bm, x, (0.0, PROUD), (0.0, height), 1, "-y")
        ws.trim(bm, x, (-t - PROUD, -t), (0.0, ws.CEILING), 1, "+y")
        xc = (x[0] + x[1]) / 2.0
        z = 0.25
        while z < height - 0.1:
            ws.stud(bm, (xc, PROUD, z), "+y", 1)
            if studs_inside and z < ws.CEILING - 0.1:
                ws.stud(bm, (xc, -t - PROUD, z), "-y", 1)
            z += STUD_STEP
    inner = (x0 + FRAME_W, x1 - FRAME_W)
    ws.trim(bm, inner, (0.0, 0.02), (0.0, 0.15), 1, "-y")                       # base band
    ws.trim(bm, inner, (0.0, 0.02), (ws.CEILING + 0.25, height), 1, "-y")       # roof edge band
    if mid_rail:
        ws.trim(bm, inner, (0.0, 0.02), (1.50, 1.56), 1, "-y")
    ws.trim(bm, inner, (-t - 0.02, -t), (0.0, 0.12), 1, "+y")                   # interior kick plate


def make_wall_panel():
    bm = ws.new_bmesh()
    ws.box(bm, (-HALF_W, HALF_W), (-ws.WALL, 0.0), (0.0, ws.WALL_HEIGHT), 0)
    wall_faces(bm, -HALF_W, HALF_W, ws.WALL_HEIGHT)
    root = ws.make_object("ws_wall_panel", bm, ["ws_panel", "ws_frame"])
    ws.collision_box(root, "ws_wall_panel_body", (-HALF_W, HALF_W), (-ws.WALL, 0.0), (0.0, ws.WALL_HEIGHT))
    return root, [root]


def make_wall_window():
    w0, w1, z0, z1 = -0.6, 0.6, 1.2, 1.8
    bm = ws.new_bmesh()
    t, h = ws.WALL, ws.WALL_HEIGHT
    pieces = [((-HALF_W, w0), (0.0, h)), ((w1, HALF_W), (0.0, h)), ((w0, w1), (0.0, z0)), ((w0, w1), (z1, h))]
    for x, z in pieces:
        ws.box(bm, x, (-t, 0.0), z, 0)
    wall_faces(bm, -HALF_W, HALF_W, h, mid_rail=False)
    for x, z in (((w0 - 0.05, w1 + 0.05), (z1, z1 + 0.05)), ((w0 - 0.05, w1 + 0.05), (z0 - 0.05, z0)),
                 ((w0 - 0.05, w0), (z0, z1)), ((w1, w1 + 0.05), (z0, z1))):
        ws.trim(bm, x, (0.0, PROUD), z, 1, "-y")
    ws.box(bm, (w0, w1), (-0.11, -0.09), (z0, z1), 2)
    root = ws.make_object("ws_wall_window", bm, ["ws_panel", "ws_frame", "ws_glass"])
    for i, (x, z) in enumerate(pieces):
        ws.collision_box(root, "ws_wall_window_body_%d" % i, x, (-t, 0.0), z)
    ws.collision_box(root, "ws_wall_window_glass", (w0, w1), (-0.11, -0.09), (z0, z1))
    return root, [root]


def make_wall_bay_door():
    """Header over the 4.0 m opening, hazard-striped plates on the neighbouring panels' end faces,
    the fold-down leaf (child `bay_door`, origin on the hinge) and its status light."""
    half = (ws.DOOR_X[1] - ws.DOOR_X[0]) / 2.0
    t, h, top = ws.WALL, ws.WALL_HEIGHT, ws.DOOR_HEIGHT
    bm = ws.new_bmesh()
    ws.box(bm, (-half, half), (-t, 0.0), (top, h), 0)
    ws.trim(bm, (-half, half), (0.0, 0.02), (ws.CEILING + 0.25, h), 1, "-y")
    ws.quad(bm, [(-half, -t, top - 0.002), (half, -t, top - 0.002), (half, 0.0, top - 0.002),
                 (-half, 0.0, top - 0.002)], 3, (0, 0, -1))                     # seal under the header
    x = -half + 0.25
    while x < half:
        ws.stud(bm, (x, 0.0, top + 0.12), "+y", 1)
        x += STUD_STEP
    # Hazard stripes on the jambs (the neighbours' end faces), both sides of the opening
    stripes = 6
    for side in (-1.0, 1.0):
        xs = side * (half - 0.002)
        for k in range(stripes):
            z0, z1 = top * k / stripes, top * (k + 1) / stripes
            ws.quad(bm, [(xs, -t, z0), (xs, 0.0, z0), (xs, 0.0, z1), (xs, -t, z1)], 2 if k % 2 == 0 else 3,
                    (-side, 0.0, 0.0))
    root = ws.make_object("ws_wall_bay_door", bm, ["ws_panel", "ws_frame", "ws_accent", "ws_dark"])
    ws.collision_box(root, "ws_wall_bay_door_header", (-half, half), (-t, 0.0), (top, h))

    # Leaf: closed, standing in the outer 8 cm of the opening; its inner face slopes to a 10 mm
    # edge at the top, which becomes the ramp's free end when it lies open
    leaf_half = half - ws.DOOR_LEAF_GAP
    leaf_top = top - 0.025
    d = ws.DOOR_LEAF_THICKNESS
    outline = [(-d, 0.0), (0.0, 0.0), (0.0, leaf_top), (-0.01, leaf_top), (-d, leaf_top - 0.2)]
    bm = ws.new_bmesh()
    faces = ws.rk.prism(bm, outline, lambda u, v, w: (w, u, v), -leaf_half, leaf_half)
    ws.bmesh.ops.recalc_face_normals(bm, faces=faces)
    for rx in (-1.5, -0.5, 0.5, 1.5):
        ws.trim(bm, (rx - 0.03, rx + 0.03), (0.0, 0.04), (0.10, leaf_top - 0.10), 1, "-y")
    for rz in (0.8, 1.7):
        for x0, x1 in ((-leaf_half + 0.05, -1.53), (-1.47, -0.53), (-0.47, 0.47), (0.53, 1.47), (1.53, leaf_half - 0.05)):
            ws.trim(bm, (x0, x1), (0.0, 0.03), (rz, rz + 0.05), 1, "-y")
    hinge = (0.0, -d, 0.0)
    leaf = ws.make_object("bay_door", bm, ["ws_panel", "ws_frame"], origin=hinge, parent=root)
    bm = ws.new_bmesh()
    faces = ws.rk.prism(bm, outline, lambda u, v, w: (w, u, v), -leaf_half, leaf_half)
    ws.bmesh.ops.recalc_face_normals(bm, faces=faces)
    ws.collision_mesh(leaf, "bay_door", bm)

    bm = ws.new_bmesh()
    for y in ((0.0, 0.04), (-t - 0.04, -t)):
        ws.trim(bm, (-0.3, 0.3), y, (top + 0.10, top + 0.16), 0, "-y" if y[0] == 0.0 else "+y")
    ws.make_object("bay_door_light", bm, ["ws_status"], parent=root)
    ws.add_empty(root, "pivot_bay_door", hinge)
    return root, [root, leaf]


def make_corner():
    bm = ws.new_bmesh()
    ws.box(bm, (-0.22, 0.02), (-0.22, 0.02), (-ws.PLINTH_DEPTH, ws.WALL_HEIGHT), 0)
    root = ws.make_object("ws_corner", bm, ["ws_frame"])
    ws.collision_box(root, "ws_corner_body", (-0.22, 0.02), (-0.22, 0.02), (-ws.PLINTH_DEPTH, ws.WALL_HEIGHT))
    return root, [root]


def make_floor_tile():
    bm = ws.new_bmesh()
    ws.box(bm, (-1.0, 1.0), (-1.0, 1.0), (-0.25, 0.0), 0)
    ws.floor_quad(bm, (0.98, 1.0), (-1.0, 1.0), 0.001, 1)
    ws.floor_quad(bm, (-1.0, 0.98), (0.98, 1.0), 0.001, 1)
    root = ws.make_object("ws_floor_tile", bm, ["ws_floor", "ws_frame"])
    ws.collision_box(root, "ws_floor_tile_body", (-1.0, 1.0), (-1.0, 1.0), (-0.25, 0.0))
    return root, [root]


def make_plinth():
    bm = ws.new_bmesh()
    ws.box(bm, (-HALF_W, HALF_W), (0.0, 0.05), (-ws.PLINTH_DEPTH, 0.05), 0)
    root = ws.make_object("ws_plinth", bm, ["ws_frame"])
    return root, [root]


def make_roof_tile():
    """Slab 3.25-3.40 (the ceiling between beams), a beam 3.00-3.25 along X (clear height 3.0 under
    it). The beam stops 1 cm short of each end so its ends never lie in a wall's face."""
    bm = ws.new_bmesh()
    ws.box(bm, (-1.0, 1.0), (-1.0, 1.0), (ws.CEILING + 0.25, ws.ROOF_TOP), 0)
    ws.box(bm, (-0.99, 0.99), (-0.075, 0.075), (ws.CEILING, ws.CEILING + 0.25), 1)
    for x in (-0.75, -0.25, 0.25, 0.75):
        ws.stud(bm, (x, 0.0, ws.CEILING), "-z", 1)
    root = ws.make_object("ws_roof_tile", bm, ["ws_panel", "ws_frame"])
    ws.collision_box(root, "ws_roof_tile_body", (-1.0, 1.0), (-1.0, 1.0), (ws.CEILING, ws.ROOF_TOP))
    return root, [root]


# --- Partition (runs along Y, centre plane x 0) ---------------------------------------------
P_HALF = ws.PARTITION_THICKNESS / 2.0
P_TOP = ws.CEILING + 0.25          # up to the ceiling slab
TRIM_PROUD = 0.02                  # trims on the operator face stay under the sliding leaf


def partition_frames(bm, y0: float, y1: float, studs: bool = True) -> None:
    for y in ((y0, y0 + FRAME_W), (y1 - FRAME_W, y1)):
        ws.trim(bm, (P_HALF, P_HALF + TRIM_PROUD), y, (0.0, P_TOP), 1, "-x")
        ws.trim(bm, (-P_HALF - PROUD, -P_HALF), y, (0.0, P_TOP), 1, "+x")
        if studs:
            # Bay face only: the personnel door's leaf slides over the operator face
            for z in (0.5, 1.5, 2.5):
                ws.stud(bm, (-P_HALF - PROUD, (y[0] + y[1]) / 2.0, z), "-x", 1)
    inner = (y0 + FRAME_W, y1 - FRAME_W)
    ws.trim(bm, (P_HALF, P_HALF + TRIM_PROUD), inner, (0.0, 0.12), 1, "-x")
    ws.trim(bm, (-P_HALF - PROUD, -P_HALF), inner, (0.0, 0.12), 1, "+x")


def make_partition_solid():
    half = 0.6
    bm = ws.new_bmesh()
    ws.box(bm, (-P_HALF, P_HALF), (-half, half), (0.0, P_TOP), 0)
    partition_frames(bm, -half, half)
    root = ws.make_object("ws_partition_solid", bm, ["ws_panel", "ws_frame"])
    ws.collision_box(root, "ws_partition_solid_body", (-P_HALF, P_HALF), (-half, half), (0.0, P_TOP))
    return root, [root]


LEAF_X = (P_HALF + TRIM_PROUD + MIN_GAP, P_HALF + TRIM_PROUD + MIN_GAP + 0.04)


def make_partition_door():
    """Jambs, a header over the 1.0 x 2.1 m opening, and the sliding leaf `personnel_door` on the
    operator face (child, origin on its centre plane at the floor)."""
    half, o0, o1, top = 0.6, -0.5, 0.5, ws.PERSONNEL_HEIGHT
    bm = ws.new_bmesh()
    pieces = [((-half, o0), (0.0, P_TOP)), ((o1, half), (0.0, P_TOP)), ((o0, o1), (top, P_TOP))]
    for y, z in pieces:
        ws.box(bm, (-P_HALF, P_HALF), y, z, 0)
    partition_frames(bm, -half, half, studs=False)
    for x, side in (((P_HALF, P_HALF + TRIM_PROUD), "-x"), ((-P_HALF - PROUD, -P_HALF), "+x")):
        ws.trim(bm, x, (o0 - 0.05, o1 + 0.05), (top, top + 0.05), 2, side)
    root = ws.make_object("ws_partition_door", bm, ["ws_panel", "ws_frame", "ws_accent"])
    for i, (y, z) in enumerate(pieces):
        ws.collision_box(root, "ws_partition_door_body_%d" % i, (-P_HALF, P_HALF), y, z)

    bm = ws.new_bmesh()
    ly, lz = (o0 - 0.02, o1 + 0.02), (0.01, top + 0.03)
    ws.box(bm, LEAF_X, ly, lz, 0)
    ws.trim(bm, (LEAF_X[1], LEAF_X[1] + 0.002), (-0.15, 0.15), (1.4, 1.8), 2, "-x")      # viewport
    ws.trim(bm, (LEAF_X[1], LEAF_X[1] + 0.03), (0.38, 0.41), (0.9, 1.2), 1, "-x")        # handle
    pivot = ((LEAF_X[0] + LEAF_X[1]) / 2.0, 0.0, 0.0)
    leaf = ws.make_object("personnel_door", bm, ["ws_panel", "ws_frame", "ws_dark"], origin=pivot, parent=root)
    ws.collision_box(leaf, "personnel_door", LEAF_X, ly, lz)

    bm = ws.new_bmesh()
    ws.trim(bm, (-P_HALF - 0.03, -P_HALF), (-0.15, 0.15), (top + 0.12, top + 0.17), 0, "+x")
    ws.trim(bm, (P_HALF, P_HALF + TRIM_PROUD), (-0.15, 0.15), (top + 0.12, top + 0.17), 0, "-x")
    ws.make_object("personnel_door_light", bm, ["ws_status"], parent=root)
    ws.add_empty(root, "pivot_personnel_door", pivot)
    return root, [root, leaf]


def make_partition_window():
    half = 1.0
    bm = ws.new_bmesh()
    pieces = [((-half, half), (0.0, ws.WINDOW_SILL)), ((-half, half), (ws.WINDOW_HEAD, P_TOP))]
    for y, z in pieces:
        ws.box(bm, (-P_HALF, P_HALF), y, z, 0)
    ws.box(bm, (-P_HALF, P_HALF), (-0.03, 0.03), (ws.WINDOW_SILL, ws.WINDOW_HEAD), 1)    # mullion
    for y in ((-half, -0.03), (0.03, half)):
        ws.box(bm, (-0.01, 0.01), y, (ws.WINDOW_SILL, ws.WINDOW_HEAD), 2)
    partition_frames(bm, -half, half, studs=False)
    for x, side in (((P_HALF, P_HALF + TRIM_PROUD), "-x"), ((-P_HALF - PROUD, -P_HALF), "+x")):
        ws.trim(bm, x, (-half + FRAME_W, half - FRAME_W), (ws.WINDOW_SILL - 0.04, ws.WINDOW_SILL), 1, side)
        ws.trim(bm, x, (-half + FRAME_W, half - FRAME_W), (ws.WINDOW_HEAD, ws.WINDOW_HEAD + 0.04), 1, side)
    root = ws.make_object("ws_partition_window", bm, ["ws_panel", "ws_frame", "ws_glass"])
    for i, (y, z) in enumerate(pieces):
        ws.collision_box(root, "ws_partition_window_body_%d" % i, (-P_HALF, P_HALF), y, z)
    ws.collision_box(root, "ws_partition_window_glass", (-0.01, 0.01), (-half, half), (ws.WINDOW_SILL, ws.WINDOW_HEAD))
    return root, [root]


def make_work_lamp():
    bm = ws.new_bmesh()
    ws.trim(bm, (-0.03, 0.03), (0.0, 0.06), (0.06, 0.15), 1, "-y")                  # bracket
    ws.box(bm, (-0.175, 0.175), (0.05, 0.20), (-0.075, 0.06), 1)                    # housing
    ws.quad(bm, [(-0.15, 0.06, -0.0752), (0.15, 0.06, -0.0752), (0.15, 0.19, -0.0752),
                 (-0.15, 0.19, -0.0752)], 0, (0, 0, -1))                             # lens, facing down
    ws.quad(bm, [(-0.15, 0.2002, -0.05), (0.15, 0.2002, -0.05), (0.15, 0.2002, 0.0),
                 (-0.15, 0.2002, 0.0)], 0, (0, 1, 0))                                # lens, facing out
    root = ws.make_object("ws_work_lamp", bm, ["ws_lamp", "ws_frame"])
    return root, [root]


def make_door_panel():
    bm = ws.new_bmesh()
    ws.trim(bm, (-0.15, 0.15), (0.0, 0.08), (-0.2, 0.2), 0, "-y")
    ws.trim(bm, (-0.06, 0.06), (0.08, 0.10), (0.02, 0.14), 1, "-y")                 # open / close
    ws.trim(bm, (-0.10, 0.10), (0.08, 0.085), (-0.15, -0.05), 2, "-y")              # placard
    root = ws.make_object("ws_door_panel", bm, ["ws_panel", "ws_accent", "ws_dark"])
    return root, [root]


MAKERS = [make_wall_panel, make_wall_window, make_wall_bay_door, make_corner, make_floor_tile, make_plinth,
          make_roof_tile, make_partition_solid, make_partition_door, make_partition_window, make_work_lamp,
          make_door_panel]
SIZES = {
    "ws_wall_panel": (2.0, ws.WALL + 2 * PROUD + 0.016, ws.WALL_HEIGHT),
    "ws_corner": (0.24, 0.24, ws.WALL_HEIGHT + ws.PLINTH_DEPTH),
    "ws_floor_tile": (2.0, 2.0, 0.251),          # with the 1 mm seam strips
    "ws_plinth": (2.0, 0.05, ws.PLINTH_DEPTH + 0.05),
    "ws_partition_solid": (None, 1.2, P_TOP),
}


# --- Checks ----------------------------------------------------------------------------------

def bvh(objects: list, matrix: Matrix = Matrix.Identity(4)) -> BVHTree:
    verts, polys = [], []
    for o in objects:
        m = matrix @ o.matrix_world
        base = len(verts)
        verts += [m @ v.co for v in o.data.vertices]
        polys += [[base + i for i in p.vertices] for p in o.data.polygons]
    return BVHTree.FromPolygons(verts, polys)


def gap(a: list, b: list, a_matrix: Matrix = Matrix.Identity(4)) -> float:
    """Approximate least distance between two groups of meshes (vertices of each against the
    other's surface), with `a_matrix` applied to group a. 0 when they intersect."""
    ta, tb = bvh(a, a_matrix), bvh(b)
    if ta.overlap(tb):
        return 0.0
    best = 1e9
    for objs, matrix, other in ((a, a_matrix, tb), (b, Matrix.Identity(4), ta)):
        for o in objs:
            m = matrix @ o.matrix_world
            for v in o.data.vertices:
                hit = other.find_nearest(m @ v.co)
                if hit[0] is not None:
                    best = min(best, hit[3])
    return best


def visible_meshes(root) -> list:
    return [o for o in [root] + list(root.children_recursive) if o.type == "MESH" and "-convcolonly" not in o.name]


def run_checks(roots: dict, rows: list) -> int:
    failures = 0
    for name, root in roots.items():
        failures += ws.check_part(root, BUDGETS[name], SIZES.get(name), rows)
    # Bay door leaf: clearance to the jamb plates and header over its swing (0 to -90 degrees)
    frame = roots["ws_wall_bay_door"]
    leaf = frame.children_recursive and next(o for o in frame.children if o.name == "bay_door")
    pivot = leaf.matrix_world.translation.copy()
    worst = (1e9, 0)
    for deg in range(0, -91, -5):
        rot = Matrix.Translation(pivot) @ Matrix.Rotation(math.radians(deg), 4, "X") @ Matrix.Translation(-pivot)
        g = gap([leaf], [frame], rot)
        worst = min(worst, (g, deg))
    ok = worst[0] >= MIN_GAP - 1e-6
    failures += 0 if ok else 1
    rows.append("bay_door swing 0..-90 deg: least gap to the header and jamb plates %.1f mm at %d deg%s" % (
        worst[0] * 1000.0, worst[1], "" if ok else "  FAIL"))
    # The open leaf lies with its top flush with the floor
    rot = Matrix.Translation(pivot) @ Matrix.Rotation(math.radians(-90), 4, "X") @ Matrix.Translation(-pivot)
    tops = [(rot @ leaf.matrix_world @ v.co) for v in leaf.data.vertices]
    top_z = max(p.z for p in tops) - frame.matrix_world.translation.z
    far_y = max(p.y for p in tops) - frame.matrix_world.translation.y
    rows.append("bay_door open: top surface at z %+.3f (floor 0), reaches %.2f m out" % (top_z, far_y))
    failures += 0 if abs(top_z) < 0.001 else 1
    # Personnel door leaf over its 1.0 m slide, against the door module and the solid module it
    # slides over (placed beside it as in the kit)
    door = roots["ws_partition_door"]
    pleaf = next(o for o in door.children if o.name == "personnel_door")
    solid = roots["ws_partition_solid"]
    saved = solid.location.copy()
    solid.location = door.location + Vector((0.0, -1.2, 0.0))
    bpy.context.view_layer.update()
    others = visible_meshes(solid) + [o for o in visible_meshes(door) if o is not pleaf]
    worst = (1e9, 0.0)
    for k in range(0, 11):
        slide = -ws.PERSONNEL_SLIDE * k / 10.0
        g = gap([pleaf], others, Matrix.Translation((0.0, slide, 0.0)))
        worst = min(worst, (g, slide))
    solid.location = saved
    bpy.context.view_layer.update()
    ok = worst[0] >= MIN_GAP - 1e-6
    failures += 0 if ok else 1
    rows.append("personnel_door slide 0..1.0 m: least gap %.1f mm at %.1f m%s" % (worst[0] * 1000.0, -worst[1],
                                                                                  "" if ok else "  FAIL"))
    rows.append("personnel_door clear opening %.2f x %.2f m" % (1.0, ws.PERSONNEL_HEIGHT))
    return failures


def render_previews(roots: dict, previews: str) -> None:
    ws.set_preview_colors(True)
    for name, root in roots.items():
        lo, hi = ws.bounds(visible_meshes(root))
        size = max(hi - lo)
        center = (lo + hi) / 2.0 - root.matrix_world.translation
        if name.startswith("ws_partition"):
            views = (("bay_side", (-1.0, -0.4, 0.3)), ("operator_side", (1.0, 0.4, 0.3)), ("end", (0.0, 1.0, 0.0)))
        elif name in ("ws_floor_tile", "ws_roof_tile"):
            views = (("above", (0.4, -0.6, 0.7)), ("below", (0.4, -0.6, -0.7)), ("side", (1.0, 0.0, 0.0)))
        else:
            views = (("outside", (0.5, 1.0, 0.35)), ("inside", (-0.5, -1.0, 0.35)), ("side", (1.0, 0.0, 0.0)))
        for view, direction in views:
            ws.render(root, os.path.join(previews, "%s_%s.png" % (name, view)), direction, size * 1.25,
                      view != "side" and view != "end", size * 3.2, tuple(center))
    # Bay door half open and open
    frame = roots["ws_wall_bay_door"]
    leaf = next(o for o in frame.children if o.name == "bay_door")
    for deg in (-45, -90):
        leaf.rotation_euler = (math.radians(deg), 0.0, 0.0)
        ws.render(frame, os.path.join(previews, "ws_wall_bay_door_open_%d.png" % -deg), (0.8, 1.0, 0.5), 6.0, True,
                  14.0, (0.0, 1.0, 1.2))
    leaf.rotation_euler = (0.0, 0.0, 0.0)
    door = roots["ws_partition_door"]
    pleaf = next(o for o in door.children if o.name == "personnel_door")
    pleaf.location.y -= ws.PERSONNEL_SLIDE
    ws.render(door, os.path.join(previews, "ws_partition_door_open.png"), (1.0, 0.4, 0.3), 3.5, True, 9.0,
              (0.0, -0.5, 1.4))
    pleaf.location.y += ws.PERSONNEL_SLIDE
    ws.set_preview_colors(False)


def main() -> None:
    previews = ws.preview_dir("shell")
    ws.rk.reset_scene()
    roots = {}
    x = 0.0
    for maker in MAKERS:
        root, _ = maker()
        roots[root.name] = root
        root.location = (x, -12.0, 0.0)
        x += 3.0
    bpy.context.view_layer.update()
    ws.add_references()
    rows = []
    failures = run_checks(roots, rows)
    for root in roots.values():
        ws.export(root)
    ws.save("shell")
    if previews:
        render_previews(roots, previews)
    rows.append("ALL CHECKS OK" if failures == 0 else "%d CHECK FAILURES" % failures)
    ws.report("shell", rows)


if __name__ == "__main__":
    main()
