"""Shared helpers and placements for the workshop decor generators (tools/blender/DECOR_KIT.md).

Run the scripts headless from the repo root, e.g.:
    blender -b --factory-startup -P tools/blender/scripts/decor/make_decor_bay.py
Previews go to tools/blender/previews/decor/<asset>/ unless `-- --previews <dir>` or `-- --no-previews`.

Builds on the workshop kit (workshop_kit_common.py): the same kit coordinates (metres, origin in
the middle of the footprint on the floor top, the bay door in the +Y wall), geometry helpers and
materials, plus the decor's four materials. Every decor placement lives here, nowhere else.

Piece frames (DECOR_KIT.md 3): every piece's front faces -Y.
- Floor pieces: origin in the middle of the footprint, on the floor.
- Wall pieces: origin in the middle of the back, where it meets the wall plane y = 0 (the piece
  is at y < 0). A placement puts that plane WALL_GAP in front of a wall face, clear of the wall
  modules' 30 mm frame members and 20 mm kick plate, and turns the piece to face into the room.
Text anchors (`text_*` empties) mark where Godot puts each piece's Label3D, facing -Y.
"""

import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

sys.path.append(os.path.join(os.path.dirname(__file__), "..", "workshop"))
import workshop_kit_common as ws  # noqa: E402

rk = ws.rk
REPO_ROOT = ws.REPO_ROOT
PARTS_DIR = os.path.join(REPO_ROOT, "tools", "blender", "parts", "decor")
EXPORT_DIR = os.path.join(REPO_ROOT, "game", "res", "models", "decor_kit")
PREVIEWS_DIR = os.path.join(REPO_ROOT, "tools", "blender", "previews", "decor")

# --- Materials (DECOR_KIT.md 5): the workshop's ten plus four ---------------------------------
DECOR_PALETTE = {
    "dc_red": "B8322A",
    "dc_green": "4E8A3A",
    "dc_grow": "D070E0",
    "dc_photo": "808080",          # the history cards' photo quads; Godot puts the photo on them
}
ws.PALETTE.update(DECOR_PALETTE)
ws.MATERIAL_SETTINGS.update({"dc_red": (0.0, 0.5), "dc_green": (0.0, 0.8), "dc_grow": (0.0, 0.5), "dc_photo": (0.0, 0.9)})
ws.EMISSIVE.update({"dc_grow": 1.5})
ws.PREVIEW_COLORS.update({"dc_photo": "A8B0B8"})

# --- Walls (DECOR_KIT.md 2) -------------------------------------------------------------------
WALL_GAP = 0.035                       # a wall piece's back to the wall face
NORTH_IN = ws.INNER_Y - WALL_GAP       # (y) inside the bay door wall, turn 0
SOUTH_IN = -ws.INNER_Y + WALL_GAP      # turn 180
WEST_IN = -ws.INNER_X + WALL_GAP       # (x) turn 90
EAST_IN = ws.INNER_X - WALL_GAP        # turn -90
PARTITION_BAY = ws.PARTITION_X - ws.PARTITION_THICKNESS / 2.0 - WALL_GAP   # the partition's bay face, turn -90
FACADE = ws.HALF_Y + WALL_GAP          # outside the bay door wall, turn 180

