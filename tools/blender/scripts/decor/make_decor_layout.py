"""Places the workshop decor (DECOR_KIT.md 2-4), writes dc_layout and the merged interior, reruns
the workshop's assembled checks with the decor in the room, runs the decor's own checks and
renders previews.

    blender -b --factory-startup -P tools/blender/scripts/decor/make_decor_layout.py [-- --previews DIR | --no-previews]

Needs the workshop's .blend files (tools/blender/scripts/workshop/) and the decor's
(make_decor_bay, make_decor_crew, make_decor_exterior). Writes tools/blender/parts/decor/layout.blend,
game/res/models/decor_kit/dc_layout.glb and dc_interior.glb, and previews in
tools/blender/previews/decor/layout/.

dc_layout (empties only, kit coordinates):
    place_<piece>_NN    an interior piece (it's in dc_interior.glb; this says where, and carries its texts)
    outside_<piece>_NN  an exterior piece: Godot puts <piece>.glb here and rests it on the ground
    text_<key>          child of a place_ / outside_ empty: a Label3D facing the piece's front
                        (-Y), with the words for <key> from game/res/decor/decor_texts.json
    path_cable_NN, path_<track>_NN   the cable run and the tyre tracks (DECOR_KIT.md 4)
dc_interior: every interior piece joined into one mesh (one surface per material), each history
card's photo quad apart (card_photo_<photo>), and the pieces' collision boxes.

Checks (all with the docked rover, the U-turn and the walkways of make_layout.py):
    - make_layout.py's checks, with every decor footprint as an obstacle from the floor to its top,
      whether it has collision or not (floor markings 2 mm proud excepted);
    - no decor in the keep-clear zone, on the pad or in the exterior lane;
    - every decor piece at least 5 cm outside every interact trigger (the desk items excepted);
    - no decor collider on a sight line from where the player stands to a reach target;
    - the triangle budget (DECOR_KIT.md 7.1).
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
sys.path.append(os.path.join(os.path.dirname(__file__), "..", "workshop"))
import make_layout as ml  # noqa: E402

BLENDS = {"decor_bay": ["dc_tool_chest", "dc_crate", "dc_cable_reel", "dc_spare_panels", "dc_wheel_spare", "dc_ladder",
                        "dc_o2_rack", "dc_extinguisher", "dc_threshold_band", "dc_sign_warning", "dc_sign_oxidiser",
                        "dc_sign_voltage"],
          "decor_crew": ["dc_mug", "dc_tablet", "dc_plant_lab", "dc_service_note", "dc_history_card"],
          "decor_exterior": ["dc_junction_box"]}
TRIANGLE_CAP = 3500
DESK_ITEMS = ("dc_mug", "dc_tablet")
# Interact triggers (workshop.gd, WORKSHOP_KIT.md 9.2): name -> size in kit axes (x, y, z)
TRIGGER_SIZES = {"trigger_charger": (0.6, 1.0, 1.2), "trigger_console": (0.6, 1.2, 0.6),
                 "trigger_bay_door": (0.4, 0.2, 0.5), "trigger_restock": (0.2, 0.2, 0.3)}
KEEP_CLEAR = ((ml.KEEP_CLEAR_WEST, ws.DOOR_X[1]), (-2.85, ws.INNER_Y))
PAD = ((ws.DOCK.x - 1.5, ws.DOCK.x + 1.5), (ws.DOCK.y - 2.0, ws.DOCK.y + 2.0))


def load_pieces() -> dict:
    pieces = {}
    for blend, names in BLENDS.items():
        for root in ws.rk.append_objects(os.path.join(dc.PARTS_DIR, blend + ".blend"), names):
            root.location = (0.0, 0.0, 0.0)
            root.rotation_euler = (0.0, 0.0, 0.0)
            pieces[root.name] = root
    bpy.context.view_layer.update()
    return pieces


def copy_tree(source, matrix):
    """A linked copy of a piece and its children at `matrix` (kit frame). Returns the copy's root."""
    mapping = {}
    for obj in [source] + list(source.children_recursive):
        dup = obj.copy()
        bpy.context.scene.collection.objects.link(dup)
        mapping[obj] = dup
    for obj, dup in mapping.items():
        if obj.parent in mapping:
            dup.parent = mapping[obj.parent]
            dup.matrix_parent_inverse = obj.matrix_parent_inverse.copy()
    root = mapping[source]
    root.matrix_world = matrix
    bpy.context.view_layer.update()
    return root


