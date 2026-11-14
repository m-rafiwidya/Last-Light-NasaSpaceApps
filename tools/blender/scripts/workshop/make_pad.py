"""Generates the charging / service pad (A02, WORKSHOP_KIT.md 6.1): ws_pad (plates, guide lines,
contact plate, status strips and the travelling charge probe), ws_charger (cabinet and beacon)
and ws_cable_cover. Checks the probe against the rover's belly at the dock zone's edge and at
any heading, and renders previews.

    blender -b --factory-startup -P tools/blender/scripts/workshop/make_pad.py [-- --previews DIR | --no-previews]

Writes tools/blender/parts/workshop/pad.blend, game/res/models/workshop_kit/{ws_pad,ws_charger,
ws_cable_cover}.glb and previews in tools/blender/previews/workshop/pad/. Needs the rover kit's
chassis, rocker and bogie .blend files (for the belly check).

Kit coordinates; origins:
    ws_pad          the dock point on the floor (-0.1, -0.3, 0)
    charge_probe    child of ws_pad, same origin; Godot moves it in x / -z up to 0.4 m and raises it
                    0.28 m (+y)
    ws_charger      middle of its back face's bottom edge, on the partition (2.05, 3.1, 0)
    ws_cable_cover  its cabinet end on the floor (1.65, 3.1, 0)
"""

import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

sys.path.append(os.path.dirname(__file__))
import workshop_kit_common as ws  # noqa: E402
import make_shell as shell  # noqa: E402

BUDGETS = {"ws_pad": 690, "ws_charger": 680, "ws_cable_cover": 40}
D = ws.DOCK
Z_PLATES, Z_CONTACT, Z_LINES = 0.002, 0.003, 0.004
PROBE_HEAD_R, PROBE_POST_R = 0.05, 0.045
CABLE_END = Vector((D.x + ws.CONTACT_PLATE / 2.0, D.y + ws.CONTACT_PLATE / 2.0, 0.0))


def chevron(cx: float, cy: float, size: float = 0.2, thickness: float = 0.07) -> list:
    """Outline of a chevron pointing +Y, centred at (cx, cy)."""
    s, t = size, thickness
    return [(cx - s, cy - 0.6 * s), (cx, cy + 0.4 * s), (cx + s, cy - 0.6 * s), (cx + s, cy - 0.6 * s + t),
            (cx, cy + 0.4 * s + t), (cx - s, cy - 0.6 * s + t)]


