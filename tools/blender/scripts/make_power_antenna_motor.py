"""Generates the rover kit power_unit (BATTERY slot), antenna (pan base + tilting dish) and motor
(drive unit in the front hatch), checks their clearances on the complete rover, renders previews
and reports the triangle count of the whole kit (ROVER_KIT.md 3.3, 5, 6.2).

    blender -b --factory-startup -P tools/blender/scripts/make_power_antenna_motor.py [-- --previews DIR | --no-previews]

Writes tools/blender/parts/{power_unit,antenna,motor}.blend, game/res/models/rover_kit/
{power_unit,antenna,motor}.glb and previews in tools/blender/previews/power_antenna_motor/.
Needs every other kit part's .blend file.

Blender world coordinates, rover at rest:
    power_unit    origin (0.00, -0.45, 0.36) on the rear face: keyed plug, boss, strut, and a
                  0.14 x 0.35 m finned cylinder angled 40 degrees up and back (Curiosity's RTG)
    antenna       base, origin (-0.15, -0.25, 0.44) on the deck: keyed plug, turntable, post and
                  yoke; Godot pans it about the vertical (any angle)
    antenna_dish  child of the base, origin on the tilt axis (-0.15, -0.25, 0.58) along X; Godot
                  tilts it +-90 degrees. Stand-off, flat hexagonal dish 0.22 m across, gold boss.
    motor         origin (0.12, 0.33, 0.30) on its back face on the hatch floor: keyed plug, a
                  0.154 x 0.112 x 0.134 m body and four cooling ribs flush with the front face
Budgets: power_unit 400, antenna 250, motor 200 triangles.
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
import make_arm as arm_kit  # noqa: E402

BUDGETS = {"power_unit": 400, "antenna": 250, "motor": 200}
MIN_CLEARANCE = 0.020

# Power unit
POWER = Vector((0.0, -0.45, 0.36))
RTG_ANGLE = math.radians(40.0)                     # up from horizontal, pointing back
RTG_AXIS = Vector((0.0, -math.cos(RTG_ANGLE), math.sin(RTG_ANGLE)))
RTG_UP = Vector((0.0, math.sin(RTG_ANGLE), math.cos(RTG_ANGLE)))
RTG_START = Vector((0.0, -0.58, 0.30))
RTG_LENGTH = 0.35
RTG_RADIUS = 0.07
FIN_OUTER = 0.11
FIN_COUNT = 8

# Antenna
ANTENNA = Vector((-0.15, -0.25, 0.44))
TILT = Vector((-0.15, -0.25, 0.58))
DISH_RADIUS = 0.11                                 # hexagon circumradius (0.22 across)
DISH_BOTTOM = TILT.z + 0.04
DISH_THICKNESS = 0.015
TILT_LIMIT = 90.0

# Motor and the hatch pocket it fills
MOTOR = Vector((0.12, 0.33, 0.30))
POCKET_X = (0.04, 0.20)
POCKET_Z = (0.23, 0.37)
FRONT_FACE_Y = 0.45
FIT_GAP = 0.003
RIB_DEPTH = 0.008

BODY, METAL, DARK, GOLD = 0, 1, 2, 3


def tag(faces: list, material: int) -> list:
    for f in faces:
        f.material_index = material
    return faces


def solid(bm, outline, place, w0, w1, material):
    faces = kit.prism(bm, outline, place, w0, w1)
    bmesh.ops.recalc_face_normals(bm, faces=faces)
    return tag(faces, material)


def build_power_unit():
    bm = bmesh.new()
    along_y = lambda u, v, w: (POWER.x + u, w, POWER.z + v)  # noqa: E731  key (+v) toward +Z
    tag(kit.keyed_plug(bm, along_y, POWER.y, POWER.y + kit.CONNECTOR_DEPTH), DARK)
    tag(kit.cylinder(bm, along_y, POWER.y - 0.02, POWER.y, kit.COLLAR_RADIUS), DARK)
    # Strut from behind the boss (20 mm clear of the rear face) back to the cylinder
    kit.box(bm, (-0.02, 0.02), (RTG_START.y - 0.02, POWER.y - 0.02), (RTG_START.z, POWER.z + 0.01), DARK)

    def rtg(angle: float = 0.0):
        """place(u, v, w) along the RTG axis: w along it, (u, v) across it, turned by `angle`."""
        side = Vector((1.0, 0.0, 0.0))
        c, s = math.cos(angle), math.sin(angle)
        return lambda u, v, w: tuple(RTG_START + RTG_AXIS * w + side * (u * c - v * s) + RTG_UP * (u * s + v * c))

    solid(bm, kit.circle_outline(RTG_RADIUS, 8, math.pi / 8), rtg(), 0.0, RTG_LENGTH, DARK)
    for k in range(FIN_COUNT):
        fin = [(RTG_RADIUS - 0.005, -0.004), (FIN_OUTER, -0.004), (FIN_OUTER, 0.004), (RTG_RADIUS - 0.005, 0.004)]
        solid(bm, fin, rtg(2.0 * math.pi * k / FIN_COUNT), 0.03, RTG_LENGTH - 0.03, DARK)
    bmesh.ops.translate(bm, vec=-POWER, verts=bm.verts)
    return bm


def power_collision():
    """Convex hull points: the finned cylinder as an octagonal prism plus the boss."""
    bm = bmesh.new()
    side = Vector((1.0, 0.0, 0.0))
    for w in (0.0, RTG_LENGTH):
        for u, v in kit.circle_outline(FIN_OUTER, 8):
            bm.verts.new(RTG_START + RTG_AXIS * w + side * u + RTG_UP * v)
    for x in (-0.03, 0.03):
        for z in (POWER.z - 0.03, POWER.z + 0.03):
            bm.verts.new((x, POWER.y, z))
    bmesh.ops.convex_hull(bm, input=bm.verts)
    bmesh.ops.translate(bm, vec=-POWER, verts=bm.verts)
    return bm


def build_antenna_base():
    bm = bmesh.new()
    vertical = lambda u, v, w: (ANTENNA.x + u, ANTENNA.y + v, w)  # noqa: E731  key toward +Y
    tag(kit.keyed_plug(bm, vertical, ANTENNA.z, ANTENNA.z - kit.CONNECTOR_DEPTH), METAL)
    tag(kit.cylinder(bm, vertical, ANTENNA.z, ANTENNA.z + 0.02, 0.035), METAL)
    tag(kit.cylinder(bm, vertical, ANTENNA.z + 0.02, TILT.z - 0.03, 0.012, 6), METAL)
    # Fork: a bar under the hinge and two cheeks either side of the dish's hub, holding the axle
    kit.box(bm, (TILT.x - 0.024, TILT.x + 0.024), (TILT.y - 0.012, TILT.y + 0.012), (TILT.z - 0.035, TILT.z - 0.025), METAL)
    for sign in (-1.0, 1.0):
        x = tuple(sorted((TILT.x + sign * 0.014, TILT.x + sign * 0.024)))
        kit.box(bm, x, (TILT.y - 0.012, TILT.y + 0.012), (TILT.z - 0.035, TILT.z + 0.015), METAL)
    bmesh.ops.translate(bm, vec=-ANTENNA, verts=bm.verts)
    return bm


def build_antenna_dish():
    bm = bmesh.new()
    along_x = lambda u, v, w: (w, TILT.y + v, TILT.z + u)  # noqa: E731
    # Axle through the fork cheeks, hub between them, stand-off up to the dish
    tag(kit.cylinder(bm, along_x, TILT.x - 0.03, TILT.x + 0.03, 0.008, 6), METAL)
    tag(kit.cylinder(bm, along_x, TILT.x - 0.012, TILT.x + 0.012, 0.011, 6), METAL)
    kit.box(bm, (TILT.x - 0.010, TILT.x + 0.010), (TILT.y - 0.008, TILT.y + 0.008), (TILT.z + 0.01, DISH_BOTTOM), METAL)
    vertical = lambda u, v, w: (TILT.x + u, TILT.y + v, w)  # noqa: E731
    solid(bm, kit.circle_outline(DISH_RADIUS, 6), vertical, DISH_BOTTOM, DISH_BOTTOM + DISH_THICKNESS, BODY)
    solid(bm, kit.circle_outline(0.018, 6), vertical, DISH_BOTTOM + DISH_THICKNESS, DISH_BOTTOM + DISH_THICKNESS + 0.01, GOLD)
    bmesh.ops.translate(bm, vec=-TILT, verts=bm.verts)
    return bm


def antenna_collision():
    """Convex box around the base and the dish's whole pan / tilt sweep (relative to the base)."""
    bm = bmesh.new()
    r = DISH_RADIUS + 0.02
    kit.box(bm, (-r, r), (-r, r), (0.0, TILT.z - ANTENNA.z + r))
    return bm