def visible_meshes(root) -> list:
    return [o for o in [root] + list(root.children_recursive) if o.type == "MESH" and "-convcolonly" not in o.name]


def footprint_box(root, name: str):
    """A preview-free stand-in collision box (-convcolonly) over a placed piece's visible bounds,
    so make_layout.py's checks see every piece, collision or not."""
    lo, hi = ws.bounds(visible_meshes(root))
    bm = bmesh.new()
    ws.rk.box(bm, (lo.x, hi.x), (lo.y, hi.y), (lo.z, hi.z), 0)
    obj = ws.rk.mesh_object(name + "-convcolonly", bm, [])
    obj.hide_render = True
    return obj, (lo, hi)


# --- dc_layout and dc_interior ---------------------------------------------------------------

def build_layout() -> bpy.types.Object:
    layout = ws.root_empty("dc_layout")
    counters = {}
    for group, prefix in ((dc.INTERIOR, "place_"), (dc.EXTERIOR, "outside_")):
        for piece, location, turn, texts in group:
            counters[(prefix, piece)] = counters.get((prefix, piece), 0) + 1
            # place_ and outside_ empties turn about Z (the workshop helper only lets place_ turn)
            place = ws.add_empty(layout, "%s%s_%02d" % (prefix, piece, counters[(prefix, piece)]), location)
            place.rotation_euler = (0.0, 0.0, math.radians(turn))
            for slot, key in texts.items():
                if slot == "photo":
                    continue
                anchor = PIECES[piece].children_recursive
                local = next(o for o in anchor if o.name.split("__")[0].split(".")[0] == slot).matrix_world.translation
                empty = bpy.data.objects.new("text_" + key, None)
                empty.empty_display_size = 0.05
                bpy.context.scene.collection.objects.link(empty)
                empty.parent = place
                empty.location = local
    for k, p in enumerate(dc.CABLE_PATH):
        ws.add_empty(layout, "path_cable_%02d" % (k + 1), p)
    for track, points in dc.TRACKS.items():
        for k, (x, y) in enumerate(points):
            ws.add_empty(layout, "path_%s_%02d" % (track, k + 1), (x, y, 0.0))
    bpy.context.view_layer.update()
    return layout


def build_interior() -> tuple:
    """Joins every interior piece into dc_interior (photo quads apart), with collision boxes."""
    root = ws.root_empty("dc_interior")
    meshes, photos, boxes = [], [], []
    counters = {}
    for piece, location, turn, texts in dc.INTERIOR:
        counters[piece] = counters.get(piece, 0) + 1
        copy = copy_tree(PIECES[piece], dc.placement_matrix(location, turn))
        tree = [copy] + list(copy.children_recursive)
        for o in tree:
            if o.type != "MESH":
                continue
            if "-convcolonly" in o.name:
                boxes.append((o, "%s_%02d" % (piece, counters[piece])))
            elif o.name.split(".")[0] == "card_photo":
                photos.append((o, texts["photo"]))
            else:
                meshes.append(o)
        # Bake each mesh's place into its own copy of the data, then drop the copy's empties
        for o in tree:
            if o.type == "MESH":
                world = o.matrix_world.copy()
                o.parent = None
                o.data = o.data.copy()
                o.data.transform(world)
                o.matrix_world = Matrix.Identity(4)
        for o in tree:
            if o.type != "MESH":
                bpy.data.objects.remove(o)
    bpy.context.view_layer.update()
    target = meshes[0]
    with bpy.context.temp_override(active_object=target, selected_editable_objects=meshes, object=target):
        bpy.ops.object.join()
    target.name = "dc_interior_mesh"
    target.data.name = "dc_interior_mesh"
    for p in target.data.polygons:
        p.use_smooth = False
    ws.rk.parent_keep_transform(target, root)
    for o, photo in photos:
        o.name = "card_photo_" + photo
        ws.rk.parent_keep_transform(o, root)
    for o, name in boxes:
        o.name = name + "-convcolonly"
        o.display_type = "WIRE"
        ws.rk.parent_keep_transform(o, root)
    bpy.context.view_layer.update()
    return root, target


