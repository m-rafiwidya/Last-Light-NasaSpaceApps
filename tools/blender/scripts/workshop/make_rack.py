"""Generates the parts rack (A04, WORKSHOP_KIT.md 6.3): ws_rack with its shelves, label rails and
plates, wheel cradles, restock button, slot and label empties. Checks that every part of the
current parts pile fits its slot (from the rover kit GLBs) and renders previews with the rack
loaded.

    blender -b --factory-startup -P tools/blender/scripts/workshop/make_rack.py [-- --previews DIR | --no-previews]

Writes tools/blender/parts/workshop/rack.blend, game/res/models/workshop_kit/ws_rack.glb and
previews in tools/blender/previews/workshop/rack/.

Kit coordinates; origin: the middle of the rack's back edge on the floor (-0.1, -3.8, 0). The
rack's front faces +Y.
"""

import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

sys.path.append(os.path.dirname(__file__))
import workshop_kit_common as ws  # noqa: E402

BUDGET = 1500
O = ws.RACK_ORIGIN
X0, X1 = O.x - ws.RACK_SIZE[0] / 2.0, O.x + ws.RACK_SIZE[0] / 2.0     # -1.35 .. 1.15
Y_BACK, Y_FRONT = O.y, O.y + ws.RACK_SIZE[1]                          # -3.8 .. -3.3
TOP = ws.RACK_SIZE[2]
UPRIGHT = 0.04
BOARD = 0.03
RAIL = 0.02                     # label rail board thickness, at the front
# Each level's front (its label rail's face)
FRONTS = [Y_BACK + d for d in ws.SHELF_DEPTHS]
# Depth (along Y) of each part as it rests on the rack, to stand it 2 cm behind its level's front
PART_DEPTH = {"wheel_L": 0.248, "motor": 0.128, "power_unit": 0.355, "mast_head": 0.092, "arm_tool": 0.058,
              "antenna": 0.191, "radio_module": 0.134, "arm_tool_thermal": 0.058, None: 0.12}
CRADLE_SPACING, CRADLE_HEIGHT = 0.18, 0.04

# WORKSHOP_KIT.md 6.3: slot -> (level, kit x, part GLB, part name). Wheels stand on their tread.
SLOTS = {
    1: (0, -0.98, "wheel_L"), 2: (0, -0.63, "wheel_L"), 3: (0, -0.28, "wheel_L"),
    4: (0, 0.08, "wheel_L"), 5: (0, 0.43, "wheel_L"), 6: (0, 0.78, "wheel_L"),
    7: (1, -1.12, "wheel_L"), 8: (1, -0.78, "wheel_L"), 9: (1, -0.44, "wheel_L"), 10: (1, -0.10, "wheel_L"),
    11: (1, 0.30, "motor"), 12: (1, 0.78, "power_unit"),
    13: (2, -0.90, "mast_head"), 14: (2, -0.45, "arm_tool"), 15: (2, 0.25, "antenna"),
    16: (2, 0.80, None), 17: (3, -0.60, None), 18: (3, 0.40, "radio_module"),
    # The thermal sensor turret (M3, make_m3_kit.py) beside the standard one, under the same plate
    19: (2, -0.20, "arm_tool_thermal"),
}
WHEEL_SLOTS = [n for n, s in SLOTS.items() if s[2] == "wheel_L"]
# label -> (level, x from, x to, text)
LABELS = {
    1: (0, -1.30, 0.95, "WHEELS"), 2: (1, -1.30, 0.08, "HIGH-GRIP WHEELS"), 3: (1, 0.08, 0.54, "MOTOR"),
    4: (1, 0.54, 1.10, "BATTERY"), 5: (2, -1.30, -0.62, "MAST CAMERA"), 6: (2, -0.62, -0.05, "TOOL TURRETS"),
    7: (2, -0.05, 0.53, "ANTENNA"), 8: (2, 0.53, 1.10, "SPARE"), 9: (3, -1.30, 1.10, "CARTRIDGES AND MODULE"),
}
PLATE_GAP = 0.01                # half of the 2 cm gap between neighbouring plates
RESTOCK = Vector((X1 + 0.06, FRONTS[1] - 0.01, 0.90))


