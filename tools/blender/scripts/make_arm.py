"""Generates the rover kit arm (ROVER_KIT.md 3.3, 5): arm_shoulder (fixed mount + yaw turntable),
arm_upper, arm_forearm, arm_wrist and the swappable tool turret arm_tool. Checks the stowed pose and
the joint ranges on the full rover and renders previews.

    blender -b --factory-startup -P tools/blender/scripts/make_arm.py [-- --previews DIR | --no-previews]

Writes tools/blender/parts/arm_*.blend, game/res/models/rover_kit/arm_*.glb and previews in
tools/blender/previews/arm/. Needs the chassis, mast, rocker, bogie, steer bracket and wheel files.

Rest pose (straight forward, +Y), Blender world coordinates. Every joint turns about its own
connector axis (ROVER_KIT.md 2.5, moving joints):
    arm_shoulder       fixed mount, origin (-0.12, 0.45, 0.32) on the chassis front face
    arm_shoulder_yaw   child turntable, origin (-0.12, 0.53, 0.265), J1 yaw about Z
    arm_upper          origin (-0.09, 0.53, 0.345), J2 shoulder pitch about X
    arm_forearm        origin (-0.09, 0.89, 0.345), J3 elbow pitch about X
    arm_wrist          origin (-0.09, 1.22, 0.345), J4 wrist pitch about X
    arm_tool           origin (-0.125, 1.29, 0.345), J5 turret roll about Y; five tools around
                       a hub: drill (pointing down at J5 = 0), scoop, brush, camera, sensor
The upper arm and wrist sit on the -X side of their joints, the forearm on the +X side, so the
arm can fold its segments side by side.
"""

import itertools
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

sys.path.append(os.path.dirname(__file__))
import rover_kit_common as kit  # noqa: E402
import make_rocker_bogie as rb  # noqa: E402
import make_mast as mast  # noqa: E402

MIN_CLEARANCE = 0.020
GROUND_Z = -0.10

# Joint origins (connector centres) at rest
MOUNT = Vector((-0.12, 0.45, 0.32))
YAW = Vector((-0.12, 0.53, 0.265))
SHOULDER = Vector((-0.09, 0.53, 0.345))
ELBOW = Vector((-0.09, 0.89, 0.345))
WRIST = Vector((-0.09, 1.22, 0.345))
TOOL = Vector((-0.125, 1.29, 0.345))

HOUSING_RADIUS = 0.035
TUBE_RADIUS = 0.018
UPPER_X = -0.13        # upper arm tube (on the -X side of the shoulder / elbow joints)
FOREARM_X = -0.05      # forearm tube (+X side)
HUB_RADIUS = 0.03

# Joint ranges (degrees). J1 positive = toward the rover's left; J2-J4 positive = raise the
# outer part; J5 turns the turret (any angle).
RANGES = {
    # Left yaw is limited by the mast: with the arm folded back over the deck, yawing left swings
    # it right, toward the mast head (+20 degrees comes within 2 mm; +15 keeps 22 mm)
    "J1": (-20.0, 15.0),
    "J2": (-30.0, 90.0),
    "J3": (-90.0, 90.0),
    "J4": (-110.0, 110.0),
}
# Stowed lifts the turret 57 mm over a loaded cargo mount (ROVER_KIT.md 9); the old stowed pose is
# the latch pose, where the turret hub's end meets a cargo part's top face on the mount
STOWED = {"J1": 0.0, "J2": 90.0, "J3": 80.0, "J4": 100.0, "J5": 0.0}
LATCH = {"J1": 0.0, "J2": 90.0, "J3": 90.0, "J4": 90.0, "J5": 0.0}
REACH_DOWN = {"J1": 0.0, "J2": -10.0, "J3": -41.0, "J4": 51.0, "J5": 0.0}
REST = {"J1": 0.0, "J2": 0.0, "J3": 0.0, "J4": 0.0, "J5": 0.0}

