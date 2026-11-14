"""Generates steer_bracket_L and steer_bracket_R for the rover kit (ROVER_KIT.md 3.3, 3.4).
Front and rear corner wheels share these meshes.

    blender -b --factory-startup -P tools/blender/scripts/make_steer_bracket.py [-- --previews DIR | --no-previews]

Writes tools/blender/parts/steer_bracket.blend, game/res/models/rover_kit/steer_bracket_L.glb /
steer_bracket_R.glb and previews (with the wheel mounted, at 0 and 30 degrees steering) in
tools/blender/previews/steer_bracket/. Needs tools/blender/parts/wheel.blend for the previews
and the clearance check.

Shape (front-right, Blender world coordinates at rest):
    origin / mating face  actuator top on the steer axis      (0.50, 0.50, 0.30)
    plug                  z 0.30 to 0.308, key at +Y, into the rocker / bogie horn above
    actuator              diameter 0.08, z 0.22 to 0.30
    arm                   inboard over the wheel, z 0.22 to 0.25
    leg                   down the wheel's inner side, x 0.33 to 0.36
    axle stub             collar x 0.36 to 0.38 with the keyed recess for the wheel's plug
    socket_wheel_hub      wheel centre                         (0.50, 0.50, 0.05)
Budget: 150 triangles. Actuator 28, plug 28, arm + leg 20, axle stub 68 = 144.
"""

import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

sys.path.append(os.path.dirname(__file__))
import rover_kit_common as kit  # noqa: E402

TRIANGLE_BUDGET = 150

ORIGIN_R = Vector((0.50, 0.50, 0.30))
WHEEL_CENTRE_Z = 0.05
MAX_STEER = 30.0

# Local coordinates (relative to the origin on the steer axis), right-hand bracket
ACTUATOR_RADIUS = 0.04
ACTUATOR_Z = (0.22 - 0.30, 0.0)
ARM_Z = (0.22 - 0.30, 0.25 - 0.30)
LEG_X = (0.33 - 0.50, 0.36 - 0.50)
LEG_BOTTOM_Z = (WHEEL_CENTRE_Z - kit.COLLAR_RADIUS) - 0.30
# 36 mm deep: the leg's outer corners stay within 0.171 m of the steer axis (sweep to x 0.329)
BEAM_HALF_DEPTH = 0.018
STUB_X = (0.36 - 0.50, 0.38 - 0.50)
STUB_Z = WHEEL_CENTRE_Z - 0.30

# ROVER_KIT.md 3.1 / 3.2 / 3.4
WHEEL_TOP_Z = WHEEL_CENTRE_Z + 0.15
HORN_BOTTOM_Z = 0.30
CHASSIS_SIDE_X = 0.25
ROCKER_OUTER_X = 0.30
BOGIE_BAND_X = (0.32, 0.36)
BOGIE_MIN_Z_NEAR_CORNER = 0.30
MIDDLE_WHEEL_FRONT_Y = 0.15


def build_actuator(bm) -> list:
    outline = kit.circle_outline(ACTUATOR_RADIUS, 8, math.radians(22.5))
    faces = kit.prism(bm, outline, lambda u, v, w: (u, v, w), *ACTUATOR_Z)
    kit.orient(bm, faces, kit.axis_outward(2, *ACTUATOR_Z))
    return faces


def build_plug(bm) -> list:
    """Child connector toward the rocker / bogie horn: plug up from the mating face (z 0),
    key notch at +Y (the connector axis is Z)."""
    faces = kit.prism(bm, kit.plug_outline(), lambda u, v, w: (u, v, w),
                      0.0, kit.CONNECTOR_DEPTH, cap0=False)
    kit.orient(bm, faces, kit.axis_outward(2, 0.0, kit.CONNECTOR_DEPTH))
    return faces


def build_arm_and_leg(bm) -> list:
    """One L-shaped beam: the arm from the axis over the wheel, the leg down its inner side."""
    outline = [
        (LEG_X[0], LEG_BOTTOM_Z), (LEG_X[1], LEG_BOTTOM_Z), (LEG_X[1], ARM_Z[0]),
        (0.0, ARM_Z[0]), (0.0, ARM_Z[1]), (LEG_X[0], ARM_Z[1]),
    ]
    faces = kit.prism(bm, outline, lambda u, v, w: (u, w, v), -BEAM_HALF_DEPTH, BEAM_HALF_DEPTH)
    bmesh.ops.recalc_face_normals(bm, faces=faces)
    return faces


