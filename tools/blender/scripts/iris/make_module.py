"""Generates the replacement radio-power module (A10) and its cradle on Kite's cargo mount (A11),
checks them on the complete rover and at IRIS's module socket, and renders previews.

    blender -b --factory-startup -P tools/blender/scripts/iris/make_module.py [-- --previews DIR | --no-previews]

Writes tools/blender/parts/radio_module.blend + module_cradle.blend, game/res/models/rover_kit/
radio_module.glb + module_cradle.glb and previews in tools/blender/previews/radio_module/. Needs every
other rover kit part's .blend, cargo_mount.blend, and parts/iris/iris.blend (make_iris.py).

Rover frame, like the cartridge (IRIS_KIT.md 4, 5):
    radio_module   0.27 x 0.13 x 0.11 m case (0.282 m with the end grips), long side along X, origin
                   the middle of its bottom face at socket_cargo_item (-0.125, 0.20, 0.505).
                   At IRIS it turns 90 degrees about Z (J5): its long side along the socket's (IRIS's Y),
                   origin on anchor_module_seated.
        anchor_latch      (0, 0, 0.11): the top's centre, where the arm's hub end meets it. The module is
                          as tall as IRIS's socket is deep (0.12) less 10 mm, so seated, the hub end is
                          4 mm below the socket's rim: a hand's reach, like the cartridge in its port
        anchor_pickup     (0, 0, 0.055): its middle
        anchor_connector  (0, 0, 0): the underside's contact, which meets the bare connector on the
                          socket's floor (anchor_module_seated is 6 mm above that floor)
    module_cradle  origin socket_cargo (like cargo_mount): two guide rails on the mount's plate, flanking
                   the module's long sides (3 mm of play beside the cartridge, 13 mm beside the module: guides, not clamps),
                   with gold caps. Fixed to the mount; the cartridge rides between them as before.
Budgets: module 350 triangles, cradle 120. Masses (the part scenes; estimates, see IRIS_KIT.md 4.1):
module 12 kg, cradle 0.8 kg.
Checks (20 mm unless said): the loaded module, mount and cradle against the stowed arm, mast and head at any
pan / tilt, the antenna and the deck; the arm over its joint ranges against the empty mount with the
cradle; the module out of the mast camera's view; the latch pose reachable; the module at IRIS's socket
from its parking window (27 corners): hub reach for the approach and the seat, the module's turn and
its margin to the opening, the module and the rover clear of IRIS and each other on the way down.
"""

import itertools
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(__file__)
sys.path.append(os.path.join(HERE, ".."))
sys.path.append(HERE)
import rover_kit_common as kit  # noqa: E402
import make_arm as arm_kit  # noqa: E402
import make_mast as mast  # noqa: E402
import make_power_antenna_motor as pam  # noqa: E402
import make_cargo_mount as cm  # noqa: E402
import make_iris as iris_kit  # noqa: E402

MODULE_BUDGET = 350
CRADLE_BUDGET = 120
SOCKET = cm.SOCKET
ITEM = cm.ITEM
HX, HY, H = 0.135, 0.065, 0.11
CHAMFER = 0.012
GRIP = 0.006
MASS_MODULE, MASS_CRADLE = 12.0, 0.8
RAIL_Y = (0.080, 0.092)          # from the mount's centre line
RAIL_HALF = 0.115
RAIL_H, CAP_H = 0.045, 0.004
MIN_GAP = 0.020
BODY, DARK, METAL, GOLD = 0, 1, 2, 3


def outline(hx: float, hy: float, c: float) -> list:
    return [(hx - c, -hy), (hx, -hy + c), (hx, hy - c), (hx - c, hy), (-hx + c, hy), (-hx, hy - c), (-hx, -hy + c),
            (-hx + c, -hy)]


def place_at(z0: float):
    return lambda u, v, w: (ITEM.x + u, ITEM.y + v, ITEM.z + z0 + w)


