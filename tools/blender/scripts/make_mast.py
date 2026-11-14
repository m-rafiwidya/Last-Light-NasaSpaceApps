"""Generates mast_base (fixed) and mast_head (swappable, pan / tilt) for the rover kit
(ROVER_KIT.md 3.3, 5), checks the head's pan / tilt range and the mast's clearances on the
assembled rover, and renders previews.

    blender -b --factory-startup -P tools/blender/scripts/make_mast.py [-- --previews DIR | --no-previews]

Writes tools/blender/parts/mast_base.blend and mast_head.blend, game/res/models/rover_kit/
mast_base.glb and mast_head.glb, and previews in tools/blender/previews/mast/. Needs the chassis,
rocker, bogie, steer bracket and wheel .blend files for the assembled checks and previews.

Blender world coordinates, rover at rest:
    mast_base         origin (0.15, 0.35, 0.44) on the deck: keyed plug into the deck, foot, pole,
                      two sensor booms, top collar with the keyed recess at z 0.95
                      socket_mast_head (0.15, 0.35, 0.95)
    mast_head         the yoke, origin at its connector (0.15, 0.35, 0.95); Godot pans it about
                      the vertical axis (any angle). Keyed plug, base, crossbar, two arms.
    mast_head_camera  child of the yoke, origin on the horizontal tilt axis (0.15, 0.35, 1.05)
                      along X; Godot tilts it +-30 degrees. Camera box (rover_body), axle stubs,
                      one large hooded lens and two small stereo cameras (rover_dark lenses).
                      pivot_camera (0.15, 0.42, 1.05), just in front of the lens.
Budgets: mast_base 300, mast_head 500 triangles (ROVER_KIT.md 6.2).
"""

import itertools
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

sys.path.append(os.path.dirname(__file__))
import rover_kit_common as kit  # noqa: E402
import make_rocker_bogie as rb  # noqa: E402

BASE_BUDGET = 300
HEAD_BUDGET = 500
MIN_CLEARANCE = 0.020

AXIS_X, AXIS_Y = 0.15, 0.35            # mast axis on the deck
DECK_Z = 0.44
HEAD_Z = 0.95                          # socket_mast_head / mast_head origin
TILT_Z = 1.05                          # mast_head_camera origin, tilt axis along X
PIVOT_CAMERA = Vector((0.15, 0.42, 1.05))
TILT_LIMIT = 30.0                      # degrees

POLE_RADIUS = 0.02
FOOT_TOP = DECK_Z + 0.03
COLLAR_BOTTOM = HEAD_Z - 0.04

# Camera box (half sizes) and lenses
BOX_HALF = Vector((0.06, 0.04, 0.04))
LENS_RADIUS = 0.017
HOOD_RADIUS = 0.022
LENS_Z = TILT_Z + 0.01
STEREO_Z = TILT_Z - 0.025
STEREO_X = 0.03
ARM_X = (0.080, 0.092)                 # yoke arms, distance from the mast axis
ARM_HALF_DEPTH = 0.012

METAL, BODY, DARK = 0, 1, 2


def at_axis(x: float = 0.0, y: float = 0.0):
    """place(u, v, w) for a vertical round part on the mast axis: w = z, key (+v) toward +Y."""
    return lambda u, v, w: (AXIS_X + x + u, AXIS_Y + y + v, w)


def tag(faces: list, material: int) -> list:
    for f in faces:
        f.material_index = material
    return faces


