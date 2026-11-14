"""Assembles the workshop from the kit parts, writes ws_layout (empties only: where every part
instance goes, lights, triggers, spawn, anchors), runs the assembled checks and renders previews
(WORKSHOP_KIT.md 5, 10, 12).

    blender -b --factory-startup -P tools/blender/scripts/workshop/make_layout.py [-- --previews DIR | --no-previews]

Needs the other workshop .blend files (make_shell, make_pad, make_rack, make_console,
make_markers, make_suit_props). Writes tools/blender/parts/workshop/layout.blend, game/res/models/workshop_kit/
ws_layout.glb and previews in tools/blender/previews/workshop/layout/.

Checks, all in plan (x, y) against the parts' collision boxes:
    the rover (WORKSHOP_KIT.md 2.1 footprint) along the entry lane, the U-turn and the way out,
    and docked anywhere in the 0.4 m dock zone at any heading;
    the player capsule (r 0.25) at the walkway points, and every target within reach of the eye.
"""

import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.append(os.path.dirname(__file__))
import workshop_kit_common as ws  # noqa: E402

D = ws.DOCK
HX, HY = ws.HALF_X, ws.HALF_Y
ENTRY_X = ws.ENTRY_X
KEEP_CLEAR_WEST = -3.6           # the keep-clear zone: x -3.6 to the door's east jamb, y -2.85 to the door
U_TURN_CENTRE = Vector((ws.U_TURN_LANE + ws.U_TURN_RADII[1], ws.U_TURN_Y))
SWEEP_RADIUS = math.hypot(ws.U_TURN_RADII[-1] + ws.ROVER_HALF_WIDTH, ws.ROVER_FRONT)


def instances() -> list:
    """(part, (x, y, z), turn about Z in degrees) for every part in the workshop."""
    out = []
    # Exterior walls: north (bay door), south, east (one window), west
    for x in (-4.0, 2.0, 4.0):
        out.append(("ws_wall_panel", (x, HY, 0.0), 0))
    out.append(("ws_wall_bay_door", ((ws.DOOR_X[0] + ws.DOOR_X[1]) / 2.0, HY, 0.0), 0))
    for x in (-4.0, -2.0, 0.0, 2.0, 4.0):
        out.append(("ws_wall_panel", (x, -HY, 0.0), 180))
    for y in (-3.0, -1.0, 1.0, 3.0):
        out.append(("ws_wall_window" if y == 1.0 else "ws_wall_panel", (HX, y, 0.0), -90))
        out.append(("ws_wall_panel", (-HX, y, 0.0), 90))
    for (x, y), turn in (((HX, HY), 0), ((-HX, HY), 90), ((-HX, -HY), 180), ((HX, -HY), -90)):
        out.append(("ws_corner", (x, y, 0.0), turn))
    for x in (-4.0, -2.0, 0.0, 2.0, 4.0):
        for y in (-3.0, -1.0, 1.0, 3.0):
            out.append(("ws_floor_tile", (x, y, 0.0), 0))
            out.append(("ws_roof_tile", (x, y, 0.0), 0))
    for x in (-4.0, 2.0, 4.0):
        out.append(("ws_plinth", (x, HY, 0.0), 0))
    for x in (-4.0, -2.0, 0.0, 2.0, 4.0):
        out.append(("ws_plinth", (x, -HY, 0.0), 180))
    for y in (-3.0, -1.0, 1.0, 3.0):
        out.append(("ws_plinth", (HX, y, 0.0), -90))
        out.append(("ws_plinth", (-HX, y, 0.0), 90))
    for part, y, _ in ws.PARTITION_MODULES:
        out.append((part, (ws.PARTITION_X, y, 0.0), 0))
    out += [("ws_work_lamp", (-1.8, -ws.INNER_Y, 2.3), 0), ("ws_work_lamp", (1.6, ws.INNER_Y, 2.6), 180),
            ("ws_work_lamp", (ws.INNER_X, 0.0, 2.6), 90),
            ("ws_door_panel", (-3.6, ws.INNER_Y, 1.2), 180)]
    out += [("ws_pad", tuple(D), 0), ("ws_charger", tuple(ws.CHARGER_ORIGIN), 0),
            ("ws_cable_cover", (ws.CHARGER_ORIGIN.x - 0.40, ws.CHARGER_ORIGIN.y, 0.0), 0),
            ("ws_rack", tuple(ws.RACK_ORIGIN), 0), ("ws_console", tuple(ws.CONSOLE_ORIGIN), 0),
            ("ws_suit_stand", tuple(ws.SUIT_STAND), 0)]
    # Markings: chevrons along the entry lane (into the bay) and the way out; stripes along the
    # keep-clear zone; the sign over the bay door
    for x, y in ((ENTRY_X, 3.4), (-2.5, 1.6), (ws.U_TURN_LANE, 0.0)):
        out.append(("ws_floor_chevron", (x, y, 0.0), 180))
    for y in (2.4, 3.2):
        out.append(("ws_floor_chevron", (D.x, y, 0.0), 0))
    for y in (-1.85, 0.15, 2.15):
        out.append(("ws_floor_stripe", (KEEP_CLEAR_WEST, y, 0.0), 90))
    out.append(("ws_floor_stripe", (ws.DOOR_X[1], 2.75, 0.0), 90))
    out.append(("ws_floor_stripe", (-2.6, -2.85, 0.0), 0))
    out.append(("ws_door_sign", ((ws.DOOR_X[0] + ws.DOOR_X[1]) / 2.0, HY, 2.95), 0))
    return out


