"""Generates the M2 sampling kit (A12), the sample containers (A13), the workshop's sample bench with its
tray, and the near sample site by IRIS (A15), checks them and renders previews.

    blender -b --factory-startup -P tools/blender/scripts/iris/make_sample_kit.py [-- --previews DIR | --no-previews]

Writes (blend in tools/blender/parts/, glb in game/res/models/<kit>/):
    rover_kit/sample_scoop.glb            the scoop the arm tool holds (assisted pose only)
    rover_kit/sample_container.glb        the sealed container, lid on, gauge at 8 % (empty)
    rover_kit/sample_container_full.glb   the same, gauge at 90 % (the full one)
    workshop_kit/ws_sample_bench.glb      a lab bench with a tray: three pockets for the kit
    iris_kit/sample_site_near.glb         the reference patch by IRIS (IRIS's frame: put it where IRIS is)
Previews in tools/blender/previews/sample_kit/.

Container (rover palette): a 12-sided jar 90 mm across and 100 mm tall, origin the middle of its bottom
face. The lid is its own object `container_lid` whose origin is the hinge (back, +Y, at the rim): turn it
about X to open. `container_fill` is the fill gauge on the front, a bar whose origin is the gauge's
bottom: scale its Z (Godot Y) to 0..1 of the gauge. Empties: anchor_pickup (0, 0, 0.06), anchor_fill
(0, 0, 0.10; the opening's centre, where the scoop pours), anchor_stow (0, 0, 0).
Scoop (rover palette): origin the grip's centre; the handle runs along +Y, the bowl bends 25 degrees down.
Empties: anchor_grip (0, 0, 0), anchor_tip (the bowl's leading edge), anchor_pour (the bowl's middle).
Sample bench (workshop palette): kit footprint 0.70 x 0.40 m, top at 0.90 m, origin the middle of its
footprint on the floor, to go at anchor_bench (4.2, 2.6). Empties: slot_sample_scoop, slot_sample_a,
slot_sample_b (where a part's bottom rests: on the tray, 0.90 + 0.012); slot_thermal_cover, slot_heater on
the low shelf (0.25; make_m3_kit.py's thermal kit). Colliders: the top, the low shelf, the legs.
Sample site (make_site; make_m3_kit.py builds the far one with it): a dark reference patch 1.1 m across, its vertices following the terrain (2 cm proud in the middle, 4 mm at its edge), with four
corner marks. Empties: anchor_sample (the centre), anchor_marker_post (0.75 m from it, where a
ws_marker_post goes), park_sample (where Kite's origin stops on the ground, heading +X in IRIS's frame:
the tool turret reaches the scoop's tip to the patch's centre).
Budgets: scoop 250, container 400, bench 400, site 300 triangles.
"""

import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(__file__)
sys.path.append(os.path.join(HERE, ".."))
sys.path.append(os.path.join(HERE, "..", "workshop"))
sys.path.append(HERE)
import rover_kit_common as kit  # noqa: E402
import make_arm as arm_kit  # noqa: E402
import make_iris as iris_kit  # noqa: E402
import workshop_kit_common as ws  # noqa: E402

BODY, DARK, METAL, GOLD = 0, 1, 2, 3
ROVER_MATS = ("rover_body", "rover_dark", "rover_metal", "rover_gold")
MASS = {"scoop": 0.4, "container": 0.5, "container_full": 0.8, "bench_tray": 0.0}

# Container
JAR_R, JAR_H = 0.045, 0.10
LID_H = 0.018
GAUGE = (0.020, 0.052)           # width, height of the window
GAUGE_Z = 0.025
# Scoop
HANDLE_LEN, HANDLE_R = 0.24, 0.011
GRIP_Y = (-0.11, 0.0)
# Bench (kit coordinates, relative to the bench's centre)
BENCH_HALF = (0.35, 0.20)
BENCH_TOP = 0.90
TRAY_HALF = (0.30, 0.16)
LIP = 0.02
SHELF_TOP = 0.25
# Site
SITE_C = Vector((2.4, 2.6))      # IRIS frame
SITE_R = 0.55
POST_OFFSET = 0.75
TOOL_TIP = Vector((0.0, 0.22, -0.046))   # the scoop's tip from its grip (see make_scoop)
GRIP_DEPTH = 0.02                       # the hub end rests on the grip's top, this far above the grip centre