def build_mast_base() -> bmesh.types.BMesh:
    bm = bmesh.new()
    # Keyed plug into the deck recess, foot, pole, collar with the recess for the head
    tag(kit.keyed_plug(bm, at_axis(), DECK_Z, DECK_Z - kit.CONNECTOR_DEPTH), METAL)
    tag(kit.cylinder(bm, at_axis(), DECK_Z, FOOT_TOP, kit.COLLAR_RADIUS), METAL)
    tag(kit.cylinder(bm, at_axis(), FOOT_TOP, COLLAR_BOTTOM, POLE_RADIUS), METAL)
    tag(kit.recessed_collar(bm, at_axis(), COLLAR_BOTTOM, HEAD_Z), METAL)
    # Sensor boom toward the rover's centre (-X) at z 0.78, and one to the rear (-Y) at z 0.72
    x0 = AXIS_X - POLE_RADIUS + 0.004
    kit.box(bm, (AXIS_X - 0.105, x0), (AXIS_Y - 0.006, AXIS_Y + 0.006), (0.774, 0.786), METAL)
    kit.box(bm, (AXIS_X - 0.13, AXIS_X - 0.105), (AXIS_Y - 0.012, AXIS_Y + 0.012), (0.768, 0.792), METAL)
    y0 = AXIS_Y - POLE_RADIUS + 0.004
    kit.box(bm, (AXIS_X - 0.006, AXIS_X + 0.006), (AXIS_Y - 0.105, y0), (0.714, 0.726), METAL)
    kit.box(bm, (AXIS_X - 0.012, AXIS_X + 0.012), (AXIS_Y - 0.13, AXIS_Y - 0.105), (0.708, 0.732), METAL)
    bmesh.ops.translate(bm, vec=-Vector((AXIS_X, AXIS_Y, DECK_Z)), verts=bm.verts)
    return bm


def build_yoke() -> bmesh.types.BMesh:
    bm = bmesh.new()
    tag(kit.keyed_plug(bm, at_axis(), HEAD_Z, HEAD_Z - kit.CONNECTOR_DEPTH), METAL)
    tag(kit.cylinder(bm, at_axis(), HEAD_Z, HEAD_Z + 0.02, kit.COLLAR_RADIUS), METAL)
    # The crossbar is part of the base: its underside rests on the mast's top collar (the pan
    # joint), which keeps it 25 mm below the camera box at full tilt
    kit.box(bm, (AXIS_X - ARM_X[1], AXIS_X + ARM_X[1]), (AXIS_Y - ARM_HALF_DEPTH, AXIS_Y + ARM_HALF_DEPTH),
            (HEAD_Z, HEAD_Z + 0.02), METAL)
    for sign in (-1.0, 1.0):
        x = tuple(sorted((AXIS_X + sign * ARM_X[0], AXIS_X + sign * ARM_X[1])))
        kit.box(bm, x, (AXIS_Y - ARM_HALF_DEPTH, AXIS_Y + ARM_HALF_DEPTH), (HEAD_Z, TILT_Z + 0.015), METAL)
    bmesh.ops.translate(bm, vec=-Vector((AXIS_X, AXIS_Y, HEAD_Z)), verts=bm.verts)
    return bm


def build_camera() -> bmesh.types.BMesh:
    """Camera box with axle stubs and lenses, in world coordinates moved to the tilt axis."""
    bm = bmesh.new()
    lo = Vector((AXIS_X, AXIS_Y, TILT_Z)) - BOX_HALF
    hi = Vector((AXIS_X, AXIS_Y, TILT_Z)) + BOX_HALF
    kit.box(bm, (lo.x, hi.x), (lo.y, hi.y), (lo.z, hi.z), BODY)
    # Axle stubs from the box sides to the yoke arms (the tilt joint)
    along_x = lambda u, v, w: (w, AXIS_Y + u, TILT_Z + v)  # noqa: E731
    for sign in (-1.0, 1.0):
        a, b = sorted((AXIS_X + sign * BOX_HALF.x, AXIS_X + sign * ARM_X[0]))
        tag(kit.cylinder(bm, along_x, a, b, 0.01, 6), METAL)
    # Large lens with a hood on the front face (+Y)
    along_y = lambda x, z: (lambda u, v, w: (x + u, w, z + v))  # noqa: E731
    front = hi.y
    tag(kit.cylinder(bm, along_y(AXIS_X, LENS_Z), front, front + 0.012, HOOD_RADIUS), BODY)
    tag(kit.cylinder(bm, along_y(AXIS_X, LENS_Z), front + 0.004, front + 0.0125, LENS_RADIUS), DARK)
    # Two small stereo cameras below it
    for sign in (-1.0, 1.0):
        x = AXIS_X + sign * STEREO_X
        kit.box(bm, (x - 0.011, x + 0.011), (front, front + 0.006), (STEREO_Z - 0.008, STEREO_Z + 0.008), BODY)
        tag(kit.cylinder(bm, along_y(x, STEREO_Z), front + 0.006, front + 0.008, 0.006, 6), DARK)
    bmesh.ops.translate(bm, vec=-Vector((AXIS_X, AXIS_Y, TILT_Z)), verts=bm.verts)
    return bm