def build_motor():
    bm = bmesh.new()
    along_y = lambda u, v, w: (MOTOR.x + u, w, MOTOR.z + v)  # noqa: E731  key (+v) toward +Z
    tag(kit.keyed_plug(bm, along_y, MOTOR.y, MOTOR.y - kit.CONNECTOR_DEPTH), DARK)
    x = (POCKET_X[0] + FIT_GAP, POCKET_X[1] - FIT_GAP)
    z = (POCKET_Z[0] + FIT_GAP, POCKET_Z[1] - FIT_GAP)
    kit.box(bm, x, (MOTOR.y, FRONT_FACE_Y - RIB_DEPTH), z, DARK)
    for rib_x in (0.07, 0.10, 0.14, 0.17):
        kit.box(bm, (rib_x - 0.004, rib_x + 0.004), (FRONT_FACE_Y - RIB_DEPTH, FRONT_FACE_Y),
                (z[0] + 0.012, z[1] - 0.012), DARK)
    bmesh.ops.translate(bm, vec=-MOTOR, verts=bm.verts)
    return bm


def motor_collision():
    bm = bmesh.new()
    kit.box(bm, (POCKET_X[0] + FIT_GAP - MOTOR.x, POCKET_X[1] - FIT_GAP - MOTOR.x), (0.0, FRONT_FACE_Y - MOTOR.y),
            (POCKET_Z[0] + FIT_GAP - MOTOR.z, POCKET_Z[1] - FIT_GAP - MOTOR.z))
    return bm