ws.PALETTE.update({"ir_patch": "5E5A52"})
ws.MATERIAL_SETTINGS.update({"ir_patch": (0.0, 0.95)})
ws.PREVIEW_COLORS.update({"ir_patch": "6F6A60"})


def flat_place(z0: float = 0.0):
    return lambda u, v, w: (u, v, z0 + w)


def circle(r: float, sides: int, phase: float = 0.0) -> list:
    return kit.circle_outline(r, sides, phase)


# --- Container (A13) --------------------------------------------------------------------------

def make_container(full: bool):
    name = "sample_container_full" if full else "sample_container"
    bm = bmesh.new()
    ring = circle(JAR_R, 12, math.pi / 12)
    body = kit.prism(bm, ring, flat_place(), 0.0, JAR_H)
    for f in body:
        f.material_index = BODY
    bmesh.ops.recalc_face_normals(bm, faces=body)
    for w0, w1, mat in ((0.0, 0.012, DARK), (0.062, 0.072, GOLD)):
        band = kit.prism(bm, circle(JAR_R + 0.002, 12, math.pi / 12), flat_place(), w0, w1, False, False)
        for f in band:
            f.material_index = mat
        bmesh.ops.recalc_face_normals(bm, faces=band)
    # The gauge window on the front (-Y) wall: a dark frame; the bar inside is container_fill
    wall = -JAR_R * math.cos(math.pi / 12) - 0.0005
    gw, gh = GAUGE
    frame = [bm.verts.new((x, wall, z)) for x, z in ((-gw / 2 - 0.004, GAUGE_Z - 0.004), (gw / 2 + 0.004, GAUGE_Z - 0.004),
                                                     (gw / 2 + 0.004, GAUGE_Z + gh + 0.004), (-gw / 2 - 0.004, GAUGE_Z + gh + 0.004))]
    f = bm.faces.new(frame)
    f.material_index = DARK
    f.normal_update()
    if f.normal.y > 0.0:
        f.normal_flip()
    # Hinge block at the back, under the lid's hinge
    kit.box(bm, (-0.02, 0.02), (JAR_R * 0.97, JAR_R * 0.97 + 0.008), (JAR_H - 0.02, JAR_H), METAL)
    jar = kit.mesh_object(name, bm, [kit.get_material(m) for m in ROVER_MATS])
    # Lid: a disc over the opening, a gold latch tab at the front, origin at the hinge
    hinge = Vector((0.0, JAR_R * 0.97 + 0.008, JAR_H))
    bm = bmesh.new()
    lid = kit.prism(bm, circle(JAR_R + 0.002, 12, math.pi / 12), lambda u, v, w: (u, v, JAR_H + w), 0.0, LID_H)
    for f in lid:
        f.material_index = 0
    bmesh.ops.recalc_face_normals(bm, faces=lid)
    kit.box(bm, (-0.012, 0.012), (-JAR_R - 0.008, -JAR_R + 0.01), (JAR_H + 0.004, JAR_H + 0.014), 1)
    disc = kit.prism(bm, circle(0.014, 8, math.pi / 8), lambda u, v, w: (u, v, JAR_H + LID_H + w), 0.0, 0.002)
    for f in disc:
        f.material_index = 2
    bmesh.ops.recalc_face_normals(bm, faces=disc)
    bmesh.ops.translate(bm, vec=-hinge, verts=bm.verts)
    lid_obj = kit.mesh_object("container_lid", bm, [kit.get_material(m) for m in ("rover_metal", "rover_gold", "rover_dark")])
    lid_obj.location = hinge
    lid_obj.parent = jar
    # Fill gauge: the bar, origin at the gauge's bottom
    level = 0.90 if full else 0.08
    bm = bmesh.new()
    kit.box(bm, (-gw / 2, gw / 2), (wall - 0.0015, wall), (0.0, gh * level), 0)
    bar = kit.mesh_object("container_fill", bm, [kit.get_material("rover_metal")])
    bar.data.transform(Matrix.Translation((0.0, 0.0, -GAUGE_Z)))
    bar.location = (0.0, 0.0, GAUGE_Z)
    bar.parent = jar
    bpy.context.view_layer.update()
    col = bmesh.new()
    kit.box(col, (-JAR_R, JAR_R), (-JAR_R, JAR_R), (0.0, JAR_H + LID_H))
    kit.make_collision_child(jar, col)
    kit.add_socket(jar, "anchor_pickup", (0.0, 0.0, 0.06))
    kit.add_socket(jar, "anchor_fill", (0.0, 0.0, JAR_H))
    kit.add_socket(jar, "anchor_stow", (0.0, 0.0, 0.0))
    return jar