# The motor hatch opening on the front face, plus the 20 mm clearance (x, z), and how far in
# front of the face the stowed arm must keep it clear
HATCH_X = (0.04 - 0.02, 0.20 + 0.02)
HATCH_Z = (0.23 - 0.02, 0.37 + 0.02)
FRONT_FACE_Y = 0.45

METAL, DARK = 0, 1


def along_x(y: float, z: float):
    return lambda u, v, w: (w, y + v, z + u)          # key (+v) toward +Y


def along_y(x: float, z: float):
    return lambda u, v, w: (x + u, w, z + v)          # key (+v) toward +Z


def along_z(x: float, y: float):
    return lambda u, v, w: (x + u, y + v, w)          # key (+v) toward +Y


def tag(faces: list, material: int) -> list:
    for f in faces:
        f.material_index = material
    return faces


def finish(bm, origin: Vector) -> bmesh.types.BMesh:
    bmesh.ops.translate(bm, vec=-origin, verts=bm.verts)
    return bm


def build_mount():
    bm = bmesh.new()
    kit.keyed_plug(bm, along_y(MOUNT.x, MOUNT.z), MOUNT.y, MOUNT.y - kit.CONNECTOR_DEPTH)
    kit.cylinder(bm, along_y(MOUNT.x, MOUNT.z), MOUNT.y, MOUNT.y + 0.02, kit.COLLAR_RADIUS)
    # Web from behind the boss down to the yaw bearing, 20 mm in front of the face
    kit.box(bm, (MOUNT.x - 0.015, MOUNT.x + 0.015), (MOUNT.y + 0.02, YAW.y), (YAW.z - 0.03, MOUNT.z - 0.02))
    kit.recessed_collar(bm, along_z(YAW.x, YAW.y), YAW.z - 0.03, YAW.z)
    return finish(bm, MOUNT)


def build_yaw():
    bm = bmesh.new()
    kit.keyed_plug(bm, along_z(YAW.x, YAW.y), YAW.z, YAW.z - kit.CONNECTOR_DEPTH)
    kit.cylinder(bm, along_z(YAW.x, YAW.y), YAW.z, YAW.z + 0.02, HOUSING_RADIUS)
    plate_x = (SHOULDER.x, SHOULDER.x + 0.015)
    kit.box(bm, plate_x, (SHOULDER.y - 0.015, SHOULDER.y + 0.015), (YAW.z + 0.005, SHOULDER.z))
    kit.recessed_collar(bm, along_x(SHOULDER.y, SHOULDER.z), plate_x[1], plate_x[0])
    return finish(bm, YAW)


def build_upper():
    bm = bmesh.new()
    kit.keyed_plug(bm, along_x(SHOULDER.y, SHOULDER.z), SHOULDER.x, SHOULDER.x + kit.CONNECTOR_DEPTH)
    kit.cylinder(bm, along_x(SHOULDER.y, SHOULDER.z), SHOULDER.x - 0.07, SHOULDER.x, HOUSING_RADIUS)
    kit.open_cylinder(bm, along_y(UPPER_X, SHOULDER.z), SHOULDER.y, ELBOW.y, TUBE_RADIUS)
    kit.recessed_collar(bm, along_x(ELBOW.y, ELBOW.z), ELBOW.x - 0.07, ELBOW.x, HOUSING_RADIUS)
    return finish(bm, SHOULDER)


def build_forearm():
    bm = bmesh.new()
    kit.keyed_plug(bm, along_x(ELBOW.y, ELBOW.z), ELBOW.x, ELBOW.x - kit.CONNECTOR_DEPTH)
    kit.cylinder(bm, along_x(ELBOW.y, ELBOW.z), ELBOW.x, ELBOW.x + 0.07, HOUSING_RADIUS)
    kit.open_cylinder(bm, along_y(FOREARM_X, ELBOW.z), ELBOW.y, WRIST.y, TUBE_RADIUS)
    kit.recessed_collar(bm, along_x(WRIST.y, WRIST.z), WRIST.x + 0.07, WRIST.x, HOUSING_RADIUS)
    return finish(bm, ELBOW)