def make_module():
    bm = bmesh.new()
    case = kit.prism(bm, outline(HX, HY, CHAMFER), place_at(0.0), 0.0, H)
    for f in case:
        f.material_index = BODY
    bmesh.ops.recalc_face_normals(bm, faces=case)
    # A dark plinth band and a gold power band, 2 mm proud
    for w0, w1, mat in ((0.0, 0.02, DARK), (0.05, 0.062, GOLD)):
        band = kit.prism(bm, outline(HX + 0.002, HY + 0.002, CHAMFER), place_at(0.0), w0, w1, False, False)
        for f in band:
            f.material_index = mat
        bmesh.ops.recalc_face_normals(bm, faces=band)
    # Ribbed grips on the two short ends: the handle for the gripper's assisted pick
    for sign in (-1.0, 1.0):
        x = ITEM.x + sign * HX
        for k in (-1, 0, 1):
            y = ITEM.y + k * 0.03
            xs = (x, x + GRIP) if sign > 0 else (x - GRIP, x)
            kit.box(bm, xs, (y - 0.008, y + 0.008), (ITEM.z + 0.022, ITEM.z + 0.088), METAL)
    # Top: a flush latch disc and a label panel (decals 0.5 mm proud)
    top = ITEM.z + H + 0.0005
    disc = [bm.verts.new((ITEM.x + 0.03 * math.cos(a), ITEM.y + 0.03 * math.sin(a), top))
            for a in [2 * math.pi * k / 8 for k in range(8)]]
    f = bm.faces.new(disc)
    f.material_index = METAL
    label = [bm.verts.new((ITEM.x + x, ITEM.y + y, top)) for x, y in ((-0.12, -0.04), (-0.05, -0.04), (-0.05, 0.04), (-0.12, 0.04))]
    f = bm.faces.new(label)
    f.material_index = DARK
    # A keyed corner: a gold chevron on the top beside the label so its turn is readable
    chev = [bm.verts.new((ITEM.x + x, ITEM.y + y, top)) for x, y in ((0.06, -0.03), (0.11, 0.0), (0.06, 0.03), (0.075, 0.0))]
    f = bm.faces.new(chev)
    f.material_index = GOLD
    bm.normal_update()
    for face in bm.faces:
        if abs(face.calc_center_median().z - top) < 1e-5 and face.normal.z < 0.0:
            face.normal_flip()
    obj = kit.mesh_object("radio_module", bm, [kit.get_material(m) for m in ("rover_body", "rover_dark", "rover_metal", "rover_gold")])
    obj.data.transform(Matrix.Translation(-ITEM))
    obj.location = ITEM
    bpy.context.view_layer.update()
    col = bmesh.new()
    kit.box(col, (ITEM.x - HX, ITEM.x + HX), (ITEM.y - HY, ITEM.y + HY), (ITEM.z, ITEM.z + H))
    kit.make_collision_child(obj, col)
    collider = obj.children[0]
    collider.data.transform(Matrix.Translation(-ITEM))
    collider.location = (0.0, 0.0, 0.0)
    kit.add_socket(obj, "anchor_latch", ITEM + Vector((0.0, 0.0, H)))
    kit.add_socket(obj, "anchor_pickup", ITEM + Vector((0.0, 0.0, H / 2.0)))
    kit.add_socket(obj, "anchor_connector", ITEM)
    return obj


def make_cradle():
    bm = bmesh.new()
    for sy in (-1.0, 1.0):
        y0, y1 = sorted((SOCKET.y + sy * RAIL_Y[0], SOCKET.y + sy * RAIL_Y[1]))
        faces = kit.box(bm, (SOCKET.x - RAIL_HALF, SOCKET.x + RAIL_HALF), (y0, y1), (ITEM.z, ITEM.z + RAIL_H), 0)
        for f in [f for f in faces if f.normal.z < -0.9]:
            bm.faces.remove(f)
        kit.box(bm, (SOCKET.x - RAIL_HALF, SOCKET.x + RAIL_HALF), (y0 - 0.002, y1 + 0.002),
                (ITEM.z + RAIL_H, ITEM.z + RAIL_H + CAP_H), 1)
    bmesh.ops.translate(bm, vec=-SOCKET, verts=bm.verts)
    obj = kit.mesh_object("module_cradle", bm, [kit.get_material("rover_metal"), kit.get_material("rover_gold")])
    obj.location = SOCKET
    bpy.context.view_layer.update()
    return obj