def materials() -> list:
    return [kit.get_material(n) for n in ("rover_body", "rover_metal", "rover_dark", "rover_gold")]


def make_parts() -> dict:
    tris = {}
    kit.reset_scene()
    power = kit.mesh_object("power_unit", build_power_unit(), materials())
    power.location = POWER
    kit.make_collision_child(power, power_collision())
    kit.save_blend(os.path.join(kit.PARTS_DIR, "power_unit.blend"))
    kit.export_part(power, os.path.join(kit.EXPORT_DIR, "power_unit.glb"))
    tris["power_unit"] = kit.triangle_count(power)

    kit.reset_scene()
    mats = materials()
    base = kit.mesh_object("antenna", build_antenna_base(), mats)
    base.location = ANTENNA
    dish = kit.mesh_object("antenna_dish", build_antenna_dish(), mats)
    dish.parent = base
    dish.matrix_parent_inverse.identity()
    dish.location = TILT - ANTENNA
    kit.make_collision_child(base, antenna_collision())
    kit.save_blend(os.path.join(kit.PARTS_DIR, "antenna.blend"))
    kit.export_part(base, os.path.join(kit.EXPORT_DIR, "antenna.glb"))
    tris["antenna"] = kit.triangle_count(base) + kit.triangle_count(dish)

    kit.reset_scene()
    motor = kit.mesh_object("motor", build_motor(), materials())
    motor.location = MOTOR
    kit.make_collision_child(motor, motor_collision())
    kit.save_blend(os.path.join(kit.PARTS_DIR, "motor.blend"))
    kit.export_part(motor, os.path.join(kit.EXPORT_DIR, "motor.glb"))
    tris["motor"] = kit.triangle_count(motor)

    for name, count in tris.items():
        if count > BUDGETS[name]:
            raise RuntimeError("%s is over budget: %d" % (name, count))
    return tris


