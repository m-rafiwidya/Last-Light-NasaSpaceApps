"""Generates the workshop decor's work clutter and safety pieces (DECOR_KIT.md 3.1, 3.2): the tool
chest, the storage crate, the cable reel, the spare panels, the old spare wheel, the folded
ladder, the oxygen rack, the fire extinguisher, the bay door's threshold band and the three hazard
signs. Checks and previews.

    blender -b --factory-startup -P tools/blender/scripts/decor/make_decor_bay.py [-- --previews DIR | --no-previews]

Writes tools/blender/parts/decor/decor_bay.blend, game/res/models/decor_kit/<piece>.glb and
previews in tools/blender/previews/decor/bay/.

Piece frames (decor_kit_common.py): fronts face -Y; floor pieces have their origin in the middle
of the footprint on the floor, wall pieces in the middle of the back on the wall plane y = 0.
"""

import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.append(os.path.dirname(__file__))
import decor_kit_common as dc  # noqa: E402

ws = dc.ws
# (budget, size x, y, z) per piece: DECOR_KIT.md 7.1, the sizes of 3.1 and 3.2
SPECS = {
    "dc_tool_chest": (300, (0.965, 0.535, 1.00)),     # with its side handle and pull bars
    "dc_crate": (110, (0.60, 0.40, 0.40)),
    "dc_cable_reel": (160, (0.40, 0.483, 0.483)),     # with the crank; 12-sided flanges
    "dc_spare_panels": (140, None),
    "dc_wheel_spare": (280, None),
    "dc_ladder": (180, None),
    "dc_o2_rack": (420, None),
    "dc_extinguisher": (140, None),
    "dc_threshold_band": (80, (4.00, 0.20, None)),
    "dc_sign_warning": (60, (0.30, None, 0.40)),
    "dc_sign_oxidiser": (90, (0.30, None, 0.40)),
    "dc_sign_voltage": (60, (0.30, None, 0.40)),
}


# --- Work clutter -------------------------------------------------------------------------------

def make_tool_chest():
    """A rolling chest: dark body on four locked casters, five pale drawer fronts with amber pull
    bars, a label plate on the top drawer, fastener heads on the front corners."""
    bm = ws.new_bmesh()
    hx, hy = 0.45, 0.25
    base = 0.08
    ws.box(bm, (-hx, hx), (-hy, hy), (base, 1.00), 0)
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            cx, cy = sx * (hx - 0.06), sy * (hy - 0.06)
            ws.box(bm, (cx - 0.025, cx + 0.025), (cy - 0.035, cy + 0.035), (0.0, base), 2)
    # Drawers, top to bottom: the top one shallow (it carries the label)
    edges = [0.98, 0.86, 0.72, 0.56, 0.38, 0.12]
    for k in range(5):
        z0, z1 = edges[k + 1] + 0.01, edges[k] - 0.01
        ws.trim(bm, (-hx + 0.04, hx - 0.04), (-hy - 0.012, -hy), (z0, z1), 1, "+y")
        bar_z = z1 - 0.035
        ws.box(bm, (-0.18, 0.18), (-hy - 0.035, -hy - 0.012), (bar_z - 0.012, bar_z + 0.012), 3)
    # Label plate on the top drawer, left of its pull bar
    ws.trim(bm, (-0.40, -0.21), (-hy - 0.016, -hy - 0.012), (0.875, 0.945), 4, "+y")
    for sx in (-1.0, 1.0):
        for z in (0.105, 0.965):
            ws.stud(bm, (sx * (hx - 0.02), -hy, z), "-y", 2)
    # Side handle (the chest is pushed by it)
    ws.box(bm, (hx, hx + 0.04), (-0.15, -0.12), (0.80, 0.84), 2)
    ws.box(bm, (hx, hx + 0.04), (0.12, 0.15), (0.80, 0.84), 2)
    ws.box(bm, (hx + 0.04, hx + 0.065), (-0.15, 0.15), (0.80, 0.84), 2)
    root = ws.make_object("dc_tool_chest", bm, ["ws_frame", "ws_panel", "ws_dark", "ws_accent", "ws_label"])
    ws.collision_box(root, "dc_tool_chest", (-hx, hx + 0.065), (-hy - 0.035, hy), (0.0, 1.00))
    dc.front_text(root, "text", (-0.305, -hy - 0.016, 0.91))
    return root