def head_collision() -> bmesh.types.BMesh:
    """Convex box around the yoke and the camera's whole tilt sweep, relative to the yoke origin."""
    bm = bmesh.new()
    kit.box(bm, (-0.095, 0.095), (-0.065, 0.065), (0.0, (TILT_Z - HEAD_Z) + 0.06))
    return bm


def make_parts() -> dict:
    kit.reset_scene()
    mats = [kit.get_material(n) for n in ("rover_metal", "rover_body", "rover_dark")]
    base = kit.mesh_object("mast_base", build_mast_base(), mats[:1])
    base.location = (AXIS_X, AXIS_Y, DECK_Z)
    kit.add_socket(base, "socket_mast_head", (AXIS_X, AXIS_Y, HEAD_Z))
    kit.save_blend(os.path.join(kit.PARTS_DIR, "mast_base.blend"))
    kit.export_part(base, os.path.join(kit.EXPORT_DIR, "mast_base.glb"))
    base_tris = kit.triangle_count(base)

    kit.reset_scene()
    mats = [kit.get_material(n) for n in ("rover_metal", "rover_body", "rover_dark")]
    yoke = kit.mesh_object("mast_head", build_yoke(), mats)
    yoke.location = (AXIS_X, AXIS_Y, HEAD_Z)
    camera = kit.mesh_object("mast_head_camera", build_camera(), mats)
    camera.location = (AXIS_X, AXIS_Y, TILT_Z)
    kit.add_socket(camera, "pivot_camera", PIVOT_CAMERA)
    camera.parent = yoke
    camera.matrix_parent_inverse.identity()
    camera.location = (0.0, 0.0, TILT_Z - HEAD_Z)
    kit.make_collision_child(yoke, head_collision())
    kit.save_blend(os.path.join(kit.PARTS_DIR, "mast_head.blend"))
    kit.export_part(yoke, os.path.join(kit.EXPORT_DIR, "mast_head.glb"))
    head_tris = kit.triangle_count(yoke) + kit.triangle_count(camera)

    if base_tris > BASE_BUDGET or head_tris > HEAD_BUDGET:
        raise RuntimeError("over budget: mast_base %d, mast_head %d" % (base_tris, head_tris))
    return {"mast_base": base_tris, "mast_head": head_tris}


# --- Checks -------------------------------------------------------------------------------------

def pose_head(yoke, camera, pan_deg: float, tilt_deg: float) -> None:
    yoke.rotation_euler.z = math.radians(pan_deg)
    camera.rotation_euler.x = math.radians(tilt_deg)
    bpy.context.view_layer.update()


def assemble(with_drivetrain: bool):
    """Chassis + mast (+ both linkage sides) from the saved part files."""
    kit.reset_scene()
    for name in ("rover_body", "rover_metal", "rover_dark"):
        kit.get_material(name)
    chassis = kit.append_objects(os.path.join(kit.PARTS_DIR, "chassis.blend"), ["chassis"])[0]
    base = kit.append_objects(os.path.join(kit.PARTS_DIR, "mast_base.blend"), ["mast_base"])[0]
    yoke = kit.append_objects(os.path.join(kit.PARTS_DIR, "mast_head.blend"), ["mast_head"])[0]
    camera = [c for c in yoke.children if c.name.startswith("mast_head_camera")][0]
    base.location = rb.socket(chassis, "socket_mast")
    bpy.context.view_layer.update()
    yoke.location = rb.socket(base, "socket_mast_head")
    bpy.context.view_layer.update()
    kit.parent_keep_transform(base, chassis)
    kit.parent_keep_transform(yoke, base)
    sides = {side: rb.assemble(side, chassis) for side in ("L", "R")} if with_drivetrain else {}
    return chassis, base, yoke, camera, sides