# --- Checks --------------------------------------------------------------------------------------

def box_gap(a: tuple, b: tuple) -> float:
    """Distance between two boxes (lo, hi), 0 if they touch or overlap."""
    d = [max(b[0][i] - a[1][i], a[0][i] - b[1][i], 0.0) for i in range(3)]
    return math.sqrt(sum(x * x for x in d))


def segment_hits_box(p0: Vector, p1: Vector, lo: Vector, hi: Vector) -> bool:
    t0, t1 = 0.0, 1.0
    d = p1 - p0
    for i in range(3):
        if abs(d[i]) < 1e-9:
            if p0[i] < lo[i] or p0[i] > hi[i]:
                return False
            continue
        a, b = (lo[i] - p0[i]) / d[i], (hi[i] - p0[i]) / d[i]
        t0, t1 = max(t0, min(a, b)), min(t1, max(a, b))
        if t0 > t1:
            return False
    return True


def decor_checks(workshop_copies: list, placed: list, rows: list) -> int:
    """placed: (piece, group, root copy, (lo, hi)) for every decor instance."""
    failures = 0

    def empty(name):
        for _, root in workshop_copies:
            for o in root.children_recursive:
                if o.name.split("__")[0].split(".")[0] == name:
                    return o.matrix_world.translation
        return Vector(ml.LAYOUT_EMPTIES[name])      # ws_layout's own empties (trigger_bay_door)
    # Keep-clear zone, pad, exterior lane: everything the rover could reach (floor markings 2 mm
    # proud and wall pieces hung above the rover's 1.22 m excepted)
    worst = []
    for piece, group, root, (lo, hi) in placed:
        if hi.z <= 0.01 or lo.z >= ws.ROVER_HEIGHT:
            continue
        for name, ((x0, x1), (y0, y1)) in (("keep-clear zone", KEEP_CLEAR), ("pad", PAD), ("exterior lane", dc.EXTERIOR_LANE)):
            if lo.x < x1 and hi.x > x0 and lo.y < y1 and hi.y > y0:
                worst.append("%s in the %s" % (root.name, name))
    failures += len(worst)
    rows.append("decor outside the keep-clear zone, the pad and the exterior lane%s" % (
        "" if not worst else "  FAIL: " + ", ".join(worst)))
    # Interact triggers: 5 cm clear (the desk items sit on the console, inside its trigger)
    least = (1e9, "", "")
    for trigger, size in TRIGGER_SIZES.items():
        c = empty(trigger)
        box = (c - Vector(size) / 2.0, c + Vector(size) / 2.0)
        for piece, group, root, bounds in placed:
            if piece in DESK_ITEMS and trigger == "trigger_console":
                continue
            g = box_gap(bounds, box)
            if g < least[0]:
                least = (g, root.name, trigger)
    ok = least[0] >= dc.TRIGGER_GAP - 1e-4
    failures += 0 if ok else 1
    rows.append("decor to the interact triggers: least %.3f m (%s to %s), needs %.2f%s" % (
        least[0], least[1], least[2], dc.TRIGGER_GAP, "" if ok else "  FAIL"))
    # Sight lines from where the player stands to every reach target, past the decor's colliders
    eye = ws.PLAYER_EYE
    at_rack = Vector((ws.DOCK.x, -2.85, eye))
    at_console = Vector((ws.CONSOLE_ORIGIN.x + 1.05, ws.CONSOLE_ORIGIN.y, eye))
    at_charger = Vector((ws.CHARGER_ORIGIN.x - 0.80, ws.CHARGER_ORIGIN.y, eye))
    at_restock = Vector((1.21, -2.75, eye))
    at_panel = Vector((-3.6, 3.0, eye))
    lines = [("rack slot_%02d" % n, at_rack, empty("slot_%02d" % n)) for n in range(1, 19)]
    for n in range(1, 16):
        slot = empty("slot_%02d" % n)
        for d in (0.45, 1.2, 2.0):
            lines.append(("rack slot_%02d from %.2f m" % (n, d), Vector((slot.x, -3.30 + d, eye)), slot))
    lines += [("console", at_console, empty("trigger_console")), ("charger", at_charger, empty("trigger_charger")),
              ("restock button", at_restock, empty("trigger_restock")), ("bay door panel", at_panel, empty("trigger_bay_door")),
              ("rover's rear power socket", at_rack, Vector((ws.DOCK.x, ws.DOCK.y - 0.45, ws.ROVER_RIDE + 0.36)))]
    blocked = []
    colliders = []
    for piece, group, root, _ in placed:
        for o in root.children_recursive:
            if o.type == "MESH" and "-convcolonly" in o.name and not o.name.startswith("footprint"):
                colliders.append((root.name, ws.bounds([o])))
    for name, p0, p1 in lines:
        for owner, (lo, hi) in colliders:
            if segment_hits_box(p0, p1, lo, hi):
                blocked.append("%s by %s" % (name, owner))
    failures += len(blocked)
    rows.append("sight lines to %d reach targets clear of the decor's %d colliders%s" % (
        len(lines), len(colliders), "" if not blocked else "  FAIL: " + ", ".join(blocked)))
    return failures