LAYOUT_EMPTIES = {
    "spawn_player": tuple(ws.SPAWN),
    "light_bay_key": (D.x, -0.8, 2.95),
    "light_rack": (-1.8, -3.45, 2.15),
    "light_door": (1.6, 3.45, 2.45),
    "light_operator": (4.45, 0.0, 2.45),
    "light_exterior": (-1.0, HY + 0.4, 2.9),
    "trigger_door_auto": (-1.0, 5.0, 1.0),
    "trigger_personnel": (ws.PARTITION_X, -2.0, 1.0),
    "trigger_bay_door": (-3.6, ws.INNER_Y - 0.1, 1.2),
    "anchor_bench": (4.2, 2.6, 0.9),
    # The seated operator and the stool, shown while the console drives the rover (ASTRONAUT_KIT.md 7.1)
    "anchor_seat": tuple(ws.SEAT),
}
BLENDS = {"shell": ["ws_wall_panel", "ws_wall_window", "ws_wall_bay_door", "ws_corner", "ws_floor_tile", "ws_plinth",
                    "ws_roof_tile", "ws_partition_solid", "ws_partition_door", "ws_partition_window", "ws_work_lamp",
                    "ws_door_panel"],
          "pad": ["ws_pad", "ws_charger", "ws_cable_cover"], "rack": ["ws_rack"], "console": ["ws_console"],
          "suit_props": ["ws_suit_stand"],
          "markers": ["ws_floor_chevron", "ws_floor_stripe", "ws_door_sign"]}


def load_parts() -> dict:
    """Appends the part roots (with children) and moves each to the origin, unrotated."""
    parts = {}
    for blend, names in BLENDS.items():
        for root in ws.rk.append_objects(os.path.join(ws.PARTS_DIR, blend + ".blend"), names):
            parts[root.name] = root
    for root in parts.values():
        root.location = (0.0, 0.0, 0.0)
        root.rotation_euler = (0.0, 0.0, 0.0)
    bpy.context.view_layer.update()
    return parts