# The rover's game camera (robot.tscn Camera3D): 90 degree vertical field of view. Checked for
# a 21:9 screen, wider than any expected, so the horizontal view is generous.
CAMERA_VFOV = 90.0
CAMERA_ASPECT = 21.0 / 9.0
CAMERA_NEAR = 0.001


def camera_view_check(yoke, camera) -> tuple:
    """Head geometry inside the game camera's view from pivot_camera (looking along the camera
    box's +Y, up = its +Z). Samples vertices, edge midpoints and face centres. Returns (number
    of samples in view, smallest angular margin to the view's edge in degrees)."""
    pivot = [c for c in camera.children if c.name.startswith("pivot_camera")][0]
    origin = pivot.matrix_world.translation
    basis = camera.matrix_world.to_3x3().normalized()
    right, forward, up = basis @ Vector((1, 0, 0)), basis @ Vector((0, 1, 0)), basis @ Vector((0, 0, 1))
    tan_v = math.tan(math.radians(CAMERA_VFOV / 2.0))
    tan_h = tan_v * CAMERA_ASPECT
    in_view, margin = 0, 180.0
    for obj in (yoke, camera):
        m = obj.matrix_world
        mesh = obj.data
        samples = [m @ v.co for v in mesh.vertices]
        samples += [m @ ((mesh.vertices[e.vertices[0]].co + mesh.vertices[e.vertices[1]].co) / 2.0) for e in mesh.edges]
        samples += [m @ poly.center for poly in mesh.polygons]
        for p in samples:
            d = p - origin
            z, x, y = d.dot(forward), d.dot(right), d.dot(up)
            if z > CAMERA_NEAR and abs(y) <= z * tan_v and abs(x) <= z * tan_h:
                in_view += 1
            # Angle outside the view (positive = outside by that much)
            out_v = math.degrees(math.atan2(abs(y), z)) - CAMERA_VFOV / 2.0
            out_h = math.degrees(math.atan2(abs(x), z)) - math.degrees(math.atan(tan_h))
            margin = min(margin, max(out_v, out_h))
    return in_view, margin


def run_checks() -> list:
    chassis, base, yoke, camera, _ = assemble(with_drivetrain=False)
    report = []
    # Designed joints: mast plug in the deck recess (and the foot on the deck), head plug in
    # the mast's top recess, the camera's axle stubs in the yoke arms
    deck_joint = rb.joint_zone(base, 2, kit.COLLAR_RADIUS + 0.001, (-0.01, 0.031))
    head_joint = rb.joint_zone(yoke, 2, kit.COLLAR_RADIUS + 0.001, (-0.01, 0.021))

    def axle_joint(p: Vector) -> bool:
        local = camera.matrix_world.inverted() @ p
        return math.hypot(local.y, local.z) < 0.0105 and BOX_HALF.x - 0.001 <= abs(local.x) <= ARM_X[1] + 0.001

    worst = {}
    margins = []
    pans = range(0, 360, 15)
    tilts = (-TILT_LIMIT, -15.0, 0.0, 15.0, TILT_LIMIT)
    for pan, tilt in itertools.product(pans, tilts):
        pose_head(yoke, camera, pan, tilt)
        pairs = {
            ("mast_head_camera", "mast_head (yoke)"): rb.pair_gap(camera, yoke, axle_joint),
            ("mast_head_camera", "mast_base"): rb.pair_gap(camera, base, None),
            ("mast_head (yoke)", "mast_base"): rb.pair_gap(yoke, base, head_joint),
            ("mast_head_camera", "chassis (deck, LGA)"): rb.pair_gap(camera, chassis, None),
            ("mast_head (yoke)", "chassis (deck, LGA)"): rb.pair_gap(yoke, chassis, None),
        }
        for key, gap in pairs.items():
            if key not in worst or gap < worst[key][0]:
                worst[key] = (gap, "pan %d, tilt %+.0f" % (pan, tilt))
        margins.append((camera_view_check(yoke, camera), "pan %d, tilt %+.0f" % (pan, tilt)))
    pose_head(yoke, camera, 0.0, 0.0)
    worst[("mast_base", "chassis (deck, LGA)")] = (rb.pair_gap(base, chassis, deck_joint), "fixed")

    failures = 0
    report.append("clearances (designed joints excluded), pan 0-345 step 15, tilt -30..+30:")
    for (a, b), (gap, config) in sorted(worst.items(), key=lambda item: item[1][0]):
        ok = gap >= MIN_CLEARANCE - 1e-4
        failures += not ok
        report.append("  %-18s vs %-20s %6.1f mm  %s  (worst at %s)" % (a, b, gap * 1000.0, "ok" if ok else "FAIL", config))
    visible = sum(view[0] for view, _ in margins)
    (_, margin), config = min(margins, key=lambda item: item[0][1])
    report.append("game camera (90 deg vertical, 21:9): head samples in view over all poses: %d; closest is %.1f deg outside the view (at %s)%s" % (
        visible, margin, config, "" if visible == 0 else "  FAIL: visible"))
    failures += visible > 0
    report.append("%s" % ("ALL MAST CHECKS OK" if failures == 0 else "%d MAST CHECK FAILURES" % failures))
    return report