def slot_y(n: int) -> float:
    level, _, name = SLOTS[n]
    return FRONTS[level] - RAIL - PART_DEPTH[name] / 2.0


def band(level: int) -> tuple:
    """Height range of the uprights' step at this level's depth."""
    z0 = 0.0 if level == 0 else ws.SHELF_TOPS[level]
    z1 = ws.SHELF_TOPS[level + 1] if level + 1 < len(ws.SHELF_TOPS) else TOP
    return (z0, z1)


def make_rack():
    bm = ws.new_bmesh()
    ws.box(bm, (X0, X1), (Y_BACK, Y_BACK + 0.02), (0.0, TOP), 0)                      # pale back panel
    inner = (X0 + UPRIGHT, X1 - UPRIGHT)
    for level, front in enumerate(FRONTS):
        # Uprights step back with the shelves
        for x in ((X0, X0 + UPRIGHT), (X1 - UPRIGHT, X1)):
            ws.box(bm, x, (Y_BACK + 0.02, front), band(level), 1)
        s = ws.SHELF_TOPS[level]
        ws.box(bm, inner, (Y_BACK + 0.02, front - RAIL), (s - BOARD, s), 1)
        ws.box(bm, inner, (front - RAIL, front), (s - ws.LABEL_RAIL, s), 1)
    ws.box(bm, inner, (Y_BACK + 0.02, FRONTS[-1]), (TOP - 0.02, TOP), 1)
    for n in WHEEL_SLOTS:
        level, x, _ = SLOTS[n]
        s, y = ws.SHELF_TOPS[level], slot_y(n)
        for dx in (-CRADLE_SPACING / 2.0, CRADLE_SPACING / 2.0):
            ws.trim(bm, (x + dx - 0.01, x + dx + 0.01), (y - 0.15, y + 0.15), (s, s + CRADLE_HEIGHT), 2, "-z")
    # Label plates on the rails
    for n, (level, xa, xb, _) in LABELS.items():
        s = ws.SHELF_TOPS[level]
        y = FRONTS[level] + 0.002
        ws.quad(bm, [(xa + PLATE_GAP, y, s - 0.13), (xb - PLATE_GAP, y, s - 0.13), (xb - PLATE_GAP, y, s - 0.01),
                     (xa + PLATE_GAP, y, s - 0.01)], 3, (0, 1, 0))
    # Restock button on a small panel beside the east upright, at shelf 1's step
    panel_y = (FRONTS[1] - 0.10, FRONTS[1] - 0.02)
    ws.box(bm, (X1, X1 + 0.10), panel_y, (0.80, 1.00), 0)
    ws.trim(bm, (X1 + 0.02, X1 + 0.08), (panel_y[1], panel_y[1] + 0.02), (0.87, 0.93), 4, "-y")
    root = ws.make_object("ws_rack", bm, ["ws_panel", "ws_frame", "ws_dark", "ws_label", "ws_accent"], origin=O)

    ws.collision_box(root, "ws_rack_back", (X0, X1), (Y_BACK, Y_BACK + 0.02), (0.0, TOP))
    for level, front in enumerate(FRONTS):
        for i, x in enumerate(((X0, X0 + UPRIGHT), (X1 - UPRIGHT, X1))):
            ws.collision_box(root, "ws_rack_upright_%d_%d" % (i, level), x, (Y_BACK + 0.02, front), band(level))
        s = ws.SHELF_TOPS[level]
        ws.collision_box(root, "ws_rack_shelf_%d" % level, inner, (Y_BACK + 0.02, front - RAIL), (s - BOARD, s))
        ws.collision_box(root, "ws_rack_rail_%d" % level, inner, (front - RAIL, front), (s - ws.LABEL_RAIL, s))
    ws.collision_box(root, "ws_rack_top", inner, (Y_BACK + 0.02, FRONTS[-1]), (TOP - 0.02, TOP))
    for n in WHEEL_SLOTS:
        level, x, _ = SLOTS[n]
        s, y = ws.SHELF_TOPS[level], slot_y(n)
        for k, dx in enumerate((-CRADLE_SPACING / 2.0, CRADLE_SPACING / 2.0)):
            ws.collision_box(root, "ws_rack_cradle_%02d_%d" % (n, k), (x + dx - 0.01, x + dx + 0.01),
                             (y - 0.15, y + 0.15), (s, s + CRADLE_HEIGHT))
    ws.collision_box(root, "ws_rack_restock", (X1, X1 + 0.10), panel_y, (0.80, 1.00))

    for n, (level, x, _) in SLOTS.items():
        ws.add_empty(root, "slot_%02d" % n, (x, slot_y(n), ws.SHELF_TOPS[level]))
    for n, (level, xa, xb, _) in LABELS.items():
        s = ws.SHELF_TOPS[level]
        ws.add_empty(root, "label_%02d" % n, ((xa + xb) / 2.0, FRONTS[level] + 0.002, s - 0.07))
    ws.add_empty(root, "trigger_restock", RESTOCK)
    return root