def place_copies(parts: dict, placements: list) -> list:
    """Linked copies of each part tree at its placement (for checks and previews)."""
    copies = []
    for part, location, turn in placements:
        matrix = Matrix.Translation(location) @ Matrix.Rotation(math.radians(turn), 4, "Z")
        source = parts[part]
        mapping = {}
        for obj in [source] + list(source.children_recursive):
            dup = obj.copy()
            bpy.context.scene.collection.objects.link(dup)
            mapping[obj] = dup
        for obj, dup in mapping.items():
            if obj.parent in mapping:
                dup.parent = mapping[obj.parent]
                dup.matrix_parent_inverse = obj.matrix_parent_inverse.copy()   # reparenting resets it
        root = mapping[source]
        root.matrix_world = matrix
        copies.append((part, root))
    for root in parts.values():
        root.hide_render = True
        for o in root.children_recursive:
            o.hide_render = True
    bpy.context.view_layer.update()
    return copies


# --- Plan checks -----------------------------------------------------------------------------

def obstacles(copies: list, top: float, skip=()) -> list:
    """2D boxes (x0, x1, y0, y1, name) of every collision box that reaches below `top` and above
    the floor. Moving pieces are left out (the bay door and personnel door are open)."""
    boxes = []
    for part, root in copies:
        for o in root.children_recursive:
            if not o.name.split(".")[0].endswith("-convcolonly"):
                continue
            base = o.name.split("-")[0]
            if base in ("bay_door", "personnel_door") or base in skip:
                continue
            lo, hi = ws.bounds([o])
            if hi.z <= 0.01 or lo.z >= top:
                continue
            boxes.append((lo.x, hi.x, lo.y, hi.y, base))
    return boxes


def rover_outline(position: Vector, heading: float, step: float = 0.02) -> list:
    """Points along the rover's plan outline (WORKSHOP_KIT.md 2.1): the tyres' rectangle and the
    power unit behind it. heading 0 = facing +Y."""
    w, f, r = ws.ROVER_HALF_WIDTH, ws.ROVER_FRONT, ws.ROVER_REAR
    loops = [[(-w, -f), (w, -f), (w, f), (-w, f)], [(-0.11, -f), (0.11, -f), (0.11, r), (-0.11, r)]]
    rot = Matrix.Rotation(heading, 2)
    pts = []
    for loop in loops:
        for k in range(len(loop)):
            a, b = Vector(loop[k]), Vector(loop[(k + 1) % len(loop)])
            n = max(1, int((b - a).length / step))
            pts += [position + rot @ (a + (b - a) * (i / n)) for i in range(n)]
    return pts


def point_box(p: Vector, box: tuple) -> float:
    dx = max(box[0] - p.x, 0.0, p.x - box[1])
    dy = max(box[2] - p.y, 0.0, p.y - box[3])
    return math.hypot(dx, dy)


def rover_gap(position: Vector, heading: float, boxes: list) -> tuple:
    """Least distance from the rover's outline to the boxes (0 if a box corner is inside it)."""
    best = (1e9, "")
    inv = Matrix.Rotation(-heading, 2)
    boxes = [b for b in boxes if point_box(position, b) < 2.5]
    for box in boxes:
        for corner in ((box[0], box[2]), (box[1], box[2]), (box[0], box[3]), (box[1], box[3])):
            local = inv @ (Vector(corner) - position)
            if abs(local.x) < ws.ROVER_HALF_WIDTH and ws.ROVER_REAR < local.y < ws.ROVER_FRONT:
                return (0.0, box[4])
    for p in rover_outline(position, heading):
        for box in boxes:
            d = point_box(p, box)
            if d < best[0]:
                best = (d, box[4])
    return best


