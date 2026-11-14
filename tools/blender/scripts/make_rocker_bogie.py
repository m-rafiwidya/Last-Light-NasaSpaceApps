"""Generates rocker_L / rocker_R and bogie_L / bogie_R for the rover kit (ROVER_KIT.md 3.2-3.4),
then assembles one full side (rocker, bogie, both steer brackets, three wheels) to check ground
contact and the section 3.4 clearances.

    blender -b --factory-startup -P tools/blender/scripts/make_rocker_bogie.py [-- --previews DIR | --no-previews]

Writes tools/blender/parts/rocker.blend and bogie.blend, game/res/models/rover_kit/rocker_*.glb
and bogie_*.glb, and previews in tools/blender/previews/rocker_bogie/. Needs wheel.blend and
steer_bracket.blend for the assembly.

Right side, Blender world coordinates at rest (the left side mirrors x):
    rocker  origin (0.25, 0.00, 0.27) on the chassis side, beam in the x band 0.27-0.30
            main pivot housing + keyed plug into the chassis; beam bogie pivot -> main pivot ->
            (0.33, 0.32) -> (0.52, 0.32); horn out to the front steering actuator, collar with
            the keyed recess opening at z 0.30; recessed bogie pivot housing
            socket_steer_front (0.50, 0.50, 0.30), socket_bogie (0.30, -0.25, 0.20)
    bogie   origin (0.30, -0.25, 0.20) on the rocker, beam in the x band 0.32-0.36
            pivot housing + keyed plug into the rocker; beam middle axle -> pivot ->
            (-0.36, 0.32) -> (-0.52, 0.32); horn out to the rear steering actuator; middle
            axle stub with the keyed recess for the wheel
            socket_wheel_mid (0.50, 0.00, 0.05), socket_steer_rear (0.50, -0.50, 0.30)
Budget: 230 triangles each (ROVER_KIT.md 6.2).
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

TRIANGLE_BUDGET = 230
MIN_CLEARANCE = 0.020

HOUSING_RADIUS = 0.035
BEAM_HALF_HEIGHT = 0.02
HORN_HALF_WIDTH = 0.02
HORN_Z = (0.30, 0.34)

ROCKER_ORIGIN = Vector((0.25, 0.00, 0.27))
ROCKER_BAND = (0.27, 0.30)
MAIN_PIVOT = (0.00, 0.27)              # (y, z)
BOGIE_PIVOT = (-0.25, 0.20)
ROCKER_LINE = [BOGIE_PIVOT, MAIN_PIVOT, (0.33, 0.32), (0.52, 0.32)]

BOGIE_ORIGIN = Vector((0.30, -0.25, 0.20))
BOGIE_BAND = (0.32, 0.36)
MIDDLE_AXLE = (0.00, 0.05)
BOGIE_LINE = [MIDDLE_AXLE, BOGIE_PIVOT, (-0.36, 0.32), (-0.52, 0.32)]

STEER_AXIS_X = 0.50
FRONT_STEER_Y, REAR_STEER_Y = 0.50, -0.50
WHEEL_X = (0.38, 0.62)
GROUND_Z = -0.10
CHASSIS_SIDE_X = 0.25

# Motion used for the clearance check
ROCKER_ANGLES = (-10.0, 0.0, 10.0)
BOGIE_ANGLES = (-15.0, 0.0, 15.0)
STEER_ANGLES = (-30.0, -15.0, 0.0, 15.0, 30.0)


def along_x(y: float, z: float, key_up_y: bool = True):
    """place(u, v, w) for a connector along X at (y, z): w = x. The key (+v) points +Y
    (ROVER_KIT.md 2.5), or +Z for wheel axles."""
    if key_up_y:
        return lambda u, v, w: (w, y + v, z + u)
    return lambda u, v, w: (w, y + u, z + v)


def vertical(x: float, y: float):
    """place(u, v, w) for a vertical connector at (x, y): w = z, key (+v) toward +Y."""
    return lambda u, v, w: (x + u, y + v, w)


def beam(bm, line: list, band: tuple) -> list:
    outline = kit.thick_polyline(line, BEAM_HALF_HEIGHT)
    faces = kit.prism(bm, outline, lambda u, v, w: (w, u, v), *band)
    bmesh.ops.recalc_face_normals(bm, faces=faces)
    return faces


def horn(bm, x_from: float, y: float) -> list:
    """Box-section horn along X from the beam's outer face to the steering actuator axis.
    Its ends sit against the beam and inside the collar, so only the four long faces exist."""
    y0, y1 = y - HORN_HALF_WIDTH, y + HORN_HALF_WIDTH
    z0, z1 = HORN_Z
    corners = [(y0, z0), (y1, z0), (y1, z1), (y0, z1)]
    a = [bm.verts.new((x_from, cy, cz)) for cy, cz in corners]
    b = [bm.verts.new((STEER_AXIS_X, cy, cz)) for cy, cz in corners]
    faces = [bm.faces.new((a[k], a[(k + 1) % 4], b[(k + 1) % 4], b[k])) for k in range(4)]

    def out(f):
        c = f.calc_center_median()
        return Vector((0.0, c.y - y, c.z - sum(HORN_Z) / 2.0))
    kit.orient(bm, faces, out)
    return faces


def build_rocker_r() -> bmesh.types.BMesh:
    bm = bmesh.new()
    beam(bm, ROCKER_LINE, ROCKER_BAND)
    # Main pivot: housing through the spacer gap and the beam, plug into the chassis
    kit.cylinder(bm, along_x(*MAIN_PIVOT), CHASSIS_SIDE_X, ROCKER_BAND[1], HOUSING_RADIUS)
    kit.keyed_plug(bm, along_x(*MAIN_PIVOT), CHASSIS_SIDE_X, CHASSIS_SIDE_X - kit.CONNECTOR_DEPTH)
    # Bogie pivot: recess opening on the beam's outer face
    kit.recessed_collar(bm, along_x(*BOGIE_PIVOT), ROCKER_BAND[0], ROCKER_BAND[1], HOUSING_RADIUS)
    # Front horn to the steering actuator, recess opening down at z 0.30
    horn(bm, ROCKER_BAND[1], FRONT_STEER_Y)
    kit.recessed_collar(bm, vertical(STEER_AXIS_X, FRONT_STEER_Y), HORN_Z[1], HORN_Z[0])
    bmesh.ops.translate(bm, vec=-ROCKER_ORIGIN, verts=bm.verts)
    return bm


def build_bogie_r() -> bmesh.types.BMesh:
    bm = bmesh.new()
    beam(bm, BOGIE_LINE, BOGIE_BAND)
    # Pivot: housing through the spacer gap and the beam, plug into the rocker
    kit.cylinder(bm, along_x(*BOGIE_PIVOT), ROCKER_BAND[1], BOGIE_BAND[1], HOUSING_RADIUS)
    kit.keyed_plug(bm, along_x(*BOGIE_PIVOT), ROCKER_BAND[1], ROCKER_BAND[1] - kit.CONNECTOR_DEPTH)
    # Middle axle stub: recess opening flush with the wheel's inner face, key at +Z
    kit.recessed_collar(bm, along_x(*MIDDLE_AXLE, key_up_y=False), BOGIE_BAND[0], WHEEL_X[0])
    # Rear horn to the steering actuator, recess opening down at z 0.30
    horn(bm, BOGIE_BAND[1], REAR_STEER_Y)
    kit.recessed_collar(bm, vertical(STEER_AXIS_X, REAR_STEER_Y), HORN_Z[1], HORN_Z[0])
    bmesh.ops.translate(bm, vec=-BOGIE_ORIGIN, verts=bm.verts)
    return bm


def make_parts(name: str, build, origin: Vector, sockets: dict) -> dict:
    kit.reset_scene()
    metal = kit.get_material("rover_metal")
    parts = {}
    for side in ("R", "L"):
        sign = 1.0 if side == "R" else -1.0
        bm = build()
        if side == "L":
            kit.mirror_bmesh_x(bm)
        obj = kit.mesh_object("%s_%s" % (name, side), bm, [metal])
        obj.location = (sign * origin.x, origin.y, origin.z)
        for socket, location in sockets.items():
            kit.add_socket(obj, socket, (sign * location[0], location[1], location[2]))
        tris = kit.triangle_count(obj)
        if tris > TRIANGLE_BUDGET:
            raise RuntimeError("%s is over budget: %d" % (obj.name, tris))
        parts[side] = obj
    kit.save_blend(os.path.join(kit.PARTS_DIR, name + ".blend"))
    for side, obj in parts.items():
        kit.export_part(obj, os.path.join(kit.EXPORT_DIR, "%s_%s.glb" % (name, side)))
    return {side: kit.triangle_count(obj) for side, obj in parts.items()}


# --- Assembly and checks ----------------------------------------------------------------------

def socket(obj, name: str) -> Vector:
    bpy.context.view_layer.update()
    for child in obj.children:
        if child.name.split(".")[0] in (name, name + "_L", name + "_R"):
            return child.matrix_world.translation.copy()
    raise KeyError("%s has no %s" % (obj.name, name))


def copy_object(obj):
    dup = obj.copy()
    bpy.context.scene.collection.objects.link(dup)
    return dup


def empty(name: str, location) -> bpy.types.Object:
    obj = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = location
    return obj


def assemble(side: str) -> dict:
    """Builds one side from the saved part files, chained through their socket empties."""
    def load(blend, name):
        return kit.append_objects(os.path.join(kit.PARTS_DIR, blend), [name])[0]

    rocker = load("rocker.blend", "rocker_" + side)
    bogie = load("bogie.blend", "bogie_" + side)
    front_bracket = load("steer_bracket.blend", "steer_bracket_" + side)
    rear_bracket = copy_object(front_bracket)
    front_wheel = load("wheel.blend", "wheel_" + side)
    middle_wheel, rear_wheel = copy_object(front_wheel), copy_object(front_wheel)

    bogie.location = socket(rocker, "socket_bogie")
    front_pivot = empty("front_steer_" + side, socket(rocker, "socket_steer_front"))
    rear_pivot = empty("rear_steer_" + side, socket(bogie, "socket_steer_rear"))
    front_bracket.location, rear_bracket.location = front_pivot.location, rear_pivot.location
    bpy.context.view_layer.update()
    hub_offset = socket(front_bracket, "socket_wheel_hub") - front_bracket.location
    front_wheel.location = front_bracket.location + hub_offset
    # The rear bracket is a copy without the socket empties; it shares the same offset
    rear_wheel.location = rear_bracket.location + hub_offset
    middle_wheel.location = socket(bogie, "socket_wheel_mid")
    bpy.context.view_layer.update()

    for child, parent in ((bogie, rocker), (front_pivot, rocker), (rear_pivot, bogie),
                          (front_bracket, front_pivot), (front_wheel, front_pivot),
                          (rear_bracket, rear_pivot), (rear_wheel, rear_pivot),
                          (middle_wheel, bogie)):
        kit.parent_keep_transform(child, parent)
    return {
        "rocker": rocker, "bogie": bogie, "front_bracket": front_bracket,
        "rear_bracket": rear_bracket, "front_wheel": front_wheel, "middle_wheel": middle_wheel,
        "rear_wheel": rear_wheel, "front_pivot": front_pivot, "rear_pivot": rear_pivot,
    }


def pose(parts: dict, rocker_deg: float, bogie_deg: float, steer_deg: float) -> None:
    parts["rocker"].rotation_euler.x = math.radians(rocker_deg)
    parts["bogie"].rotation_euler.x = math.radians(bogie_deg)
    parts["front_pivot"].rotation_euler.z = math.radians(steer_deg)
    parts["rear_pivot"].rotation_euler.z = math.radians(-steer_deg)  # rear counter-steers
    bpy.context.view_layer.update()


def joint_zone(reference, axis: int, radius: float, w_range: tuple):
    """Predicate for points inside a designed joint, in `reference`'s local frame: within
    `radius` of its local `axis` and with that coordinate in `w_range`."""
    def inside(p: Vector) -> bool:
        local = reference.matrix_world.inverted() @ p
        others = [local[i] for i in range(3) if i != axis]
        return math.hypot(*others) < radius and w_range[0] <= local[axis] <= w_range[1]
    return inside


def joints(parts: dict, sign: float) -> dict:
    """Designed contacts (plug in recess, actuator against horn, hub against stub)."""
    def axle(wheel):
        lo, hi = sorted((sign * -0.15, sign * -0.115))
        return joint_zone(wheel, 0, 0.045, (lo, hi))

    def steer(bracket):
        return joint_zone(bracket, 2, 0.041, (-0.01, 0.05))

    lo, hi = sorted((sign * -0.04, sign * 0.07))
    return {
        ("rocker", "bogie"): joint_zone(parts["bogie"], 0, HOUSING_RADIUS + 0.001, (lo, hi)),
        ("rocker", "front_bracket"): steer(parts["front_bracket"]),
        ("bogie", "rear_bracket"): steer(parts["rear_bracket"]),
        ("bogie", "middle_wheel"): axle(parts["middle_wheel"]),
        ("front_bracket", "front_wheel"): axle(parts["front_wheel"]),
        ("rear_bracket", "rear_wheel"): axle(parts["rear_wheel"]),
    }


def tree(obj, skip) -> BVHTree:
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.transform(obj.matrix_world)
    if skip:
        doomed = [f for f in bm.faces if all(skip(v.co) for v in f.verts)]
        bmesh.ops.delete(bm, geom=doomed, context="FACES_ONLY")
    result = BVHTree.FromBMesh(bm)
    bm.free()
    return result


def pair_gap(a, b, skip) -> float:
    a_points = [p for p in kit.world_vertices(a) if not (skip and skip(p))]
    b_points = [p for p in kit.world_vertices(b) if not (skip and skip(p))]
    a_tree, b_tree = tree(a, skip), tree(b, skip)
    gap = 1e9
    for p in b_points:
        hit = a_tree.find_nearest(p)
        if hit[0] is not None:
            gap = min(gap, hit[3])
    for p in a_points:
        hit = b_tree.find_nearest(p)
        if hit[0] is not None:
            gap = min(gap, hit[3])
    return gap


def check_side(side: str) -> list:
    sign = 1.0 if side == "R" else -1.0
    parts = assemble(side)
    meshes = ["rocker", "bogie", "front_bracket", "rear_bracket", "front_wheel", "middle_wheel", "rear_wheel"]
    report = []

    pose(parts, 0.0, 0.0, 0.0)
    for name in ("front_wheel", "middle_wheel", "rear_wheel"):
        bottom = min(p.z for p in kit.world_vertices(parts[name]))
        report.append("  %s bottom z %.4f (ground %.2f): %s" % (
            name, bottom, GROUND_Z, "touches" if abs(bottom - GROUND_Z) < 1e-4 else "OFF THE GROUND"))
    others_low = min(min(p.z for p in kit.world_vertices(parts[n])) for n in meshes if "wheel" not in n)
    report.append("  lowest non-wheel point z %.3f: %.0f mm above the ground" % (
        others_low, (others_low - GROUND_Z) * 1000.0))

    zones = joints(parts, sign)
    chassis_zone = joint_zone(parts["rocker"], 0, HOUSING_RADIUS + 0.001,
                              tuple(sorted((sign * -0.01, sign * 0.0195))))
    worst = {}
    chassis = {}
    for rocker_deg, bogie_deg, steer_deg in itertools.product(ROCKER_ANGLES, BOGIE_ANGLES, STEER_ANGLES):
        pose(parts, rocker_deg, bogie_deg, steer_deg)
        config = "rocker %+.0f, bogie %+.0f, steer %+.0f" % (rocker_deg, bogie_deg, steer_deg)
        for a, b in itertools.combinations(meshes, 2):
            gap = pair_gap(parts[a], parts[b], zones.get((a, b)))
            if (a, b) not in worst or gap < worst[(a, b)][0]:
                worst[(a, b)] = (gap, config)
        for name in meshes:
            skip = chassis_zone if name == "rocker" else None
            inner = min(sign * p.x for p in kit.world_vertices(parts[name]) if not (skip and skip(p)))
            gap = inner - CHASSIS_SIDE_X
            if name not in chassis or gap < chassis[name][0]:
                chassis[name] = (gap, config)
    pose(parts, 0.0, 0.0, 0.0)

    failures = 0
    report.append("  vs chassis side plane (x = %.2f):" % CHASSIS_SIDE_X)
    for name, (gap, config) in sorted(chassis.items(), key=lambda item: item[1][0]):
        ok = gap >= MIN_CLEARANCE - 1e-4
        failures += not ok
        report.append("    %-13s %6.1f mm  %s  (worst at %s)" % (name, gap * 1000.0, "ok" if ok else "FAIL", config))
    report.append("  part vs part (designed joints excluded):")
    for (a, b), (gap, config) in sorted(worst.items(), key=lambda item: item[1][0]):
        ok = gap >= MIN_CLEARANCE - 1e-4
        failures += not ok
        joint = " [joint pair]" if (a, b) in zones else ""
        report.append("    %-13s vs %-13s %6.1f mm  %s  (worst at %s)%s" % (
            a, b, gap * 1000.0, "ok" if ok else "FAIL", config, joint))
    report.append("  %s" % ("ALL CLEARANCES OK" if failures == 0 else "%d CLEARANCE FAILURES" % failures))
    return parts, report


def ground_plane(sign: float) -> bpy.types.Object:
    """Preview ground: a thin slab whose top is the ground at rest, so it also shows edge-on."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=(1.0, 1.6, 0.02), verts=bm.verts)
    bmesh.ops.translate(bm, vec=(sign * 0.45, 0.0, GROUND_Z - 0.01), verts=bm.verts)
    material = bpy.data.materials.new("preview_ground")
    material.diffuse_color = (0.55, 0.42, 0.33, 1.0)
    obj = kit.mesh_object("preview_ground", bm, [material])
    return obj