def make_crate():
    """A storage crate: pale ribbed body, a dark lid, two handle slots and a label plate."""
    bm = ws.new_bmesh()
    hx, hy = 0.30, 0.20
    lid = 0.37
    ws.box(bm, (-hx + 0.01, hx - 0.01), (-hy + 0.01, hy - 0.01), (0.0, lid), 0)
    ws.box(bm, (-hx, hx), (-hy, hy), (lid, 0.40), 1)
    # Vertical ribs on the long faces, near the corners
    for sy, side in ((-1.0, "+y"), (1.0, "-y")):
        y0 = sy * (hy - 0.01)
        y = (y0 - 0.01, y0) if sy < 0 else (y0, y0 + 0.01)
        for rx in (-hx + 0.04, hx - 0.04):
            ws.trim(bm, (rx - 0.02, rx + 0.02), y, (0.0, lid), 2, side)
    # Handle slots (dark recesses drawn as plates) on the short ends
    for sx in (-1.0, 1.0):
        x = (hx - 0.01, hx - 0.008) if sx > 0 else (-hx + 0.008, -hx + 0.01)
        ws.quad(bm, [(x[0], -0.06, 0.27), (x[0], 0.06, 0.27), (x[0], 0.06, 0.31), (x[0], -0.06, 0.31)], 1, (sx, 0.0, 0.0))
    # Label plate in the middle of the front
    ws.trim(bm, (-0.15, 0.15), (-hy + 0.006, -hy + 0.01), (0.17, 0.27), 3, "+y")
    root = ws.make_object("dc_crate", bm, ["ws_panel", "ws_dark", "ws_frame", "ws_label"])
    ws.collision_box(root, "dc_crate", (-hx, hx), (-hy, hy), (0.0, 0.40))
    dc.front_text(root, "text", (0.0, -hy + 0.006, 0.22))
    return root


def make_cable_reel():
    """A cable reel on its flange rims, axle along X: two 12-sided flanges, amber cable wound on
    the drum, a crank handle."""
    bm = ws.new_bmesh()
    r = 0.25
    cz = r * math.cos(math.pi / 12)       # resting on a flange flat
    ws.cylinder(bm, (-0.135, 0.0, cz), "x", r, -0.015, 0.015, 0, 12)
    ws.cylinder(bm, (0.135, 0.0, cz), "x", r, -0.015, 0.015, 0, 12)
    ws.cylinder(bm, (0.0, 0.0, cz), "x", 0.19, -0.12, 0.12, 1, 12, (False, False))
    # Axle stub and crank on the +X side
    ws.cylinder(bm, (0.0, 0.0, cz), "x", 0.03, 0.15, 0.19, 2, 6, (False, True))
    ws.box(bm, (0.17, 0.19), (-0.02, 0.02), (cz, cz + 0.16), 2)
    ws.box(bm, (0.19, 0.25), (-0.015, 0.015), (cz + 0.13, cz + 0.16), 2)
    root = ws.make_object("dc_cable_reel", bm, ["ws_frame", "ws_accent", "ws_dark"])
    # (the crank stands 0.10 m past the flange; the collision box is the reel itself)
    ws.collision_box(root, "dc_cable_reel", (-0.15, 0.15), (-cz, cz), (0.0, 2.0 * cz))
    return root