def build_axle_stub(bm) -> list:
    """Parent connector for the wheel: collar along X with the keyed recess (the plug outline,
    tab at +Z) opening on the wheel side, flush with the wheel's inner face."""
    def place(u, v, w):
        return (w, u, STUB_Z + v)

    collar = kit.circle_outline(kit.COLLAR_RADIUS, 8, math.radians(22.5))
    recess = kit.plug_outline()
    face_x, floor_x = STUB_X[1], STUB_X[1] - kit.CONNECTOR_DEPTH

    # Collar (back cap + sides) and recess (floor + walls), both open at the face plane
    faces = kit.prism(bm, collar, place, STUB_X[0], face_x, cap0=True, cap1=False)
    faces += kit.prism(bm, recess, place, floor_x, face_x, cap0=True, cap1=False)
    # Fill the ring between the collar rim and the recess opening (the recess stays a hole)
    rim_edges = [e for e in bm.edges if all(abs(v.co.x - face_x) < 1e-7 for v in e.verts)]
    filled = bmesh.ops.triangle_fill(bm, use_beauty=True, use_dissolve=False, edges=rim_edges,
                                     normal=(1.0, 0.0, 0.0))
    faces += [g for g in filled["geom"] if isinstance(g, bmesh.types.BMFace)]
    bmesh.ops.recalc_face_normals(bm, faces=faces)
    return faces


def build_bracket_r() -> bmesh.types.BMesh:
    bm = bmesh.new()
    build_actuator(bm)
    build_plug(bm)
    build_arm_and_leg(bm)
    build_axle_stub(bm)
    return bm


# --- Checks ---------------------------------------------------------------------------------

def bvh(obj, skip=None) -> BVHTree:
    """BVH of an object in world space, leaving out faces whose vertices all satisfy `skip`."""
    bpy.context.view_layer.update()
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.transform(obj.matrix_world)
    if skip:
        doomed = [f for f in bm.faces if all(skip(v.co) for v in f.verts)]
        bmesh.ops.delete(bm, geom=doomed, context="FACES_ONLY")
    tree = BVHTree.FromBMesh(bm)
    bm.free()
    return tree


def bracket_wheel_gap(bracket, wheel, sign: float) -> float:
    """Smallest distance between the bracket and its wheel outside the axle joint, checked
    from both meshes' vertices. The joint is the bracket's axle stub and the wheel's plug and
    hub end, which touch (or sit inside each other) by design."""
    axle_y, axle_z = bracket.matrix_world.translation.y, WHEEL_CENTRE_Z

    def stub(p):
        return math.hypot(p.y - axle_y, p.z - axle_z) < kit.COLLAR_RADIUS + 0.001 and sign * p.x > 0.355

    def plug_and_hub(p):
        return math.hypot(p.y - axle_y, p.z - axle_z) < 0.045 and sign * p.x > 0.355

    wheel_tree, bracket_tree = bvh(wheel, plug_and_hub), bvh(bracket, stub)
    gap = 1e9
    for p in kit.world_vertices(bracket):
        if not stub(p):
            gap = min(gap, wheel_tree.find_nearest(p)[3])
    for p in kit.world_vertices(wheel):
        if not plug_and_hub(p):
            gap = min(gap, bracket_tree.find_nearest(p)[3])
    return gap


def sweep(pivot, bracket, wheel, sign: float) -> dict:
    """Extremes of the bracket and wheel while steering through +-MAX_STEER degrees."""
    result = {"bracket_inner_x": 1e9, "wheel_inner_x": 1e9, "bracket_top_in_bogie_band": -1e9,
              "assembly_inner_y": 1e9}
    for degrees in range(-int(MAX_STEER), int(MAX_STEER) + 1):
        pivot.rotation_euler.z = math.radians(degrees)
        bracket_points = kit.world_vertices(bracket)
        wheel_points = kit.world_vertices(wheel)
        result["bracket_inner_x"] = min(result["bracket_inner_x"], min(sign * p.x for p in bracket_points))
        result["wheel_inner_x"] = min(result["wheel_inner_x"], min(sign * p.x for p in wheel_points))
        band = [p.z for p in bracket_points if BOGIE_BAND_X[0] - 0.02 <= sign * p.x <= BOGIE_BAND_X[1] + 0.02]
        if band:
            result["bracket_top_in_bogie_band"] = max(result["bracket_top_in_bogie_band"], max(band))
        result["assembly_inner_y"] = min(result["assembly_inner_y"],
                                         min(p.y for p in bracket_points + wheel_points))
    pivot.rotation_euler.z = 0.0
    return result


def mm(value: float) -> str:
    return "%.1f mm" % (value * 1000.0)