# --- Parts on the rack (checks and previews) -------------------------------------------------

def import_part(name: str) -> list:
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(ws.REPO_ROOT, "game", "res", "models", "rover_kit", name + ".glb"))
    new = [o for o in bpy.data.objects if o not in before]
    for o in [o for o in new if "convcolonly" in o.name.lower() or o.name.startswith("Collision")]:
        bpy.data.objects.remove(o)
    return [o for o in bpy.data.objects if o not in before]


def load_parts() -> list:
    """Imports each slot's part and stands it on its slot: wheels with the axle along Y on the
    cradles, everything else as mounted, its lowest point on the shelf (the battery on its side)."""
    placed = []
    for n, (level, x, name) in SLOTS.items():
        if name is None:
            continue
        objs = import_part(name)
        roots = [o for o in objs if o.parent is None]
        turn = Matrix.Identity(4)
        if name == "wheel_L":
            turn = Matrix.Rotation(math.radians(90), 4, "Z")
        elif name == "power_unit":
            # On its side, then turned so its 0.355 m side runs across the shelf
            turn = Matrix.Rotation(math.radians(90), 4, "Z") @ Matrix.Rotation(math.radians(90), 4, "Y")
        for r in roots:
            r.matrix_world = turn @ r.matrix_world
        bpy.context.view_layer.update()
        meshes = [o for o in objs if o.type == "MESH"]
        lo, hi = ws.bounds(meshes)
        s = ws.SHELF_TOPS[level]
        # Lifted a few mm (Godot drops them into place): wheels onto the cradles, the rest onto the shelf
        if name == "wheel_L":
            bottom = s + CRADLE_HEIGHT + math.sqrt(0.15 ** 2 - (CRADLE_SPACING / 2.0 - 0.01) ** 2) - 0.15 + 0.003   # on the rails' inner edges
        else:
            bottom = s + 0.005
        shift = Vector((x - (lo.x + hi.x) / 2.0, slot_y(n) - (lo.y + hi.y) / 2.0, bottom - lo.z))
        for r in roots:
            r.location += shift
        bpy.context.view_layer.update()
        placed.append((n, name, meshes))
    return placed