def leaning_slab(bm, x: tuple, width_y: float, lean_out: float, height: float, thickness: float, mat: int):
    """A board leaning on the wall plane y = 0: its foot `lean_out` in front of the wall, its top
    against the wall at `height`. Returns the function mapping (x, s, t) -> point, with s along
    its height (0..height) and t out of its front face."""
    angle = math.asin(lean_out / height)

    def at(px, s, t):
        # Along the board from foot (s 0) to top (s height), t out of its front (towards -Y)
        foot = Vector((px, -lean_out - thickness / math.cos(angle), 0.0))
        up = Vector((0.0, math.sin(angle), math.cos(angle)))
        out = Vector((0.0, -math.cos(angle), math.sin(angle)))
        return foot + up * s + out * t
    corners = [at(px, s, t) for t in (-thickness, 0.0) for s in (0.0, height) for px in x]
    verts = [bm.verts.new(c) for c in corners]
    idx = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    faces = [bm.faces.new([verts[i] for i in f]) for f in idx]
    for f in faces:
        f.material_index = mat
    centre = at((x[0] + x[1]) / 2.0, height / 2.0, -thickness / 2.0)
    ws.rk.orient(bm, faces, lambda f: f.calc_center_median() - centre)
    return at


def make_spare_panels():
    """Two spare wall panels (1.00 x 1.80 x 0.03) leaning on the wall, matching the walls: pale
    faces, dark edge strips, fastener holes; a paper tag on the front one."""
    bm = ws.new_bmesh()
    boards = [((-0.55, 0.45), 0.30), ((-0.45, 0.55), 0.34)]       # back one, then the front one
    front_at = None
    for k, (x, lean) in enumerate(boards):
        at = leaning_slab(bm, x, 0.0, lean, 1.80, 0.03, 0)
        # Dark edge strips on its front face, both long sides
        for x0, x1 in ((x[0], x[0] + 0.05), (x[1] - 0.05, x[1])):
            pts = [at(x0, 0.0, 0.002), at(x1, 0.0, 0.002), at(x1, 1.80, 0.002), at(x0, 1.80, 0.002)]
            ws.quad(bm, pts, 1, at(0.0, 0.9, 1.0) - at(0.0, 0.9, 0.0))
        # Fastener holes along the strips
        for s in (0.30, 0.90, 1.50):
            for px in (x[0] + 0.025, x[1] - 0.025):
                c = at(px, s, 0.003)
                pts = [c + Vector(d) for d in ((-0.01, 0.0, -0.01), (0.01, 0.0, -0.01), (0.01, 0.0, 0.01), (-0.01, 0.0, 0.01))]
                ws.quad(bm, pts, 2, at(0.0, 0.9, 1.0) - at(0.0, 0.9, 0.0))
        front_at = at
    # The tag hangs straight down from a wire on the front panel's top corner area
    hook = front_at(0.30, 1.30, 0.0)
    ws.box(bm, (0.30 - 0.003, 0.30 + 0.003), (hook.y - 0.06, hook.y - 0.054), (hook.z - 0.12, hook.z), 1)
    tag_y = hook.y - 0.065
    ws.box(bm, (0.24, 0.36), (tag_y, tag_y + 0.002), (hook.z - 0.20, hook.z - 0.12), 3)
    root = ws.make_object("dc_spare_panels", bm, ["ws_panel", "ws_frame", "ws_dark", "ws_label"])
    ws.collision_box(root, "dc_spare_panels", (-0.55, 0.55), (-0.37, 0.0), (0.0, 1.80))
    dc.front_text(root, "text", (0.30, tag_y - 0.001, hook.z - 0.16))
    return root