def render_previews(previews: str) -> None:
    # Head alone, panned and tilted
    chassis, base, yoke, camera, _ = assemble(with_drivetrain=False)
    kit.set_preview_colors(True)
    for name, pan, tilt, direction, distance in (
        ("head_rest_three_quarter", 0, 0, (0.7, 1.0, 0.45), 0.75),
        ("head_front", 0, 0, (0.0, 1.0, 0.0), 0.75),
        ("head_side_tilt_up_30", 0, 30, (1.0, 0.0, 0.0), 0.75),
        ("head_side_tilt_down_30", 0, -30, (1.0, 0.0, 0.0), 0.75),
        ("head_panned_120_tilt_down_30", 120, -30, (0.7, 1.0, 0.45), 0.75),
    ):
        pose_head(yoke, camera, pan, tilt)
        kit.render_view(yoke, os.path.join(previews, name + ".png"), direction, 0.3, True, distance,
                        focus=(0.0, 0.0, 0.08))
    pose_head(yoke, camera, 0, 0)
    kit.render_view(base, os.path.join(previews, "mast_three_quarter.png"), (0.7, 1.0, 0.4), 0.9, True, 2.4,
                    focus=(0.0, 0.0, 0.3))
    kit.render_view(chassis, os.path.join(previews, "mast_on_deck_above.png"), (0.0, 0.0, 1.0), 1.1,
                    focus=(0.0, 0.0, 0.0))

    # Full rover with the mast
    chassis, base, yoke, camera, sides = assemble(with_drivetrain=True)
    ground = rb.ground_plane(0.0, 1.9)
    kit.set_preview_colors(True)  # assemble() starts a new scene with the real palette
    for name, direction, perspective, distance in (
        ("rover_three_quarter_front", (0.75, 1.0, 0.5), True, 5.0),
        ("rover_side", (1.0, 0.0, 0.0), False, 0.0),
        ("rover_front", (0.0, 1.0, 0.0), False, 0.0),
    ):
        kit.render_view(chassis, os.path.join(previews, name + ".png"), direction, 1.9, perspective, distance,
                        focus=(0.0, 0.0, 0.4), keep_visible=(ground,))
    pose_head(yoke, camera, 35, -20)
    kit.render_view(chassis, os.path.join(previews, "rover_head_panned_35_tilt_down_20.png"), (0.75, 1.0, 0.5),
                    1.9, True, 5.0, focus=(0.0, 0.0, 0.4), keep_visible=(ground,))
    kit.set_preview_colors(False)
    kit.render_view(chassis, os.path.join(previews, "rover_palette.png"), (0.75, 1.0, 0.5), 1.9, True, 5.0,
                    focus=(0.0, 0.0, 0.4), keep_visible=(ground,))


def main() -> None:
    previews = kit.preview_dir("mast")
    tris = make_parts()
    report = ["mast_base: %d triangles (budget %d), mast_head: %d triangles (budget %d)" % (
        tris["mast_base"], BASE_BUDGET, tris["mast_head"], HEAD_BUDGET)]
    report += run_checks()
    if previews:
        render_previews(previews)
    print("\n".join("ROVER_KIT " + line for line in report))


main()