def run_checks(root, placed: list, rows: list) -> int:
    failures = ws.check_part(root, BUDGET, (ws.RACK_SIZE[0] + 0.10, None, ws.RACK_SIZE[2]), rows)
    rack_meshes = [root]
    from make_shell import gap
    for n, name, meshes in placed:
        level = SLOTS[n][0]
        lo, hi = ws.bounds(meshes)
        above = (ws.SHELF_TOPS[level + 1] - ws.LABEL_RAIL if level + 1 < len(ws.SHELF_TOPS) else TOP - 0.02) - hi.z
        g = gap(meshes, rack_meshes)
        ok = above >= 0.02 and g >= 0.001
        failures += 0 if ok else 1
        rows.append("slot_%02d %-10s %.3f x %.3f x %.3f m, %.0f mm under the shelf above, %.1f mm from the rack%s" % (
            n, name, hi.x - lo.x, hi.y - lo.y, hi.z - lo.z, above * 1000.0, g * 1000.0, "" if ok else "  FAIL"))
    # Seen from the walkway at any distance: from eyes standing (1.5 m) and crouched (1.25 m), 0.3 to
    # 2.5 m in front of the rack, a ray to a point near the top front of every part's protruding
    # part reaches it without crossing the rack
    from mathutils.bvhtree import BVHTree
    from make_shell import bvh
    rack_tree = bvh([root])
    blocked = []
    for n, name, meshes in placed:
        level = SLOTS[n][0]
        lo, hi = ws.bounds(meshes)
        above = FRONTS[level + 1] if level + 1 < len(FRONTS) else Y_BACK
        protrudes = hi.y - above
        target = Vector(((lo.x + hi.x) / 2.0, hi.y - 0.01, hi.z - 0.01))
        part_tree = bvh(meshes)
        for d in (0.3, 0.6, 1.0, 1.5, 2.0, 2.5):
            for eye_z in (1.5, 1.25):
                eye = Vector((target.x, Y_FRONT + d, eye_z))
                direction = (target - eye).normalized()
                hit_rack = rack_tree.ray_cast(eye, direction, (target - eye).length)
                hit_part = part_tree.ray_cast(eye, direction, (target - eye).length + 0.05)
                if hit_rack[0] is not None and (hit_part[0] is None or hit_rack[3] < hit_part[3]):
                    blocked.append("slot_%02d from %.1f m, eye %.2f" % (n, d, eye_z))
        rows.append("slot_%02d %-10s stands %.0f mm in front of the shelf above" % (n, name, protrudes * 1000.0))
        failures += 0 if protrudes >= 0.04 else 1
    failures += 1 if blocked else 0
    rows.append("sight lines from the walkway (0.3-2.5 m, standing and crouched): %s" % (
        "all clear" if not blocked else "BLOCKED " + ", ".join(blocked) + "  FAIL"))
    # Neighbours on the same level keep apart
    worst = 1e9
    for i in range(len(placed)):
        for j in range(i + 1, len(placed)):
            if SLOTS[placed[i][0]][0] != SLOTS[placed[j][0]][0]:
                continue
            worst = min(worst, gap(placed[i][2], placed[j][2]))
    ok = worst >= 0.02
    failures += 0 if ok else 1
    rows.append("least gap between neighbouring parts: %.0f mm%s" % (worst * 1000.0, "" if ok else "  FAIL"))
    for n, (level, xa, xb, text) in LABELS.items():
        rows.append("label_%02d plate %.2f x 0.12 m: %s (65 mm caps: about %.2f m of text)" % (
            n, xb - xa - 2 * PLATE_GAP, text, len(text) * 0.065 * 0.62))
    return failures


def render_previews(root, placed: list, previews: str) -> None:
    ws.set_preview_colors(True)
    keep = tuple(m for _, _, meshes in placed for m in meshes)
    ws.render(root, os.path.join(previews, "rack_loaded_front.png"), (0.0, 1.0, 0.1), 2.9, keep_visible=keep,
              focus=(0.0, 0.25, 0.9))
    ws.render(root, os.path.join(previews, "rack_loaded_walkway.png"), (0.35, 1.0, 0.25), 3.0, True, 5.5,
              (0.0, 0.25, 0.85), keep_visible=keep)
    ws.render(root, os.path.join(previews, "rack_empty_three_quarter.png"), (-0.6, 1.0, 0.4), 3.0, True, 6.0,
              (0.0, 0.25, 0.9))
    ws.render(root, os.path.join(previews, "rack_side.png"), (1.0, 0.0, 0.0), 2.0, keep_visible=keep,
              focus=(0.0, 0.25, 0.9))
    ws.set_preview_colors(False)


def main() -> None:
    previews = ws.preview_dir("rack")
    ws.rk.reset_scene()
    root = make_rack()
    bpy.context.view_layer.update()
    ws.export(root)
    ws.add_references()
    placed = load_parts()
    rows = []
    failures = run_checks(root, placed, rows)
    if previews:
        render_previews(root, placed, previews)
    # The parts were only borrowed for the checks and previews
    keep = {root, *root.children_recursive} | {o for o in bpy.data.objects if o.name.startswith("ref_")}
    for o in [o for o in bpy.data.objects if o not in keep]:
        bpy.data.objects.remove(o)
    ws.save("rack")
    rows.append("ALL CHECKS OK" if failures == 0 else "%d CHECK FAILURES" % failures)
    ws.report("rack", rows)


if __name__ == "__main__":
    main()