# --- Scoop (A12) ------------------------------------------------------------------------------

def make_scoop():
    bm = bmesh.new()
    # Handle: a rod along +Y, a dark rubber grip over GRIP_Y
    place_y = lambda u, v, w: (u, w, v)           # outline (u, v) in X, Z; extruded along Y
    rod = kit.prism(bm, circle(HANDLE_R, 8, math.pi / 8), place_y, GRIP_Y[0] - 0.03, HANDLE_LEN - 0.12)
    for f in rod:
        f.material_index = METAL
    bmesh.ops.recalc_face_normals(bm, faces=rod)
    grip = kit.prism(bm, circle(HANDLE_R + 0.004, 8, math.pi / 8), place_y, GRIP_Y[0], GRIP_Y[1], True, True)
    for f in grip:
        f.material_index = DARK
    bmesh.ops.recalc_face_normals(bm, faces=grip)
    cap = kit.prism(bm, circle(HANDLE_R + 0.006, 8, math.pi / 8), place_y, GRIP_Y[0] - 0.03, GRIP_Y[0], True, True)
    for f in cap:
        f.material_index = GOLD
    bmesh.ops.recalc_face_normals(bm, faces=cap)
    # Bowl: a U-section trough bent 25 degrees down from the handle's end, open on top and at the tip
    tilt = Matrix.Rotation(math.radians(-25.0), 4, "X")
    start = Vector((0.0, HANDLE_LEN - 0.12, 0.0))
    # outer U: the section (x, z) extruded 0.10 along the bowl's axis, thick walls by two offset outlines
    outer = [(-0.036, 0.016), (-0.028, -0.004), (-0.014, -0.016), (0.014, -0.016), (0.028, -0.004), (0.036, 0.016),
             (0.030, 0.016), (0.022, -0.002), (0.011, -0.011), (-0.011, -0.011), (-0.022, -0.002), (-0.030, 0.016)]
    bowl_place = lambda u, v, w: tuple(start + tilt @ Vector((u, w, v)))
    faces = kit.prism(bm, outer, bowl_place, 0.0, 0.11)
    for f in faces:
        f.material_index = METAL
    bmesh.ops.recalc_face_normals(bm, faces=faces)
    obj = kit.mesh_object("sample_scoop", bm, [kit.get_material(m) for m in ROVER_MATS])
    bpy.context.view_layer.update()
    col = bmesh.new()
    kit.box(col, (-0.036, 0.036), (GRIP_Y[0] - 0.03, 0.21), (-0.07, 0.02))
    kit.make_collision_child(obj, col)
    tip = start + tilt @ Vector((0.0, 0.11, 0.0))
    kit.add_socket(obj, "anchor_grip", (0.0, 0.0, 0.0))
    kit.add_socket(obj, "anchor_tip", tip)
    kit.add_socket(obj, "anchor_pour", start + tilt @ Vector((0.0, 0.055, 0.0)))
    return obj, tip


# --- Sample bench (workshop) ------------------------------------------------------------------

