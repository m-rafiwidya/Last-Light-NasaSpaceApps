"""Generates the mission console (A03, WORKSHOP_KIT.md 6.2): ws_console (desk, sloped control
deck with switches, dials and a T-handle, the reserved cartridge reader spot, screen housing) and
its child console_screen, one 16:9 quad with UVs 0-1 for Godot's UI. Checks and previews.

    blender -b --factory-startup -P tools/blender/scripts/workshop/make_console.py [-- --previews DIR | --no-previews]

Writes tools/blender/parts/workshop/console.blend, game/res/models/workshop_kit/ws_console.glb and
previews in tools/blender/previews/workshop/console/.

Kit coordinates; origin: the middle of the desk's back edge on the floor (2.15, -0.3, 0). The
operator stands on the +X side and faces -X (the bay, through the partition window).
"""

import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.append(os.path.dirname(__file__))
import workshop_kit_common as ws  # noqa: E402

BUDGET = 1500
O = ws.CONSOLE_ORIGIN
X_BACK, X_FRONT = O.x, O.x + 0.65
Y0, Y1 = O.y - 0.6, O.y + 0.6
DESK_TOP = 0.90
SLOPE = math.radians(15.0)
DECK_BACK = X_BACK + 0.30                       # the control deck rises from the front edge to here
SCREEN_CENTER = Vector((O.x + 0.15, O.y, 1.14))
SCREEN_W, SCREEN_H = 0.64, 0.36
SCREEN_NORMAL = Vector((math.cos(SLOPE), 0.0, math.sin(SLOPE)))   # faces the operator, tilted back 15 degrees
SCREEN_UP = Vector((-math.sin(SLOPE), 0.0, math.cos(SLOPE)))
SCREEN_RIGHT = Vector((0.0, 1.0, 0.0))          # the operator's right, facing -X
CARTRIDGE = (Vector((X_FRONT - 0.25, O.y + 0.30)), Vector((X_FRONT - 0.09, O.y + 0.40)))   # reserved spot


def screen_point(right: float, up: float, out: float = 0.0) -> Vector:
    return SCREEN_CENTER + SCREEN_RIGHT * right + SCREEN_UP * up + SCREEN_NORMAL * out


def oriented_box(bm, right: tuple, up: tuple, out: tuple, mat: int) -> list:
    corners = [screen_point(r, u, o) for o in out for u in up for r in right]
    verts = [bm.verts.new(c) for c in corners]
    quads = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    faces = [bm.faces.new([verts[i] for i in q]) for q in quads]
    for f in faces:
        f.material_index = mat
    ws.bmesh.ops.recalc_face_normals(bm, faces=faces)
    return faces