def main() -> None:
    previews = kit.preview_dir("rocker_bogie")
    report = []
    sockets_rocker = {"socket_steer_front": (STEER_AXIS_X, FRONT_STEER_Y, HORN_Z[0]),
                      "socket_bogie": (BOGIE_ORIGIN.x, BOGIE_ORIGIN.y, BOGIE_ORIGIN.z)}
    sockets_bogie = {"socket_wheel_mid": (STEER_AXIS_X, MIDDLE_AXLE[0], MIDDLE_AXLE[1]),
                     "socket_steer_rear": (STEER_AXIS_X, REAR_STEER_Y, HORN_Z[0])}
    for name, build, origin, sockets in (("rocker", build_rocker_r, ROCKER_ORIGIN, sockets_rocker),
                                         ("bogie", build_bogie_r, BOGIE_ORIGIN, sockets_bogie)):
        tris = make_parts(name, build, origin, sockets)
        report.append("%s: %s triangles (budget %d)" % (
            name, ", ".join("%s %d" % (s, t) for s, t in sorted(tris.items())), TRIANGLE_BUDGET))
        if previews:
            kit.set_preview_colors(True)
            for side in ("R", "L"):
                sign = 1.0 if side == "R" else -1.0
                obj = bpy.data.objects["%s_%s" % (name, side)]
                kit.render_view(obj, os.path.join(previews, "%s_%s_alone.png" % (name, side)),
                                (sign * 0.6, 0.55, 0.5), 0.6, True, 1.8,
                                focus=(sign * 0.05, -0.12 if name == "bogie" else 0.12, 0.0))

    kit.reset_scene()
    kit.get_material("rover_metal")
    kit.get_material("rover_dark")
    for side in ("R", "L"):
        parts, side_report = check_side(side)
        report.append("assembled side %s:" % side)
        report += side_report
        if previews and side == "R":
            sign = 1.0
            ground = ground_plane(sign)
            kit.set_preview_colors(True)
            focus = (0.0, 0.0, -0.08)
            rocker = parts["rocker"]
            kit.render_view(rocker, os.path.join(previews, "side_R_from_outboard.png"),
                            (1.0, 0.0, 0.0), 1.5, focus=focus, keep_visible=(ground,))
            kit.render_view(rocker, os.path.join(previews, "side_R_from_above.png"),
                            (0.0, 0.0, 1.0), 1.5, focus=(0.15, 0.0, 0.0), keep_visible=(ground,))
            kit.render_view(rocker, os.path.join(previews, "side_R_three_quarter.png"),
                            (0.8, 0.9, 0.45), 1.5, True, 3.6, focus, keep_visible=(ground,))
            kit.render_view(rocker, os.path.join(previews, "side_R_from_inboard.png"),
                            (-1.0, 0.0, 0.0), 1.5, focus=focus, keep_visible=(ground,))
            # A clearance-check pose, not a resting one, so without the ground
            pose(parts, 8.0, -12.0, 30.0)
            kit.render_view(rocker, os.path.join(previews, "side_R_tilted_three_quarter.png"),
                            (0.8, 0.9, 0.45), 1.5, True, 3.6, focus)
            pose(parts, 0.0, 0.0, 0.0)
            bpy.data.objects.remove(ground)
        # Clear the side before building the other one
        for obj in list(bpy.data.objects):
            bpy.data.objects.remove(obj)

    print("\n".join("ROVER_KIT " + line for line in report))


main()