def build_wrist():
    bm = bmesh.new()
    kit.keyed_plug(bm, along_x(WRIST.y, WRIST.z), WRIST.x, WRIST.x + kit.CONNECTOR_DEPTH)
    kit.cylinder(bm, along_x(WRIST.y, WRIST.z), WRIST.x - 0.07, WRIST.x, HOUSING_RADIUS)
    kit.open_cylinder(bm, along_y(TOOL.x, TOOL.z), WRIST.y, TOOL.y - 0.03, HUB_RADIUS)
    kit.recessed_collar(bm, along_y(TOOL.x, TOOL.z), TOOL.y - 0.03, TOOL.y)
    return finish(bm, WRIST)


# Tool turret: tools stick out radially around the hub's axis (Y) at 72 degree steps
TOOL_ANGLES = {"drill": 270.0, "scoop": 342.0, "brush": 54.0, "camera": 126.0, "sensor": 198.0}
HUB_LENGTH = 0.05


def radial(angle_deg: float):
    """place(u, v, w) in a tool's frame: w = distance out from the hub axis, u = sideways
    (tangential), v = along the hub axis (+Y)."""
    a = math.radians(angle_deg)
    centre = Vector((TOOL.x, TOOL.y + HUB_LENGTH / 2.0, TOOL.z))
    out = Vector((math.cos(a), 0.0, math.sin(a)))
    side = Vector((-math.sin(a), 0.0, math.cos(a)))
    along = Vector((0.0, 1.0, 0.0))
    return lambda u, v, w: tuple(centre + out * w + side * u + along * v)


def rect(half_u: float, half_v: float, v0: float = 0.0) -> list:
    return [(-half_u, v0 - half_v), (half_u, v0 - half_v), (half_u, v0 + half_v), (-half_u, v0 + half_v)]


def solid(bm, outline, place, w0, w1, material=METAL):
    faces = kit.prism(bm, outline, place, w0, w1)
    bmesh.ops.recalc_face_normals(bm, faces=faces)
    return tag(faces, material)


def lens(bm, place, w: float, radius: float, sides: int = 6):
    """Single outward-facing lens disc at distance w (rover_dark)."""
    face = bm.faces.new([bm.verts.new(place(u, v, w)) for u, v in kit.circle_outline(radius, sides)])
    face.material_index = DARK
    face.normal_update()
    outward = Vector(place(0, 0, w + 1.0)) - Vector(place(0, 0, w))
    if face.normal.dot(outward) < 0.0:
        face.normal_flip()


def build_tool(sensor=None):
    """The turret. `sensor(bm, place)` replaces the plain sensor tool (a variant, e.g. make_m3_kit.py's
    thermal turret); `place` is its radial() frame."""
    bm = bmesh.new()
    kit.keyed_plug(bm, along_y(TOOL.x, TOOL.z), TOOL.y, TOOL.y - kit.CONNECTOR_DEPTH)
    kit.cylinder(bm, along_y(TOOL.x, TOOL.z), TOOL.y, TOOL.y + HUB_LENGTH, HUB_RADIUS)
    p = radial(TOOL_ANGLES["drill"])
    solid(bm, kit.circle_outline(0.014, 6), p, 0.025, 0.07)
    solid(bm, kit.circle_outline(0.004, 4), p, 0.07, 0.095)
    p = radial(TOOL_ANGLES["scoop"])
    solid(bm, rect(0.018, 0.012), p, 0.025, 0.07)
    solid(bm, rect(0.02, 0.004, -0.008), p, 0.07, 0.088)
    p = radial(TOOL_ANGLES["brush"])
    solid(bm, kit.circle_outline(0.007, 6), p, 0.025, 0.06)
    solid(bm, kit.circle_outline(0.022, 8), p, 0.06, 0.07)
    p = radial(TOOL_ANGLES["camera"])
    solid(bm, rect(0.016, 0.014), p, 0.025, 0.06)
    lens(bm, p, 0.0605, 0.008)
    p = radial(TOOL_ANGLES["sensor"])
    if sensor:
        sensor(bm, p)
    else:
        solid(bm, kit.circle_outline(0.015, 8), p, 0.025, 0.065)
        solid(bm, kit.circle_outline(0.011, 6), p, 0.065, 0.069, DARK)
    return finish(bm, TOOL)