def main() -> None:
    previews = kit.preview_dir("steer_bracket")
    kit.reset_scene()
    metal = kit.get_material("rover_metal")

    brackets = {}
    for side in ("R", "L"):
        bm = build_bracket_r()
        if side == "L":
            kit.mirror_bmesh_x(bm)
        bracket = kit.mesh_object("steer_bracket_" + side, bm, [metal])
        sign = 1.0 if side == "R" else -1.0
        bracket.location = (sign * ORIGIN_R.x, ORIGIN_R.y, ORIGIN_R.z)
        kit.add_socket(bracket, "socket_wheel_hub", (sign * ORIGIN_R.x, ORIGIN_R.y, WHEEL_CENTRE_Z))
        brackets[side] = bracket
        tris = kit.triangle_count(bracket)
        if tris > TRIANGLE_BUDGET:
            raise RuntimeError("steer_bracket_%s is over budget: %d" % (side, tris))

    kit.save_blend(os.path.join(kit.PARTS_DIR, "steer_bracket.blend"))
    for side, bracket in brackets.items():
        kit.export_part(bracket, os.path.join(kit.EXPORT_DIR, "steer_bracket_%s.glb" % side))

    # Assemble with the wheels (not saved) for the clearance check and previews
    wheels = {w.name: w for w in kit.append_objects(os.path.join(kit.PARTS_DIR, "wheel.blend"),
                                                    ["wheel_L", "wheel_R"])}
    report = []
    pivots = {}
    for side, bracket in brackets.items():
        sign = 1.0 if side == "R" else -1.0
        wheel = wheels["wheel_" + side]
        wheel.location = (sign * ORIGIN_R.x, ORIGIN_R.y, WHEEL_CENTRE_Z)
        pivot = bpy.data.objects.new("steer_pivot_" + side, None)
        bpy.context.scene.collection.objects.link(pivot)
        pivot.location = bracket.location
        bpy.context.view_layer.update()
        kit.parent_keep_transform(bracket, pivot)
        kit.parent_keep_transform(wheel, pivot)
        pivots[side] = pivot

        points = kit.world_vertices(bracket)
        over_wheel = [p.z for p in points if 0.38 <= sign * p.x <= 0.62]
        arm_top = max(p.z for p in points
                      if math.hypot(p.x - bracket.location.x, p.y - bracket.location.y) > ACTUATOR_RADIUS + 0.001)
        wheel_top = max(p.z for p in kit.world_vertices(wheel))
        s = sweep(pivot, bracket, wheel, sign)
        report += [
            "steer_bracket_%s: %d triangles (budget %d), plug top z %.3f"
            % (side, kit.triangle_count(bracket), TRIANGLE_BUDGET, max(p.z for p in points)),
            "  bracket vs its wheel (outside the axle joint): %s" % mm(bracket_wheel_gap(bracket, wheel, sign)),
            "  wheel top %.3f vs arm bottom %.3f: %s" % (wheel_top, min(over_wheel), mm(min(over_wheel) - wheel_top)),
            "  arm top %.3f vs horn bottom %.2f: %s" % (arm_top, HORN_BOTTOM_Z, mm(HORN_BOTTOM_Z - arm_top)),
            "  steering +-%d deg: bracket reaches |x| %.4f -> chassis side %s, rocker beam %s"
            % (MAX_STEER, s["bracket_inner_x"], mm(s["bracket_inner_x"] - CHASSIS_SIDE_X),
               mm(s["bracket_inner_x"] - ROCKER_OUTER_X)),
            "  steering: wheel reaches |x| %.4f -> rocker beam %s, chassis side %s"
            % (s["wheel_inner_x"], mm(s["wheel_inner_x"] - ROCKER_OUTER_X), mm(s["wheel_inner_x"] - CHASSIS_SIDE_X)),
            "  steering: bracket top inside the bogie band %.3f vs bogie at z >= %.2f: %s"
            % (s["bracket_top_in_bogie_band"], BOGIE_MIN_Z_NEAR_CORNER,
               mm(BOGIE_MIN_Z_NEAR_CORNER - s["bracket_top_in_bogie_band"])),
            "  steering: front assembly reaches y %.4f vs middle wheel front y %.2f: %s"
            % (s["assembly_inner_y"], MIDDLE_WHEEL_FRONT_Y, mm(s["assembly_inner_y"] - MIDDLE_WHEEL_FRONT_Y)),
        ]

    if previews:
        kit.set_preview_colors(True)
        for side, pivot in pivots.items():
            sign = 1.0 if side == "R" else -1.0
            for degrees in (0, 30):
                pivot.rotation_euler.z = math.radians(degrees)
                tag = "steer_bracket_%s_%ddeg" % (side, degrees)
                focus = (0.0, 0.0, -0.13)
                kit.render_view(pivot, os.path.join(previews, tag + "_front.png"), (0.0, 1.0, 0.0), 0.5,
                                focus=focus)
                kit.render_view(pivot, os.path.join(previews, tag + "_top.png"), (0.0, 0.0, 1.0), 0.5,
                                focus=focus)
                kit.render_view(pivot, os.path.join(previews, tag + "_three_quarter.png"),
                                (-sign * 0.7, 0.75, 0.5), 0.5, True, 1.7, focus)
            pivot.rotation_euler.z = 0.0
        # The bracket alone, from inboard, to show the stub recess and the top plug
        for side, bracket in brackets.items():
            sign = 1.0 if side == "R" else -1.0
            wheels["wheel_" + side].hide_render = True
            kit.render_view(pivots[side], os.path.join(previews, "steer_bracket_%s_alone.png" % side),
                            (sign * 0.8, 0.6, 0.45), 0.5, True, 0.9, (0.0, 0.0, -0.13))
            wheels["wheel_" + side].hide_render = False
        kit.set_preview_colors(False)

    print("\n".join("ROVER_KIT " + line for line in report))


main()
