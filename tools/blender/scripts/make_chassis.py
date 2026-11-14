"""Generates the rover kit chassis (ROVER_KIT.md 3.3), then assembles the whole drivetrain
(chassis, both sides of linkage, four steer brackets, six wheels) from the saved part files to run
the section 3.4 checks over the verified pose range.

    blender -b --factory-startup -P tools/blender/scripts/make_chassis.py [-- --previews DIR | --no-previews]

Writes tools/blender/parts/chassis.blend, game/res/models/rover_kit/chassis.glb and previews in
tools/blender/previews/chassis/. Needs wheel, steer_bracket, rocker and bogie .blend files.

Chassis (Blender world coordinates, origin = rover physics origin):
    body        x +-0.25, y +-0.45, z 0.20-0.44, 30 mm chamfer on the top edges, flat deck
    panels      3 mm inset panels: two per side, two at the rear, one on the deck
    recesses    keyed connector recesses (rover_metal) at every socket below
    motor hatch 0.16 x 0.14 pocket in the front face, 0.12 deep, connector on its floor
    hazcams     a camera pair on a bar under the front edge and under the rear edge
    LGA         low-gain antenna post with a disc on the deck
    collision   chassis-convcolonly box
Budget: 1,300 triangles.
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

TRIANGLE_BUDGET = 1300
MIN_CLEARANCE = 0.020

HALF_W, HALF_L = 0.25, 0.45
BOTTOM_Z, SIDE_TOP_Z, DECK_Z = 0.20, 0.41, 0.44
CHAMFER = DECK_Z - SIDE_TOP_Z
PANEL_DEPTH = 0.003

HATCH_X = (0.04, 0.20)
HATCH_Z = (0.23, 0.37)
HATCH_FLOOR_Y = 0.33

SOCKETS = {
    "socket_rocker_L": (-HALF_W, 0.00, 0.27),
    "socket_rocker_R": (HALF_W, 0.00, 0.27),
    "socket_mast": (0.15, 0.35, DECK_Z),
    "socket_arm": (-0.12, HALF_L, 0.32),
    # On the hatch floor, so the drive unit sits flush in the front face (ROVER_KIT.md 3.3)
    "socket_motor": (0.12, HATCH_FLOOR_Y, 0.30),
    "socket_power": (0.00, -HALF_L, 0.36),
    "socket_antenna": (-0.15, -0.25, DECK_Z),
    # Under the stowed arm's turret: the only deck patch the arm reaches pointing straight down
    # (ROVER_KIT.md 9, IRIS_KIT.md 5)
    "socket_cargo": (-0.125, 0.20, DECK_Z),
}
for _side, _sign in (("L", -1.0), ("R", 1.0)):
    for _pos, _y in (("front", 0.5), ("middle", 0.0), ("rear", -0.5)):
        SOCKETS["socket_wheel_%s_%s" % (_pos, _side)] = (_sign * 0.5, _y, 0.05)

LGA_XY = (0.15, -0.30)
BODY, METAL, DARK = 0, 1, 2


# --- Body construction helpers -----------------------------------------------------------------

def ring_edges(bm, verts: list) -> list:
    edges = []
    for k in range(len(verts)):
        a, b = verts[k], verts[(k + 1) % len(verts)]
        edges.append(bm.edges.get((a, b)) or bm.edges.new((a, b)))
    return edges


def fill(bm, loops: list, normal, material: int) -> list:
    """Fills a flat face bounded by the first loop, with the other loops as holes."""
    edges = [e for loop in loops for e in ring_edges(bm, loop)]
    result = bmesh.ops.triangle_fill(bm, use_beauty=True, use_dissolve=False, edges=edges,
                                     normal=Vector(normal))
    faces = [g for g in result["geom"] if isinstance(g, bmesh.types.BMFace)]
    for f in faces:
        f.material_index = material
    return faces


def sunk(bm, outline: list, place, w_face: float, w_floor: float, material: int, floor: bool = True) -> list:
    """A pocket: the outline's opening at w_face, walls down to w_floor and (optionally) its
    floor. Returns the opening ring (to cut the hole in the face) and the floor ring."""
    opening = [bm.verts.new(place(u, v, w_face)) for u, v in outline]
    bottom = [bm.verts.new(place(u, v, w_floor)) for u, v in outline]
    for k in range(len(outline)):
        n = (k + 1) % len(outline)
        bm.faces.new((opening[k], opening[n], bottom[n], bottom[k])).material_index = material
    if floor:
        bm.faces.new(bottom).material_index = material
    return opening, bottom


def recess(bm, place, w_face: float) -> list:
    """Keyed connector recess (ROVER_KIT.md 2.5): plug outline (tab at +v), opening flush at
    w_face, floor CONNECTOR_DEPTH into the body (toward the origin side of w_face)."""
    w_floor = w_face - math.copysign(kit.CONNECTOR_DEPTH, w_face)
    opening, _ = sunk(bm, kit.plug_outline(), place, w_face, w_floor, METAL)
    return opening


def panel(bm, rect: tuple, place, w_face: float) -> list:
    """3 mm inset panel (a panel line around it). rect = (u0, u1, v0, v1)."""
    u0, u1, v0, v1 = rect
    w_in = w_face - math.copysign(PANEL_DEPTH, w_face)
    opening, _ = sunk(bm, [(u0, v0), (u1, v0), (u1, v1), (u0, v1)], place, w_face, w_in, BODY)
    return opening


def build_body(bm) -> None:
    def corners(half_w, half_l, z):
        return [bm.verts.new((x, y, z)) for x, y in
                ((-half_w, -half_l), (half_w, -half_l), (half_w, half_l), (-half_w, half_l))]

    b = corners(HALF_W, HALF_L, BOTTOM_Z)
    m = corners(HALF_W, HALF_L, SIDE_TOP_Z)
    t = corners(HALF_W - CHAMFER, HALF_L - CHAMFER, DECK_Z)
    bm.faces.new(b).material_index = BODY
    for k in range(4):
        n = (k + 1) % 4
        bm.faces.new((m[k], m[n], t[n], t[k])).material_index = BODY

    # Deck: mast and antenna recesses, one panel
    deck_holes = [
        recess(bm, lambda u, v, w: (0.15 + u, 0.35 + v, w), DECK_Z),
        recess(bm, lambda u, v, w: (-0.15 + u, -0.25 + v, w), DECK_Z),
        panel(bm, (-0.18, 0.05, -0.05, 0.28), lambda u, v, w: (u, v, w), DECK_Z),
    ]
    fill(bm, [t] + deck_holes, (0, 0, 1), BODY)

    # Sides: rocker pivot recess (key +Y) and two panels each
    for sign, loop in ((1.0, [b[1], b[2], m[2], m[1]]), (-1.0, [b[3], b[0], m[0], m[3]])):
        x = sign * HALF_W
        holes = [
            recess(bm, lambda u, v, w: (w, v, 0.27 + u), x),
            panel(bm, (0.08, 0.40, 0.23, 0.38), lambda u, v, w: (w, u, v), x),
            panel(bm, (-0.40, -0.08, 0.23, 0.38), lambda u, v, w: (w, u, v), x),
        ]
        fill(bm, [loop] + holes, (sign, 0, 0), BODY)

    # Front: arm recess (key +Z) and the motor hatch with its connector on the floor
    hatch_outline = [(HATCH_X[0], HATCH_Z[0]), (HATCH_X[1], HATCH_Z[0]),
                     (HATCH_X[1], HATCH_Z[1]), (HATCH_X[0], HATCH_Z[1])]
    hatch_open, hatch_floor = sunk(bm, hatch_outline, lambda u, v, w: (u, w, v), HALF_L,
                                   HATCH_FLOOR_Y, METAL, floor=False)
    motor_recess = recess(bm, lambda u, v, w: (0.12 + u, w, 0.30 + v), HATCH_FLOOR_Y)
    fill(bm, [hatch_floor, motor_recess], (0, 1, 0), METAL)
    front_holes = [recess(bm, lambda u, v, w: (-0.12 + u, w, 0.32 + v), HALF_L), hatch_open]
    fill(bm, [[b[2], b[3], m[3], m[2]]] + front_holes, (0, 1, 0), BODY)

    # Rear: power recess (key +Z) and two panels
    rear_holes = [
        recess(bm, lambda u, v, w: (u, w, 0.36 + v), -HALF_L),
        panel(bm, (-0.20, -0.06, 0.23, 0.32), lambda u, v, w: (u, w, v), -HALF_L),
        panel(bm, (0.06, 0.20, 0.23, 0.32), lambda u, v, w: (u, w, v), -HALF_L),
    ]
    fill(bm, [[b[0], b[1], m[1], m[0]]] + rear_holes, (0, -1, 0), BODY)


def build_hazcams(bm, front: bool) -> None:
    """A camera pair on a bar under the front (or rear) edge, lenses facing out."""
    s = 1.0 if front else -1.0
    y_bar = tuple(sorted((s * (HALF_L - 0.04), s * (HALF_L - 0.01))))
    kit.box(bm, (-0.07, 0.07), y_bar, (BOTTOM_Z - 0.01, BOTTOM_Z), METAL)
    y_cam = tuple(sorted((s * (HALF_L - 0.035), s * (HALF_L - 0.005))))
    lens_y = s * (HALF_L - 0.005 + 0.001)
    for x in (-0.0475, 0.0475):
        kit.box(bm, (x - 0.0175, x + 0.0175), y_cam, (BOTTOM_Z - 0.04, BOTTOM_Z - 0.01), METAL)
        lens = [bm.verts.new((x + u, lens_y, BOTTOM_Z - 0.025 + v))
                for u, v in kit.circle_outline(0.01, 6)]
        face = bm.faces.new(lens)
        face.material_index = DARK
        face.normal_update()
        if face.normal.y * s < 0.0:
            face.normal_flip()


def build_lga(bm) -> None:
    x, y = LGA_XY
    post = kit.cylinder(bm, lambda u, v, w: (x + u, y + v, w), DECK_Z, DECK_Z + 0.08, 0.012, 6)
    disc = kit.cylinder(bm, lambda u, v, w: (x + u, y + v, w), DECK_Z + 0.08, DECK_Z + 0.09, 0.025, 6)
    for f in post:
        f.material_index = METAL
    for f in disc:
        f.material_index = BODY


def build_chassis():
    bm = bmesh.new()
    build_body(bm)
    body_faces = list(bm.faces)
    bmesh.ops.recalc_face_normals(bm, faces=body_faces)
    non_manifold = sum(1 for e in bm.edges if len(e.link_faces) != 2)
    build_hazcams(bm, front=True)
    build_hazcams(bm, front=False)
    build_lga(bm)
    return bm, non_manifold


def collision_box():
    bm = bmesh.new()
    kit.box(bm, (-HALF_W, HALF_W), (-HALF_L, HALF_L), (BOTTOM_Z, DECK_Z), 0)
    return bm


# --- Assembly checks ----------------------------------------------------------------------------

def check_assembly(previews) -> list:
    kit.reset_scene()
    for name in ("rover_body", "rover_metal", "rover_dark"):
        kit.get_material(name)
    chassis = kit.append_objects(os.path.join(kit.PARTS_DIR, "chassis.blend"), ["chassis"])[0]
    sides = {side: rb.assemble(side, chassis) for side in ("L", "R")}
    report = []
    bpy.context.view_layer.update()

    # Rest pose: wheels on the ground and on the chassis wheel sockets
    for side, parts in sides.items():
        rb.pose(parts, 0.0, 0.0, 0.0)
        for pos in ("front", "middle", "rear"):
            wheel = parts["%s_wheel" % pos]
            centre = wheel.matrix_world.translation
            target = rb.socket(chassis, "socket_wheel_%s_%s" % (pos, side))
            bottom = min(p.z for p in kit.world_vertices(wheel))
            report.append("  wheel %s_%s: centre %s vs chassis socket %s, bottom z %.4f%s" % (
                pos, side, tuple(round(c, 4) for c in centre), tuple(round(c, 4) for c in target),
                bottom, "" if (centre - target).length < 1e-4 and abs(bottom - rb.GROUND_Z) < 1e-4 else "  MISMATCH"))

    points = kit.world_vertices(chassis)
    lowest = min(p.z for p in points)
    # The hazcams hang under the front / rear edges (|x| <= 0.07, |y| >= 0.41); the rest is body
    body_bottom = min(p.z for p in points
                      if not (abs(p.x) <= 0.071 and abs(p.y) >= HALF_L - 0.041 and p.z < BOTTOM_Z - 1e-6))
    compressed_ground = 0.19 - 0.15  # full suspension compression: wheel centre z 0.19
    report += [
        "  chassis body bottom z %.3f vs ground %.2f: %.0f mm (spec 300)" % (
            body_bottom, rb.GROUND_Z, (body_bottom - rb.GROUND_Z) * 1000.0),
        "  lowest chassis point (hazcams) z %.3f: %.0f mm above the ground" % (
            lowest, (lowest - rb.GROUND_Z) * 1000.0),
        "  at full suspension compression the ground under a wheel is at z %.2f: body %.0f mm, hazcams %.0f mm" % (
            compressed_ground, (body_bottom - compressed_ground) * 1000.0, (lowest - compressed_ground) * 1000.0),
    ]

    # Pose sweep per side, chassis included; designed joints excluded
    failures = 0
    for side, parts in sides.items():
        sign = 1.0 if side == "R" else -1.0
        names = ["chassis", "rocker", "bogie", "front_bracket", "rear_bracket",
                 "front_wheel", "middle_wheel", "rear_wheel"]
        objects = dict(parts, chassis=chassis)
        zones = rb.joints(parts, sign)
        lo, hi = sorted((sign * -0.01, sign * 0.0195))
        zones[("chassis", "rocker")] = rb.joint_zone(parts["rocker"], 0, rb.HOUSING_RADIUS + 0.001, (lo, hi))
        worst = {}
        for rocker_deg, bogie_deg, steer_deg in itertools.product(rb.ROCKER_ANGLES, rb.BOGIE_ANGLES, rb.STEER_ANGLES):
            rb.pose(parts, rocker_deg, bogie_deg, steer_deg)
            config = "rocker %+.0f, bogie %+.0f, steer %+.0f" % (rocker_deg, bogie_deg, steer_deg)
            for a, b in itertools.combinations(names, 2):
                gap = rb.pair_gap(objects[a], objects[b], zones.get((a, b)))
                if (a, b) not in worst or gap < worst[(a, b)][0]:
                    worst[(a, b)] = (gap, config)
        rb.pose(parts, 0.0, 0.0, 0.0)
        report.append("  side %s, part vs part over the pose sweep (designed joints excluded):" % side)
        for (a, b), (gap, config) in sorted(worst.items(), key=lambda item: item[1][0]):
            ok = gap >= MIN_CLEARANCE - 1e-4
            failures += not ok
            report.append("    %-13s vs %-13s %6.1f mm  %s  (worst at %s)%s" % (
                a, b, gap * 1000.0, "ok" if ok else "FAIL", config, " [joint pair]" if (a, b) in zones else ""))
    report.append("  %s" % ("ALL CLEARANCES OK" if failures == 0 else "%d CLEARANCE FAILURES" % failures))

    if previews:
        ground = rb.ground_plane(0.0, 1.9)
        kit.set_preview_colors(True)
        focus = (0.0, 0.0, 0.15)
        for name, direction, perspective, distance in (
            ("assembled_three_quarter_front", (0.75, 1.0, 0.55), True, 4.6),
            ("assembled_side", (1.0, 0.0, 0.0), False, 0.0),
            ("assembled_front", (0.0, 1.0, 0.0), False, 0.0),
            ("assembled_above", (0.0, 0.0, 1.0), False, 0.0),
        ):
            kit.render_view(chassis, os.path.join(previews, name + ".png"), direction, 1.7, perspective,
                            distance, (0.0, 0.0, 0.0) if name == "assembled_above" else focus,
                            keep_visible=(ground,))
        kit.set_preview_colors(False)
        kit.render_view(chassis, os.path.join(previews, "assembled_palette.png"), (0.75, 1.0, 0.55), 1.7,
                        True, 4.6, focus, keep_visible=(ground,))
    return report


def main() -> None:
    previews = kit.preview_dir("chassis")
    kit.reset_scene()
    materials = [kit.get_material(n) for n in ("rover_body", "rover_metal", "rover_dark")]
    bm, non_manifold = build_chassis()
    chassis = kit.mesh_object("chassis", bm, materials)
    kit.make_collision_child(chassis, collision_box())
    for name, location in SOCKETS.items():
        kit.add_socket(chassis, name, location)
    tris = kit.triangle_count(chassis)
    if tris > TRIANGLE_BUDGET:
        raise RuntimeError("chassis is over budget: %d" % tris)
    kit.save_blend(os.path.join(kit.PARTS_DIR, "chassis.blend"))
    kit.export_part(chassis, os.path.join(kit.EXPORT_DIR, "chassis.glb"))

    report = ["chassis: %d triangles (budget %d), body non-manifold edges: %d" % (tris, TRIANGLE_BUDGET, non_manifold)]
    if previews:
        kit.set_preview_colors(True)
        for name, direction in (("chassis_three_quarter_front", (0.75, 1.0, 0.6)),
                                ("chassis_three_quarter_rear", (-0.75, -1.0, 0.6)),
                                ("chassis_below_front", (0.5, 1.0, -0.45))):
            kit.render_view(chassis, os.path.join(previews, name + ".png"), direction, 1.2, True, 2.6,
                            (0.0, 0.0, 0.32))
        kit.set_preview_colors(False)

    report += check_assembly(previews)
    print("\n".join("ROVER_KIT " + line for line in report))


main()