def tool_collision():
    bm = bmesh.new()
    kit.box(bm, (-0.1, 0.1), (-0.0, HUB_LENGTH), (-0.1, 0.1))
    return bm


PARTS = [
    # (blend / glb name, builder, origin, sockets)
    ("arm_upper", build_upper, SHOULDER, {"socket_arm_forearm": ELBOW}),
    ("arm_forearm", build_forearm, ELBOW, {"socket_arm_wrist": WRIST}),
    ("arm_wrist", build_wrist, WRIST, {"socket_arm_tool": TOOL}),
]


def make_parts() -> dict:
    tris = {}
    kit.reset_scene()
    metal = kit.get_material("rover_metal")
    mount = kit.mesh_object("arm_shoulder", build_mount(), [metal])
    mount.location = MOUNT
    yaw = kit.mesh_object("arm_shoulder_yaw", build_yaw(), [metal])
    yaw.location = YAW
    kit.add_socket(yaw, "socket_arm_upper", SHOULDER)
    yaw.parent = mount
    yaw.matrix_parent_inverse.identity()
    yaw.location = YAW - MOUNT
    kit.save_blend(os.path.join(kit.PARTS_DIR, "arm_shoulder.blend"))
    kit.export_part(mount, os.path.join(kit.EXPORT_DIR, "arm_shoulder.glb"))
    tris["arm_shoulder"] = kit.triangle_count(mount) + kit.triangle_count(yaw)

    for name, build, origin, sockets in PARTS:
        kit.reset_scene()
        obj = kit.mesh_object(name, build(), [kit.get_material("rover_metal")])
        obj.location = origin
        for socket, location in sockets.items():
            kit.add_socket(obj, socket, location)
        kit.save_blend(os.path.join(kit.PARTS_DIR, name + ".blend"))
        kit.export_part(obj, os.path.join(kit.EXPORT_DIR, name + ".glb"))
        tris[name] = kit.triangle_count(obj)

    kit.reset_scene()
    tool = kit.mesh_object("arm_tool", build_tool(), [kit.get_material("rover_metal"), kit.get_material("rover_dark")])
    tool.location = TOOL
    kit.make_collision_child(tool, tool_collision())
    # The hub's end face, along the wrist: a carried cargo part's anchor_latch goes here
    kit.add_socket(tool, "pivot_latch", TOOL + Vector((0.0, HUB_LENGTH, 0.0)))
    kit.save_blend(os.path.join(kit.PARTS_DIR, "arm_tool.blend"))
    kit.export_part(tool, os.path.join(kit.EXPORT_DIR, "arm_tool.glb"))
    tris["arm_tool"] = kit.triangle_count(tool)
    return tris


# --- Assembly and checks -------------------------------------------------------------------------

def load(blend: str, name: str):
    return kit.append_objects(os.path.join(kit.PARTS_DIR, blend), [name])[0]


def child(obj, prefix: str):
    return [c for c in obj.children if c.name.startswith(prefix)][0]