# --- Placements: (piece, (x, y, z), turn about Z in degrees, {text slot: text key}) -----------
# Text keys are "<style>_<name>"; the words are in game/res/decor/decor_texts.json
INTERIOR = [
    # Work clutter (3.1)
    ("dc_tool_chest", (WEST_IN + 0.25, -1.95, 0.0), 90, {"text": "label_tool_chest"}),
    ("dc_crate", (WEST_IN + 0.30, SOUTH_IN + 0.20, 0.0), 180, {"text": "label_crate_seals"}),
    ("dc_crate", (WEST_IN + 0.30, SOUTH_IN + 0.20, 0.40), 188, {"text": "label_crate_filters"}),
    ("dc_crate", (WEST_IN + 0.97, SOUTH_IN + 0.20, 0.0), 180, {"text": "label_crate_fasteners"}),
    ("dc_crate", (2.50, NORTH_IN - 0.20, 0.0), 0, {"text": "label_crate_rations"}),
    ("dc_cable_reel", (-2.90, SOUTH_IN + 0.25, 0.0), 0, {}),
    ("dc_spare_panels", (WEST_IN, -0.60, 0.0), 90, {"text": "label_panels_tag"}),
    ("dc_wheel_spare", (WEST_IN, 0.75, 1.55), 90, {"text": "label_wheel_tag"}),
    ("dc_ladder", (WEST_IN, 1.425, 0.35), 90, {}),
    # Life support and safety (3.2)
    ("dc_o2_rack", (WEST_IN, 2.35, 0.0), 90, {}),
    ("dc_sign_oxidiser", (WEST_IN, 2.35, 2.00), 90, {"text": "sign_oxygen"}),
    ("dc_extinguisher", (-4.45, NORTH_IN, 0.45), 0, {"text": "redlabel_fire_bay"}),
    ("dc_extinguisher", (3.30, NORTH_IN, 0.45), 0, {"text": "redlabel_fire_operator"}),
    ("dc_threshold_band", (-1.0, ws.INNER_Y - 0.10, 0.0), 0, {}),
    ("dc_sign_warning", (1.35, NORTH_IN, 1.75), 0, {"text": "sign_vehicle_ramp"}),
    ("dc_sign_voltage", (PARTITION_BAY, 3.10, 2.05), -90, {"text": "sign_charger"}),
    # Signs of the crew (3.3)
    ("dc_mug", (2.22, 0.20, 0.90), 30, {}),
    ("dc_tablet", (2.30, -0.78, 0.90), 78, {}),
    ("dc_plant_lab", (EAST_IN, 1.00, 0.88), -90, {"text": "label_plant"}),
    # Service notes (3.4)
    ("dc_service_note", (-4.00, NORTH_IN, 1.40), 0, {"text": "note_bay_door"}),
    ("dc_service_note", (1.35, NORTH_IN, 1.20), 0, {"text": "note_charger"}),
    ("dc_service_note", (PARTITION_BAY, -3.30, 1.45), -90, {"text": "note_rack"}),
    ("dc_service_note", (EAST_IN, -2.75, 1.45), -90, {"text": "note_suit"}),
    ("dc_service_note", (EAST_IN, 1.80, 1.30), -90, {"text": "note_plant"}),
    # History cards (6)
    ("dc_history_card", (EAST_IN, -0.95, 1.45), -90, {"text": "card_apollo12", "photo": "apollo12"}),
    ("dc_history_card", (EAST_IN, -1.65, 1.45), -90, {"text": "card_surveyor3", "photo": "surveyor3"}),
]
# Exterior pieces stay separate: Godot rests each on the ground (DECOR_KIT.md 4.3)
EXTERIOR = [
    ("dc_crate", (-4.65, FACADE + 0.20, 0.0), 0, {"text": "label_crate_return"}),
    ("dc_crate", (-4.70, 5.00, 0.0), 20, {"text": "label_crate_bags"}),
    ("dc_cable_reel", (3.60, 4.60, 0.0), 0, {}),
    ("dc_junction_box", (2.60, FACADE, 0.60), 180, {"text": "label_junction"}),
    ("dc_sign_warning", (-3.70, FACADE, 1.60), 180, {"text": "sign_ramp_outside"}),
]
# Paths (kit x, y, z): the cable from the junction box's gland to the reel (points at z 0 are
# rested on the ground), and the tyre tracks on the apron (Moon terrain only)
CABLE_PATH = [(2.60, FACADE + 0.10, 0.55), (2.60, FACADE + 0.10, 0.12), (2.62, FACADE + 0.16, 0.0),
              (2.85, 4.45, 0.0), (3.05, 4.85, 0.0), (3.30, 4.95, 0.0), (3.42, 4.78, 0.0), (3.45, 4.62, 0.0)]
