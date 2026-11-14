"""Generates the rover's cargo mount (ROVER_KIT.md 9, IRIS_KIT.md 5), checks it on the complete rover
with the cartridge loaded, and renders previews.

    blender -b --factory-startup -P tools/blender/scripts/iris/make_cargo_mount.py [-- --previews DIR | --no-previews]

Writes tools/blender/parts/cargo_mount.blend, game/res/models/rover_kit/cargo_mount.glb and previews
in tools/blender/previews/cargo_mount/. Needs every other rover kit part's .blend and cartridge.blend.

Rover frame:
    cargo_mount        origin socket_cargo (-0.125, 0.20, 0.44) on the deck: a 0.29 x 0.19 m plate on
                       four legs, its top at z 0.505, and four corner lips
    socket_cargo_item  (-0.125, 0.20, 0.505): a cargo part's origin goes here
Budget 120 triangles. Checks (20 mm unless said):
    the mount and a loaded cartridge against the stowed arm, the mast and its head at any pan and
    tilt, the antenna over its pan / tilt range and the deck's other parts;
    the latch pose: the arm's pivot_latch on the cartridge's anchor_latch;
    the arm over its joint ranges against the empty mount;
    the loaded cartridge out of the mast camera's view with the head at rest.
"""

import itertools
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

HERE = os.path.dirname(__file__)
sys.path.append(os.path.join(HERE, ".."))
sys.path.append(HERE)
import rover_kit_common as kit  # noqa: E402
import make_arm as arm_kit  # noqa: E402
import make_mast as mast  # noqa: E402
import make_power_antenna_motor as pam  # noqa: E402

BUDGET = 120
SOCKET = Vector((-0.125, 0.20, 0.44))
ITEM = Vector((-0.125, 0.20, 0.505))
PLATE = (0.145, 0.095)            # half sizes
LIP = 0.02
MIN_GAP = 0.020


def make_mount():
    bm = bmesh.new()
    x0, x1 = SOCKET.x - PLATE[0], SOCKET.x + PLATE[0]
    y0, y1 = SOCKET.y - PLATE[1], SOCKET.y + PLATE[1]
    kit.box(bm, (x0, x1), (y0, y1), (ITEM.z - 0.01, ITEM.z), 0)
    for x in (x0 + 0.01, x1 - 0.03):
        for y in (y0 + 0.01, y1 - 0.03):
            faces = kit.box(bm, (x, x + 0.02), (y, y + 0.02), (SOCKET.z, ITEM.z - 0.01), 0)
            for f in [f for f in faces if abs(f.normal.z) > 0.9]:
                bm.faces.remove(f)
    # Corner lips round the cartridge (it fits between them: they touch by design)
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            cx = SOCKET.x + sx * (PLATE[0] - 0.01)
            cy = SOCKET.y + sy * (PLATE[1] - 0.01)
            faces = kit.box(bm, (cx - 0.01, cx + 0.01), (cy - 0.01, cy + 0.01), (ITEM.z, ITEM.z + LIP), 0)
            for f in [f for f in faces if f.normal.z < -0.9]:
                bm.faces.remove(f)
    bmesh.ops.translate(bm, vec=-SOCKET, verts=bm.verts)
    obj = kit.mesh_object("cargo_mount", bm, [kit.get_material("rover_metal")])
    obj.location = SOCKET
    bpy.context.view_layer.update()
    kit.add_socket(obj, "socket_cargo_item", ITEM)
    return obj