def make_wheel_spare():
    """An old, larger wheel on a wall hook (not a rover part): a 0.44 m open-spoked rim with a
    worn dark tread, its axis out of the wall; a paper tag under it."""
    bm = ws.new_bmesh()
    r_out, r_in = 0.22, 0.185
    y0, y1 = -0.20, -0.02                 # the wheel's width, 2 cm off the wall plane
    yc = (y0 + y1) / 2.0
    sides = 14
    # Tread ring: outer and inner cylinders plus the two annular faces
    ws.cylinder(bm, (0.0, yc, 0.0), "y", r_out, y0 - yc, y1 - yc, 0, sides, (False, False))
    inner = ws.cylinder(bm, (0.0, yc, 0.0), "y", r_in, y0 - yc, y1 - yc, 0, sides, (False, False))
    for f in inner:
        f.normal_flip()
    for y, n in ((y0, -1.0), (y1, 1.0)):
        for k in range(sides):
            a0 = 2 * math.pi * k / sides + math.pi / sides
            a1 = 2 * math.pi * (k + 1) / sides + math.pi / sides
            pts = [(r * math.cos(a), y, r * math.sin(a)) for r, a in ((r_in, a0), (r_out, a0), (r_out, a1), (r_in, a1))]
            ws.quad(bm, pts, 0, (0.0, n, 0.0))
    # Worn grousers: raised bars across the tread, every other one worn away
    for k in range(0, sides, 2):
        if k in (4, 10):
            continue
        a = 2 * math.pi * (k + 0.5) / sides
        c = Vector((math.cos(a), 0.0, math.sin(a)))
        t = Vector((-math.sin(a), 0.0, math.cos(a)))
        p0 = c * r_out
        pts = [p0 + t * -0.02 + Vector((0.0, y0 + 0.01, 0.0)), p0 + t * 0.02 + Vector((0.0, y0 + 0.01, 0.0)),
               p0 + t * 0.02 + Vector((0.0, y1 - 0.01, 0.0)), p0 + t * -0.02 + Vector((0.0, y1 - 0.01, 0.0))]
        ws.quad(bm, [q + c * 0.004 for q in pts], 3, c)
    # Six spokes and the hub
    for k in range(6):
        a = 2 * math.pi * k / 6
        c, t = Vector((math.cos(a), 0.0, math.sin(a))), Vector((-math.sin(a), 0.0, math.cos(a)))
        corners = []
        for s in (0.045, r_in + 0.004):
            for w in (-0.012, 0.012):
                corners.append(c * s + t * w)
        verts = []
        for y in (yc - 0.012, yc + 0.012):
            verts += [bm.verts.new(p + Vector((0.0, y, 0.0))) for p in corners]
        idx = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
        faces = [bm.faces.new([verts[i] for i in f]) for f in idx]
        for f in faces:
            f.material_index = 1
        centre = c * (0.045 + r_in) / 2.0 + Vector((0.0, yc, 0.0))
        ws.rk.orient(bm, faces, lambda f, centre=centre: f.calc_center_median() - centre)
    ws.cylinder(bm, (0.0, yc, 0.0), "y", 0.05, y0 + 0.03 - yc, y1 - yc, 1, 8)
    # The hook: a bar out of the wall through the hub
    ws.box(bm, (-0.015, 0.015), (y0 - 0.03, 0.0), (0.035, 0.065), 2)
    ws.box(bm, (-0.015, 0.015), (y0 - 0.03, y0 - 0.01), (0.065, 0.10), 2)
    # Paper tag on a string under the wheel
    ws.box(bm, (-0.002, 0.002), (y0 + 0.012, y0 + 0.016), (-r_out - 0.06, -r_out + 0.01), 2)
    ws.box(bm, (-0.06, 0.06), (y0 + 0.010, y0 + 0.012), (-r_out - 0.14, -r_out - 0.06), 4)
    root = ws.make_object("dc_wheel_spare", bm, ["ws_dark", "ws_panel", "ws_frame", "ws_accent", "ws_label"])
    dc.front_text(root, "text", (0.0, y0 + 0.009, -r_out - 0.10))
    return root


def make_ladder():
    """A three-step aluminium step ladder, folded and hung on two wall hooks: its origin is the
    back's middle at the ladder's foot."""
    bm = ws.new_bmesh()
    height = 1.25
    for x in (-0.20, 0.20):
        ws.box(bm, (x - 0.02, x + 0.02), (-0.04, -0.01), (0.0, height), 0)        # rear legs, against the wall side
        ws.box(bm, (x - 0.02, x + 0.02), (-0.08, -0.05), (0.0, height), 0)        # front rails
    for z in (0.32, 0.62, 0.92):
        ws.box(bm, (-0.18, 0.18), (-0.10, -0.05), (z - 0.015, z + 0.015), 0)
        ws.trim(bm, (-0.18, 0.18), (-0.104, -0.10), (z - 0.015, z + 0.015), 1, "+y")
    ws.box(bm, (-0.20, 0.20), (-0.08, -0.01), (height - 0.04, height), 2)         # top cap
    for x in (-0.12, 0.12):
        ws.box(bm, (x - 0.012, x + 0.012), (-0.10, 0.0), (height - 0.10, height - 0.08), 3)   # hooks
        ws.box(bm, (x - 0.012, x + 0.012), (-0.10, -0.085), (height - 0.08, height - 0.03), 3)
    return ws.make_object("dc_ladder", bm, ["ws_panel", "ws_accent", "ws_dark", "ws_frame"])