TRACKS = {
    # The way out: straight from the ramp's end, then bending right towards Kite (10 degrees right)
    "track1": [(-0.5, 6.5), (-0.5, 9.0), (-0.3, 10.8), (0.2, 12.6), (0.9, 14.6), (1.6, 16.5)],
    # The way in (older): from Kite's side onto the entry lane
    "track2": [(1.2, 16.5), (0.1, 14.6), (-1.2, 12.6), (-2.0, 10.6), (-2.2, 8.5), (-2.2, 6.5)],
    # An old loop across the apron
    "track3": [(4.5, 7.0), (3.0, 9.4), (1.0, 11.0), (-1.5, 11.6), (-4.0, 11.0), (-5.5, 9.4)],
}
# Rules (DECOR_KIT.md 1, 4.1)
EXTERIOR_LANE = ((-4.0, 2.0), (ws.HALF_Y, 16.5))
TRIGGER_GAP = 0.05


def placement_matrix(location, turn: float) -> Matrix:
    return Matrix.Translation(Vector(location)) @ Matrix.Rotation(math.radians(turn), 4, "Z")


# --- Pieces: export, save, checks --------------------------------------------------------------

def export(root: bpy.types.Object) -> str:
    """Exports a piece and its children to game/res/models/decor_kit/<root>.glb (the workshop
    kit's exporter, with its post-import script)."""
    saved = ws.EXPORT_DIR
    ws.EXPORT_DIR = EXPORT_DIR
    try:
        return ws.export(root)
    finally:
        ws.EXPORT_DIR = saved


def save(asset: str) -> None:
    rk.save_blend(os.path.join(PARTS_DIR, asset + ".blend"))


def preview_dir(asset: str):
    args = rk.script_args()
    if "--no-previews" in args:
        return None
    path = args[args.index("--previews") + 1] if "--previews" in args else os.path.join(PREVIEWS_DIR, asset)
    os.makedirs(path, exist_ok=True)
    return path


def check_piece(root, budget: int, size: tuple, rows: list) -> int:
    """The workshop kit's part check (names, unrotated empties, only kit materials, triangles,
    size to 1 mm), plus: every text anchor faces -Y in the piece's frame."""
    failures = ws.check_part(root, budget, size, rows)
    return failures


def report(asset: str, rows: list) -> None:
    print("\n".join("DECOR_KIT %s " % asset + line for line in rows))


def front_text(parent, name: str, location) -> bpy.types.Object:
    """A text anchor (Label3D centre) just in front of a surface facing -Y."""
    return ws.add_empty(parent, name, location)


def visible_bounds(root) -> tuple:
    return ws.bounds([o for o in [root] + list(root.children_recursive) if o.type == "MESH" and "-convcolonly" not in o.name])


def render_pieces(pieces: dict, previews: str) -> None:
    """Per piece: front, side, a three-quarter view and the inner face (the back of a wall
    piece, the top of a floor piece)."""
    ws.set_preview_colors(True)
    for name, root in pieces.items():
        lo, hi = visible_bounds(root)
        wall = hi.y <= 1e-6 and hi.z - lo.z > 0.01
        size = max(hi.x - lo.x, hi.z - lo.z, hi.y - lo.y) * 1.25
        focus = ((lo.x + hi.x) / 2.0, (lo.y + hi.y) / 2.0, (lo.z + hi.z) / 2.0)
        short = name[3:]
        ws.render(root, os.path.join(previews, short + "_front.png"), (0.0, -1.0, 0.0), size, focus=focus, size=600)
        ws.render(root, os.path.join(previews, short + "_side.png"), (1.0, 0.0, 0.0), size, focus=focus, size=600)
        ws.render(root, os.path.join(previews, short + "_three_quarter.png"), (0.7, -1.0, 0.55), size, True, size * 3.6,
                  focus, size=600)
        if wall:
            ws.render(root, os.path.join(previews, short + "_back.png"), (0.0, 1.0, 0.0), size, focus=focus, size=600)
        else:
            ws.render(root, os.path.join(previews, short + "_top.png"), (0.0, 0.0, 1.0), size, focus=focus, size=600)
    ws.set_preview_colors(False)