def make_console():
    bm = ws.new_bmesh()
    # Frame: two side panels, a modesty panel at the back, the desk top
    for y in ((Y0, Y0 + 0.04), (Y1 - 0.04, Y1)):
        ws.box(bm, (X_BACK, X_FRONT), y, (0.0, DESK_TOP - 0.05), 1)
    ws.box(bm, (X_BACK, X_BACK + 0.04), (Y0 + 0.04, Y1 - 0.04), (0.10, DESK_TOP - 0.05), 1)
    ws.box(bm, (X_BACK, X_FRONT), (Y0, Y1), (DESK_TOP - 0.05, DESK_TOP), 0)
    # Control deck: a wedge rising 15 degrees from the front edge back to DECK_BACK
    front = X_FRONT - 0.02
    rise = (front - DECK_BACK) * math.tan(SLOPE)
    outline = [(DECK_BACK, DESK_TOP), (front, DESK_TOP), (DECK_BACK, DESK_TOP + rise)]
    faces = ws.rk.prism(bm, outline, lambda u, v, w: (u, w, v), Y0 + 0.05, Y1 - 0.05)
    for f in faces:
        f.material_index = 2
    ws.bmesh.ops.recalc_face_normals(bm, faces=faces)

    def on_deck(x: float) -> float:
        return DESK_TOP + (front - x) * math.tan(SLOPE)

    # Eight toggle switches in a row, two dials, a T-handle
    for k in range(8):
        y = Y0 + 0.10 + 0.085 * k
        x = front - 0.10
        z = on_deck(x)
        ws.box(bm, (x - 0.02, x + 0.02), (y - 0.015, y + 0.015), (z - 0.01, z + 0.012), 1)
        ws.trim(bm, (x - 0.004, x + 0.004), (y - 0.004, y + 0.004), (z + 0.012, z + 0.04), 3, "-z")
    for y in (Y0 + 0.10, Y0 + 0.25):
        x = DECK_BACK + 0.06
        ws.cylinder(bm, (x, y, on_deck(x) - 0.01), "z", 0.025, 0.0, 0.035, 3, 8, (False, True))
    x, y = front - 0.08, Y1 - 0.12
    ws.box(bm, (x - 0.012, x + 0.012), (y - 0.012, y + 0.012), (on_deck(x) - 0.01, on_deck(x) + 0.06), 1)
    ws.box(bm, (x - 0.012, x + 0.012), (y - 0.06, y + 0.06), (on_deck(x) + 0.06, on_deck(x) + 0.08), 3)
    # Reserved cartridge reader spot: a blank plate flush on the deck (the reader comes with A06)
    (a, b) = CARTRIDGE
    corners = [(a.x, a.y), (b.x, a.y), (b.x, b.y), (a.x, b.y)]
    ws.quad(bm, [(cx, cy, on_deck(cx) + 0.002) for cx, cy in corners], 1, (math.sin(SLOPE), 0.0, math.cos(SLOPE)))
    # Screen housing on a stand at the back edge
    oriented_box(bm, (-SCREEN_W / 2.0 - 0.04, SCREEN_W / 2.0 + 0.04), (-SCREEN_H / 2.0 - 0.04, SCREEN_H / 2.0 + 0.04),
                 (-0.065, -0.004), 1)
    base = screen_point(0.0, -SCREEN_H / 2.0, -0.04)
    ws.box(bm, (X_BACK + 0.02, base.x + 0.01), (O.y - 0.05, O.y + 0.05), (DESK_TOP, base.z + 0.02), 1)
    root = ws.make_object("ws_console", bm, ["ws_panel", "ws_frame", "ws_dark", "ws_accent"], origin=O)

    # The screen: one quad facing the operator, UV (0, 0) at its bottom-left as the operator sees it
    bm = ws.new_bmesh()
    uv = bm.loops.layers.uv.new("UVMap")
    corners = [screen_point(-SCREEN_W / 2.0, -SCREEN_H / 2.0), screen_point(SCREEN_W / 2.0, -SCREEN_H / 2.0),
               screen_point(SCREEN_W / 2.0, SCREEN_H / 2.0), screen_point(-SCREEN_W / 2.0, SCREEN_H / 2.0)]
    face = bm.faces.new([bm.verts.new(c) for c in corners])
    bm.normal_update()
    if face.normal.dot(SCREEN_NORMAL) < 0.0:
        raise RuntimeError("console_screen faces away from the operator")
    for loop, coord in zip(face.loops, ((0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0))):
        loop[uv].uv = coord
    ws.make_object("console_screen", bm, ["ws_screen"], origin=SCREEN_CENTER, parent=root)

    ws.collision_box(root, "ws_console_desk", (X_BACK, X_FRONT), (Y0, Y1), (0.0, DESK_TOP))
    bm = ws.new_bmesh()
    oriented_box(bm, (-SCREEN_W / 2.0 - 0.04, SCREEN_W / 2.0 + 0.04), (-SCREEN_H / 2.0 - 0.04, SCREEN_H / 2.0 + 0.04),
                 (-0.065, 0.0), 0)
    ws.collision_mesh(root, "ws_console_screen_housing", bm)

    ws.add_empty(root, "trigger_console", (O.x + 0.40, O.y, 1.10))
    ws.add_empty(root, "pivot_console_view", SCREEN_CENTER + SCREEN_NORMAL * 0.60)
    ws.add_empty(root, "anchor_prompt_console", (SCREEN_CENTER.x, O.y, 1.42))
    ws.add_empty(root, "anchor_cartridge", ((a.x + b.x) / 2.0, (a.y + b.y) / 2.0, on_deck((a.x + b.x) / 2.0)))
    ws.add_empty(root, "anchor_operator", (O.x + 1.05, O.y, 0.0))
    return root


def run_checks(root, rows: list) -> int:
    failures = ws.check_part(root, BUDGET, None, rows)
    screen = next(o for o in root.children if o.name == "console_screen")
    lo, hi = ws.bounds([screen])
    rows.append("console_screen %.2f x %.2f m (16:9), %d triangles, bottom edge z %.3f, top %.3f, centre (%.2f, %.2f, %.2f)" % (
        SCREEN_W, SCREEN_H, ws.rk.triangle_count(screen), lo.z, hi.z, *SCREEN_CENTER))
    failures += 0 if ws.rk.triangle_count(screen) == 2 else 1
    eye = Vector((O.x + 1.05, O.y, ws.PLAYER_EYE))
    to_screen = SCREEN_CENTER - eye
    rows.append("operator's eye (standing at anchor_operator) to the screen centre: %.2f m, %.0f degrees below level" % (
        to_screen.length, math.degrees(math.asin(-to_screen.z / to_screen.length))))
    lo, hi = ws.bounds([root])
    size = hi - lo
    rows.append("desk %.2f x %.2f m, top at %.2f; with the housing %.2f m tall" % (X_FRONT - X_BACK, Y1 - Y0, DESK_TOP, size.z))
    failures += 0 if abs(X_FRONT - X_BACK - 0.65) < 1e-6 and abs(Y1 - Y0 - 1.2) < 1e-6 else 1
    return failures


def render_previews(root, previews: str) -> None:
    ws.set_preview_colors(True)
    for name, direction in (("operator", (1.0, 0.25, 0.45)), ("operator_low", (1.0, -0.3, 0.1)),
                            ("back", (-1.0, -0.4, 0.4)), ("side", (0.0, 1.0, 0.0))):
        ws.render(root, os.path.join(previews, "console_%s.png" % name), direction, 1.6, name != "side", 3.6,
                  (0.32, 0.0, 0.7))
    ws.render(root, os.path.join(previews, "console_deck_close.png"), (1.0, 0.0, 0.8), 0.9, True, 1.6,
              (0.45, 0.0, 0.95))
    ws.set_preview_colors(False)


def main() -> None:
    previews = ws.preview_dir("console")
    ws.rk.reset_scene()
    root = make_console()
    bpy.context.view_layer.update()
    ws.export(root)
    ws.add_references()
    rows = []
    failures = run_checks(root, rows)
    if previews:
        render_previews(root, previews)
    ws.save("console")
    rows.append("ALL CHECKS OK" if failures == 0 else "%d CHECK FAILURES" % failures)
    ws.report("console", rows)


if __name__ == "__main__":
    main()