def make_pad():
    hx, hy = ws.PAD_SIZE[0] / 2.0, ws.PAD_SIZE[1] / 2.0
    bm = ws.new_bmesh()
    # Six dark plates with 2 cm seams
    xs = [(-hx, -0.01), (0.01, hx)]
    ys = [(-hy, -hy / 3.0 - 0.01), (-hy / 3.0 + 0.01, hy / 3.0 - 0.01), (hy / 3.0 + 0.01, hy)]
    for x in xs:
        for y in ys:
            ws.floor_quad(bm, (D.x + x[0], D.x + x[1]), (D.y + y[0], D.y + y[1]), Z_PLATES, 0)
    # Contact plate (grating) with an amber border and the dock-zone circle
    c = ws.CONTACT_PLATE / 2.0
    ws.floor_quad(bm, (D.x - c, D.x + c), (D.y - c, D.y + c), Z_CONTACT, 2)
    b = 0.04
    for x, y in (((-c, c), (c - b, c)), ((-c, c), (-c, -c + b)), ((-c, -c + b), (-c + b, c - b)), ((c - b, c), (-c + b, c - b))):
        ws.floor_quad(bm, (D.x + x[0], D.x + x[1]), (D.y + y[0], D.y + y[1]), Z_LINES, 1)
    ws.ring(bm, (D.x, D.y), ws.DOCK_ZONE - 0.015, ws.DOCK_ZONE + 0.015, Z_LINES, 1, 24)
    # Guide lines: dashed centre line (the way in and out) and two wheel tracks
    for sign in (-1.0, 1.0):
        y = c + 0.05
        while y + 0.25 <= hy - 0.1:
            ws.floor_quad(bm, (D.x - 0.025, D.x + 0.025), (D.y + sign * y, D.y + sign * (y + 0.25)), Z_LINES, 1)
            y += 0.4
        ws.floor_quad(bm, (D.x + sign * 0.475, D.x + sign * 0.525), (D.y - hy + 0.1, D.y + hy - 0.1), Z_LINES, 1)
    # Chevrons at the door end, pointing out
    for cx in (-0.95, 0.95):
        ws.floor_polygon(bm, chevron(D.x + cx, D.y + hy - 0.35), Z_LINES, 1)
    root = ws.make_object("ws_pad", bm, ["ws_frame", "ws_accent", "ws_dark"], origin=D)

    bm = ws.new_bmesh()
    for sign in (-1.0, 1.0):
        ws.floor_quad(bm, (D.x + sign * (hx - 0.06), D.x + sign * (hx - 0.02)), (D.y - hy + 0.2, D.y + hy - 0.2),
                      Z_LINES, 0)
    ws.make_object("pad_status_light", bm, ["ws_status"], parent=root)

    # Probe, lowered: the contact head's top just under the contact plate
    bm = ws.new_bmesh()
    ws.cylinder(bm, (D.x, D.y, 0.0), "z", 0.08, -0.36, -0.32, 0, 8)                        # carriage foot
    ws.cylinder(bm, (D.x, D.y, 0.0), "z", PROBE_POST_R, -0.32, -0.03, 0, 8)
    ws.cylinder(bm, (D.x, D.y, 0.0), "z", PROBE_HEAD_R, -0.03, 0.0, 1, 8)
    ws.make_object("charge_probe", bm, ["ws_frame", "ws_accent"], origin=D, parent=root)

    ws.add_empty(root, "dock_point", (D.x, D.y, ws.ROVER_RIDE))
    ws.add_empty(root, "anchor_charge", (D.x, D.y, ws.ROVER_BELLY))
    ws.add_empty(root, "pivot_charge_probe", D)
    ws.add_empty(root, "trigger_dock", (D.x, D.y, 0.75))
    return root


def make_charger():
    o = ws.CHARGER_ORIGIN
    x0, x1, y0, y1, top = o.x - 0.40, o.x, o.y - 0.40, o.y + 0.40, 1.6
    bm = ws.new_bmesh()
    ws.box(bm, (x0, x1), (y0, y1), (0.0, top), 0)
    ws.trim(bm, (x0 - 0.02, x0), (y0, y1), (0.0, 0.10), 1, "+x")                  # kick plate
    for z in (0.25, 0.35, 0.45, 0.55):                                             # vents
        ws.quad(bm, [(x0 - 0.001, y0 + 0.15, z), (x0 - 0.001, y1 - 0.15, z), (x0 - 0.001, y1 - 0.15, z + 0.05),
                     (x0 - 0.001, y0 + 0.15, z + 0.05)], 2, (-1, 0, 0))
    for y, z in (((y0 + 0.05, y1 - 0.05), (0.70, 0.72)), ((y0 + 0.05, y1 - 0.05), (1.45, 1.47)),
                 ((y0 + 0.05, y0 + 0.07), (0.72, 1.45)), ((y1 - 0.07, y1 - 0.05), (0.72, 1.45))):
        ws.trim(bm, (x0 - 0.01, x0), y, z, 1, "+x")                                 # service door seam
    ws.trim(bm, (x0 - 0.03, x0), (y0 + 0.30, y0 + 0.36), (1.0, 1.15), 1, "+x")      # handle
    ws.cylinder(bm, (x0, o.y, 0.06), "x", 0.04, -0.05, 0.0, 2, 8, (True, False))   # cable gland
    root = ws.make_object("ws_charger", bm, ["ws_panel", "ws_frame", "ws_dark"], origin=o)
    ws.collision_box(root, "ws_charger_body", (x0, x1), (y0, y1), (0.0, top))
    bm = ws.new_bmesh()
    ws.dome(bm, (x0 + 0.20, o.y, top), 0.06, 0, 8)
    ws.trim(bm, (x0 - 0.01, x0), (o.y - 0.15, o.y + 0.15), (1.30, 1.36), 0, "+x")
    ws.make_object("charger_status_light", bm, ["ws_status"], parent=root)
    ws.add_empty(root, "trigger_charger", (x0 + 0.20, o.y, 1.0))
    return root