# --- Life support and safety ---------------------------------------------------------------------

def make_o2_rack():
    """Three oxygen cylinders standing in a floor tray against the wall, held by a strap bar:
    pale bodies with a green shoulder band, dark necks and valves."""
    bm = ws.new_bmesh()
    ws.box(bm, (-0.50, 0.50), (-0.32, 0.0), (0.0, 0.05), 0)
    ws.trim(bm, (-0.48, 0.48), (-0.322, -0.32), (0.01, 0.04), 4, "+y")            # amber tray edge
    r = 0.115
    for x in (-0.30, 0.0, 0.30):
        c = (x, -0.16, 0.0)
        ws.cylinder(bm, c, "z", r, 0.05, 1.15, 1, 10, (False, False))
        ws.cylinder(bm, c, "z", r, 1.15, 1.28, 2, 10, (False, False))
        # Shoulder: a cone to the neck (one ring of quads)
        ws.cylinder(bm, c, "z", 0.05, 1.28, 1.38, 3, 8, (True, False))
        top = [bm.verts.new((x + 0.05 * math.cos(2 * math.pi * k / 10), -0.16 + 0.05 * math.sin(2 * math.pi * k / 10), 1.32))
               for k in range(10)]
        low = [bm.verts.new((x + r * math.cos(2 * math.pi * k / 10), -0.16 + r * math.sin(2 * math.pi * k / 10), 1.28))
               for k in range(10)]
        faces = [bm.faces.new((low[k], low[(k + 1) % 10], top[(k + 1) % 10], top[k])) for k in range(10)]
        for f in faces:
            f.material_index = 2
        ws.rk.orient(bm, faces, lambda f, x=x: f.calc_center_median() - Vector((x, -0.16, 1.2)))
        ws.box(bm, (x - 0.035, x + 0.035), (-0.195, -0.125), (1.38, 1.44), 3)     # valve
        ws.box(bm, (x - 0.01, x + 0.01), (-0.24, -0.195), (1.40, 1.42), 3)        # outlet
    # Uprights at the tray's ends and the strap bar in front of the cylinders at 1.0 m
    for x in (-0.50, 0.46):
        ws.box(bm, (x, x + 0.04), (-0.32, -0.28), (0.05, 1.04), 3)
        ws.box(bm, (x, x + 0.04), (-0.28, 0.0), (0.98, 1.02), 3)
    ws.box(bm, (-0.50, 0.50), (-0.32, -0.28), (0.97, 1.03), 3)
    for x in (-0.15, 0.15):
        ws.stud(bm, (x, -0.32, 1.0), "-y", 3)
    root = ws.make_object("dc_o2_rack", bm, ["ws_frame", "ws_label", "dc_green", "ws_dark", "ws_accent"])
    ws.collision_box(root, "dc_o2_rack", (-0.50, 0.50), (-0.32, 0.0), (0.0, 1.44))
    return root


def make_extinguisher():
    """A red fire extinguisher in a wall bracket (origin: the back's middle at the body's
    foot), with its red "FIRE EXTINGUISHER" plate 0.90 m above."""
    bm = ws.new_bmesh()
    r, yc = 0.08, -0.10
    ws.cylinder(bm, (0.0, yc, 0.0), "z", r, 0.0, 0.46, 0, 10)
    ws.cylinder(bm, (0.0, yc, 0.46), "z", 0.05, 0.0, 0.04, 0, 8, (False, False))
    ws.cylinder(bm, (0.0, yc, 0.50), "z", 0.025, 0.0, 0.05, 1, 6, (False, True))
    ws.box(bm, (-0.015, 0.015), (yc - 0.10, yc + 0.02), (0.53, 0.55), 2)          # handle
    ws.box(bm, (-0.015, 0.015), (yc - 0.08, yc + 0.01), (0.56, 0.58), 2)          # lever
    ws.box(bm, (0.04, 0.06), (yc - 0.07, yc - 0.05), (0.08, 0.52), 2)             # hose down the side
    # Bracket: a wall plate and a strap round the body
    ws.box(bm, (-0.06, 0.06), (-0.015, 0.0), (0.12, 0.40), 1)
    ws.box(bm, (-r - 0.01, r + 0.01), (yc - r - 0.01, -0.015), (0.30, 0.33), 1)
    # The red plate on the wall above it
    ws.trim(bm, (-0.15, 0.15), (-0.008, 0.0), (0.85, 0.95), 0, "+y")
    root = ws.make_object("dc_extinguisher", bm, ["dc_red", "ws_frame", "ws_dark"])
    dc.front_text(root, "text", (0.0, -0.009, 0.90))
    return root


