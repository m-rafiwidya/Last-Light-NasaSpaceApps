"""Generates the exterior decor's own piece (DECOR_KIT.md 4.2): dc_junction_box, the power outlet
on the facade east of the bay door. The exterior also uses dc_crate, dc_cable_reel and
dc_sign_warning (make_decor_bay.py); the cable run is built by Godot along CABLE_PATH, resting on
the ground. Checks and previews.

    blender -b --factory-startup -P tools/blender/scripts/decor/make_decor_exterior.py [-- --previews DIR | --no-previews]

Writes tools/blender/parts/decor/decor_exterior.blend, game/res/models/decor_kit/dc_junction_box.glb
and previews in tools/blender/previews/decor/exterior/.
"""

import os
import sys

import bpy
from mathutils import Vector

sys.path.append(os.path.dirname(__file__))
import decor_kit_common as dc  # noqa: E402

ws = dc.ws
BUDGET = 90
SIZE = (0.40, 0.20, 0.50)     # plus 8 mm fastener heads in front


def make_junction_box():
    """A pale outlet box on the wall (origin: the back's middle at its bottom): a dark door seam
    and hinge strip, fastener heads, a cable gland under it (where CABLE_PATH starts) and a
    label plate."""
    bm = ws.new_bmesh()
    hx, d, h = 0.20, 0.20, 0.50
    ws.box(bm, (-hx, hx), (-d + 0.01, 0.0), (0.0, h), 0)
    ws.trim(bm, (-hx + 0.02, hx - 0.02), (-d, -d + 0.01), (0.03, h - 0.03), 0, "+y")     # door
    ws.trim(bm, (-hx + 0.02, -hx + 0.035), (-d - 0.004, -d), (0.06, h - 0.06), 1, "+y")  # hinge strip
    ws.trim(bm, (-0.12, 0.12), (-d - 0.004, -d), (h - 0.13, h - 0.07), 2, "+y")          # label plate
    for x in (-hx + 0.04, hx - 0.04):
        for z in (0.06, h - 0.04):
            ws.stud(bm, (x, -d, z), "-y", 1)
    # Gland under the box: the cable leaves it downwards, 0.10 m out from the wall
    ws.cylinder(bm, (0.0, -0.10, 0.0), "z", 0.025, -0.05, 0.0, 1, 8, (True, False))
    root = ws.make_object("dc_junction_box", bm, ["ws_panel", "ws_frame", "ws_label"])
    dc.front_text(root, "text", (0.0, -d - 0.005, h - 0.10))
    ws.add_empty(root, "anchor_cable", (0.0, -0.10, -0.05))
    return root


def main() -> None:
    previews = dc.preview_dir("exterior")
    ws.rk.reset_scene()
    box = make_junction_box()
    bpy.context.view_layer.update()
    dc.export(box)
    rows = []
    failures = dc.check_piece(box, BUDGET, None, rows)
    lo, hi = dc.visible_bounds(box)
    ok = abs(hi.x - lo.x - SIZE[0]) < 1e-3 and abs(-lo.y - SIZE[1] - 0.008) < 1e-3 and hi.y <= 1e-6
    failures += 0 if ok else 1
    rows.append("dc_junction_box %.2f x %.3f m, %.2f m tall with the gland, back on the wall plane%s" % (
        hi.x - lo.x, -lo.y, hi.z - lo.z, "" if ok else "  FAIL"))
    # The cable path's first point is the gland's bottom, where the placement puts it
    placed = [p for p in dc.EXTERIOR if p[0] == "dc_junction_box"][0]
    anchor = next(o for o in box.children if o.name == "anchor_cable")
    gland = dc.placement_matrix(placed[1], placed[2]) @ anchor.matrix_world.translation
    ok = (gland - Vector(dc.CABLE_PATH[0])).length < 1e-3
    failures += 0 if ok else 1
    rows.append("the cable path starts at the gland, kit (%.2f, %.3f, %.2f)%s" % (tuple(gland) + ("" if ok else "  FAIL",)))
    if previews:
        dc.render_pieces({"dc_junction_box": box}, previews)
    dc.save("decor_exterior")
    rows.append("ALL CHECKS OK" if failures == 0 else "%d CHECK FAILURES" % failures)
    dc.report("exterior", rows)


if __name__ == "__main__":
    main()