def hub_point(arm) -> Vector:
    return cm._latch_point(arm)


def basis_for(axis_x: Vector) -> Matrix:
    x = Vector((axis_x.x, axis_x.y, 0.0)).normalized()
    z = Vector((0.0, 0.0, 1.0))
    return Matrix(((x.x, -x.y, 0.0), (x.y, x.x, 0.0), (0.0, 0.0, 1.0))).to_4x4()


def run_rover_checks(scene: dict, mount, cradle, module, rows: list) -> int:
    failures = 0
    arm = scene["arm"]
    moving = [arm[k] for k in ("yaw", "upper", "forearm", "wrist", "tool")]
    load = [mount, cradle, module]

    def report(name, value, need=MIN_GAP):
        nonlocal failures
        ok = value >= need - 1e-4
        failures += 0 if ok else 1
        rows.append("%-62s %6.1f mm%s" % (name, value * 1000.0, "" if ok else "  FAIL"))

    arm_kit.pose_arm(arm, arm_kit.STOWED)
    report("mount + cradle + module vs stowed arm", arm_kit.gap(arm_kit.world_bvh(moving), arm_kit.world_bvh(load)))
    report("module top vs stowed turret hub end",
           (hub_point(arm) - (module.matrix_world.translation + Vector((0.0, 0.0, H)))).length)
    mast_parts = [scene["mast_base"], scene["mast_head"], scene["mast_camera"]]
    worst = 1e9
    for pan, tilt in itertools.product(range(0, 360, 15), (-30, 0, 30)):
        pam.pose_mast_head(scene, pan, tilt)
        worst = min(worst, arm_kit.gap(arm_kit.world_bvh(mast_parts), arm_kit.world_bvh(load)))
    pam.pose_mast_head(scene, 0, 0)
    report("mount + cradle + module vs mast and head (any pan, tilt +-30)", worst)
    worst = 1e9
    for pan, tilt in itertools.product(range(0, 360, 15), (-90, -45, 0, 45, 90)):
        pam.pose_antenna(scene, pan, tilt)
        worst = min(worst, arm_kit.gap(arm_kit.world_bvh([scene["antenna"], scene["antenna_dish"]]), arm_kit.world_bvh(load)))
    pam.pose_antenna(scene, 0, 0)
    report("mount + cradle + module vs antenna (any pan, tilt +-90)", worst)
    report("module vs chassis (deck)", arm_kit.gap(arm_kit.world_bvh([scene["chassis"]]), arm_kit.world_bvh([module])))
    # The arm over its joint ranges against the empty mount with the cradle on it
    worst = (1e9, None)
    grid = {"J1": (-20, -10, 0, 8, 15), "J2": tuple(range(-30, 91, 15)), "J3": tuple(range(-90, 91, 15)),
            "J4": tuple(range(-110, 111, 22)), "J5": (0, 36)}
    tree = arm_kit.world_bvh([mount, cradle])
    for values in itertools.product(*grid.values()):
        joints = dict(zip(grid.keys(), values))
        arm_kit.pose_arm(arm, joints)
        g = arm_kit.gap(arm_kit.world_bvh(moving), tree)
        if g < worst[0]:
            worst = (g, joints)
    arm_kit.pose_arm(arm, arm_kit.STOWED)
    report("arm over its joint ranges (%d poses) vs the mount with the cradle" % math.prod(len(v) for v in grid.values()), worst[0])
    rows.append("    worst at %s" % worst[1])
    in_view, margin = mast.camera_view_check(scene["mast_camera"], load)
    ok = in_view == 0
    failures += 0 if ok else 1
    rows.append("loaded module in the mast camera's view (head at rest): %d samples (closest %.1f deg outside)%s" % (
        in_view, margin, "" if ok else "  FAIL"))
    # The latch pose: the hub end on the module's top. Folded over the deck, it isn't the IK's
    # pointing-down pose: found by a search over the elbow joints (J1 and J5 at 0)
    latch = module.matrix_world.translation + Vector((0.0, 0.0, H))
    best = (1e9, None)
    for j2, j3, j4 in itertools.product(range(70, 91, 2), range(60, 101, 2), range(70, 111, 2)):
        joints = {"J1": 0.0, "J2": float(j2), "J3": float(j3), "J4": float(j4), "J5": 0.0}
        arm_kit.pose_arm(arm, joints)
        miss = (hub_point(arm) - latch).length
        if miss < best[0]:
            best = (miss, joints)
    arm_kit.pose_arm(arm, arm_kit.STOWED)
    ok = best[0] < 0.003
    failures += 0 if ok else 1
    j = best[1]
    rows.append("latch pose (hub end on anchor_latch): J1 %.0f J2 %.0f J3 %.0f J4 %.0f J5 %.0f, %.1f mm off (the cartridge's: 0 90 90 90 0)%s" % (
        j["J1"], j["J2"], j["J3"], j["J4"], j["J5"], best[0] * 1000.0, "" if ok else "  FAIL"))
    return failures