def make_cable_cover():
    start = Vector((ws.CHARGER_ORIGIN.x - 0.40, ws.CHARGER_ORIGIN.y, 0.0))
    end = CABLE_END
    direction = (end - start).normalized()
    across = Vector((-direction.y, direction.x, 0.0))
    length = (end - start).length

    def place(u, v, w):
        return tuple(start + across * u + Vector((0.0, 0.0, v)) + direction * w)
    bm = ws.new_bmesh()
    faces = ws.rk.prism(bm, [(-0.06, 0.0), (0.06, 0.0), (0.04, 0.005), (-0.04, 0.005)], place, 0.0, length)
    ws.bmesh.ops.recalc_face_normals(bm, faces=faces)
    # The bottom never shows
    for f in [f for f in faces if f.normal.z < -0.9]:
        bm.faces.remove(f)
    root = ws.make_object("ws_cable_cover", bm, ["ws_frame"], origin=start)
    return root


# --- Checks ----------------------------------------------------------------------------------

def append_rover() -> list:
    """The rover's body and linkage in their rest pose (rover frame: origin at the physics origin,
    ground at z -0.10)."""
    roots = []
    for blend, names in (("chassis", ["chassis"]), ("rocker", ["rocker_L", "rocker_R"]), ("bogie", ["bogie_L", "bogie_R"])):
        roots += ws.rk.append_objects(os.path.join(ws.ROVER_PARTS_DIR, blend + ".blend"), names)
    # The linkage files keep their roots at the origin: put them on their sockets (ROVER_KIT.md 3.3)
    sockets = {"rocker_R": (0.25, 0.0, 0.27), "rocker_L": (-0.25, 0.0, 0.27),
               "bogie_R": (0.30, -0.25, 0.20), "bogie_L": (-0.30, -0.25, 0.20), "chassis": (0.0, 0.0, 0.0)}
    for r in roots:
        r.location = sockets[r.name]
    bpy.context.view_layer.update()
    return roots


def rover_meshes(roots: list) -> list:
    out = []
    for r in roots:
        out += [o for o in [r] + list(r.children_recursive) if o.type == "MESH" and "-convcolonly" not in o.name]
    return out


def run_checks(roots: dict, rover: list, rows: list) -> int:
    failures = 0
    for name, root in roots.items():
        failures += ws.check_part(root, BUDGETS[name], None, rows)
    pad = roots["ws_pad"]
    probe = next(o for o in pad.children if o.name == "charge_probe")
    meshes = rover_meshes(rover)
    # The probe follows the rover's origin, so test the rover at the zone's edge and odd headings
    worst = (1e9, "")
    for dx, dy in ((0.0, 0.0), (ws.DOCK_ZONE, 0.0), (0.0, -ws.DOCK_ZONE), (-0.283, 0.283)):
        for heading in (0, 37, 90, 180, 251):
            rover_matrix = (Matrix.Translation((D.x + dx, D.y + dy, ws.ROVER_RIDE)) @
                            Matrix.Rotation(math.radians(heading), 4, "Z"))
            probe_matrix = Matrix.Translation((dx, dy, ws.PROBE_RISE))
            for r in rover:
                r.matrix_world = rover_matrix @ r.matrix_world
            bpy.context.view_layer.update()
            g = shell.gap([probe], meshes, probe_matrix)
            for r in rover:
                r.matrix_world = rover_matrix.inverted() @ r.matrix_world
            bpy.context.view_layer.update()
            worst = min(worst, (g, "offset (%+.2f, %+.2f), heading %d" % (dx, dy, heading)))
    ok = worst[0] >= shell.MIN_GAP - 1e-6
    failures += 0 if ok else 1
    rows.append("charge_probe raised (top z %.2f) to the rover's belly: least gap %.1f mm (%s)%s" % (
        ws.PROBE_RISE, worst[0] * 1000.0, worst[1], "" if ok else "  FAIL"))
    lo, hi = ws.bounds([probe])
    rows.append("charge_probe lowered: top at z %.3f, under the contact plate (z %.3f)" % (hi.z, Z_CONTACT))
    failures += 0 if hi.z < Z_CONTACT else 1
    lo, hi = ws.bounds([pad])
    rows.append("ws_pad plates %.2f x %.2f m, decals %.0f-%.0f mm above the floor" % (
        hi.x - lo.x, hi.y - lo.y, lo.z * 1000.0, hi.z * 1000.0))
    lo, hi = ws.bounds([roots["ws_charger"]])
    rows.append("ws_charger %.2f x %.2f x %.2f m (beacon included), front at x %.2f" % (
        hi.x - lo.x, hi.y - lo.y, hi.z - lo.z, lo.x))
    lo, hi = ws.bounds([roots["ws_cable_cover"]])
    rows.append("ws_cable_cover %.3f m high" % (hi.z - lo.z))
    return failures