def assemble(with_drivetrain: bool = True) -> dict:
    """Chassis, mast (head at rest), arm and optionally both linkage sides, from the saved parts."""
    kit.reset_scene()
    for name in ("rover_body", "rover_metal", "rover_dark"):
        kit.get_material(name)
    chassis = load("chassis.blend", "chassis")
    base = load("mast_base.blend", "mast_base")
    head = load("mast_head.blend", "mast_head")
    base.location = rb.socket(chassis, "socket_mast")
    bpy.context.view_layer.update()
    head.location = rb.socket(base, "socket_mast_head")
    bpy.context.view_layer.update()
    kit.parent_keep_transform(base, chassis)
    kit.parent_keep_transform(head, base)

    mount = load("arm_shoulder.blend", "arm_shoulder")
    yaw = child(mount, "arm_shoulder_yaw")
    mount.location = rb.socket(chassis, "socket_arm")
    bpy.context.view_layer.update()
    chain = {"mount": mount, "yaw": yaw}
    parent, socket_name = yaw, "socket_arm_upper"
    for key, name, next_socket in (("upper", "arm_upper", "socket_arm_forearm"),
                                   ("forearm", "arm_forearm", "socket_arm_wrist"),
                                   ("wrist", "arm_wrist", "socket_arm_tool"),
                                   ("tool", "arm_tool", None)):
        obj = load(name + ".blend", name)
        obj.location = rb.socket(parent, socket_name)
        bpy.context.view_layer.update()
        kit.parent_keep_transform(obj, parent)
        chain[key] = obj
        parent, socket_name = obj, next_socket
    kit.parent_keep_transform(mount, chassis)
    sides = {side: rb.assemble(side, chassis) for side in ("L", "R")} if with_drivetrain else {}
    return {"chassis": chassis, "mast_base": base, "mast_head": head,
            "mast_camera": child(head, "mast_head_camera"), "arm": chain, "sides": sides}


def pose_arm(arm: dict, joints: dict) -> None:
    arm["yaw"].rotation_euler.z = math.radians(joints["J1"])
    arm["upper"].rotation_euler.x = math.radians(joints["J2"])
    arm["forearm"].rotation_euler.x = math.radians(joints["J3"])
    arm["wrist"].rotation_euler.x = math.radians(joints["J4"])
    arm["tool"].rotation_euler.y = math.radians(joints["J5"])
    bpy.context.view_layer.update()


# Pairs whose bounding boxes are further apart than this are not measured exactly: the box
# distance is a lower bound, and only gaps below it are reported in detail.
EXACT_BELOW = 0.06


def world_bvh(objects: list):
    """(BVH tree, world vertices, (min, max) bounds) of the objects' meshes in world space."""
    points, polygons = [], []
    for obj in objects:
        m = obj.matrix_world
        offset = len(points)
        points += [m @ v.co for v in obj.data.vertices]
        polygons += [[offset + i for i in poly.vertices] for poly in obj.data.polygons]
    lo = Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points)))
    hi = Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points)))
    return BVHTree.FromPolygons(points, polygons), points, (lo, hi)


def gap(a, b) -> float:
    """Smallest distance between two world_bvh() results, from both sides' vertices. Pairs
    whose bounds are at least EXACT_BELOW apart return the bounds' distance (a lower bound)."""
    (alo, ahi), (blo, bhi) = a[2], b[2]
    apart = Vector((max(blo[i] - ahi[i], alo[i] - bhi[i], 0.0) for i in range(3))).length
    if apart >= EXACT_BELOW:
        return apart
    best = 1e9
    for tree, points in ((a[0], b[1]), (b[0], a[1])):
        for p in points:
            hit = tree.find_nearest(p)
            if hit[0] is not None:
                best = min(best, hit[3])
    return best


def obstacles(scene: dict) -> dict:
    """Obstacles for the arm (front wheels and brackets as currently steered)."""
    result = {"chassis": [scene["chassis"]], "mast": [scene["mast_base"], scene["mast_head"], scene["mast_camera"]]}
    for side, parts in scene["sides"].items():
        result["front wheel " + side] = [parts["front_wheel"]]
        result["front bracket " + side] = [parts["front_bracket"]]
        result["rocker " + side] = [parts["rocker"]]
    return result


def arm_groups(arm: dict) -> dict:
    return {"turntable": [arm["yaw"]], "upper arm": [arm["upper"]], "forearm": [arm["forearm"]],
            "wrist": [arm["wrist"]], "tool": [arm["tool"]]}