def path_poses() -> dict:
    """Rover poses (position, heading) along the way in (through the door, drifting west inside
    the bay, a U-turn at each radius in U_TURN_RADII, onto the dock) and the ways out."""
    poses = {"entry lane": [], "drift west in the bay": []}
    y = HY + 4.0
    while y >= 3.0:
        poses["entry lane"].append((Vector((ENTRY_X, y)), math.pi))
        y -= 0.05
    a, b = Vector((ENTRY_X, 3.0)), Vector((ws.U_TURN_LANE, 0.2))
    heading = math.atan2(-(b - a).x, (b - a).y)
    for k in range(41):
        poses["drift west in the bay"].append((a.lerp(b, k / 40.0), heading))
    y = 0.2
    while y >= ws.U_TURN_Y:
        poses["drift west in the bay"].append((Vector((ws.U_TURN_LANE, y)), math.pi))
        y -= 0.05
    for r in ws.U_TURN_RADII:
        name = "U-turn, radius %.2f m" % r
        centre = Vector((ws.U_TURN_LANE + r, ws.U_TURN_Y))
        poses[name] = []
        for k in range(0, 181, 3):
            a = math.radians(180 + k)
            poses[name].append((centre + Vector((math.cos(a), math.sin(a))) * r, a))   # counter-clockwise: heading = angle
        end_x = ws.U_TURN_LANE + 2.0 * r
        name = "to the dock after radius %.2f m (ends %.2f m across from it)" % (r, abs(end_x - D.x))
        poses[name] = []
        y = ws.U_TURN_Y
        while y <= D.y:
            poses[name].append((Vector((end_x, y)), 0.0))
            y += 0.05
    for name, x in (("out from the dock", D.x), ("out from the dock zone's east edge", D.x + ws.DOCK_ZONE),
                    ("out from the dock zone's west edge", D.x - ws.DOCK_ZONE)):
        poses[name] = []
        y = D.y
        while y <= HY + 4.0:
            poses[name].append((Vector((x, y)), 0.0))
            y += 0.05
    return poses


