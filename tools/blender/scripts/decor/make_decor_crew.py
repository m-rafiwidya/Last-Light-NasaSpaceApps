"""Generates the workshop decor's signs of the crew (DECOR_KIT.md 3.3, 3.4, 6): the mug, the
tablet (screen off), the plant-growth lab under the east window, the service-note clipboard and
the history card frame. Checks and previews.

    blender -b --factory-startup -P tools/blender/scripts/decor/make_decor_crew.py [-- --previews DIR | --no-previews]

Writes tools/blender/parts/decor/decor_crew.blend, game/res/models/decor_kit/<piece>.glb and
previews in tools/blender/previews/decor/crew/.

No words are modelled: every piece with text has `text` (and the card `photo`) anchors, and
Godot draws the words from game/res/decor/decor_texts.json and puts the photo on `card_photo`.
"""

import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.append(os.path.dirname(__file__))
import decor_kit_common as dc  # noqa: E402

ws = dc.ws
SPECS = {
    "dc_mug": (130, (0.11, 0.08, 0.10)),
    "dc_tablet": (40, (0.25, None, None)),
    "dc_plant_lab": (400, (0.90, 0.25, None)),
    "dc_service_note": (40, (0.23, None, 0.32)),
    "dc_history_card": (50, (0.50, None, 0.75)),
}
# The history card (DECOR_KIT.md 6): frame, photo and caption plate, from the frame's centre
CARD_W, CARD_H = 0.50, 0.75
PHOTO = 0.42
PHOTO_TOP = CARD_H / 2.0 - 0.04
CAPTION = (-CARD_H / 2.0 + 0.04, PHOTO_TOP - PHOTO - 0.03)   # the caption plate's z range
# The service note: clipboard and paper
BOARD_W, BOARD_H = 0.23, 0.32
PAPER_W, PAPER_H = 0.21, 0.27


def make_mug():
    """A mug on the desk: white with an amber band, coffee in it, a handle on +X."""
    bm = ws.new_bmesh()
    r, h = 0.04, 0.10
    ws.cylinder(bm, (0.0, 0.0, 0.0), "z", r, 0.0, 0.07, 0, 8, (False, False))
    ws.cylinder(bm, (0.0, 0.0, 0.0), "z", r, 0.07, 0.085, 1, 8, (False, False))
    ws.cylinder(bm, (0.0, 0.0, 0.0), "z", r, 0.085, h, 0, 8, (False, False))
    inner = ws.cylinder(bm, (0.0, 0.0, 0.0), "z", r - 0.005, 0.075, h, 0, 8, (False, False))
    for f in inner:
        f.normal_flip()
    ws.ring(bm, (0.0, 0.0, 0.0), r - 0.005, r, h, 0, 8)
    ws.floor_polygon(bm, [((r - 0.005) * math.cos(a), (r - 0.005) * math.sin(a))
                          for a in (2 * math.pi * (k + 0.5) / 8 for k in range(8))], 0.075, 2)      # coffee
    # Handle: an outer bar and two arms
    ws.box(bm, (r + 0.02, r + 0.03), (-0.006, 0.006), (0.025, 0.080), 0)
    for z in (0.025, 0.068):
        ws.box(bm, (r - 0.004, r + 0.02), (-0.006, 0.006), (z, z + 0.012), 0)
    return ws.make_object("dc_mug", bm, ["ws_label", "ws_accent", "ws_dark"])


def make_tablet():
    """A tablet propped up on its kickstand, screen off, facing the operator (-Y): 60 degrees up
    from the desk, so it shows over the console's control deck."""
    bm = ws.new_bmesh()
    ws.box(bm, (-0.125, 0.125), (-0.09, 0.09), (0.0, 0.01), 0)
    ws.floor_quad(bm, (-0.112, 0.112), (-0.077, 0.077), 0.012, 1)
    # Stand it on its long bottom edge (y -0.09) and lean it back 30 degrees from upright
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0.0, -0.09, 0.0), matrix=Matrix.Rotation(math.radians(60.0), 3, "X"))
    # Kickstand: a thin strut from the tablet's back (6.5 cm up) down to the desk behind it
    top = Vector((0.0, -0.09 + 0.065 / math.tan(math.radians(60.0)), 0.065))
    foot = Vector((0.0, 0.045, 0.0))
    run = top - foot
    faces = ws.box(bm, (-0.03, 0.03), (0.0, run.length), (0.0, 0.005), 0)
    verts = list({v for f in faces for v in f.verts})
    bmesh.ops.rotate(bm, verts=verts, cent=(0.0, 0.0, 0.0), matrix=Matrix.Rotation(math.atan2(run.z, run.y), 3, "X"))
    bmesh.ops.translate(bm, verts=verts, vec=foot)
    return ws.make_object("dc_tablet", bm, ["ws_dark", "ws_screen"])