def check_pose(scene: dict, obstacle_trees: dict) -> dict:
    """Gaps (m) between each moving arm part and each obstacle, and between non-adjacent arm
    parts. The fixed mount is attached to the chassis and checked once on its own."""
    arm = scene["arm"]
    trees = {name: world_bvh(objs) for name, objs in arm_groups(arm).items()}
    gaps = {}
    for part, tree in trees.items():
        for obstacle, otree in obstacle_trees.items():
            gaps[(part, obstacle)] = gap(tree, otree)
    mount = world_bvh([arm["mount"]])
    for a, b in (("upper arm", "wrist"), ("upper arm", "tool"), ("turntable", "wrist"), ("turntable", "tool"),
                 ("turntable", "forearm")):
        gaps[(a, b)] = gap(trees[a], trees[b])
    for part in ("forearm", "wrist", "tool"):
        gaps[(part, "mount")] = gap(trees[part], mount)
    return gaps


def lowest_z(objects: list) -> float:
    return min(p.z for obj in objects for p in kit.world_vertices(obj))


def hatch_blockers(arm: dict) -> int:
    """Arm vertices in front of the motor hatch opening (with 20 mm margin)."""
    count = 0
    for obj in arm.values():
        for p in kit.world_vertices(obj):
            if HATCH_X[0] <= p.x <= HATCH_X[1] and HATCH_Z[0] <= p.z <= HATCH_Z[1] and p.y >= FRONT_FACE_Y:
                count += 1
    return count