def run_iris_checks(scene: dict, module, rows: list, previews) -> int:
    """The module at IRIS's socket, from the socket's own parking window (27 corners)."""
    failures = 0
    arm = scene["arm"]
    root = kit.append_objects(os.path.join(iris_kit.PARTS_DIR, "iris.blend"), ["iris"])[0]
    bpy.context.view_layer.update()
    sock = next(o for o in root.children_recursive if o.name == "socket_module")
    seat = next(o for o in root.children_recursive if o.name == "anchor_module_seated")
    top = sock.matrix_world.translation.copy()
    seat_iris = seat.matrix_world.translation.copy()
    iris_meshes = [o for o in root.children_recursive if o.type == "MESH" and "convcolonly" not in o.name]
    iris_other = [o for o in iris_meshes if o.name != "iris_module_socket"]
    rover = [scene["chassis"], scene["mast_base"], scene["mast_head"]] + \
        [o for side in scene["sides"].values() for k, o in side.items() if k.endswith("wheel")]
    other_tree = arm_kit.world_bvh(iris_other)
    reach, turns, clear_iris, clear_rover = 0, [], 1e9, 1e9
    shot = None
    for d, bearing, turn in itertools.product((iris_kit.WINDOW_D[0], sum(iris_kit.WINDOW_D) / 2, iris_kit.WINDOW_D[1]),
                                              (iris_kit.WINDOW_BEARING[0], 0.0, iris_kit.WINDOW_BEARING[1]), (-10.0, 0.0, 10.0)):
        place = iris_kit.rescuer_pose(top, d, bearing, turn, iris_kit.MODULE_FACE_DEG)
        root.matrix_world = place
        bpy.context.view_layer.update()
        seated_hub = place @ (seat_iris + Vector((0.0, 0.0, H)))
        approach_hub = place @ (top + Vector((0.0, 0.0, iris_kit.SEAT_GAP + iris_kit.STROKE)))
        j_seat, j_approach = iris_kit.ik_down(seated_hub), iris_kit.ik_down(approach_hub)
        if not (j_seat and j_approach):
            continue
        reach += 1
        # The module's long side along the socket's (IRIS's Y), in the rover frame
        long_axis = place.to_3x3() @ Vector((0.0, 1.0, 0.0))
        yaw = basis_for(long_axis)
        # J5 is the turn from the module's stowed X (across the rover) to the socket's: any angle works
        angle = (math.degrees(math.atan2(long_axis.y, long_axis.x)) + 90.0) % 180.0 - 90.0   # the body is symmetric end to end
        turns.append(angle)
        for hub, joints in ((approach_hub, j_approach), (seated_hub, j_seat)):
            module.matrix_world = Matrix.Translation(hub - Vector((0.0, 0.0, H))) @ yaw
            arm_kit.pose_arm(arm, joints)
            bpy.context.view_layer.update()
            tree = arm_kit.world_bvh([module])
            clear_iris = min(clear_iris, arm_kit.gap(tree, other_tree))
            clear_rover = min(clear_rover, arm_kit.gap(tree, arm_kit.world_bvh(rover)))
        if previews and shot is None and d == sum(iris_kit.WINDOW_D) / 2 and bearing == 0.0 and turn == 0.0:
            shot = (module.matrix_world.copy(), j_seat, place.copy())
    ok = reach == 27
    failures += 0 if ok else 1
    rows.append("module at IRIS's socket: window corners where the hub reaches the approach and the seat: %d of 27%s" % (
        reach, "" if ok else "  FAIL"))
    rows.append("    J5 turn from the stowed pose to the socket's long side: %.0f to %.0f deg (the case is symmetric end to end; J5 turns any angle)" % (
        min(turns), max(turns)))
    for name, value in (("module on the way down vs IRIS (not its socket)", clear_iris), ("module on the way down vs the rover", clear_rover)):
        ok = value >= MIN_GAP - 1e-4
        failures += 0 if ok else 1
        rows.append("%-62s %6.1f mm%s" % (name, value * 1000.0, "" if ok else "  FAIL"))
    ox, oy = iris_kit.MODULE_OPENING[0], iris_kit.MODULE_OPENING[1]
    mx, my = HX + GRIP, HY + 0.002
    ok = ox - mx >= 0.010 and oy - my >= 0.010
    failures += 0 if ok else 1
    rows.append("module in the socket's opening (%.0f x %.0f mm): %.0f mm a side along, %.0f mm across (needs 10)%s" % (
        2000 * ox, 2000 * oy, 1000 * (ox - mx), 1000 * (oy - my), "" if ok else "  FAIL"))
    depth = iris_kit.MODULE_OPENING[2]
    rows.append("module %.0f mm tall in a %.0f mm deep socket: its top %.0f mm under the rim, seated" % (
        1000 * H, 1000 * depth, 1000 * (depth - H - iris_kit.SEAT_GAP)))
    if previews and shot:
        module.matrix_world, joints, place = shot
        root.matrix_world = place
        arm_kit.pose_arm(arm, joints)
        bpy.context.view_layer.update()
        kit.set_preview_colors(True)
        keep = tuple(iris_meshes) + (module,)
        for name, direction in (("three_quarter", (-0.8, -0.8, 0.6)), ("side", (0.0, -1.0, 0.15))):
            kit.render_view(scene["chassis"], os.path.join(previews, "seated_%s.png" % name), direction, 1.3, True, 3.0,
                            (0.1, 0.9, 0.45), keep_visible=keep)
        kit.set_preview_colors(False)
    arm_kit.pose_arm(arm, arm_kit.STOWED)
    return failures