def run_checks(copies: list, rows: list) -> int:
    failures = 0
    rover_boxes = obstacles(copies, ws.ROVER_HEIGHT)
    # Heading convention here: 0 faces +Y, positive turns towards -X (counter-clockwise)
    for name, poses in path_poses().items():
        worst = (1e9, "", None)
        for p, h in poses:
            g, what = rover_gap(p, h, rover_boxes)
            if g < worst[0]:
                worst = (g, what, p)
        target = 0.48 if name.startswith("U-turn") else 0.10 if name == "entry lane" else 0.30
        ok = worst[0] >= target - 1e-3
        failures += 0 if ok else 1
        if worst[2] is None:
            rows.append("rover %-36s nothing within 2.5 m" % (name + ":"))
            continue
        rows.append("rover %-36s least gap %.2f m to %s at (%.2f, %.2f) (needs %.2f)%s" % (
            name + ":", worst[0], worst[1], worst[2].x, worst[2].y, target, "" if ok else "  FAIL"))
    # Docked anywhere in the zone, any heading
    docked = []
    for k in range(8):
        a = 2 * math.pi * k / 8
        for r in (0.0, ws.DOCK_ZONE):
            for heading in range(0, 360, 30):
                docked.append((Vector((D.x, D.y)) + Vector((math.cos(a), math.sin(a))) * r, math.radians(heading)))
    worst = min((rover_gap(p, h, rover_boxes) + (p, h) for p, h in docked), key=lambda t: t[0])
    ok = worst[0] >= 0.5
    failures += 0 if ok else 1
    rows.append("rover docked anywhere in the 0.4 m zone at any heading: least gap %.2f m to %s%s" % (
        worst[0], worst[1], "" if ok else "  FAIL"))

    # Player: capsule at the walkway points, clear of fixtures and of the docked rover anywhere in
    # its zone; then reach from the eye
    player_boxes = obstacles(copies, ws.PLAYER_HEIGHT)
    points = {
        "walkway beside the rover": Vector((ws.PARTITION_X - ws.PARTITION_THICKNESS / 2.0 - 0.45, -0.5)),
        "between the rover and the rack": Vector((D.x, -2.85)),
        "at the console": Vector((ws.CONSOLE_ORIGIN.x + 1.05, ws.CONSOLE_ORIGIN.y)),
        "bay side of the personnel door": Vector((ws.PARTITION_X - 0.35, -2.0)),
        "operator side of the personnel door": Vector((ws.PARTITION_X + 0.40, -2.0)),
        "at the charger": Vector((ws.CHARGER_ORIGIN.x - 0.80, ws.CHARGER_ORIGIN.y)),
        "at the restock button": Vector((1.21, -2.75)),
        "spawn": Vector((ws.SPAWN.x, ws.SPAWN.y)),
        "at the bay door panel": Vector((-3.6, 3.0)),
        "walking past the suit stand": Vector((3.4, -2.6)),
    }
    for name, p in points.items():
        fixture = min((point_box(p, b), b[4]) for b in player_boxes)
        rover = min(min(point_box(p, (q.x, q.x, q.y, q.y, "")) for q in rover_outline(pos, h, 0.05))
                    for pos, h in docked if h in (0.0, math.pi))
        free = min(fixture[0], rover) - ws.PLAYER_RADIUS
        ok = free >= 0.05
        failures += 0 if ok else 1
        rows.append("player %-38s %.2f m clear (fixtures: %.2f to %s, docked rover: %.2f)%s" % (
            name + ":", free, fixture[0] - ws.PLAYER_RADIUS, fixture[1], rover - ws.PLAYER_RADIUS, "" if ok else "  FAIL"))
    # Walkway widths with the rover anywhere in the dock zone: square to the pad (heading within
    # 15 degrees of either way along it) the 1.0 m walkway rule, at any heading the 0.8 m pinch rule
    face = ws.PARTITION_X - ws.PARTITION_THICKNESS / 2.0
    rack_front = ws.RACK_ORIGIN.y + ws.RACK_SIZE[1]

    def square(h):
        return min(abs(math.remainder(h, math.pi)), abs(math.remainder(h - math.pi, math.pi))) <= math.radians(15) + 1e-6
    for name, poses, need in (("rover square to the pad", [ph for ph in docked if square(ph[1])], 1.0),
                              ("rover at any heading", docked, 0.8)):
        side = face - max(max(q.x for q in rover_outline(p, h, 0.05)) for p, h in poses)
        back = min(min(q.y for q in rover_outline(p, h, 0.05)) for p, h in poses) - rack_front
        ok = side >= need - 1e-3 and back >= need - 1e-3
        failures += 0 if ok else 1
        rows.append("walkways with the %s anywhere in the zone: beside it %.2f m, behind it to the rack %.2f m (needs %.1f)%s" % (
            name, side, back, need, "" if ok else "  FAIL"))

    def empty(name):
        for _, root in copies:
            for o in root.children_recursive:
                if o.name.split("__")[0].split(".")[0] == name:
                    return o.matrix_world.translation
        raise KeyError(name)
    reach = []
    rack_point = points["between the rover and the rack"]
    for n in range(1, 19):
        reach.append(("rack slot_%02d" % n, rack_point, empty("slot_%02d" % n)))
    reach += [("console screen", points["at the console"], Vector((ws.CONSOLE_ORIGIN.x + 0.15, ws.CONSOLE_ORIGIN.y, 1.14))),
              ("console trigger", points["at the console"], empty("trigger_console")),
              ("charger trigger", points["at the charger"], empty("trigger_charger")),
              ("restock button", points["at the restock button"], empty("trigger_restock")),
              ("rover's rear power socket", rack_point, Vector((D.x, D.y - 0.45, ws.ROVER_RIDE + 0.36))),
              ("rover's front right wheel", points["walkway beside the rover"], Vector((D.x + 0.5, D.y + 0.5, 0.15))),
              ("rover's motor hatch", Vector((D.x + 0.3, D.y + 1.3)), Vector((D.x + 0.12, D.y + 0.45, 0.40))),
              ("bay door panel", points["at the bay door panel"], Vector((-3.6, ws.INNER_Y - 0.1, 1.2)))]
    worst = max(((t - Vector((p.x, p.y, ws.PLAYER_EYE))).length, name) for name, p, t in reach)
    ok = worst[0] <= ws.PLAYER_REACH
    failures += 0 if ok else 1
    rows.append("reach: every target within %.2f m of the eye (farthest: %s), limit %.1f m%s" % (
        worst[0], worst[1], ws.PLAYER_REACH, "" if ok else "  FAIL"))
    return failures