def seedling(bm, x: float, y: float, z: float, height: float, turn: float):
    """A seedling: a thin stem and three leaves."""
    ws.box(bm, (x - 0.003, x + 0.003), (y - 0.003, y + 0.003), (z, z + height), 0)
    for k in range(3):
        a = turn + 2 * math.pi * k / 3
        d = Vector((math.cos(a), math.sin(a), 0.0))
        n = Vector((-math.sin(a), math.cos(a), 0.0))
        base = Vector((x, y, z + height * (0.75 + 0.1 * k)))
        tip = base + d * 0.045 + Vector((0.0, 0.0, 0.012))
        pts = [base - n * 0.004, base + n * 0.004, tip + n * 0.018 - d * 0.015, tip, tip - n * 0.018 - d * 0.015]
        quad1 = [pts[0], pts[1], pts[2], pts[3]]
        quad2 = [pts[0], pts[3], pts[4]]
        for poly in (quad1, quad2):
            # One-sided: the kit's materials export double-sided
            f = bm.faces.new([bm.verts.new(p) for p in poly])
            f.material_index = 0


def make_plant_lab():
    """A plant-growth chamber on a wall shelf (origin: the back's middle at the shelf top): a
    tray with soil and six seedlings under a clear lid with a grow strip, a small label plate."""
    bm = ws.new_bmesh()
    plants = ws.new_bmesh()
    # Shelf and two brackets under it
    ws.box(bm, (-0.45, 0.45), (-0.25, 0.0), (-0.03, 0.0), 0)
    for x in (-0.35, 0.35):
        ws.box(bm, (x - 0.015, x + 0.015), (-0.20, 0.0), (-0.10, -0.03), 0)
    # Chamber: a tray, soil, the lid (glass, with corner posts) and the grow strip under its top
    x0, x1, y0, y1 = -0.40, 0.40, -0.23, -0.01
    ws.box(bm, (x0, x1), (y0, y1), (0.0, 0.06), 0)
    ws.floor_quad(bm, (x0 + 0.02, x1 - 0.02), (y0 + 0.02, y1 - 0.02), 0.062, 3)
    ws.box(bm, (x0, x1), (y0, y1), (0.06, 0.30), 4)
    for x in (x0, x1 - 0.015):
        for y in (y0, y1 - 0.015):
            ws.box(bm, (x - 0.001, x + 0.016), (y - 0.001, y + 0.016), (0.06, 0.30), 0)
    ws.box(bm, (-0.35, 0.35), (-0.135, -0.105), (0.272, 0.285), 5)
    # Label plate on the tray front
    ws.trim(bm, (-0.36, -0.12), (y0 - 0.003, y0), (0.012, 0.050), 2, "+y")
    for k, (x, y) in enumerate(((-0.28, -0.08), (-0.16, -0.16), (-0.04, -0.07), (0.08, -0.16), (0.20, -0.08), (0.30, -0.15))):
        seedling(plants, x, y, 0.062, 0.05 + 0.015 * (k % 3), 0.7 * k)
    root = ws.make_object("dc_plant_lab", bm, ["ws_frame", "ws_panel", "ws_label", "ws_dark", "ws_glass", "dc_grow"])
    ws.make_object("plant_leaves", plants, ["dc_green"], parent=root)
    ws.collision_box(root, "dc_plant_lab", (-0.45, 0.45), (-0.25, 0.0), (-0.10, 0.30))
    dc.front_text(root, "text", (-0.24, y0 - 0.004, 0.031))
    return root


def make_service_note():
    """A service-note clipboard hung on a nail (origin: the back's middle): a dark board, the
    paper sheet and a pale clip. Godot writes the note on the paper (`text`)."""
    bm = ws.new_bmesh()
    hw, hh = BOARD_W / 2.0, BOARD_H / 2.0
    ws.trim(bm, (-hw, hw), (-0.006, 0.0), (-hh, hh), 0, "+y")
    top = hh - 0.035
    paper_bottom = top - PAPER_H
    ws.quad(bm, [(-PAPER_W / 2.0, -0.007, paper_bottom), (PAPER_W / 2.0, -0.007, paper_bottom),
                 (PAPER_W / 2.0, -0.007, top), (-PAPER_W / 2.0, -0.007, top)], 1, (0.0, -1.0, 0.0))
    ws.box(bm, (-0.05, 0.05), (-0.016, -0.007), (top - 0.03, hh - 0.005), 2)
    ws.box(bm, (-0.012, 0.012), (-0.020, -0.016), (top - 0.02, hh - 0.012), 0)
    root = ws.make_object("dc_service_note", bm, ["ws_frame", "ws_label", "ws_panel"])
    dc.front_text(root, "text", (0.0, -0.008, (top + paper_bottom) / 2.0))
    return root