def run_checks(scene: dict, mount, cartridge, rows: list) -> int:
    failures = 0
    tris = kit.triangle_count(mount)
    failures += 0 if tris <= BUDGET else 1
    rows.append("cargo_mount: %d triangles (budget %d)%s" % (tris, BUDGET, "" if tris <= BUDGET else "  FAIL"))
    arm = scene["arm"]
    moving = [arm[k] for k in ("yaw", "upper", "forearm", "wrist", "tool")]
    load = [mount, cartridge]

    def report(name, value, need=MIN_GAP):
        nonlocal failures
        ok = value >= need - 1e-4
        failures += 0 if ok else 1
        rows.append("%-60s %6.1f mm%s" % (name, value * 1000.0, "" if ok else "  FAIL"))

    arm_kit.pose_arm(arm, arm_kit.STOWED)
    report("mount + cartridge vs stowed arm (new stowed pose)", arm_kit.gap(arm_kit.world_bvh(moving), arm_kit.world_bvh(load)))
    report("cartridge top vs stowed turret hub end",
           (_latch_point(arm) - (cartridge.matrix_world.translation + Vector((0.0, 0.0, 0.08)))).length, 0.05)
    mast_parts = [scene["mast_base"], scene["mast_head"], scene["mast_camera"]]
    worst = 1e9
    for pan, tilt in itertools.product(range(0, 360, 15), (-30, 0, 30)):
        pam.pose_mast_head(scene, pan, tilt)
        worst = min(worst, arm_kit.gap(arm_kit.world_bvh(mast_parts), arm_kit.world_bvh(load)))
    pam.pose_mast_head(scene, 0, 0)
    report("mount + cartridge vs mast and head (any pan, tilt +-30)", worst)
    worst = 1e9
    for pan, tilt in itertools.product(range(0, 360, 15), (-90, -45, 0, 45, 90)):
        pam.pose_antenna(scene, pan, tilt)
        worst = min(worst, arm_kit.gap(arm_kit.world_bvh([scene["antenna"], scene["antenna_dish"]]), arm_kit.world_bvh(load)))
    pam.pose_antenna(scene, 0, 0)
    report("mount + cartridge vs antenna (any pan, tilt +-90)", worst)
    report("cartridge vs chassis (deck)", arm_kit.gap(arm_kit.world_bvh([scene["chassis"]]), arm_kit.world_bvh([cartridge])))
    # Latch pose: the hub end on the cartridge's top face
    arm_kit.pose_arm(arm, arm_kit.LATCH)
    anchor = next(o for o in cartridge.children if o.name == "anchor_latch").matrix_world.translation
    miss = (_latch_point(arm) - anchor).length
    ok = miss < 0.002
    failures += 0 if ok else 1
    rows.append("latch pose: pivot_latch %.1f mm from the cartridge's anchor_latch%s" % (miss * 1000.0, "" if ok else "  FAIL"))
    # The arm over its joint ranges against the empty mount
    worst = (1e9, None)
    grid = {"J1": (-20, -10, 0, 8, 15), "J2": tuple(range(-30, 91, 15)), "J3": tuple(range(-90, 91, 15)),
            "J4": tuple(range(-110, 111, 22)), "J5": (0, 36)}
    mount_tree = arm_kit.world_bvh([mount])
    for values in itertools.product(*grid.values()):
        joints = dict(zip(grid.keys(), values))
        arm_kit.pose_arm(arm, joints)
        g = arm_kit.gap(arm_kit.world_bvh(moving), mount_tree)
        if g < worst[0]:
            worst = (g, joints)
    arm_kit.pose_arm(arm, arm_kit.STOWED)
    report("arm over its joint ranges (%d poses) vs the empty mount" % math.prod(len(v) for v in grid.values()), worst[0])
    rows.append("    worst at %s" % worst[1])
    in_view, margin = mast.camera_view_check(scene["mast_camera"], load)
    ok = in_view == 0
    failures += 0 if ok else 1
    rows.append("loaded cartridge in the mast camera's view (head at rest): %d samples (closest %.1f deg outside)%s" % (
        in_view, margin, "" if ok else "  FAIL"))
    return failures


def _latch_point(arm) -> Vector:
    tool = arm["tool"]
    pivot = next((o for o in tool.children if o.name.startswith("pivot_latch")), None)
    return pivot.matrix_world.translation if pivot else tool.matrix_world @ Vector((0.0, arm_kit.HUB_LENGTH, 0.0))


def main() -> None:
    previews = kit.preview_dir("cargo_mount")
    kit.reset_scene()
    mount = make_mount()
    kit.save_blend(os.path.join(kit.PARTS_DIR, "cargo_mount.blend"))
    kit.export_part(mount, os.path.join(kit.EXPORT_DIR, "cargo_mount.glb"))
    scene = pam.assemble()
    mount = arm_kit.load("cargo_mount.blend", "cargo_mount")
    mount.location = SOCKET
    cartridge = arm_kit.load("cartridge.blend", "cartridge")
    cartridge.location = ITEM
    bpy.context.view_layer.update()
    rows = []
    failures = run_checks(scene, mount, cartridge, rows)
    if previews:
        kit.set_preview_colors(True)
        chassis = scene["chassis"]
        ground = pam.rb.ground_plane(0.0, 2.2)
        keep = (mount, cartridge, ground)
        kit.render_view(mount, os.path.join(previews, "cargo_mount_empty.png"), (0.7, -1.0, 0.6), 0.45, True, 1.2,
                        (0.0, 0.0, 0.03))
        for name, joints in (("stowed", arm_kit.STOWED), ("latch", arm_kit.LATCH)):
            arm_kit.pose_arm(scene["arm"], joints)
            kit.render_view(chassis, os.path.join(previews, "loaded_%s_chase.png" % name), (-0.6, -1.0, 0.75), 2.2, True,
                            4.2, (0.0, 0.0, 0.35), keep_visible=keep)
            kit.render_view(chassis, os.path.join(previews, "loaded_%s_side.png" % name), (-1.0, 0.0, 0.0), 1.6,
                            focus=(0.0, 0.2, 0.55), keep_visible=keep)
        arm_kit.pose_arm(scene["arm"], arm_kit.STOWED)
        kit.set_preview_colors(False)
    rows.append("ALL CHECKS OK" if failures == 0 else "%d CHECK FAILURES" % failures)
    print("\n".join("IRIS_KIT cargo_mount " + r for r in rows))


if __name__ == "__main__":
    main()