def check_layout_root(layout, rows: list) -> int:
    failures = 0
    for o in layout.children:
        ws.rk.check_export_name(o.name)
    rows.append("ws_layout: %d place_* empties, %d others" % (
        sum(1 for o in layout.children if o.name.startswith("place_")),
        sum(1 for o in layout.children if not o.name.startswith("place_"))))
    return failures


# --- Previews --------------------------------------------------------------------------------

def preview_material(name: str, hex_color: str):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.diffuse_color = ws.rk.srgb_to_linear(hex_color)
    return m


def plan_overlay() -> list:
    """Flat preview-only shapes: keep-clear zone, U-turn envelope, dock zone, rover footprints at
    the dock and along the path, player capsules at the walkway points."""
    objs = []

    def flat(name, polys, color, z):
        bm = bmesh.new()
        for poly in polys:
            f = bm.faces.new([bm.verts.new((p.x, p.y, z)) for p in poly])
            bm.normal_update()
            if f.normal.z < 0:
                f.normal_flip()
        mesh = bpy.data.meshes.new(name)
        bm.to_mesh(mesh)
        bm.free()
        obj = bpy.data.objects.new(name, mesh)
        obj.data.materials.append(preview_material(name, color))
        bpy.context.scene.collection.objects.link(obj)
        objs.append(obj)

    def ring(c, r0, r1, n=48):
        return [[c + Vector((math.cos(a), math.sin(a))) * r for r, a in
                 ((r0, 2 * math.pi * k / n), (r1, 2 * math.pi * k / n), (r1, 2 * math.pi * (k + 1) / n),
                  (r0, 2 * math.pi * (k + 1) / n))] for k in range(n)]

    def outline_rect(x0, x1, y0, y1, w):
        return [[Vector(a), Vector(b), Vector(c), Vector(d)] for a, b, c, d in (
            ((x0, y0), (x1, y0), (x1, y0 + w), (x0, y0 + w)), ((x0, y1 - w), (x1, y1 - w), (x1, y1), (x0, y1)),
            ((x0, y0), (x0 + w, y0), (x0 + w, y1), (x0, y1)), ((x1 - w, y0), (x1, y0), (x1, y1), (x1 - w, y1)))]

    flat("preview_keep_clear", outline_rect(KEEP_CLEAR_WEST, ws.DOOR_X[1], -2.85, ws.INNER_Y, 0.04), "30A0E0", 0.02)
    flat("preview_u_turn", ring(U_TURN_CENTRE, SWEEP_RADIUS - 0.03, SWEEP_RADIUS), "E04040", 0.02)
    flat("preview_dock_zone", ring(Vector((D.x, D.y)), ws.DOCK_ZONE - 0.02, ws.DOCK_ZONE), "40C040", 0.03)
    for p, h in ((Vector((D.x, D.y)), 0.0), (Vector((D.x + 0.4, D.y)), math.radians(30))):
        rot = Matrix.Rotation(h, 2)
        w, f, r = ws.ROVER_HALF_WIDTH, ws.ROVER_FRONT, ws.ROVER_REAR
        flat("preview_rover", [[p + rot @ Vector(c) for c in ((-w, -f), (w, -f), (w, f), (-w, f))],
                               [p + rot @ Vector(c) for c in ((-0.11, -f), (0.11, -f), (0.11, r), (-0.11, r))]],
             "F0F0F0" if h == 0.0 else "B0B0B0", 0.025 if h == 0.0 else 0.022)
    for p in (Vector((ws.PARTITION_X - 0.5, -0.5)), Vector((D.x, -2.85)), Vector((3.2, -0.3)), Vector((1.75, -2.0)),
              Vector((1.25, 3.1)), Vector((ws.SPAWN.x, ws.SPAWN.y))):
        flat("preview_player", ring(p, 0.0, ws.PLAYER_RADIUS, 16), "E0A030", 0.04)
    return objs