# --- Complete rover ------------------------------------------------------------------------------

def assemble() -> dict:
    """The complete rover from the saved parts: drivetrain, mast, arm (stowed), power unit,
    antenna and motor."""
    scene = arm_kit.assemble(with_drivetrain=True)
    chassis = scene["chassis"]
    kit.get_material("rover_gold")
    for name, socket in (("power_unit", "socket_power"), ("antenna", "socket_antenna"), ("motor", "socket_motor")):
        obj = arm_kit.load(name + ".blend", name)
        obj.location = rb.socket(chassis, socket)
        bpy.context.view_layer.update()
        kit.parent_keep_transform(obj, chassis)
        scene[name] = obj
    scene["antenna_dish"] = arm_kit.child(scene["antenna"], "antenna_dish")
    arm_kit.pose_arm(scene["arm"], arm_kit.STOWED)
    return scene


def pose_antenna(scene: dict, pan: float, tilt: float) -> None:
    scene["antenna"].rotation_euler.z = math.radians(pan)
    scene["antenna_dish"].rotation_euler.x = math.radians(tilt)
    bpy.context.view_layer.update()


def pose_mast_head(scene: dict, pan: float, tilt: float) -> None:
    scene["mast_head"].rotation_euler.z = math.radians(pan)
    scene["mast_camera"].rotation_euler.x = math.radians(tilt)
    bpy.context.view_layer.update()


def tree(objs: list):
    return arm_kit.world_bvh(objs)


def report_line(rows: list, a: str, b: str, value: float, config: str, note: str = "") -> int:
    ok = value >= MIN_CLEARANCE - 1e-4
    rows.append("  %-26s vs %-28s %7.1f mm  %s  (worst at %s)%s" % (a, b, value * 1000.0, "ok" if ok else "FAIL", config, note))
    return 0 if ok else 1