def run_part_checks(module, cradle, rows: list) -> int:
    failures = 0
    for obj, budget in ((module, MODULE_BUDGET), (cradle, CRADLE_BUDGET)):
        tris = kit.triangle_count(obj)
        ok = tris <= budget
        failures += 0 if ok else 1
        rows.append("%s: %d triangles (budget %d)%s" % (obj.name, tris, budget, "" if ok else "  FAIL"))
        names = {m.name for m in obj.data.materials}
        ok = names <= set(kit.PALETTE)
        failures += 0 if ok else 1
        rows.append("%s materials %s%s" % (obj.name, sorted(names), "" if ok else "  FAIL"))
        for child in obj.children:
            kit.check_export_name(child.name)
            if child.type == "EMPTY":
                rows.append("%s: %s at %s from the origin" % (obj.name, child.name, tuple(round(c, 3) for c in child.location)))
    verts = kit.world_vertices(module)
    lo = Vector((min(v.x for v in verts), min(v.y for v in verts), min(v.z for v in verts)))
    hi = Vector((max(v.x for v in verts), max(v.y for v in verts), max(v.z for v in verts)))
    rows.append("module %.3f x %.3f x %.3f m with grips and bands (case 0.270 x 0.130 x 0.110)" % (hi.x - lo.x, hi.y - lo.y, hi.z - lo.z))
    ok = abs(lo.z - ITEM.z) < 1e-6 and hi.z - ITEM.z <= H + 0.001
    failures += 0 if ok else 1
    rows.append("module origin on the bottom face, top at +%.4f m%s" % (hi.z - ITEM.z, "" if ok else "  FAIL"))
    # The shelf (WORKSHOP_KIT.md 6.3, level 3): 0.18 m deep less the 20 mm back panel and 20 mm label rail
    ok = hi.y - lo.y <= 0.136
    failures += 0 if ok else 1
    rows.append("module depth %.0f mm on the 140 mm usable top shelf%s" % ((hi.y - lo.y) * 1000.0, "" if ok else "  FAIL"))
    return failures