def triangle_report(pieces: dict, interior_mesh, rows: list) -> int:
    inside = ws.rk.triangle_count(interior_mesh) + 2 * 2
    outside = sum(ws.visible_triangles(pieces[p]) for p, _, _, _ in dc.EXTERIOR)
    cable = 8 * (len(dc.CABLE_PATH) - 1)                 # built by Godot: 4 sides per segment
    total = inside + outside + cable
    ok = total <= TRIANGLE_CAP
    rows.append("triangles: interior %d (one mesh, photos included), exterior pieces %d, cable %d: %d in all (cap %d)%s" % (
        inside, outside, cable, total, TRIANGLE_CAP, "" if ok else "  FAIL"))
    rows.append("dc_interior: %d surfaces (draw calls), %d collision boxes" % (
        len(interior_mesh.data.materials), sum(1 for o in interior_mesh.parent.children if "-convcolonly" in o.name)))
    return 0 if ok else 1


# --- Previews ------------------------------------------------------------------------------------

def render_previews(workshop_copies, decor_roots, previews: str) -> None:
    ws.set_preview_colors(True)
    target = next(r for p, r in workshop_copies if p == "ws_pad")
    decor = tuple(o for r in decor_roots for o in [r] + list(r.children_recursive))
    no_roof = tuple(o for p, r in workshop_copies if p != "ws_roof_tile" for o in [r] + list(r.children_recursive))
    everything = tuple(o for _, r in workshop_copies for o in [r] + list(r.children_recursive))
    overlay = tuple(ml.plan_overlay())
    d = ws.DOCK
    ws.render(target, os.path.join(previews, "plan.png"), (0.0, 0.0, 1.0), 13.0, focus=(-d.x, -d.y + 1.2, 0.0),
              keep_visible=no_roof + overlay + decor, size=1200)
    def without(hide) -> tuple:
        """The workshop without its roof and the parts `hide` picks (part name, root)."""
        return tuple(o for p, r in workshop_copies if p != "ws_roof_tile" and not hide(p, r)
                     for o in [r] + list(r.children_recursive))
    walls = ("ws_wall_panel", "ws_wall_window", "ws_corner", "ws_plinth")
    partition = ("ws_partition_solid", "ws_partition_door", "ws_partition_window")
    open_side = without(lambda p, r: p in walls and (r.location.y < -ws.HALF_Y + 0.5 or r.location.x > ws.HALF_X - 0.5))
    ws.render(target, os.path.join(previews, "inside_from_south_east.png"), (0.8, -1.0, 0.9), 12.0, True, 18.0,
              (-d.x, -d.y, 0.8), keep_visible=open_side + decor, size=1100)
    # The bay's west wall, from the east (the partition and the east and south walls left out)
    bay = without(lambda p, r: p in partition or (p in walls and (r.location.y < -ws.HALF_Y + 0.5 or r.location.x > ws.HALF_X - 0.5)))
    ws.render(target, os.path.join(previews, "bay_west_wall.png"), (1.0, -0.35, 0.35), 9.0, True, 12.0,
              (-4.2 - d.x, -0.6 - d.y, 1.0), keep_visible=bay + decor, size=1100)
    ws.render(target, os.path.join(previews, "bay_door_wall.png"), (0.2, -1.0, 0.35), 9.0, True, 11.0,
              (-1.5 - d.x, 3.2 - d.y, 1.1), keep_visible=bay + decor, size=1100)
    # The operator area's east wall, from the west (the partition, west and south walls left out)
    operator = without(lambda p, r: p in partition or (p in walls and (r.location.y < -ws.HALF_Y + 0.5 or r.location.x < -ws.HALF_X + 0.5)))
    ws.render(target, os.path.join(previews, "operator_area.png"), (-1.0, -0.3, 0.3), 7.0, True, 8.5,
              (4.3 - d.x, -0.4 - d.y, 1.2), keep_visible=operator + decor, size=1100)
    ws.render(target, os.path.join(previews, "console_desk.png"), (1.0, 0.0, 0.8), 2.0, True, 3.2,
              (2.3 - d.x, -0.3 - d.y, 0.95), keep_visible=operator + decor, size=900)
    ws.render(target, os.path.join(previews, "exterior_door.png"), (0.15, 1.0, 0.35), 16.0, True, 26.0,
              (-1.5 - d.x, 4.5 - d.y, 1.0), keep_visible=everything + decor, size=1100)
    for o in overlay:
        bpy.data.objects.remove(o)
    ws.set_preview_colors(False)