def clip_polygon(poly: list, x0: float, x1: float) -> list:
    """Sutherland-Hodgman clip of a 2D polygon to x0 <= x <= x1."""
    def clip(points, inside, cross):
        out = []
        for k in range(len(points)):
            a, b = points[k - 1], points[k]
            if inside(b):
                if not inside(a):
                    out.append(cross(a, b))
                out.append(b)
            elif inside(a):
                out.append(cross(a, b))
        return out

    def at_x(xc):
        return lambda a, b: (xc, a[1] + (b[1] - a[1]) * (xc - a[0]) / (b[0] - a[0]))
    poly = clip(poly, lambda p: p[0] >= x0, at_x(x0))
    return clip(poly, lambda p: p[0] <= x1, at_x(x1)) if poly else poly


def make_threshold_band():
    """A 4.00 x 0.20 floor band of diagonal amber and black hazard stripes, 2 mm proud, inside
    the bay door's threshold (no collision)."""
    bm = ws.new_bmesh()
    hx, hy, z = 2.0, 0.10, 0.002
    w = 0.20                               # stripe width along the band, 45 degrees
    x = -hx - 2 * hy
    k = 0
    while x < hx:
        poly = [(x, -hy), (x + w, -hy), (x + w + 2 * hy, hy), (x + 2 * hy, hy)]
        poly = clip_polygon(poly, -hx, hx)
        if len(poly) >= 3:
            ws.floor_polygon(bm, poly, z, k % 2)
        x += w
        k += 1
    return ws.make_object("dc_threshold_band", bm, ["ws_accent", "ws_dark"])


def sign_plate(bm):
    """The hazard sign's plate (0.30 x 0.40 x 0.01, its back on the wall plane) and the triangle
    (dark border, amber field) in its upper part. Returns the triangle's centre height and the
    glyph's depth (y)."""
    ws.trim(bm, (-0.15, 0.15), (-0.010, 0.0), (-0.20, 0.20), 0, "+y")
    cz, size = 0.075, 0.115
    def tri(scale, y, mat):
        pts = [(size * scale * math.cos(a), y, cz + size * scale * math.sin(a))
               for a in (math.radians(90), math.radians(210), math.radians(330))]
        f = bm.faces.new([bm.verts.new(p) for p in pts])
        f.material_index = mat
        bm.normal_update()
        if f.normal.y > 0:
            f.normal_flip()
    tri(1.0, -0.012, 1)
    tri(0.78, -0.014, 2)
    return cz, -0.016


def glyph_polygon(bm, points: list, y: float, mat: int = 1) -> None:
    f = bm.faces.new([bm.verts.new((p[0], y, p[1])) for p in points])
    f.material_index = mat
    bm.normal_update()
    if f.normal.y > 0:
        f.normal_flip()