def main() -> None:
    previews = kit.preview_dir("radio_module")
    kit.reset_scene()
    module = make_module()
    kit.save_blend(os.path.join(kit.PARTS_DIR, "radio_module.blend"))
    kit.export_part(module, os.path.join(kit.EXPORT_DIR, "radio_module.glb"))
    kit.reset_scene()
    cradle = make_cradle()
    kit.save_blend(os.path.join(kit.PARTS_DIR, "module_cradle.blend"))
    kit.export_part(cradle, os.path.join(kit.EXPORT_DIR, "module_cradle.glb"))
    scene = pam.assemble()
    mount = arm_kit.load("cargo_mount.blend", "cargo_mount")
    mount.location = SOCKET
    cradle = arm_kit.load("module_cradle.blend", "module_cradle")
    cradle.location = SOCKET
    module = arm_kit.load("radio_module.blend", "radio_module")
    module.location = ITEM
    bpy.context.view_layer.update()
    rows = []
    failures = run_part_checks(module, cradle, rows)
    failures += run_rover_checks(scene, mount, cradle, module, rows)
    if previews:
        kit.set_preview_colors(True)
        chassis = scene["chassis"]
        ground = pam.rb.ground_plane(0.0, 2.2)
        keep = (mount, cradle, module, ground)
        for name, d in (("three_quarter", (0.8, -1.0, 0.7)), ("top", (0.0, 0.0, 1.0)), ("end", (1.0, 0.0, 0.0)),
                        ("side", (0.0, -1.0, 0.0))):
            kit.render_view(module, os.path.join(previews, "module_%s.png" % name), d, 0.38, name == "three_quarter", 1.1,
                            (0.0, 0.0, 0.055))
        kit.render_view(cradle, os.path.join(previews, "cradle_empty.png"), (0.7, -1.0, 0.6), 0.45, True, 1.2, (0.0, 0.0, 0.1),
                        keep_visible=(mount, cradle))
        kit.render_view(chassis, os.path.join(previews, "loaded_chase.png"), (-0.6, -1.0, 0.75), 2.2, True, 4.2,
                        (0.0, 0.0, 0.35), keep_visible=keep)
        kit.render_view(chassis, os.path.join(previews, "loaded_side.png"), (-1.0, 0.0, 0.0), 1.6, focus=(0.0, 0.2, 0.55),
                        keep_visible=keep)
        kit.set_preview_colors(False)
    failures += run_iris_checks(scene, module, rows, previews)
    rows.append("ALL CHECKS OK" if failures == 0 else "%d CHECK FAILURES" % failures)
    print("\n".join("IRIS_KIT radio_module " + r for r in rows))


if __name__ == "__main__":
    main()