def run_checks() -> list:
    scene = assemble(with_drivetrain=True)
    arm, sides = scene["arm"], scene["sides"]
    report = []
    moving = [arm[k] for k in ("yaw", "upper", "forearm", "wrist", "tool")]

    # Fixed mount against the chassis, outside the plug / boss joint on the front face
    mount_joint = rb.joint_zone(arm["mount"], 1, kit.COLLAR_RADIUS + 0.001, (-0.01, 0.021))
    report.append("fixed mount vs chassis (outside the front-face joint): %.1f mm" % (
        rb.pair_gap(arm["mount"], scene["chassis"], mount_joint) * 1000.0))

    # Named poses
    for name, joints in (("stowed", STOWED), ("latch", LATCH), ("reaching down", REACH_DOWN), ("rest", REST)):
        pose_arm(arm, joints)
        line = "%s %s: lowest arm point z %.3f (%.0f mm above the ground)" % (
            name, joints, lowest_z(moving), (lowest_z(moving) - GROUND_Z) * 1000.0)
        if name == "stowed":
            in_view, margin = mast.camera_view_check(scene["mast_camera"], list(arm.values()))
            line += "; arm samples in the game camera's view (head at rest): %d (closest %.1f deg outside)" % (in_view, margin)
            scene["mast_head"].rotation_euler.z = 0.0
            scene["mast_camera"].rotation_euler.x = math.radians(-30.0)
            bpy.context.view_layer.update()
            in_view_down, _ = mast.camera_view_check(scene["mast_camera"], list(arm.values()))
            scene["mast_camera"].rotation_euler.x = 0.0
            bpy.context.view_layer.update()
            line += ", looking 30 deg down: %d" % in_view_down
            line += "; arm vertices in front of the motor hatch: %d" % hatch_blockers(arm)
        report.append(line)

    # Joint-range sweep at full steering both ways (and straight)
    def steps(lo: float, hi: float, step: float) -> tuple:
        count = max(1, round((hi - lo) / step))
        return tuple(lo + (hi - lo) * i / count for i in range(count + 1))

    # Every range end-to-end; J5 over one tool spacing (72 degrees), as the turret repeats
    grid = {
        "J1": steps(*RANGES["J1"], 5.0),
        "J2": steps(*RANGES["J2"], 15.0),
        "J3": steps(*RANGES["J3"], 15.0),
        "J4": steps(*RANGES["J4"], 22.0),
        "J5": steps(0.0, 54.0, 18.0),
    }
    worst = {}
    lowest = (1e9, "")
    poses = 0
    for steer in (-30.0, 0.0, 30.0):
        for parts in sides.values():
            rb.pose(parts, 0.0, 0.0, steer)
        obstacle_trees = {name: world_bvh(objs) for name, objs in obstacles(scene).items()}
        for values in itertools.product(*grid.values()):
            joints = dict(zip(grid.keys(), values))
            pose_arm(arm, joints)
            config = "steer %+.0f, %s" % (steer, ", ".join("%s %+.0f" % kv for kv in joints.items()))
            for key, value in check_pose(scene, obstacle_trees).items():
                if key not in worst or value < worst[key][0]:
                    worst[key] = (value, config)
            low = lowest_z(moving)
            if low < lowest[0]:
                lowest = (low, config)
            poses += 1
    for parts in sides.values():
        rb.pose(parts, 0.0, 0.0, 0.0)
    pose_arm(arm, REST)

    failures = 0
    report.append("joint-range sweep: %d arm poses x 3 steering angles (-30, 0, +30); steps %s" % (
        poses // 3, ", ".join("%s %d values %+.0f..%+.0f" % (k, len(v), v[0], v[-1]) for k, v in grid.items())))
    for (a, b), (value, config) in sorted(worst.items(), key=lambda item: item[1][0]):
        ok = value >= MIN_CLEARANCE - 1e-4
        failures += not ok
        if not ok or value < EXACT_BELOW:
            report.append("  %-10s vs %-16s %6.1f mm  %s  (worst at %s)" % (a, b, value * 1000.0, "ok" if ok else "FAIL", config))
    report.append("  (all other pairs >= 60 mm)")
    report.append("  lowest arm point over the sweep: z %.3f, %.0f mm below the rest ground (at %s)" % (
        lowest[0], (GROUND_Z - lowest[0]) * 1000.0, lowest[1]))
    report.append("%s" % ("ALL ARM CLEARANCES OK" if failures == 0 else "%d ARM CLEARANCE FAILURES" % failures))
    return report


def render_previews(previews: str) -> None:
    scene = assemble(with_drivetrain=True)
    arm = scene["arm"]
    ground = rb.ground_plane(0.0, 1.9)
    kit.set_preview_colors(True)
    focus = (0.0, 0.0, 0.35)
    for name, joints in (("rest", REST), ("stowed", STOWED), ("reaching_down", REACH_DOWN)):
        pose_arm(arm, joints)
        kit.render_view(scene["chassis"], os.path.join(previews, "rover_%s_three_quarter.png" % name),
                        (0.9, 1.0, 0.55), 2.2, True, 5.2, focus, keep_visible=(ground,))
        kit.render_view(scene["chassis"], os.path.join(previews, "rover_%s_side.png" % name),
                        (-1.0, 0.0, 0.0), 2.2, focus=(0.0, 0.25, 0.35), keep_visible=(ground,))
    pose_arm(arm, STOWED)
    kit.render_view(scene["chassis"], os.path.join(previews, "rover_stowed_front.png"), (0.0, 1.0, 0.0), 1.9,
                    focus=focus, keep_visible=(ground,))
    pose_arm(arm, REST)
    kit.render_view(arm["tool"], os.path.join(previews, "tool_turret.png"), (0.6, 1.0, 0.4), 0.3, True, 0.7,
                    (0.0, 0.025, 0.0))
    kit.render_view(arm["mount"], os.path.join(previews, "arm_rest_alone.png"), (0.9, 0.5, 0.6), 1.2, True, 2.4,
                    (0.0, 0.42, 0.02))
    kit.set_preview_colors(False)
    pose_arm(arm, REACH_DOWN)
    kit.render_view(scene["chassis"], os.path.join(previews, "rover_reaching_down_palette.png"), (0.9, 1.0, 0.55),
                    2.2, True, 5.2, focus, keep_visible=(ground,))


def main() -> None:
    previews = kit.preview_dir("arm")
    tris = make_parts()
    report = ["triangles: " + ", ".join("%s %d" % kv for kv in tris.items())]
    report += run_checks()
    if previews:
        render_previews(previews)
    print("\n".join("ROVER_KIT " + line for line in report))


if __name__ == "__main__":
    main()
