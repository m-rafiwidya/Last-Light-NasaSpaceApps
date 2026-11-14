"""Generates the astronaut's two workshop props (ASTRONAUT_KIT.md 7): ws_suit_stand, the storage
stand for the empty suit in the operator area's south-east corner, and ws_stool, the counter stool
the seated operator sits on at the console. Checks and previews.

    blender -b --factory-startup -P tools/blender/scripts/workshop/make_suit_props.py [-- --previews DIR | --no-previews]

Writes tools/blender/parts/workshop/suit_props.blend, game/res/models/workshop_kit/ws_suit_stand.glb
and ws_stool.glb, and previews in tools/blender/previews/workshop/suit_props/.

Kit coordinates. ws_suit_stand's origin is the middle of its back edge on the south wall's face;
it carries `anchor_suit`, where the empty suit's origin goes (astronaut_rack.glb). ws_stool's
origin is its centre on the floor; the workshop shows it only with the seated operator, so it
has no collision.
"""

import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.append(os.path.dirname(__file__))
import workshop_kit_common as ws  # noqa: E402

STAND_BUDGET = 250
STOOL_BUDGET = 200
S = ws.SUIT_STAND
WALL_Y = S.y
PLATE = ws.SUIT_STAND_PLATE
SHELF_TOP = ws.SUIT_STAND_SHELF
SUIT = ws.SUIT_ON_STAND
BACKPACK_BACK = SUIT.y - 0.40          # the suit's backpack back face (ASTRONAUT_KIT.md 4)
CONTACT = 0.002                        # the clamp pads stop this short of the backpack
UPRIGHTS = ((S.x - 0.32, S.x - 0.26), (S.x + 0.26, S.x + 0.32))
STAND_TOP = 2.00
# The stand with its suit and helmet, for the collision box (the suit fits inside it:
# make_astronaut.py checks that)
STAND_BOX = ((S.x - 0.45, S.x + 0.45), (WALL_Y, WALL_Y + 0.80), (0.0, 2.15))


def make_stand():
    bm = ws.new_bmesh()
    x0, x1 = S.x - 0.38, S.x + 0.38
    front = WALL_Y + 0.75
    # Floor plate with a flush amber front strip
    ws.box(bm, (x0, x1), (WALL_Y, front), (0.0, PLATE), 0)
    ws.floor_quad(bm, (x0 + 0.02, x1 - 0.02), (front - 0.025, front - 0.005), PLATE + 0.002, 1)
    # Two uprights against the wall, outside the backpack's width
    for ux in UPRIGHTS:
        ws.box(bm, ux, (WALL_Y, WALL_Y + 0.06), (PLATE, STAND_TOP), 0)
    # Backpack clamp: a crossbar between the uprights, two pads forward to the backpack's back face
    clamp_z = (PLATE + 1.22, PLATE + 1.28)
    ws.box(bm, (UPRIGHTS[0][1], UPRIGHTS[1][0]), (WALL_Y, WALL_Y + 0.04), clamp_z, 0)
    for px in ((S.x - 0.15, S.x - 0.08), (S.x + 0.08, S.x + 0.15)):
        ws.box(bm, px, (WALL_Y + 0.04, BACKPACK_BACK - CONTACT), clamp_z, 2)
    # Helmet shelf between the uprights at SHELF_TOP, an amber front lip, two brackets under it
    shelf_front = WALL_Y + 0.40
    ws.box(bm, (UPRIGHTS[0][1], UPRIGHTS[1][0]), (WALL_Y, shelf_front), (SHELF_TOP - 0.03, SHELF_TOP), 0)
    ws.box(bm, (UPRIGHTS[0][1], UPRIGHTS[1][0]), (shelf_front - 0.015, shelf_front), (SHELF_TOP, SHELF_TOP + 0.02), 1)
    for ux in UPRIGHTS:
        inner = ux[1] if ux[0] < S.x else ux[0] - 0.03
        ws.box(bm, (inner, inner + 0.03), (WALL_Y + 0.06, shelf_front - 0.06), (SHELF_TOP - 0.10, SHELF_TOP - 0.03), 0)
    root = ws.make_object("ws_suit_stand", bm, ["ws_frame", "ws_accent", "ws_dark"], origin=S)
    ws.collision_box(root, "ws_suit_stand", *STAND_BOX)
    ws.add_empty(root, "anchor_suit", SUIT)
    return root