def render_previews(roots: dict, rover: list, previews: str) -> None:
    ws.set_preview_colors(True)
    pad = roots["ws_pad"]
    shown = tuple(r for r in roots.values() if r is not pad)
    keep = tuple(o for r in shown for o in [r] + list(r.children_recursive))
    ws.render(pad, os.path.join(previews, "pad_above.png"), (0.0, 0.0, 1.0), 5.5, keep_visible=keep,
              focus=(0.6, 1.2, 0.0))
    ws.render(pad, os.path.join(previews, "pad_from_door.png"), (0.15, 1.0, 0.6), 6.0, True, 11.0, (0.4, 0.8, 0.3),
              keep_visible=keep)
    ws.render(roots["ws_charger"], os.path.join(previews, "charger_front.png"), (-1.0, -0.4, 0.3), 2.0, True, 4.5,
              (-0.2, 0.0, 0.85))
    ws.render(roots["ws_charger"], os.path.join(previews, "charger_side.png"), (0.0, -1.0, 0.0), 2.0)
    # Probe raised under the rover, docked 0.3 m off the dock point at a skewed heading
    probe = next(o for o in pad.children if o.name == "charge_probe")
    probe.location = D + Vector((0.3, -0.1, ws.PROBE_RISE))   # parent-inverse space: world
    rover_matrix = Matrix.Translation((D.x + 0.3, D.y - 0.1, ws.ROVER_RIDE)) @ Matrix.Rotation(math.radians(37), 4, "Z")
    for r in rover:
        r.matrix_world = rover_matrix @ r.matrix_world
    bpy.context.view_layer.update()
    rover_objs = tuple(o for r in rover for o in [r] + list(r.children_recursive))
    ws.render(pad, os.path.join(previews, "probe_under_rover_side.png"), (1.0, -0.3, 0.02), 1.4, False,
              focus=(0.3, -0.1, 0.25), keep_visible=rover_objs)
    ws.render(pad, os.path.join(previews, "probe_under_rover_low.png"), (0.9, -0.6, 0.12), 2.0, True, 4.0,
              (0.3, -0.1, 0.2), keep_visible=rover_objs)
    ws.set_preview_colors(False)


def main() -> None:
    previews = ws.preview_dir("pad")
    ws.rk.reset_scene()
    roots = {"ws_pad": make_pad(), "ws_charger": make_charger(), "ws_cable_cover": make_cable_cover()}
    bpy.context.view_layer.update()
    for root in roots.values():
        ws.export(root)
    ws.add_references()
    rover = append_rover()
    rows = []
    failures = run_checks(roots, rover, rows)
    if previews:
        render_previews(roots, rover, previews)
    # The rover was only borrowed for the checks and previews
    for r in rover:
        for o in [r] + list(r.children_recursive):
            bpy.data.objects.remove(o)
    probe = bpy.data.objects["charge_probe"]
    probe.location = D.copy()
    ws.save("pad")
    rows.append("ALL CHECKS OK" if failures == 0 else "%d CHECK FAILURES" % failures)
    ws.report("pad", rows)


if __name__ == "__main__":
    main()