def run_checks(scene: dict) -> list:
    rows, failures = [], 0
    chassis = scene["chassis"]

    # Power unit: rear wheels, brackets and bogies over steering and suspension; chassis outside the joint
    worst = {}
    for rocker, bogie, steer in itertools.product(rb.ROCKER_ANGLES, rb.BOGIE_ANGLES, rb.STEER_ANGLES):
        for side, parts in scene["sides"].items():
            rb.pose(parts, rocker, bogie, steer)
            for part in ("rear_wheel", "rear_bracket", "bogie"):
                value = rb.pair_gap(scene["power_unit"], parts[part], None)
                key = "%s %s" % (part.replace("_", " "), side)
                if key not in worst or value < worst[key][0]:
                    worst[key] = (value, "rocker %+.0f, bogie %+.0f, steer %+.0f" % (rocker, bogie, steer))
    for parts in scene["sides"].values():
        rb.pose(parts, 0.0, 0.0, 0.0)
    rows.append("power unit (rocker +-10, bogie +-15, steering +-30):")
    for key, (value, config) in sorted(worst.items(), key=lambda item: item[1][0]):
        failures += report_line(rows, "power_unit", key, value, config)
    joint = rb.joint_zone(scene["power_unit"], 1, kit.COLLAR_RADIUS + 0.001, (-0.021, 0.01))
    failures += report_line(rows, "power_unit", "chassis (outside the joint)", rb.pair_gap(scene["power_unit"], chassis, joint), "fixed")
    low = min(p.z for p in kit.world_vertices(scene["power_unit"]))
    rows.append("  power_unit lowest point z %.3f, %.0f mm above the ground" % (low, (low - rb.GROUND_Z) * 1000.0))

    # Antenna over its own range: deck + low-gain antenna (chassis), mast head over its range
    antenna_objs = [scene["antenna"], scene["antenna_dish"]]
    chassis_tree = tree([chassis])
    base_joint = rb.joint_zone(scene["antenna"], 2, 0.036, (-0.01, 0.021))
    head_poses = [(p, t) for p in range(0, 360, 30) for t in (-30.0, 0.0, 30.0)]
    head_trees = []
    for pan, tilt in head_poses:
        pose_mast_head(scene, pan, tilt)
        head_trees.append((tree([scene["mast_head"], scene["mast_camera"]]), "head pan %d tilt %+.0f" % (pan, tilt)))
    pose_mast_head(scene, 0.0, 0.0)
    worst = {}
    for pan, tilt in itertools.product(range(0, 360, 15), range(-90, 91, 15)):
        pose_antenna(scene, pan, tilt)
        config = "pan %d, tilt %+d" % (pan, tilt)
        dish = tree([scene["antenna_dish"]])
        checks = {("antenna_dish", "chassis (deck, LGA)"): (arm_kit.gap(dish, chassis_tree), config),
                  ("antenna_dish", "antenna base (outside the hinge)"): (rb.pair_gap(scene["antenna_dish"], scene["antenna"], rb.joint_zone(
                      scene["antenna_dish"], 0, 0.031, (-0.035, 0.035))), config)}
        for head, head_config in head_trees:
            checks[("antenna_dish", "mast head")] = min(checks.get(("antenna_dish", "mast head"), (1e9, "")),
                                                         (arm_kit.gap(dish, head), config + ", " + head_config))
        for key, value in checks.items():
            if key not in worst or value[0] < worst[key][0]:
                worst[key] = value
    pose_antenna(scene, 0.0, 0.0)
    worst[("antenna base", "chassis (outside the joint)")] = (rb.pair_gap(scene["antenna"], chassis, base_joint), "pans in place")
    rows.append("antenna (pan any angle, tilt +-90):")
    for (a, b), (value, config) in sorted(worst.items(), key=lambda item: item[1][0]):
        failures += report_line(rows, a, b, value, config)

    # Antenna and motor against the arm over the arm's whole range. The antenna is taken as its
    # swept envelope: a sphere around the tilt axis point holding the dish in every pose, and a
    # cylinder around the pan axis holding the base.
    dish_points = kit.world_vertices(scene["antenna_dish"])
    dish_radius = max((p - TILT).length for p in dish_points)
    base_points = kit.world_vertices(scene["antenna"])
    base_radius = max(math.hypot(p.x - ANTENNA.x, p.y - ANTENNA.y) for p in base_points)
    axis_samples = [Vector((ANTENNA.x, ANTENNA.y, ANTENNA.z + 0.01 * i)) for i in range(0, 16)]
    motor_tree = tree([scene["motor"]])
    arm = scene["arm"]
    groups = arm_kit.arm_groups(arm)

    def steps(lo, hi, step):
        count = max(1, round((hi - lo) / step))
        return [lo + (hi - lo) * i / count for i in range(count + 1)]

    grid = {"J1": steps(*arm_kit.RANGES["J1"], 5.0), "J2": steps(*arm_kit.RANGES["J2"], 15.0),
            "J3": steps(*arm_kit.RANGES["J3"], 15.0), "J4": steps(*arm_kit.RANGES["J4"], 22.0),
            "J5": steps(0.0, 54.0, 18.0)}
    worst = {}
    for values in itertools.product(*grid.values()):
        joints = dict(zip(grid.keys(), values))
        arm_kit.pose_arm(arm, joints)
        config = ", ".join("%s %+.0f" % kv for kv in joints.items())
        arm_tree = tree([o for objs in groups.values() for o in objs])
        dish_gap = arm_tree[0].find_nearest(TILT)[3] - dish_radius
        base_gap = min(arm_tree[0].find_nearest(p)[3] for p in axis_samples) - base_radius
        for key, value in ((("arm", "antenna dish envelope"), dish_gap), (("arm", "antenna base envelope"), base_gap),
                           (("arm", "motor"), arm_kit.gap(arm_tree, motor_tree))):
            if key not in worst or value < worst[key][0]:
                worst[key] = (value, config)
    arm_kit.pose_arm(arm, arm_kit.STOWED)
    rows.append("antenna and motor vs the arm over its whole range (%d poses):" % math.prod(len(v) for v in grid.values()))
    for (a, b), (value, config) in sorted(worst.items(), key=lambda item: item[1][0]):
        failures += report_line(rows, a, b, value, config)

    # Motor: fit in the pocket, flush front, stowed arm
    # Side walls only: the back face rests on the hatch floor (the mating face)
    fit = rb.pair_gap(scene["motor"], chassis, lambda p: p.y < MOTOR.y + 0.004)
    front = max(p.y for p in kit.world_vertices(scene["motor"]))
    rows.append("motor: gap to the hatch pocket's side walls %.1f mm (designed fit), front of the ribs at y %.3f (face at %.2f)" % (
        fit * 1000.0, front, FRONT_FACE_Y))
    failures += report_line(rows, "motor", "stowed arm", arm_kit.gap(motor_tree, tree([o for objs in groups.values() for o in objs] + [arm["mount"]])), "stowed")
    rows.append("ALL CHECKS OK" if failures == 0 else "%d CHECK FAILURES" % failures)
    return rows