def make_bench():
    bm = ws.new_bmesh()
    hx, hy = BENCH_HALF
    t = BENCH_TOP
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            x, y = sx * (hx - 0.04), sy * (hy - 0.04)
            ws.box(bm, (x - 0.025, x + 0.025), (y - 0.025, y + 0.025), (0.0, t - 0.04), 1)
    ws.box(bm, (-hx, hx), (-hy, hy), (t - 0.04, t), 0)                            # the top
    ws.box(bm, (-hx + 0.03, hx - 0.03), (-hy + 0.03, hy - 0.03), (SHELF_TOP - 0.03, SHELF_TOP), 1)     # the low shelf
    th, tw = TRAY_HALF[0], TRAY_HALF[1]
    for x, y in (((-th, th), (-tw, -tw + 0.012)), ((-th, th), (tw - 0.012, tw)), ((-th, -th + 0.012), (-tw, tw)),
                 ((th - 0.012, th), (-tw, tw))):
        ws.box(bm, x, y, (t, t + LIP), 1)                                           # the tray's lips
    ws.box(bm, (-th + 0.012, th - 0.012), (-tw + 0.012, tw - 0.012), (t, t + 0.004), 2)   # the tray floor (dark)
    # Pockets: a ring for each container and two cradle posts for the scoop (ws_accent)
    pockets = {"slot_sample_a": (-0.17, 0.0), "slot_sample_b": (0.0, 0.0)}
    for name, (px, py) in pockets.items():
        ws.ring(bm, (px, py), 0.052, 0.060, t + 0.004, 4)
    for px in (0.12, 0.26):
        ws.box(bm, (px - 0.012, px + 0.012), (-0.045, -0.025), (t + 0.004, t + 0.020), 4)
        ws.box(bm, (px - 0.012, px + 0.012), (0.025, 0.045), (t + 0.004, t + 0.020), 4)
    root = ws.make_object("ws_sample_bench", bm, ["ws_panel", "ws_frame", "ws_dark", "ws_label", "ws_accent"])
    # The low shelf (top at SHELF_TOP) holds the M3 thermal kit: the cover lying flat, turned so its
    # 0.40 m runs along the bench, and the heater beside it (make_m3_kit.py)
    for name, x in (("slot_thermal_cover", -0.08), ("slot_heater", 0.20)):
        ws.add_empty(root, name, (x, 0.0, SHELF_TOP))
    rest = t + 0.004
    ws.add_empty(root, "slot_sample_a", (-0.17, 0.0, rest))
    ws.add_empty(root, "slot_sample_b", (0.0, 0.0, rest))
    # The scoop lies across its cradle posts, grip at -Y, so its centre is over the posts' gap
    ws.add_empty(root, "slot_sample_scoop", (0.19, 0.0, rest))
    # The top, the low shelf (it holds the thermal kit) and the legs; open between them
    ws.collision_box(root, "ws_sample_bench", (-hx, hx), (-hy, hy), (t - 0.04, t))
    ws.collision_box(root, "ws_sample_bench_shelf", (-hx + 0.03, hx - 0.03), (-hy + 0.03, hy - 0.03), (SHELF_TOP - 0.03, SHELF_TOP))
    for i, (sx, sy) in enumerate(((-1, -1), (1, -1), (1, 1), (-1, 1))):
        x, y = sx * (hx - 0.04), sy * (hy - 0.04)
        ws.collision_box(root, "ws_sample_bench_leg_%d" % i, (x - 0.025, x + 0.025), (y - 0.025, y + 0.025), (0.0, t - 0.04))
    return root


# --- Sample site (A15) ------------------------------------------------------------------------