def make_history_card():
    """A history card (origin: the back's middle): a dark frame with fastener heads, the photo
    quad (child `card_photo`, UVs 0-1, the photo upright as seen from the front) and a pale
    caption plate under it."""
    bm = ws.new_bmesh()
    hw, hh = CARD_W / 2.0, CARD_H / 2.0
    ws.trim(bm, (-hw, hw), (-0.02, 0.0), (-hh, hh), 0, "+y")
    ws.trim(bm, (-PHOTO / 2.0, PHOTO / 2.0), (-0.024, -0.02), CAPTION, 1, "+y")
    for x in (-hw + 0.02, hw - 0.02):
        for z in (-hh + 0.02, hh - 0.02):
            ws.stud(bm, (x, -0.02, z), "-y", 2)
    root = ws.make_object("dc_history_card", bm, ["ws_frame", "ws_label", "ws_dark"])
    # The photo: u along +X (left to right seen from the front), v up
    photo = bmesh.new()
    z0, z1 = PHOTO_TOP - PHOTO, PHOTO_TOP
    verts = [photo.verts.new(p) for p in ((-PHOTO / 2.0, -0.022, z0), (PHOTO / 2.0, -0.022, z0),
                                         (PHOTO / 2.0, -0.022, z1), (-PHOTO / 2.0, -0.022, z1))]
    face = photo.faces.new(verts)
    photo.normal_update()
    if face.normal.y > 0:
        face.normal_flip()
    uv = photo.loops.layers.uv.new("UVMap")
    for loop in face.loops:
        p = loop.vert.co
        loop[uv].uv = ((p.x + PHOTO / 2.0) / PHOTO, (p.z - z0) / PHOTO)
    ws.make_object("card_photo", photo, ["dc_photo"], parent=root)
    dc.front_text(root, "text", (0.0, -0.025, (CAPTION[0] + CAPTION[1]) / 2.0))
    return root


def run_checks(pieces: dict, rows: list) -> int:
    failures = 0
    for name, root in pieces.items():
        budget, size = SPECS[name]
        failures += dc.check_piece(root, budget, size, rows)
    for name in ("dc_plant_lab", "dc_service_note", "dc_history_card"):
        lo, hi = dc.visible_bounds(pieces[name])
        ok = hi.y <= 1e-6
        failures += 0 if ok else 1
        rows.append("%s: %.3f m deep, back on the wall plane%s" % (name, -lo.y, "" if ok else "  FAIL"))
    # The card photo's UVs: 0-1, (0, 0) at the bottom left seen from the front
    photo = next(o for o in pieces["dc_history_card"].children if o.name == "card_photo")
    uvs = [(l.uv[0], l.uv[1], photo.data.vertices[photo.data.loops[i].vertex_index].co)
           for i, l in enumerate(photo.data.uv_layers[0].data)]
    ok = all(abs(u - (co.x + PHOTO / 2.0) / PHOTO) < 1e-5 and abs(v - (co.z - PHOTO_TOP + PHOTO) / PHOTO) < 1e-5 for u, v, co in uvs)
    failures += 0 if ok else 1
    rows.append("card_photo %.2f m square, UVs 0-1 upright from the front%s" % (PHOTO, "" if ok else "  FAIL"))
    # The plant lab stays under the east window's 1.2 m sill when its shelf top is at 0.88 m
    lo, hi = dc.visible_bounds(pieces["dc_plant_lab"])
    top = [p for p in dc.INTERIOR if p[0] == "dc_plant_lab"][0][1][2] + hi.z
    ok = top < 1.2
    failures += 0 if ok else 1
    rows.append("dc_plant_lab top at %.2f m, under the 1.2 m window sill%s" % (top, "" if ok else "  FAIL"))
    return failures


MAKERS = {"dc_mug": make_mug, "dc_tablet": make_tablet, "dc_plant_lab": make_plant_lab,
          "dc_service_note": make_service_note, "dc_history_card": make_history_card}


def main() -> None:
    previews = dc.preview_dir("crew")
    ws.rk.reset_scene()
    pieces = {name: maker() for name, maker in MAKERS.items()}
    bpy.context.view_layer.update()
    for root in pieces.values():
        dc.export(root)
    rows = []
    failures = run_checks(pieces, rows)
    if previews:
        dc.render_pieces(pieces, previews)
    for k, root in enumerate(pieces.values()):
        root.location = (1.2 * k, 0.0, 0.0)
    dc.save("decor_crew")
    rows.append("ALL CHECKS OK" if failures == 0 else "%d CHECK FAILURES" % failures)
    dc.report("crew", rows)


if __name__ == "__main__":
    main()