def kit_triangles(scene: dict) -> tuple:
    """Triangles of every visible mesh on the complete rover, grouped by part name."""
    counts = {}
    for obj in bpy.context.scene.objects:
        if obj.type != "MESH" or "-convcolonly" in obj.name or obj.name.startswith("preview_"):
            continue
        name = obj.name.split(".")[0]
        counts[name] = counts.get(name, 0) + kit.triangle_count(obj)
    return sum(counts.values()), counts


def render_previews(scene: dict, previews: str) -> None:
    chassis = scene["chassis"]
    ground = rb.ground_plane(0.0, 2.2)
    kit.set_preview_colors(True)
    kit.render_view(scene["power_unit"], os.path.join(previews, "power_unit_rear_three_quarter.png"),
                    (-0.8, -1.0, 0.5), 0.5, True, 1.4, (0.0, -0.22, 0.05))
    kit.render_view(scene["motor"], os.path.join(previews, "motor_in_hatch.png"), (0.5, 1.0, 0.3), 0.5, True, 1.0,
                    (0.0, 0.06, 0.0))
    for pan, tilt in ((0, 0), (30, 60), (200, -90)):
        pose_antenna(scene, pan, tilt)
        kit.render_view(scene["antenna"], os.path.join(previews, "antenna_pan_%d_tilt_%+d.png" % (pan, tilt)),
                        (0.7, -1.0, 0.6), 0.5, True, 1.0, (0.0, 0.0, 0.15))
    pose_antenna(scene, 0, 0)
    kit.render_view(chassis, os.path.join(previews, "rover_rear_three_quarter_preview_colours.png"), (-0.8, -1.0, 0.55),
                    2.2, True, 5.4, (0.0, 0.0, 0.35), keep_visible=(ground,))
    kit.set_preview_colors(False)
    for name, direction, perspective in (("front_three_quarter", (0.8, 1.0, 0.55), True),
                                         ("rear_three_quarter", (-0.8, -1.0, 0.55), True),
                                         ("side", (-1.0, 0.0, 0.0), False),
                                         ("above", (0.0, 0.0, 1.0), False)):
        kit.render_view(chassis, os.path.join(previews, "rover_complete_%s.png" % name), direction, 2.3, perspective,
                        5.4, (0.0, 0.0, 0.35) if name != "above" else (0.0, 0.0, 0.0), keep_visible=(ground,))


def main() -> None:
    previews = kit.preview_dir("power_antenna_motor")
    tris = make_parts()
    report = ["triangles: " + ", ".join("%s %d (budget %d)" % (k, v, BUDGETS[k]) for k, v in tris.items())]
    scene = assemble()
    report += run_checks(scene)
    total, counts = kit_triangles(scene)
    report.append("whole kit on the complete rover: %d triangles (%s)" % (
        total, ", ".join("%s %d" % kv for kv in sorted(counts.items()))))
    if previews:
        render_previews(scene, previews)
    print("\n".join("ROVER_KIT " + line for line in report))


if __name__ == "__main__":
    main()