def make_stool():
    c = ws.SEAT
    bm = ws.new_bmesh()
    top = ws.STOOL_SEAT_TOP
    ws.cylinder(bm, (c.x, c.y, top), "z", ws.STOOL_SEAT_RADIUS, -0.04, 0.0, 2, 12)
    ws.cylinder(bm, (c.x, c.y, 0.0), "z", 0.025, 0.03, top - 0.04, 0, 8, (False, False))
    # Base: two crossed feet
    for along in ("x", "y"):
        h = 0.25
        if along == "x":
            ws.box(bm, (c.x - h, c.x + h), (c.y - 0.02, c.y + 0.02), (0.0, 0.03), 0)
        else:
            ws.box(bm, (c.x - 0.02, c.x + 0.02), (c.y - h, c.y + h), (0.0, 0.03), 0)
    # Foot ring (8 segments, square section) on two crossed spokes
    r, t = ws.STOOL_RING_RADIUS, 0.012
    zc = ws.STOOL_RING_TOP - t
    corners = [(-t, -t), (t, -t), (t, t), (-t, t)]
    n = 8
    rings = []
    for k in range(n):
        a = 2 * math.pi * (k + 0.5) / n
        radial = Vector((math.cos(a), math.sin(a), 0.0))
        rings.append([bm.verts.new(Vector((c.x, c.y, zc)) + radial * (r + du) + Vector((0, 0, dv))) for du, dv in corners])
    faces = []
    for k in range(n):
        a, b = rings[k], rings[(k + 1) % n]
        for j in range(4):
            f = bm.faces.new((a[j], a[(j + 1) % 4], b[(j + 1) % 4], b[j]))
            faces.append(f)
    # Each face points away from the ring's own centre line
    bm.normal_update()
    for f in faces:
        m = f.calc_center_median()
        radial = Vector((m.x - c.x, m.y - c.y, 0.0))
        mid = Vector((c.x, c.y, zc)) + radial.normalized() * r
        if f.normal.dot(m - mid) < 0.0:
            f.normal_flip()
        f.material_index = 0
    ws.box(bm, (c.x - r, c.x + r), (c.y - 0.01, c.y + 0.01), (zc - 0.01, zc + 0.01), 0)
    ws.box(bm, (c.x - 0.01, c.x + 0.01), (c.y - r, c.y + r), (zc - 0.01, zc + 0.01), 0)
    return ws.make_object("ws_stool", bm, ["ws_frame", "ws_accent", "ws_dark"], origin=c)


def run_checks(stand, stool, rows: list) -> int:
    failures = ws.check_part(stand, STAND_BUDGET, None, rows)
    failures += ws.check_part(stool, STOOL_BUDGET, None, rows)
    lo, hi = ws.bounds([stand])
    inside = lo.x >= ws.PARTITION_X + 0.05 and hi.x <= ws.INNER_X - 0.02 and lo.y >= -ws.INNER_Y - 1e-6
    failures += 0 if inside else 1
    rows.append("ws_suit_stand x %.2f to %.2f, y %.2f to %.2f, top %.2f; %.2f m to the east wall%s" % (
        lo.x, hi.x, lo.y, hi.y, hi.z, ws.INNER_X - hi.x, "" if inside else "  FAIL"))
    lo, hi = ws.bounds([stool])
    rows.append("ws_stool %.2f m across, seat top %.2f m, foot ring top %.2f m" % (hi.x - lo.x, hi.z, ws.STOOL_RING_TOP))
    failures += 0 if abs(hi.z - ws.STOOL_SEAT_TOP) < 1e-6 else 1
    return failures


def render_previews(stand, stool, previews: str) -> None:
    ws.set_preview_colors(True)
    ws.render(stand, os.path.join(previews, "stand_front.png"), (0.3, 1.0, 0.35), 2.6, True, 6.5, (0.0, 0.3, 1.0))
    ws.render(stand, os.path.join(previews, "stand_side.png"), (1.0, 0.0, 0.0), 2.4, focus=(0.0, 0.4, 1.05))
    ws.render(stool, os.path.join(previews, "stool.png"), (0.8, -1.0, 0.6), 1.0, True, 3.0, (0.0, 0.0, 0.32))
    ws.set_preview_colors(False)


def main() -> None:
    previews = ws.preview_dir("suit_props")
    ws.rk.reset_scene()
    stand = make_stand()
    stool = make_stool()
    bpy.context.view_layer.update()
    ws.export(stand)
    ws.export(stool)
    ws.add_references()
    rows = []
    failures = run_checks(stand, stool, rows)
    if previews:
        render_previews(stand, stool, previews)
    ws.save("suit_props")
    rows.append("ALL CHECKS OK" if failures == 0 else "%d CHECK FAILURES" % failures)
    ws.report("suit_props", rows)


if __name__ == "__main__":
    main()