def make_site(park: Vector, name: str = "sample_site_near", centre: Vector = SITE_C, ground=None, post=None):
    """A reference patch in some frame: `ground(x, y)` is the terrain's height there (IRIS's frame and
    iris_kit.ground_local by default), `post` where anchor_marker_post goes (default: POST_OFFSET out)."""
    ground = ground or iris_kit.ground_local
    bm = ws.new_bmesh()
    rings = [0.0, 0.20, 0.38, SITE_R]
    sides = 16
    cx, cy = centre
    post = post or (cx + POST_OFFSET, cy - POST_OFFSET * 0.4)
    lifts = [0.020, 0.020, 0.012, 0.004]       # a shallow mound: the render terrain is finer than the 2 m physics grid

    def z(x, y, ring=0):
        return ground(x, y) + lifts[ring]

    centre = bm.verts.new((cx, cy, z(cx, cy)))
    grid = [[centre]]
    for i, r in enumerate(rings[1:], 1):
        grid.append([bm.verts.new((cx + r * math.cos(2 * math.pi * k / sides), cy + r * math.sin(2 * math.pi * k / sides),
                                   z(cx + r * math.cos(2 * math.pi * k / sides), cy + r * math.sin(2 * math.pi * k / sides), i)))
                     for k in range(sides)])
    for k in range(sides):
        n = (k + 1) % sides
        f = bm.faces.new((centre, grid[1][k], grid[1][n]))
        f.material_index = 0
        for ring in (1, 2):
            f = bm.faces.new((grid[ring][k], grid[ring + 1][k], grid[ring + 1][n], grid[ring][n]))
            f.material_index = 0 if ring == 1 else 1        # inner discs dark, the outer band dust
    for f in bm.faces:
        f.normal_update()
        if f.normal.z < 0.0:
            f.normal_flip()
    # Four corner marks, 6 cm legs 1 cm wide, on a square 0.62 m from the centre
    for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
        px, py = cx + sx * 0.62, cy + sy * 0.62
        for dx, dy in ((-sx * 0.06, 0.0), (0.0, -sy * 0.06)):
            x0, x1 = sorted((px, px + dx if dx else px))
            y0, y1 = sorted((py, py + dy if dy else py))
            half = 0.005
            xs = (x0 - (half if not dx else 0.0), x1 + (half if not dx else 0.0))
            ys = (y0 - (half if not dy else 0.0), y1 + (half if not dy else 0.0))
            ws.box(bm, xs, ys, (z(px, py, 3) - 0.002, z(px, py, 3) + 0.004), 2)
    root = ws.make_object(name, bm, ["ir_patch", "ir_dust", "ws_accent"], origin=(0.0, 0.0, 0.0))
    ws.add_empty(root, "anchor_sample", (cx, cy, z(cx, cy)))
    ws.add_empty(root, "anchor_marker_post", (post[0], post[1], ground(post[0], post[1])))
    ws.add_empty(root, "park_sample", (park.x, park.y, ground(park.x, park.y)))
    return root


def site_reach() -> tuple:
    """The scoop tip's reach on the ground ahead of the turret (J1 0): the hub end rests on the grip, so
    the hub is TOOL_TIP's drop plus the grip depth above the ground. Returns (near, far) metres from the
    yaw axis, the tip's distance."""
    ground = iris_kit.GROUND_Z
    hub_z = ground + (-TOOL_TIP.z) + GRIP_DEPTH
    ok = []
    for mm in range(150, 1100, 5):
        d = mm / 1000.0
        if iris_kit.ik_down(Vector((iris_kit.YAW_AXIS.x, iris_kit.YAW_AXIS.y + d - TOOL_TIP.y, hub_z))):
            ok.append(d)
    return (min(ok), max(ok)) if ok else (0.0, 0.0)


# --- Checks and previews ----------------------------------------------------------------------

def check_rover_part(obj, budget: int, rows: list) -> int:
    failures = 0
    tris = kit.triangle_count(obj) + sum(kit.triangle_count(c) for c in obj.children if c.type == "MESH" and "convcolonly" not in c.name)
    ok = tris <= budget
    failures += 0 if ok else 1
    rows.append("%s: %d triangles (budget %d)%s" % (obj.name, tris, budget, "" if ok else "  FAIL"))
    for o in [obj] + list(obj.children_recursive):
        kit.check_export_name(o.name)
        if o.type == "MESH" and "convcolonly" not in o.name:
            names = {m.name for m in o.data.materials}
            ok = names <= set(kit.PALETTE)
            failures += 0 if ok else 1
            if not ok:
                rows.append("%s materials %s  FAIL" % (o.name, sorted(names)))
        if o.type == "EMPTY":
            rows.append("%s: %s at %s" % (obj.name, o.name, tuple(round(c, 3) for c in o.location)))
    meshes = [o for o in [obj] + list(obj.children_recursive) if o.type == "MESH" and "convcolonly" not in o.name]
    lo, hi = ws.bounds(meshes)
    rows.append("%s size %.3f x %.3f x %.3f m, bottom at z %.4f" % (obj.name, hi.x - lo.x, hi.y - lo.y, hi.z - lo.z, lo.z))
    return failures