PIECES = {}


def main() -> None:
    previews = dc.preview_dir("layout")
    ws.rk.reset_scene()
    PIECES.update(load_pieces())
    layout = build_layout()
    dc.export(layout)
    rows = ["dc_layout: %d interior and %d exterior placements, %d texts, %d path points" % (
        len(dc.INTERIOR), len(dc.EXTERIOR), sum(len(t) - (1 if "photo" in t else 0) for _, _, _, t in dc.INTERIOR + dc.EXTERIOR),
        len(dc.CABLE_PATH) + sum(len(p) for p in dc.TRACKS.values()))]
    interior, interior_mesh = build_interior()
    dc.export(interior)

    # The assembled checks: the workshop with every decor piece placed, each with a footprint box
    workshop_parts = ml.load_parts()
    workshop_copies = ml.place_copies(workshop_parts, ml.instances())
    placed = []
    for group_name, group in (("interior", dc.INTERIOR), ("exterior", dc.EXTERIOR)):
        for piece, location, turn, _ in group:
            root = copy_tree(PIECES[piece], dc.placement_matrix(location, turn))
            box, bounds = footprint_box(root, "footprint_" + piece)
            ws.rk.parent_keep_transform(box, root)
            placed.append((piece, group_name, root, bounds))
    failures = ml.run_checks(workshop_copies + [(p, r) for p, g, r, _ in placed], rows)
    failures += decor_checks(workshop_copies, placed, rows)
    failures += triangle_report(PIECES, interior_mesh, rows)
    if previews:
        for r in PIECES.values():
            r.hide_render = True
            for o in r.children_recursive:
                o.hide_render = True
        interior.hide_render = True
        for o in interior.children_recursive:
            o.hide_render = True
        render_previews(workshop_copies, [r for _, _, r, _ in placed], previews)
    # Keep the layout, the merged interior and the references in the .blend
    keep = {layout, *layout.children_recursive, interior, *interior.children_recursive}
    for o in [o for o in bpy.data.objects if o not in keep]:
        bpy.data.objects.remove(o)
    ws.add_references()
    dc.save("layout")
    rows.append("ALL CHECKS OK" if failures == 0 else "%d CHECK FAILURES" % failures)
    dc.report("layout", rows)


if __name__ == "__main__":
    main()