def make_sign(name: str, glyph: str):
    bm = ws.new_bmesh()
    cz, gy = sign_plate(bm)
    c = cz - 0.012
    if glyph == "warning":
        glyph_polygon(bm, [(-0.008, c + 0.045), (0.008, c + 0.045), (0.006, c - 0.005), (-0.006, c - 0.005)], gy)
        glyph_polygon(bm, [(-0.008, c - 0.030), (0.008, c - 0.030), (0.008, c - 0.016), (-0.008, c - 0.016)], gy)
    elif glyph == "voltage":
        glyph_polygon(bm, [(0.010, c + 0.050), (-0.020, c + 0.002), (0.000, c + 0.002), (-0.012, c - 0.040),
                           (0.022, c + 0.010), (0.003, c + 0.010), (0.022, c + 0.050)], gy)
    elif glyph == "oxidiser":
        # Flame over a circle: a ring (8 quads) and a flame outline above it
        cc = c - 0.018
        for k in range(8):
            a0, a1 = 2 * math.pi * k / 8, 2 * math.pi * (k + 1) / 8
            pts = [(rr * math.cos(a), cc + rr * math.sin(a)) for rr, a in ((0.014, a0), (0.024, a0), (0.024, a1), (0.014, a1))]
            glyph_polygon(bm, pts, gy)
        glyph_polygon(bm, [(0.0, c + 0.050), (0.016, c + 0.022), (0.012, c + 0.010), (0.0, c + 0.016),
                           (-0.012, c + 0.010), (-0.016, c + 0.022)], gy)
    root = ws.make_object(name, bm, ["ws_label", "ws_dark", "ws_accent"])
    dc.front_text(root, "text", (0.0, -0.011, -0.105))
    return root


# --- Checks and previews -------------------------------------------------------------------------

def run_checks(pieces: dict, rows: list) -> int:
    failures = 0
    for name, root in pieces.items():
        budget, size = SPECS[name]
        failures += dc.check_piece(root, budget, size, rows)
    # Wall pieces stay behind their back plane's front (nothing pokes into the wall)
    for name in ("dc_spare_panels", "dc_wheel_spare", "dc_ladder", "dc_o2_rack", "dc_extinguisher",
                 "dc_sign_warning", "dc_sign_oxidiser", "dc_sign_voltage"):
        lo, hi = dc.visible_bounds(pieces[name])
        ok = hi.y <= 1e-6
        failures += 0 if ok else 1
        rows.append("%s: %.3f m deep, %.2f m wide, %.2f m tall, back on the wall plane%s" % (
            name, -lo.y, hi.x - lo.x, hi.z - lo.z, "" if ok else "  FAIL (pokes %.3f m into the wall)" % hi.y))
    # The spare wheel must not read as a rover wheel (0.30 m): 0.44 m across
    lo, hi = ws.bounds([pieces["dc_wheel_spare"]])
    ok = hi.x - lo.x >= 0.43
    failures += 0 if ok else 1
    rows.append("dc_wheel_spare %.2f m across (the rover's wheels are 0.30 m)%s" % (hi.x - lo.x, "" if ok else "  FAIL"))
    return failures


MAKERS = {
    "dc_tool_chest": make_tool_chest, "dc_crate": make_crate, "dc_cable_reel": make_cable_reel,
    "dc_spare_panels": make_spare_panels, "dc_wheel_spare": make_wheel_spare, "dc_ladder": make_ladder,
    "dc_o2_rack": make_o2_rack, "dc_extinguisher": make_extinguisher, "dc_threshold_band": make_threshold_band,
    "dc_sign_warning": lambda: make_sign("dc_sign_warning", "warning"),
    "dc_sign_oxidiser": lambda: make_sign("dc_sign_oxidiser", "oxidiser"),
    "dc_sign_voltage": lambda: make_sign("dc_sign_voltage", "voltage"),
}


def main() -> None:
    previews = dc.preview_dir("bay")
    ws.rk.reset_scene()
    pieces = {}
    for name, maker in MAKERS.items():
        pieces[name] = maker()
    bpy.context.view_layer.update()
    for root in pieces.values():
        dc.export(root)
    rows = []
    failures = run_checks(pieces, rows)
    if previews:
        dc.render_pieces(pieces, previews)
    # Spread the pieces out in the .blend so they can be looked at side by side
    for k, root in enumerate(pieces.values()):
        root.location = (1.5 * (k % 6), -2.0 * (k // 6), 0.0)
    dc.save("decor_bay")
    rows.append("ALL CHECKS OK" if failures == 0 else "%d CHECK FAILURES" % failures)
    dc.report("bay", rows)


if __name__ == "__main__":
    main()