def export_rover(obj, name: str) -> None:
    kit.save_blend(os.path.join(kit.PARTS_DIR, name + ".blend"))
    kit.GODOT_IMPORT_SCRIPT = "res://src/robot/kit/rover_kit_import.gd"
    kit.export_part(obj, os.path.join(kit.EXPORT_DIR, name + ".glb"))


def main() -> None:
    previews = kit.preview_dir("sample_kit")
    rows = []
    failures = 0
    jars = {}
    # Scoop
    kit.reset_scene()
    scoop, tip = make_scoop()
    failures += check_rover_part(scoop, 250, rows)
    ok = abs(tip.y - TOOL_TIP.y) < 0.02 and abs(tip.z - TOOL_TIP.z) < 0.02
    failures += 0 if ok else 1
    rows.append("scoop tip %.3f, %.3f from the grip (site reach assumes %.2f, %.2f)%s" % (tip.y, tip.z, TOOL_TIP.y, TOOL_TIP.z, "" if ok else "  FAIL"))
    export_rover(scoop, "sample_scoop")
    scoop_shot = scoop
    if previews:
        kit.set_preview_colors(True)
        for name, d in (("three_quarter", (0.9, -0.8, 0.7)), ("side", (1.0, 0.0, 0.0)), ("top", (0.0, 0.0, 1.0))):
            kit.render_view(scoop, os.path.join(previews, "scoop_%s.png" % name), d, 0.36, name == "three_quarter", 0.9, (0.0, 0.1, -0.02))
        kit.set_preview_colors(False)
    # Containers
    for full in (False, True):
        kit.reset_scene()
        jar = make_container(full)
        failures += check_rover_part(jar, 400, rows)
        export_rover(jar, jar.name)
        if previews:
            kit.set_preview_colors(True)
            tag = "full" if full else "empty"
            kit.render_view(jar, os.path.join(previews, "container_%s_front.png" % tag), (0.4, -1.0, 0.45), 0.2, True, 0.7, (0.0, 0.0, 0.06))
            lid = next(c for c in jar.children if c.name == "container_lid")
            lid.rotation_euler.x = math.radians(-110.0)
            bpy.context.view_layer.update()
            kit.render_view(jar, os.path.join(previews, "container_%s_open.png" % tag), (0.4, -1.0, 0.8), 0.2, True, 0.7, (0.0, 0.0, 0.07))
            lid.rotation_euler.x = 0.0
            kit.set_preview_colors(False)
        jars[jar.name] = jar
    # Bench
    kit.reset_scene()
    bench = make_bench()
    failures += ws.check_part(bench, 400, (2 * BENCH_HALF[0], 2 * BENCH_HALF[1], BENCH_TOP + LIP), rows)
    ws.export(bench)
    ws.save("sample_bench")
    # The kit lies on the tray: containers in their pockets, the scoop across its posts
    if previews:
        def borrow(name: str, slot_name: str, turn: float = 0.0) -> None:
            before = set(bpy.data.objects)
            bpy.ops.import_scene.gltf(filepath=os.path.join(kit.EXPORT_DIR, name + ".glb"))
            new = [o for o in bpy.data.objects if o not in before]
            for o in [o for o in new if "convcolonly" in o.name.lower() or o.name.startswith("Collision")]:
                bpy.data.objects.remove(o)
            root = next(o for o in bpy.data.objects if o not in before and o.parent is None)
            slot = next(c for c in bench.children if c.name.startswith(slot_name)).location
            root.rotation_euler = (0.0, 0.0, math.radians(turn))
            root.location = slot
            bpy.context.view_layer.update()
        borrow("sample_container", "slot_sample_a")
        borrow("sample_container_full", "slot_sample_b")
        borrow("sample_scoop", "slot_sample_scoop", 90.0)
        for name, slot, turn in (("thermal_cover", "slot_thermal_cover", 90.0), ("thermal_heater", "slot_heater", 0.0)):
            if os.path.exists(os.path.join(kit.EXPORT_DIR, name + ".glb")):
                borrow(name, slot, turn)
        bpy.context.view_layer.update()
        ws.set_preview_colors(True)
        kit.set_preview_colors(True)
        keep = tuple(o for o in bpy.data.objects if o.type == "MESH" and "convcolonly" not in o.name)
        ws.render(bench, os.path.join(previews, "bench_three_quarter.png"), (0.7, -1.0, 0.6), 1.1, True, 2.2, (0.0, 0.0, 0.8), keep_visible=keep)
        ws.render(bench, os.path.join(previews, "bench_front.png"), (0.0, -1.0, 0.25), 1.1, False, 2.2, (0.0, 0.0, 0.8), keep_visible=keep)
        ws.set_preview_colors(False)
        kit.set_preview_colors(False)
    # Site
    kit.reset_scene()
    near, far = site_reach()
    d_mid = (near + far) / 2.0
    ok = far - near >= 0.15
    failures += 0 if ok else 1
    rows.append("scoop tip reaches the ground %.2f to %.2f m ahead of the turret's yaw axis (heading straight; J1 0)%s" % (
        near, far, "" if ok else "  FAIL"))
    # The rover heads +X (IRIS frame): its forward is IRIS +X, its right is IRIS -Y. The tip at d_mid ahead of the yaw axis.
    ahead = iris_kit.YAW_AXIS.y + d_mid
    # The yaw axis is 0.12 m left of the rover's centre line (rover x -0.12): IRIS y +0.12 with the rover heading +X
    park = Vector((SITE_C.x - ahead, SITE_C.y - 0.12))
    site = make_site(park)
    failures += ws.check_part(site, 300, None, rows)
    cx, cy = SITE_C
    zs = [iris_kit.ground_local(cx + SITE_R * math.cos(a), cy + SITE_R * math.sin(a)) for a in [k * math.pi / 8 for k in range(16)]]
    span = max(zs) - min(zs)
    ok = span <= 0.06
    failures += 0 if ok else 1
    rows.append("terrain under the patch varies %.0f mm across its 1.1 m%s" % (span * 1000.0, "" if ok else "  FAIL"))
    wx, wz = iris_kit.iris_to_world((cx, cy))
    rows.append("Godot: the patch sits in IRIS's frame (the Iris node's transform); centre at world (%.2f, %.3f, %.2f)" % (wx, iris_kit.H0 + iris_kit.ground_local(cx, cy), wz))
    px, pz = iris_kit.iris_to_world((cx + POST_OFFSET, cy - POST_OFFSET * 0.4))
    rows.append("Godot: marker post at world (%.2f, %.3f, %.2f)" % (px, iris_kit.H0 + iris_kit.ground_local(cx + POST_OFFSET, cy - POST_OFFSET * 0.4), pz))
    rows.append("park_sample (IRIS frame) (%.2f, %.2f), %.2f m from the patch's centre, %.2f m from IRIS's origin; Kite heads +X" % (
        park.x, park.y, math.hypot(park.x - cx, park.y - cy), math.hypot(*park)))
    ws.rk.GODOT_IMPORT_SCRIPT = ws.GODOT_IMPORT_SCRIPT
    os.makedirs(iris_kit.EXPORT_DIR, exist_ok=True)
    kit.GODOT_IMPORT_SCRIPT = ws.GODOT_IMPORT_SCRIPT
    kit.export_part(site, os.path.join(iris_kit.EXPORT_DIR, "sample_site_near.glb"))
    os.makedirs(iris_kit.PARTS_DIR, exist_ok=True)
    kit.save_blend(os.path.join(iris_kit.PARTS_DIR, "sample_site_near.blend"))
    if previews:
        ws.set_preview_colors(True)
        ws.render(site, os.path.join(previews, "site_top.png"), (0.0, 0.0, 1.0), 2.6, False, 1.0, (cx, cy, 0.0))
        ws.render(site, os.path.join(previews, "site_three_quarter.png"), (-0.6, -1.0, 0.5), 2.6, True, 6.0, (cx, cy, 0.0))
        ws.set_preview_colors(False)
    rows.append("masses for the part scenes (kg, estimates): scoop %.1f, container %.1f, full container %.1f" % (
        MASS["scoop"], MASS["container"], MASS["container_full"]))
    rows.append("ALL CHECKS OK" if failures == 0 else "%d CHECK FAILURES" % failures)
    print("\n".join("IRIS_KIT sample_kit " + r for r in rows))


if __name__ == "__main__":
    main()