def render_previews(copies: list, previews: str) -> None:
    ws.set_preview_colors(True)
    target = next(r for p, r in copies if p == "ws_pad")
    everything = tuple(o for _, r in copies for o in [r] + list(r.children_recursive))
    no_roof = tuple(o for p, r in copies if p != "ws_roof_tile" for o in [r] + list(r.children_recursive))
    overlay = tuple(plan_overlay())
    # Godot's view of the site: north up is -Y in the kit, so show the plan with +Y (the door) up
    ws.render(target, os.path.join(previews, "plan.png"), (0.0, 0.0, 1.0), 11.0, focus=(-D.x, -D.y + 0.5, 0.0),
              keep_visible=no_roof + overlay, size=1100)
    ws.render(target, os.path.join(previews, "exterior_door.png"), (0.6, 1.0, 0.45), 14.0, True, 24.0,
              (-D.x, -D.y, 1.5), keep_visible=everything, size=1000)
    ws.render(target, os.path.join(previews, "exterior_back.png"), (-0.7, -1.0, 0.4), 14.0, True, 24.0,
              (-D.x, -D.y, 1.5), keep_visible=everything, size=1000)
    # Inside, without the roof and the south and east walls: from the operator area and the door
    open_side = tuple(o for p, r in copies
                      if p != "ws_roof_tile" and not (p in ("ws_wall_panel", "ws_wall_window", "ws_corner", "ws_plinth")
                                                      and (r.location.y < -HY + 0.5 or r.location.x > HX - 0.5))
                      for o in [r] + list(r.children_recursive))
    ws.render(target, os.path.join(previews, "inside_from_south_east.png"), (0.8, -1.0, 0.9), 12.0, True, 18.0,
              (-D.x, -D.y, 0.8), keep_visible=open_side, size=1000)
    ws.render(target, os.path.join(previews, "inside_bay_low.png"), (0.5, -1.0, 0.25), 9.0, True, 12.0,
              (-D.x - 0.5, -D.y + 0.5, 1.0), keep_visible=open_side, size=1000)
    for o in overlay:
        bpy.data.objects.remove(o)
    ws.set_preview_colors(False)


def main() -> None:
    previews = ws.preview_dir("layout")
    ws.rk.reset_scene()
    parts = load_parts()
    placements = instances()
    layout = ws.root_empty("ws_layout")
    counters = {}
    for part, location, turn in placements:
        counters[part] = counters.get(part, 0) + 1
        ws.add_empty(layout, "place_%s_%02d" % (part, counters[part]), location, turn)
    for name, location in LAYOUT_EMPTIES.items():
        ws.add_empty(layout, name, location)
    bpy.context.view_layer.update()
    rows = []
    failures = check_layout_root(layout, rows)
    ws.export(layout)
    copies = place_copies(parts, placements)
    failures += run_checks(copies, rows)
    tris = sum(ws.visible_triangles(r) for _, r in copies)
    rows.append("assembled workshop: %d part instances, %d triangles (target about 15,500 with markers)" % (len(copies), tris))
    if previews:
        render_previews(copies, previews)
    # Keep only the layout and the references in the .blend; the parts live in their own files
    keep = {layout, *layout.children_recursive}
    for o in [o for o in bpy.data.objects if o not in keep]:
        bpy.data.objects.remove(o)
    ws.add_references()
    ws.save("layout")
    rows.append("ALL CHECKS OK" if failures == 0 else "%d CHECK FAILURES" % failures)
    ws.report("layout", rows)


if __name__ == "__main__":
    main()
