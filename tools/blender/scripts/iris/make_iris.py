"""Generates IRIS (A07, IRIS_KIT.md 6, 7), the uncrewed research station: an instrument body on four
legs with the service panel, the diagnostic (cartridge) port, the radio-power module's socket, a mast
with the station indicator and a pan/tilt antenna, and four years of dust. Posed on the Apollo 12
terrain where the port's pose is the one the delivery was tuned to; checks the cartridge delivery
against it (IRIS_KIT.md 2, 8), the module socket's reach, the antenna's swing, and renders previews.

    blender -b --factory-startup -P tools/blender/scripts/iris/make_iris.py [-- --previews DIR | --no-previews]

Writes tools/blender/parts/iris/iris.blend, game/res/models/iris_kit/iris.glb and previews in
tools/blender/previews/iris/. Needs the rover kit's .blend files (with cargo_mount and cartridge)
and game/res/terrain/moon_apollo12/play.f32.

IRIS's frame: the rover frame (ground at z -0.10, front +Y), the GLB root on the ground under IRIS's
origin (Godot places it on the terrain there, turned to IRIS_YAW_DEG). The tilt and height on the
terrain (PORT_POSE) are baked under the root:
    iris_body            2.0 x 1.5 m, 1.3 m tall on four footpads; radiator, solar plate, name plate
      iris_service_panel   the front's left: connector strip (J1-J3, each labelled twice), and
        service_door         its door, hinged on its left edge (title plate, Evan's service tag)
      iris_mast            3 m mast behind the panel, with the indicator lamp (iris_indicator)
        iris_antenna_pan     pan head (turns about Z), exported parked
          iris_antenna         tilt (about X), with iris_antenna_dish
      iris_dust            drifts, the dusty band round the foot, films on the lid and solar plate
    iris_port            the diagnostic port bracket: box centre (0.08, 0.70), top z 0.46 (rover
                         frame), opening 0.28 x 0.17 m, 0.08 deep, a 10 mm lead-in; iris_status_light
    iris_module_socket   the radio-power module's bay on the left side, at the port's height
    socket_cartridge, anchor_cartridge_seated, socket_module, anchor_module_seated, scan_point,
    park_cartridge, park_module (where Kite's origin stops, on the ground, facing -Y), text_*
    (Label3D anchors, IRIS_KIT.md 6.6)
    colliders: body, port, module socket
"""

import itertools
import math
import os
import random
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector

HERE = os.path.dirname(__file__)
sys.path.append(os.path.join(HERE, ".."))
sys.path.append(os.path.join(HERE, "..", "workshop"))
import rover_kit_common as kit  # noqa: E402
import make_arm as arm_kit  # noqa: E402
import make_power_antenna_motor as pam  # noqa: E402
import workshop_kit_common as ws  # noqa: E402

# IRIS's one material of its own (IRIS_KIT.md 6.5): regolith dust, on top of the workshop's
ws.PALETTE.update({"ir_dust": "8C8579"})
ws.MATERIAL_SETTINGS.update({"ir_dust": (0.0, 0.95)})
ws.PREVIEW_COLORS.update({"ir_dust": "A39A8A"})

PARTS_DIR = os.path.join(kit.REPO_ROOT, "tools", "blender", "parts", "iris")
EXPORT_DIR = os.path.join(kit.REPO_ROOT, "game", "res", "models", "iris_kit")
PLAY = os.path.join(kit.REPO_ROOT, "game", "res", "terrain", "moon_apollo12", "play.f32")

# IRIS_KIT.md 7
IRIS_XZ = (-204.0, 136.0)
IRIS_YAW_DEG = 140.4                 # Godot rotation about Y: IRIS's front faces azimuth 219.6
GROUND_Z = -0.10                     # the rover frame's ground at rest

PORT_CENTRE = Vector((0.08, 0.70))
PORT_TOP = 0.46
PORT_BOX = (0.17, 0.12, 0.12)        # half x, half y, height
# 0.28 x 0.17 m, 0.08 deep: the cartridge (0.262 m with its end grips, 0.154 with its stripe) with
# 9 mm a side, plus the 10 mm lead-in
OPENING = (0.14, 0.085, 0.08)        # half x, half y, depth
SEAT_GAP = 0.006                     # released 6 mm above the port floor (the port tilts up to 3 mm across), then snapped onto the seat
LEAD_IN = 0.01
# The port bracket's pose under the root (location, rotation w x y z): the pose the delivery, the
# approach route and tests/test_iris.gd were tuned to (it was solved on the terrain for the
# disabled rover this spot held before)
PORT_POSE = ((0.067931, 0.691832, 0.559296), (0.99987638, 0.00872574, -0.01308914, -0.00011423))
# The body (rover frame): ASSET_BRIEF's 2 x 1.5 x 1.3 m. Its front stays where the placeholder's
# was, so the port's struts and the parking window are unchanged
BODY_X = (-1.0, 1.0)
BODY_Y = (-1.05, 0.45)
BODY_BOTTOM = 0.24                   # above the ground, on the legs
BODY_TOP = 1.30
LID = 0.05
CHAMFER = 0.06
SKIRT = 0.15                         # the collider reaches this far into the ground
LEGS = [(-0.86, -0.90), (0.86, -0.90), (-0.86, 0.30), (0.86, 0.30)]
PAD_RADIUS = 0.11
PAD_HEIGHT = 0.06
PAD_SINK = 0.035                     # the footpads' bottoms below the ground under them
DRIFT = 0.07                         # dust drifts round the pads
SOLAR = ((-0.98, 1.34), (-0.36, 1.62))   # the solar plate's low and high edge (y, height)
SOLAR_X = (-0.40, 0.92)
NAME_PLATE = ((0.38, 0.92), (1.02, 1.16))       # x, heights
LID_DUST = [((0.55, 0.12), (0.32, 0.22)), ((-0.20, 0.20), (0.22, 0.14)), ((0.70, -0.55), (0.18, 0.14))]   # (centre), (radii)
# Service panel (front, left, under the mast)
SERVICE_PANEL = ((-0.90, -0.20), (0.30, 1.17))  # x, heights
DOOR_Z = (0.52, 1.13)
TITLE_PLATE = (-0.80, -0.40)
TAG_PLATE = ((-0.82, -0.44), (0.64, 0.80))
CONNECTORS = (-0.75, -0.55, -0.35)              # J1 radio power, J2 data, J3 heater
CONNECTOR_Z = 0.405
# The radio-power module's socket (M2): on the left side (beside the service panel), at the port's
# height and as far out of its face as the port, so the arm reaches it the same way from a parking
# window on that side. Built facing out of its face, then turned onto it: (along, out of the face)
MODULE_FACE_DEG = 180.0              # the left face's outward normal, from +X
MODULE_IN_FACE = Vector((0.0, 0.22))
MODULE_BOX = (0.175, 0.125, 0.16)
MODULE_RAISE = 0.09                  # the ground on that side is higher: the top 0.46 in Kite's frame too
MODULE_OPENING = (0.16, 0.11, 0.12)
# Mast and antenna (pan about Z, tilt about X, + = up); ANTENNA_* are (pan, tilt) in degrees and
# iris.gd uses the same numbers
MAST_XY = (-0.55, -0.20)
MAST_TOP = 2.62
MAST_RADIUS = 0.04
INDICATOR_Z = (2.30, 2.40)
TILT_Z = 2.80
YOKE_X = 0.09
DISH_OFFSET = 0.20
DISH_RADIUS = 0.26
DISH_DEPTH = 0.06
FEED_LENGTH = 0.17
ANTENNA_PARKED = (0.0, -25.0)
ANTENNA_TRACKED = (35.0, 40.0)

BUDGET = 6000
# The delivery (IRIS_KIT.md 8): parking window from the rescuer's arm yaw axis to the port
YAW_AXIS = Vector((-0.12, 0.53))
WINDOW_D = (0.45, 0.57)
WINDOW_BEARING = (-18.0, 13.0)
LIFT = {"J1": 0.0, "J2": 90.0, "J3": 70.0, "J4": 110.0, "J5": 0.0}     # the latch still points down, J4 at its limit
STROKE = 0.10
MIN_GAP = 0.020


# --- Terrain -----------------------------------------------------------------------------------

_heights = np.fromfile(PLAY, dtype="<f4").reshape(513, 513)


def terrain(x: float, z: float) -> float:
    c, r = (x + 512.0) / 2.0, (z + 512.0) / 2.0
    c0, r0 = int(math.floor(c)), int(math.floor(r))
    fc, fr = c - c0, r - r0
    h = _heights
    if fc + fr <= 1.0:
        return float(h[r0, c0] + (h[r0, c0 + 1] - h[r0, c0]) * fc + (h[r0 + 1, c0] - h[r0, c0]) * fr)
    return float(h[r0 + 1, c0 + 1] + (h[r0 + 1, c0] - h[r0 + 1, c0 + 1]) * (1 - fc) + (h[r0, c0 + 1] - h[r0 + 1, c0 + 1]) * (1 - fr))


def iris_to_world(p) -> tuple:
    """IRIS frame (x, y) to Godot world (x, z)."""
    t = math.radians(IRIS_YAW_DEG)
    a, c = p[0], -p[1]
    return (IRIS_XZ[0] + a * math.cos(t) + c * math.sin(t), IRIS_XZ[1] - a * math.sin(t) + c * math.cos(t))


H0 = terrain(*IRIS_XZ)


def ground_local(x: float, y: float) -> float:
    """Terrain height under an IRIS-frame point, relative to the ground under IRIS's origin."""
    return terrain(*iris_to_world((x, y))) - H0


# --- Building IRIS -----------------------------------------------------------------------------

def hg(v: float) -> float:
    """A height above the ground (m) as a rover-frame z."""
    return GROUND_Z + v


def tilt_matrix() -> Matrix:
    """Rover frame to IRIS's root frame: what puts the port (origin at its top centre) on PORT_POSE."""
    loc, rot = PORT_POSE
    port_world = Matrix.Translation(loc) @ Quaternion(rot).to_matrix().to_4x4()
    return port_world @ Matrix.Translation((-PORT_CENTRE.x, -PORT_CENTRE.y, -PORT_TOP))


def top_loading_bay(bm, centre, top: float, half: tuple, opening: tuple, height: float, lead_in: float,
                    face: float = BODY_Y[1]) -> tuple:
    """A bracket box with a top-loading opening (materials 0 frame, 1 dark floor, 2 lead-in), as
    the cartridge port; the struts back to the body's front face. Returns (z0, floor z)."""
    cx, cy = centre
    hx, hy = half
    ox, oy, depth = opening
    z0, z1 = top - height, top
    zf = top - depth
    ws.box(bm, (cx - hx, cx + hx), (cy - hy, cy + hy), (z0, zf), 0)                        # floor block
    for x, y in (((cx - hx, cx - ox), (cy - hy, cy + hy)), ((cx + ox, cx + hx), (cy - hy, cy + hy)),
                 ((cx - ox, cx + ox), (cy - hy, cy - oy)), ((cx - ox, cx + ox), (cy + oy, cy + hy))):
        ws.box(bm, x, y, (zf, z1 - lead_in), 0)
    # Lead-in: the rim's inner edge chamfered (amber), the rim top
    outer = [(cx - hx, cy - hy), (cx + hx, cy - hy), (cx + hx, cy + hy), (cx - hx, cy + hy)]
    mid = [(cx - ox - lead_in, cy - oy - lead_in), (cx + ox + lead_in, cy - oy - lead_in),
           (cx + ox + lead_in, cy + oy + lead_in), (cx - ox - lead_in, cy + oy + lead_in)]
    inner = [(cx - ox, cy - oy), (cx + ox, cy - oy), (cx + ox, cy + oy), (cx - ox, cy + oy)]
    for k in range(4):
        n = (k + 1) % 4
        ws.quad(bm, [(outer[k][0], outer[k][1], z1 - lead_in), (outer[n][0], outer[n][1], z1 - lead_in),
                     (mid[n][0], mid[n][1], z1 - lead_in), (mid[k][0], mid[k][1], z1 - lead_in)], 0, (0, 0, 1))
        ws.quad(bm, [(mid[k][0], mid[k][1], z1 - lead_in), (mid[n][0], mid[n][1], z1 - lead_in),
                     (inner[n][0], inner[n][1], z1 - 2 * lead_in), (inner[k][0], inner[k][1], z1 - 2 * lead_in)], 2, (0, 0, 1))
    ws.floor_quad(bm, (cx - ox, cx + ox), (cy - oy, cy + oy), zf + 0.001, 1)                 # dark floor
    for x in (cx - hx * 0.5, cx + hx * 0.5):                                                # struts to the body
        ws.box(bm, (x - 0.015, x + 0.015), (face, cy - hy), (z0 + 0.02, z0 + 0.07), 0)
    return z0, zf


def build_port() -> bpy.types.Object:
    """The diagnostic port bracket (the cartridge's, IRIS_KIT.md 6.2), unchanged from the placeholder."""
    bm = bmesh.new()
    cx, cy = PORT_CENTRE
    hx, hy, h = PORT_BOX
    z0, zf = top_loading_bay(bm, PORT_CENTRE, PORT_TOP, (hx, hy), OPENING, h, LEAD_IN)
    port = ws.make_object("iris_port", bm, ["ws_frame", "ws_dark", "ws_accent"], origin=(cx, cy, PORT_TOP))
    bm = bmesh.new()
    ws.trim(bm, (cx - 0.10, cx + 0.10), (cy + hy, cy + hy + 0.005), (PORT_TOP - 0.06, PORT_TOP - 0.03), 0, "-y")
    ws.dome(bm, (cx + hx - 0.04, cy - hy + 0.04, PORT_TOP - LEAD_IN), 0.025, 0, 8)
    ws.make_object("iris_status_light", bm, ["ws_status"], parent=port)
    ws.add_empty(port, "socket_cartridge", (cx, cy, PORT_TOP))
    ws.add_empty(port, "anchor_cartridge_seated", (cx, cy, zf + SEAT_GAP))
    ws.collision_box(port, "iris_port", (cx - hx, cx + hx), (cy - hy, cy + hy), (z0, PORT_TOP))
    return port


def module_face_matrix() -> Matrix:
    """The module socket's face frame (x along the face, y out of it, the face at y 0) to IRIS's."""
    return Matrix.Translation((BODY_X[0], 0.0, 0.0)) @ Matrix.Rotation(math.radians(MODULE_FACE_DEG - 90.0), 4, "Z")


def build_module_socket() -> bpy.types.Object:
    """The radio-power module's socket (M2, A10) on IRIS's left side: a bigger top-loading bay at the
    port's height, its long side along the face (IRIS's Y). Empty now (the module was lost): a dark
    bay with a bare connector on its floor."""
    bm = bmesh.new()
    cx, cy = MODULE_IN_FACE
    hx, hy, h = MODULE_BOX
    top = PORT_TOP + MODULE_RAISE
    z0, zf = top_loading_bay(bm, MODULE_IN_FACE, top, (hx, hy), MODULE_OPENING, h, LEAD_IN, face=0.0)
    ws.cylinder(bm, (cx, cy, zf), "z", 0.03, 0.0, 0.02, 1, 8)                               # the bare connector
    ws.trim(bm, (cx - 0.12, cx + 0.12), (cy + hy, cy + hy + 0.004), (top - 0.05, top - 0.025), 2, "-y")
    m = module_face_matrix()
    bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
    centre = m @ Vector((cx, cy, top))
    sock = ws.make_object("iris_module_socket", bm, ["ws_frame", "ws_dark", "ws_accent"], origin=centre)
    ws.add_empty(sock, "socket_module", centre)
    ws.add_empty(sock, "anchor_module_seated", (centre.x, centre.y, zf + SEAT_GAP))
    corners = [m @ Vector((cx + sx * hx, cy + sy * hy, 0.0)) for sx in (-1, 1) for sy in (-1, 1)]
    ws.collision_box(sock, "iris_module_socket", (min(c.x for c in corners), max(c.x for c in corners)),
                     (min(c.y for c in corners), max(c.y for c in corners)), (z0, top))
    return sock


def leg_ground(lx: float, ly: float) -> float:
    """The terrain under a leg as a z in IRIS's own (untilted) frame: each leg is cut to it."""
    tilt = tilt_matrix()
    p = tilt @ Vector((lx, ly, GROUND_Z))
    return GROUND_Z + ground_local(p.x, p.y) - p.z


def outline(inset: float = 0.0) -> list:
    """The body's plan, its vertical edges chamfered."""
    x0, x1 = BODY_X[0] + inset, BODY_X[1] - inset
    y0, y1 = BODY_Y[0] + inset, BODY_Y[1] - inset
    c = CHAMFER
    return [(x0 + c, y0), (x1 - c, y0), (x1, y0 + c), (x1, y1 - c), (x1 - c, y1), (x0 + c, y1), (x0, y1 - c), (x0, y0 + c)]


def slab(bm, x: tuple, p0: tuple, p1: tuple, thickness: float, mat: int) -> list:
    """A plate across x from p0 to p1 (y, z), `thickness` below that line."""
    d = Vector((p1[0] - p0[0], p1[1] - p0[1])).normalized()
    n = Vector((-d.y, d.x)) * thickness
    pts = [Vector(p0), Vector(p1), Vector(p1) - n, Vector(p0) - n]
    faces = rk_prism_x(bm, [(p.x, p.y) for p in pts], x)
    for f in faces:
        f.material_index = mat
    return faces


def rk_prism_x(bm, outline_yz: list, x: tuple) -> list:
    faces = kit.prism(bm, outline_yz, lambda u, v, w: (w, u, v), x[0], x[1])
    bmesh.ops.recalc_face_normals(bm, faces=faces)
    return faces


def build_body() -> bpy.types.Object:
    """The instrument body on four legs, its radiator, handle rail, solar plate and name plate."""
    bm = bmesh.new()
    PANEL, FRAME, DARK, ACCENT, CELLS, LABEL = range(6)
    ws.prism_xy(bm, outline(), hg(BODY_BOTTOM), hg(BODY_TOP - LID), PANEL)
    ws.prism_xy(bm, outline(0.03), hg(BODY_TOP - LID), hg(BODY_TOP), FRAME)                # lid
    ws.prism_xy(bm, outline(-0.015), hg(BODY_BOTTOM), hg(BODY_BOTTOM + 0.07), FRAME)       # base rail
    ws.prism_xy(bm, outline(-0.012), hg(BODY_TOP - LID - 0.04), hg(BODY_TOP - LID), FRAME)   # top rail
    for lx, ly in LEGS:
        g = leg_ground(lx, ly)
        ws.box(bm, (lx - 0.035, lx + 0.035), (ly - 0.035, ly + 0.035), (g, hg(BODY_BOTTOM)), FRAME)
        ws.cylinder(bm, (lx, ly, g), "z", PAD_RADIUS, -PAD_SINK, PAD_HEIGHT - PAD_SINK, FRAME, 10)
    # Radiator on the right (+x): a dark plate with fins
    x1 = BODY_X[1]
    ws.trim(bm, (x1, x1 + 0.006), (-0.90, 0.20), (hg(0.42), hg(1.12)), DARK, "-x")
    for k in range(8):
        y = -0.84 + k * 0.145
        ws.trim(bm, (x1 + 0.006, x1 + 0.045), (y - 0.006, y + 0.006), (hg(0.44), hg(1.10)), DARK, "-x")
    # Left (-x): a handle rail on two stand-offs and a vent
    x0 = BODY_X[0]
    for y in (-0.92, -0.42):
        ws.trim(bm, (x0 - 0.06, x0), (y - 0.015, y + 0.015), (hg(0.90), hg(0.93)), FRAME, "+x")
    ws.box(bm, (x0 - 0.075, x0 - 0.05), (-0.96, -0.38), (hg(0.895), hg(0.935)), ACCENT)
    ws.trim(bm, (x0 - 0.005, x0), (-0.95, -0.45), (hg(0.45), hg(0.70)), DARK, "+x")
    # Rear: a cable gland and a lifting eye on each top corner
    ws.trim(bm, (-0.30, 0.30), (BODY_Y[0] - 0.004, BODY_Y[0]), (hg(0.40), hg(0.62)), DARK, "+y")
    for x in (-0.80, 0.80):
        ws.cylinder(bm, (x, BODY_Y[0] + 0.10, hg(BODY_TOP)), "z", 0.03, 0.0, 0.04, ACCENT, 8)
    # Panel seams on the front and the sides
    yf = BODY_Y[1]
    ws.trim(bm, (-0.12, 0.92), (yf, yf + 0.003), (hg(0.885), hg(0.897)), FRAME, "-y")
    ws.trim(bm, (0.294, 0.306), (yf, yf + 0.003), (hg(0.32), hg(0.885)), FRAME, "-y")
    ws.trim(bm, (x0 - 0.003, x0), (-0.306, -0.294), (hg(0.32), hg(1.18)), FRAME, "+x")
    ws.trim(bm, (x1, x1 + 0.003), (0.294, 0.306), (hg(0.32), hg(1.18)), FRAME, "-x")
    # Name plate on the front's right
    ws.trim(bm, NAME_PLATE[0], (yf, yf + 0.004), (hg(NAME_PLATE[1][0]), hg(NAME_PLATE[1][1])), LABEL, "-y")
    ws.trim(bm, (NAME_PLATE[0][0], NAME_PLATE[0][1]), (yf, yf + 0.005), (hg(NAME_PLATE[1][0] - 0.03), hg(NAME_PLATE[1][0] - 0.015)), ACCENT, "-y")
    # Solar plate on the rear half of the lid, facing up and back, on two struts
    (sy0, sz0), (sy1, sz1) = SOLAR
    slab(bm, SOLAR_X, (sy0, hg(sz0)), (sy1, hg(sz1)), 0.03, FRAME)
    d = Vector((sy1 - sy0, sz1 - sz0)).normalized()
    n = Vector((-d.y, d.x))
    for a, b in ((0.04, 0.47), (0.53, 0.96)):
        p0 = Vector((sy0, hg(sz0))) + d * (Vector((sy1 - sy0, sz1 - sz0)).length * a) + n * 0.002
        p1 = Vector((sy0, hg(sz0))) + d * (Vector((sy1 - sy0, sz1 - sz0)).length * b) + n * 0.002
        for xs in ((SOLAR_X[0] + 0.04, -0.02), (0.02, SOLAR_X[1] - 0.04)):
            q = [(xs[0], p0.x, p0.y), (xs[1], p0.x, p0.y), (xs[1], p1.x, p1.y), (xs[0], p1.x, p1.y)]
            ws.quad(bm, q, CELLS, (0.0, n.x, n.y))
    for x in (SOLAR_X[0] + 0.15, SOLAR_X[1] - 0.15):
        ws.box(bm, (x - 0.02, x + 0.02), (sy1 - 0.06, sy1 - 0.02), (hg(BODY_TOP), hg(sz1) - 0.02), FRAME)
    body = ws.make_object("iris_body", bm, ["ws_panel", "ws_frame", "ws_dark", "ws_accent", "ws_screen", "ws_label"],
                          origin=(0.0, 0.0, GROUND_Z))
    ws.collision_box(body, "iris_body", BODY_X, BODY_Y, (GROUND_Z - SKIRT, hg(BODY_TOP)))
    ws.add_empty(body, "text_name", ((NAME_PLATE[0][0] + NAME_PLATE[0][1]) / 2.0, yf + 0.006,
                                      hg((NAME_PLATE[1][0] + NAME_PLATE[1][1]) / 2.0)))
    return body


def build_service_panel(body) -> bpy.types.Object:
    """The service panel on the front's left, under the antenna (M1's photo target): a framed door
    (hinged on its left edge) with a stencilled title and Evan's handwritten service tag, and under
    it a connector strip, every connector labelled twice."""
    (px0, px1), (pz0, pz1) = SERVICE_PANEL
    yf = BODY_Y[1]
    bm = bmesh.new()
    FRAME, DARK, LABEL, PANEL = range(4)
    w = 0.03
    for x, z in (((px0, px1), (pz0, pz0 + w)), ((px0, px1), (pz1 - w, pz1)), ((px0, px0 + w), (pz0, pz1)),
                 ((px1 - w, px1), (pz0, pz1)), ((px0, px1), (DOOR_Z[0] - 0.035, DOOR_Z[0] - 0.01))):
        ws.trim(bm, x, (yf, yf + 0.025), (hg(z[0]), hg(z[1])), FRAME, "-y")
    ws.trim(bm, (px0 + w, px1 - w), (yf, yf + 0.012), (hg(pz0 + w), hg(DOOR_Z[0] - 0.035)), DARK, "-y")   # connector strip
    for i, x in enumerate(CONNECTORS):
        zc = hg(CONNECTOR_Z)
        ws.cylinder(bm, (x, yf + 0.012, zc), "y", 0.034, 0.0, 0.026, FRAME, 10)
        ws.cylinder(bm, (x, yf + 0.012, zc), "y", 0.022, 0.026, 0.036, PANEL if i else DARK, 10)
        for side, dz in (("a", 0.058), ("b", -0.058)):
            ws.trim(bm, (x - 0.095, x + 0.095), (yf + 0.012, yf + 0.015), (zc + dz - 0.014, zc + dz + 0.014), LABEL, "-y")
    panel = ws.make_object("iris_service_panel", bm, ["ws_frame", "ws_dark", "ws_label", "ws_panel"],
                           origin=(px0, yf, hg(pz0)), parent=body)
    for i, x in enumerate(CONNECTORS):
        for side, dz in (("a", 0.058), ("b", -0.058)):
            ws.add_empty(panel, "text_conn_j%d_%s" % (i + 1, side), (x, yf + 0.016, hg(CONNECTOR_Z) + dz))
    ws.add_empty(panel, "scan_point", ((px0 + px1) / 2.0, yf + 0.05, hg((pz0 + pz1) / 2.0)))
    # The door, its origin on the hinge line
    bm = bmesh.new()
    PANEL, FRAME, LABEL, ACCENT = range(4)
    dx0, dx1 = px0 + w + 0.005, px1 - w - 0.005
    dz0, dz1 = DOOR_Z
    ws.trim(bm, (dx0, dx1), (yf + 0.005, yf + 0.025), (hg(dz0), hg(dz1)), PANEL, "-y")
    ws.trim(bm, TITLE_PLATE, (yf + 0.025, yf + 0.029), (hg(dz1 - 0.10), hg(dz1 - 0.045)), LABEL, "-y")
    ws.trim(bm, TAG_PLATE[0], (yf + 0.025, yf + 0.028), (hg(TAG_PLATE[1][0]), hg(TAG_PLATE[1][1])), LABEL, "-y")
    for z in (dz0 + 0.14, dz1 - 0.14):                                                   # hinge knuckles
        ws.cylinder(bm, (dx0 - 0.004, yf + 0.03, hg(z)), "z", 0.012, -0.04, 0.04, FRAME, 8)
    ws.trim(bm, (dx1 - 0.07, dx1 - 0.04), (yf + 0.025, yf + 0.055), (hg(dz0 + 0.18), hg(dz1 - 0.18)), ACCENT, "-y")   # handle
    for x, z in ((dx0 + 0.03, dz0 + 0.03), (dx1 - 0.03, dz0 + 0.03), (dx0 + 0.03, dz1 - 0.03), (dx1 - 0.03, dz1 - 0.03)):
        ws.stud(bm, (x, yf + 0.025, hg(z)), "+y", FRAME)
    door = ws.make_object("service_door", bm, ["ws_panel", "ws_frame", "ws_label", "ws_accent"],
                          origin=(dx0 - 0.004, yf + 0.03, hg((dz0 + dz1) / 2.0)), parent=panel)
    ws.add_empty(door, "text_panel_title", ((TITLE_PLATE[0] + TITLE_PLATE[1]) / 2.0, yf + 0.030, hg(dz1 - 0.0725)))
    ws.add_empty(door, "text_service_label", ((TAG_PLATE[0][0] + TAG_PLATE[0][1]) / 2.0, yf + 0.029,
                                               hg((TAG_PLATE[1][0] + TAG_PLATE[1][1]) / 2.0)))
    return panel


def dish(bm, centre, radius: float, depth: float, mat: int, sides: int = 16, rings: int = 3) -> list:
    """A closed parabolic dish facing +Y: the centre at `centre`, the rim `depth` in front of it,
    a conical back."""
    c = Vector(centre)

    def p(r, k, y):
        a = 2.0 * math.pi * k / sides
        return bm.verts.new((c.x + r * math.cos(a), c.y + y, c.z + r * math.sin(a)))
    front_c = bm.verts.new(c)
    front = [[p(radius * i / rings, k, depth * (i / rings) ** 2) for k in range(sides)] for i in range(1, rings + 1)]
    back = [p(radius * 0.45, k, -0.025) for k in range(sides)]
    back_c = bm.verts.new(c + Vector((0.0, -0.04, 0.0)))
    faces = []
    for k in range(sides):
        n = (k + 1) % sides
        faces.append(bm.faces.new((front_c, front[0][k], front[0][n])))
        for i in range(rings - 1):
            faces.append(bm.faces.new((front[i][k], front[i + 1][k], front[i + 1][n], front[i][n])))
        faces.append(bm.faces.new((front[-1][k], back[k], back[n], front[-1][n])))
        faces.append(bm.faces.new((back[k], back_c, back[n])))
    for f in faces:
        f.material_index = mat
    bmesh.ops.recalc_face_normals(bm, faces=faces)
    return faces


def build_mast(body) -> dict:
    """The mast (behind the service panel), the station indicator on it and the antenna: a pan head
    (`iris_antenna_pan`, turns about Z) and a tilting dish (`iris_antenna`, about X), exported
    parked."""
    mx, my = MAST_XY
    bm = bmesh.new()
    kit.cylinder(bm, lambda u, v, w: (mx + u, my + v, w), hg(BODY_TOP), hg(MAST_TOP), MAST_RADIUS, 12)
    ws.cylinder(bm, (mx, my, hg(BODY_TOP)), "z", 0.09, 0.0, 0.03, 0, 12)                   # base flange
    ws.cylinder(bm, (mx, my, hg(INDICATOR_Z[0])), "z", 0.065, -0.02, 0.0, 1, 12)          # lamp collars
    ws.cylinder(bm, (mx, my, hg(INDICATOR_Z[1])), "z", 0.065, 0.0, 0.02, 1, 12)
    ws.box(bm, (mx - 0.012, mx + 0.012), (my - MAST_RADIUS - 0.022, my - MAST_RADIUS), (hg(BODY_TOP + 0.03), hg(INDICATOR_Z[0] - 0.02)), 1)  # cable duct
    mast = ws.make_object("iris_mast", bm, ["ws_frame", "ws_dark"], origin=(mx, my, hg(BODY_TOP)), parent=body)
    bm = bmesh.new()
    ws.cylinder(bm, (mx, my, hg(INDICATOR_Z[0])), "z", 0.05, 0.0, INDICATOR_Z[1] - INDICATOR_Z[0], 0, 12)
    ws.make_object("iris_indicator", bm, ["ws_status"], origin=(mx, my, hg(INDICATOR_Z[0])), parent=mast)
    # Pan head: housing, yoke, the fixed axle
    tz = hg(TILT_Z)
    bm = bmesh.new()
    ws.cylinder(bm, (mx, my, hg(MAST_TOP)), "z", 0.07, 0.0, 0.08, 0, 12)
    ws.box(bm, (mx - YOKE_X - 0.02, mx + YOKE_X + 0.02), (my - 0.03, my + 0.03), (hg(MAST_TOP + 0.08), hg(MAST_TOP + 0.11)), 0)
    for sx in (-1.0, 1.0):
        ws.box(bm, tuple(sorted((mx + sx * YOKE_X, mx + sx * (YOKE_X + 0.02)))), (my - 0.025, my + 0.025),
               (hg(MAST_TOP + 0.11), tz + 0.03), 0)
    ws.cylinder(bm, (mx, my, tz), "x", 0.016, -YOKE_X - 0.025, YOKE_X + 0.025, 1, 8)
    pan = ws.make_object("iris_antenna_pan", bm, ["ws_frame", "ws_dark"], origin=(mx, my, hg(MAST_TOP)), parent=mast)
    # Tilt: hub on the axle, boom, the dish (its own mesh) with a feed
    bm = bmesh.new()
    ws.cylinder(bm, (mx, my, tz), "x", 0.035, -YOKE_X + 0.02, YOKE_X - 0.02, 0, 10)
    ws.box(bm, (mx - 0.025, mx + 0.025), (my + 0.02, my + DISH_OFFSET - 0.03), (tz - 0.025, tz + 0.025), 0)
    tilt = ws.make_object("iris_antenna", bm, ["ws_frame"], origin=(mx, my, tz), parent=pan)
    bm = bmesh.new()
    dish(bm, (mx, my + DISH_OFFSET, tz), DISH_RADIUS, DISH_DEPTH, 0)
    ws.cylinder(bm, (mx, my + DISH_OFFSET, tz), "y", 0.010, 0.0, FEED_LENGTH, 1, 6)
    ws.box(bm, (mx - 0.03, mx + 0.03), (my + DISH_OFFSET + FEED_LENGTH, my + DISH_OFFSET + FEED_LENGTH + 0.05), (tz - 0.03, tz + 0.03), 2)
    ws.make_object("iris_antenna_dish", bm, ["ws_panel", "ws_frame", "ws_accent"], origin=(mx, my, tz), parent=tilt)
    return {"mast": mast, "pan": pan, "tilt": tilt}


def pose_antenna(parts: dict, pose: tuple) -> None:
    """(pan, tilt) in degrees: the pan about IRIS's Z, the tilt about X (+ = up)."""
    parts["pan"].rotation_euler = (0.0, 0.0, math.radians(pose[0]))
    parts["tilt"].rotation_euler = (math.radians(pose[1]), 0.0, 0.0)
    bpy.context.view_layer.update()


def build_dust(body) -> bpy.types.Object:
    """Four years of dust (ir_dust): drifts banked round the feet, a dusty band round the body's
    foot, a film on the lid and on the solar plate's lower half. Ragged edges, fixed seed."""
    rng = random.Random(4)
    bm = bmesh.new()
    sides = 12
    for lx, ly in LEGS:                                                  # drifts round the footpads
        g = leg_ground(lx, ly) - GROUND_Z
        inner = [(lx + (PAD_RADIUS + 0.004) * math.cos(a), ly + (PAD_RADIUS + 0.004) * math.sin(a))
                 for a in (2 * math.pi * k / sides for k in range(sides))]
        outer = [(lx + (PAD_RADIUS + DRIFT * rng.uniform(0.6, 1.0)) * math.cos(a),
                  ly + (PAD_RADIUS + DRIFT * rng.uniform(0.6, 1.0)) * math.sin(a)) for a in (2 * math.pi * k / sides for k in range(sides))]
        for k in range(sides):
            n = (k + 1) % sides
            ws.quad(bm, [(inner[k][0], inner[k][1], hg(g + PAD_HEIGHT - PAD_SINK - 0.012)), (outer[k][0], outer[k][1], hg(g - 0.03)),
                         (outer[n][0], outer[n][1], hg(g - 0.03)), (inner[n][0], inner[n][1], hg(g + PAD_HEIGHT - PAD_SINK - 0.012))], 0, (0, 0, 1))
    pts = outline(-0.0025)                                               # band round the body's foot
    for k in range(len(pts)):
        a, b = Vector(pts[k]), Vector(pts[(k + 1) % len(pts)])
        steps = max(1, int((b - a).length / 0.12))
        normal = Vector(((b - a).y, -(b - a).x)).normalized()
        for s in range(steps):
            p0, p1 = a.lerp(b, s / steps), a.lerp(b, (s + 1) / steps)
            t0 = hg(BODY_BOTTOM + 0.07 + rng.uniform(0.03, 0.10))
            t1 = hg(BODY_BOTTOM + 0.07 + rng.uniform(0.03, 0.10))
            ws.quad(bm, [(p0.x, p0.y, hg(BODY_BOTTOM + 0.072)), (p1.x, p1.y, hg(BODY_BOTTOM + 0.072)), (p1.x, p1.y, t1), (p0.x, p0.y, t0)],
                    0, (normal.x, normal.y, 0.0))
    for (cxl, cyl), (rx, ry) in LID_DUST:                                # patches on the lid
        patch = []
        for k in range(14):
            a = 2.0 * math.pi * k / 14
            r = rng.uniform(0.6, 1.0)
            patch.append((cxl + rx * r * math.cos(a), cyl + ry * r * math.sin(a)))
        ws.floor_polygon(bm, patch, hg(BODY_TOP) + 0.002, 0)
    (sy0, sz0), (sy1, sz1) = SOLAR                                       # the solar plate's lower half
    d = Vector((sy1 - sy0, sz1 - sz0))
    n = Vector((-d.normalized().y, d.normalized().x)) * 0.004
    xs = [SOLAR_X[0] + 0.02 + (SOLAR_X[1] - SOLAR_X[0] - 0.04) * k / 8 for k in range(9)]
    low = Vector((sy0, hg(sz0))) + n
    edge = [low + d * rng.uniform(0.25, 0.45) for _ in xs]
    for k in range(8):
        q = [(xs[k], low.x, low.y), (xs[k + 1], low.x, low.y), (xs[k + 1], edge[k + 1].x, edge[k + 1].y), (xs[k], edge[k].x, edge[k].y)]
        ws.quad(bm, q, 0, (0.0, n.x, n.y))
    return ws.make_object("iris_dust", bm, ["ir_dust"], origin=(0.0, 0.0, GROUND_Z), parent=body)


def build_iris(port, module) -> tuple:
    """Everything tilted onto the terrain under one root. Returns (root, antenna parts)."""
    tilt = tilt_matrix()
    body = build_body()
    build_service_panel(body)
    antenna = build_mast(body)
    build_dust(body)
    root = bpy.data.objects.new("iris", None)
    bpy.context.scene.collection.objects.link(root)
    for o in (body, port, module):
        o.matrix_world = tilt @ o.matrix_world
        bpy.context.view_layer.update()
        kit.parent_keep_transform(o, root)
    pose_antenna(antenna, ANTENNA_PARKED)
    return root, antenna


def ground_gaps() -> dict:
    """The footpads' bottoms below the ground and tops above it, the body's bottom above it (m,
    smallest each)."""
    tilt = tilt_matrix()
    out = {"pad buried": 1e9, "pad top above": 1e9, "body bottom above": 1e9}
    for lx, ly in LEGS:
        g = leg_ground(lx, ly)
        for a in range(0, 360, 45):
            x = lx + PAD_RADIUS * math.cos(math.radians(a))
            y = ly + PAD_RADIUS * math.sin(math.radians(a))
            bottom = tilt @ Vector((x, y, g - PAD_SINK))
            top = tilt @ Vector((x, y, g + PAD_HEIGHT - PAD_SINK))
            out["pad buried"] = min(out["pad buried"], ground_local(bottom.x, bottom.y) - bottom.z)
            out["pad top above"] = min(out["pad top above"], top.z - ground_local(top.x, top.y))
    for x, y in itertools.product((BODY_X[0], 0.0, BODY_X[1]), (BODY_Y[0], 0.0, BODY_Y[1])):
        p = tilt @ Vector((x, y, hg(BODY_BOTTOM)))
        out["body bottom above"] = min(out["body bottom above"], p.z - ground_local(p.x, p.y))
    return out


# --- Delivery checks ---------------------------------------------------------------------------

def port_in_iris(root) -> tuple:
    """The port's top centre and its axes (x, z) in the IRIS frame, after the tilt."""
    sock = next(o for o in root.children_recursive if o.name == "socket_cartridge")
    port = sock.parent
    return sock.matrix_world.translation.copy(), port.matrix_world.to_3x3() @ Vector((1, 0, 0)), port.matrix_world.to_3x3() @ Vector((0, 0, 1))


def rescuer_pose(port_iris: Vector, d: float, bearing_deg: float, heading_offset_deg: float,
                 face_deg: float = 90.0) -> Matrix:
    """Where IRIS goes in the rescuer's frame (the rescuer at the origin, facing +Y) so that the
    port is d from the rescuer's yaw axis at the bearing. The rescuer faces IRIS's face whose
    outward normal is face_deg from +X (90: the front) head on, turned by heading_offset."""
    b = math.radians(bearing_deg)
    target = Vector((YAW_AXIS.x - d * math.sin(b), YAW_AXIS.y + d * math.cos(b)))   # bearing + = left (-X)
    yaw = math.radians(-90.0 - face_deg + heading_offset_deg)
    rot = Matrix.Rotation(yaw, 4, "Z")
    p = rot @ Vector((port_iris.x, port_iris.y, 0.0))
    flat = Matrix.Translation((target.x - p.x, target.y - p.y, GROUND_Z)) @ rot
    # IRIS's ground under its origin vs the rescuer's: the terrain at the parking spot
    spot = flat.inverted() @ Vector((0.0, 0.0, 0.0))
    dz = H0 - terrain(*iris_to_world((spot.x, spot.y)))
    return Matrix.Translation((0.0, 0.0, dz)) @ flat


def ik_down(point: Vector) -> dict:
    """Joints putting the rescuer's turret hub end on `point` (rover frame), pointing down."""
    yaw_axis = Vector((-0.12, 0.53))
    rel = Vector((point.x, point.y)) - yaw_axis
    dist = rel.length
    off = -0.005
    r_local = math.sqrt(max(dist * dist - off * off, 0.0))
    j1 = math.degrees(math.atan2(-rel.x, rel.y) - math.atan2(-off, r_local))
    S = Vector((0.53, 0.345))
    L = Vector((0.53 + r_local, point.z))
    W = Vector((L.x, L.y + 0.12))
    v = W - S
    d = v.length
    a, bl = 0.36, 0.33
    c3 = (d * d - a * a - bl * bl) / (2 * a * bl)
    if abs(c3) > 1.0:
        return None
    for sgn in (1.0, -1.0):
        t3 = sgn * math.acos(c3)
        t2 = math.atan2(v.y, v.x) - math.atan2(bl * math.sin(t3), a + bl * math.cos(t3))
        j2, j3 = math.degrees(t2), math.degrees(t3)
        j4 = ((-90.0 - (j2 + j3)) + 180.0) % 360.0 - 180.0
        if -30 <= j2 <= 90 and -90 <= j3 <= 90 and -110 <= j4 <= 110 and -20 <= j1 <= 15:
            return {"J1": j1, "J2": j2, "J3": j3, "J4": j4, "J5": 0.0}
    return None


def run_delivery_checks(rows: list, previews) -> int:
    failures = 0
    scene = pam.assemble()                        # the rescuer
    arm = scene["arm"]
    mount = arm_kit.load("cargo_mount.blend", "cargo_mount")
    mount.location = (-0.125, 0.20, 0.44)
    cart = arm_kit.load("cartridge.blend", "cartridge")
    cart.location = (-0.125, 0.20, 0.505)
    iris_root = kit.append_objects(os.path.join(PARTS_DIR, "iris.blend"), ["iris"])[0]
    bpy.context.view_layer.update()
    port_top, port_x, port_z = port_in_iris(iris_root)
    iris_meshes = [o for o in iris_root.children_recursive if o.type == "MESH" and "convcolonly" not in o.name]
    port_obj = next(o for o in iris_meshes if o.name.startswith("iris_port"))
    iris_other = [o for o in iris_meshes if o is not port_obj and not o.name.startswith("iris_status")]
    moving = [arm[k] for k in ("yaw", "upper", "forearm", "wrist", "tool")]
    rover_parts = [o for o in [scene["chassis"], *scene["chassis"].children_recursive]
                   if o.type == "MESH" and "convcolonly" not in o.name and o not in moving and o is not cart]
    wheels = [o for side in scene["sides"].values() for k, o in side.items() if k.endswith("wheel")]
    arm_kit.pose_arm(arm, arm_kit.LATCH)
    tool = arm["tool"]
    rel = tool.matrix_world.inverted() @ cart.matrix_world
    worst = {}
    gate = {"window": 0}

    def note(key, value, where):
        if key not in worst or value < worst[key][0]:
            worst[key] = (value, where)

    for d, bearing, turn in itertools.product((WINDOW_D[0], sum(WINDOW_D) / 2, WINDOW_D[1]),
                                              (WINDOW_BEARING[0], 0.0, WINDOW_BEARING[1]), (-10.0, 0.0, 10.0)):
        place = rescuer_pose(port_top, d, bearing, turn)
        iris_root.matrix_world = place
        bpy.context.view_layer.update()
        where = "d %.2f, bearing %+.0f, heading %+.0f" % (d, bearing, turn)
        top = place @ port_top
        approach = ik_down(top + Vector((0, 0, STROKE)))
        seated = ik_down(top + Vector((0, 0, SEAT_GAP)))
        if approach is None or seated is None:
            note("port in reach (0 = out of reach)", 0.0, where)
            failures += 1
            continue
        gate["window"] += 1
        # J5: turn the held cartridge's long side to the port's
        px = (place.to_3x3() @ port_x)
        best5 = (1e9, 0.0)
        for j5 in range(-90, 91, 1):
            arm_kit.pose_arm(arm, dict(approach, J5=float(j5)))
            cx = (tool.matrix_world @ rel).to_3x3() @ Vector((1, 0, 0))
            err = abs(math.degrees(math.atan2(cx.x * px.y - cx.y * px.x, cx.x * px.x + cx.y * px.y)))
            err = min(err, 180.0 - err)
            if err < best5[0]:
                best5 = (err, float(j5))
        note("cartridge heading error at the port (deg, smaller is better; >= -2 means ok)", -best5[0], where)
        approach["J5"] = seated["J5"] = best5[1]
        # The path: latch, lift, transit to the approach (J5 0), turn J5, stroke down
        keys = [arm_kit.LATCH, LIFT, dict(approach, J5=0.0), approach]
        samples = []
        for a, b in zip(keys, keys[1:]):
            span = max(abs(b[j] - a[j]) for j in a)
            n = max(2, int(span / 2.0))
            samples += [{j: a[j] + (b[j] - a[j]) * k / n for j in a} for k in range(n + 1)]
        stroke = []
        for k in range(6):
            p = ik_down(top + Vector((0, 0, SEAT_GAP + (STROKE - SEAT_GAP) * (1 - k / 5.0))))
            if p is None:
                note("stroke in reach", 0.0, where)
                failures += 1
                break
            p["J5"] = best5[1]
            stroke.append(p)
        for i, joints in enumerate(samples + stroke):
            arm_kit.pose_arm(arm, joints)
            cart.matrix_world = tool.matrix_world @ rel
            bpy.context.view_layer.update()
            in_stroke = i >= len(samples)
            arm_tree = arm_kit.world_bvh(moving)
            cart_tree = arm_kit.world_bvh([cart])
            note("arm vs IRIS", arm_kit.gap(arm_tree, arm_kit.world_bvh(iris_other + [port_obj])), where)
            note("cartridge vs IRIS (not the port)", arm_kit.gap(cart_tree, arm_kit.world_bvh(iris_other)), where)
            if not in_stroke:
                note("cartridge vs port before the stroke", arm_kit.gap(cart_tree, arm_kit.world_bvh([port_obj])), where)
                note("cartridge vs the rescuer (not the mount, after leaving it)",
                     arm_kit.gap(cart_tree, arm_kit.world_bvh(rover_parts)) if i > 3 else 1.0, where)
            else:
                g = arm_kit.gap(cart_tree, arm_kit.world_bvh([port_obj]))
                if i - len(samples) < len(stroke) - 1:
                    note("cartridge vs port during the stroke (lead-in fit)", g, where)
                else:
                    # The release, just over the port's floor (the seat): only no penetration
                    note("cartridge over the port's floor at the release (none in it)", g + 0.003, where)
                if "--debug" in kit.script_args():
                    pt = arm_kit.world_bvh([port_obj])
                    bestp = min(((pt[0].find_nearest(v)[3], v, pt[0].find_nearest(v)[0]) for v in cart_tree[1]), key=lambda t: t[0])
                    if bestp[0] < 0.003:
                        inv = port_obj.matrix_world.inverted()
                        print("DEBUG %s step %d: %.1f mm, cartridge point %s, port point %s (port local)" % (
                            where, i - len(samples), bestp[0] * 1000, tuple(round(c, 4) for c in inv @ bestp[1]), tuple(round(c, 4) for c in inv @ bestp[2])))
            note("cartridge above the ground", min(v.z for v in kit.world_vertices(cart)) - GROUND_Z, where)
            note("arm above the ground", min(min(v.z for v in kit.world_vertices(o)) for o in moving) - GROUND_Z, where)
        # The rescuer's wheels and body against IRIS
        note("rescuer wheels and body vs IRIS (footprint, needs 150 mm)",
             arm_kit.gap(arm_kit.world_bvh(wheels + [scene["chassis"]]), arm_kit.world_bvh(iris_meshes)), where)
        if previews and d == sum(WINDOW_D) / 2 and bearing == 0.0 and turn == 0.0:
            kit.set_preview_colors(True)
            ws.set_preview_colors(True)
            keep = tuple(iris_meshes) + (cart, mount)
            for name, joints in (("approach", approach), ("seated", stroke[-1])):
                arm_kit.pose_arm(arm, joints)
                cart.matrix_world = tool.matrix_world @ rel
                bpy.context.view_layer.update()
                kit.render_view(scene["chassis"], os.path.join(previews, "delivery_%s_side.png" % name), (1.0, 0.0, 0.15), 2.6,
                                focus=(0.0, 0.9, 0.4), keep_visible=keep)
                kit.render_view(scene["chassis"], os.path.join(previews, "delivery_%s_three_quarter.png" % name),
                                (0.9, -0.6, 0.6), 3.0, True, 6.0, (0.0, 0.9, 0.35), keep_visible=keep)
            kit.set_preview_colors(False)
            ws.set_preview_colors(False)
    arm_kit.pose_arm(arm, arm_kit.STOWED)
    rows.append("parking window corners in reach: %d of 27" % gate["window"])
    for key, (value, where) in sorted(worst.items()):
        if key.startswith("cartridge heading"):
            ok = value >= -2.0
            rows.append("%-74s %5.1f deg at %s%s" % (key, -value, where, "" if ok else "  FAIL"))
        else:
            need = 0.150 if "footprint" in key else 0.100 if key == "cartridge above the ground" else 0.003 if ("stroke" in key or "release" in key) else MIN_GAP
            ok = value >= need - 1e-4
            rows.append("%-74s %6.1f mm (needs %.0f) at %s%s" % (key, value * 1000.0, need * 1000.0, where, "" if ok else "  FAIL"))
        failures += 0 if ok else 1
    return failures


def antenna_checks(root, antenna: dict, rows: list) -> int:
    """The dish keeps 20 mm from the rest of IRIS (and its own pan head) over the whole swing from
    parked to tracked."""
    dish_obj = next(o for o in root.children_recursive if o.name == "iris_antenna_dish")
    moving = {antenna["pan"], antenna["tilt"], dish_obj}
    others = [o for o in root.children_recursive if o.type == "MESH" and "convcolonly" not in o.name and o not in moving]
    worst = 1e9
    for k in range(21):
        t = k / 20.0
        pose_antenna(antenna, tuple(a + (b - a) * t for a, b in zip(ANTENNA_PARKED, ANTENNA_TRACKED)))
        worst = min(worst, arm_kit.gap(arm_kit.world_bvh([dish_obj]), arm_kit.world_bvh(others + [antenna["pan"]])))
    pose_antenna(antenna, ANTENNA_PARKED)
    ok = worst >= MIN_GAP
    rows.append("antenna dish vs IRIS over the swing parked %s to tracked %s: %.1f mm (needs 20)%s" % (
        ANTENNA_PARKED, ANTENNA_TRACKED, worst * 1000.0, "" if ok else "  FAIL"))
    return 0 if ok else 1


def module_checks(rows: list) -> int:
    """The module socket from its own parking window (the cartridge's, moved sideways): the arm
    reaches its top pointing down at every corner, and the rescuer's footprint keeps 150 mm."""
    failures = 0
    scene = pam.assemble()                        # resets the scene: IRIS comes back from its .blend
    root = kit.append_objects(os.path.join(PARTS_DIR, "iris.blend"), ["iris"])[0]
    bpy.context.view_layer.update()
    sock = next(o for o in root.children_recursive if o.name == "socket_module")
    top = sock.matrix_world.translation.copy()
    wheels = [o for side in scene["sides"].values() for k, o in side.items() if k.endswith("wheel")]
    iris_meshes = [o for o in root.children_recursive if o.type == "MESH" and "convcolonly" not in o.name]
    reach, foot = 0, 1e9
    for d, bearing, turn in itertools.product((WINDOW_D[0], sum(WINDOW_D) / 2, WINDOW_D[1]),
                                              (WINDOW_BEARING[0], 0.0, WINDOW_BEARING[1]), (-10.0, 0.0, 10.0)):
        place = rescuer_pose(top, d, bearing, turn, MODULE_FACE_DEG)
        root.matrix_world = place
        bpy.context.view_layer.update()
        t = place @ top
        if ik_down(t + Vector((0, 0, STROKE))) and ik_down(t + Vector((0, 0, SEAT_GAP))):
            reach += 1
        foot = min(foot, arm_kit.gap(arm_kit.world_bvh(wheels + [scene["chassis"]]), arm_kit.world_bvh(iris_meshes)))
    rows.append("module socket's top in the rover's frame at its window's middle: z %.3f (the port's at its own: 0.46)" % (
        (rescuer_pose(top, sum(WINDOW_D) / 2.0, 0.0, 0.0, MODULE_FACE_DEG) @ top).z))
    ok = reach == 27
    failures += 0 if ok else 1
    rows.append("module socket: window corners in reach %d of 27%s" % (reach, "" if ok else "  FAIL"))
    ok = foot >= 0.150 - 1e-4
    failures += 0 if ok else 1
    rows.append("module socket: rescuer wheels and body vs IRIS %.1f mm (needs 150)%s" % (foot * 1000.0, "" if ok else "  FAIL"))
    return failures


def add_parking(root) -> None:
    """park_cartridge / park_module: where Kite's origin stops (on the ground) for the middle of each
    window, facing IRIS's -Y (the port) or +X (the module socket)."""
    for name, marker, face in (("park_cartridge", "socket_cartridge", 90.0), ("park_module", "socket_module", MODULE_FACE_DEG)):
        top = next(o for o in root.children_recursive if o.name == marker).matrix_world.translation.copy()
        place = rescuer_pose(top, sum(WINDOW_D) / 2.0, 0.0, 0.0, face)
        p = place.inverted() @ Vector((0.0, 0.0, GROUND_Z))
        ws.add_empty(root, name, (p.x, p.y, p.z))


# --- Main --------------------------------------------------------------------------------------

def main() -> None:
    previews = kit.preview_dir("iris")
    rows = []
    failures = 0
    port = build_port()
    module = build_module_socket()
    root, antenna = build_iris(port, module)
    bpy.context.view_layer.update()
    add_parking(root)
    g = ground_gaps()
    ok = g["pad buried"] >= 0.005 and g["pad top above"] >= 0.0 and g["body bottom above"] >= 0.15
    failures += 0 if ok else 1
    rows.append("on the terrain: footpads %.0f mm in the ground at least, their tops %.0f mm above it; body bottom %.0f mm above it%s" % (
        g["pad buried"] * 1000.0, g["pad top above"] * 1000.0, g["body bottom above"] * 1000.0, "" if ok else "  FAIL"))
    tris = sum(kit.triangle_count(o) for o in root.children_recursive if o.type == "MESH" and "convcolonly" not in o.name)
    ok = tris <= BUDGET
    failures += 0 if ok else 1
    rows.append("IRIS: %d triangles (budget %d)%s" % (tris, BUDGET, "" if ok else "  FAIL"))
    lo, hi = ws.bounds([o for o in root.children_recursive if o.type == "MESH" and "convcolonly" not in o.name and o.name != "iris_dust"])
    rows.append("size: %.2f x %.2f m, %.2f m tall (antenna parked); body %.2f x %.2f x %.2f" % (
        hi.x - lo.x, hi.y - lo.y, hi.z - lo.z, BODY_X[1] - BODY_X[0], BODY_Y[1] - BODY_Y[0], BODY_TOP))
    top, _, _ = port_in_iris(root)
    rows.append("port's top centre in the IRIS frame (tilted): (%.3f, %.3f, %.3f), %.3f m above the ground under it" % (
        top.x, top.y, top.z, top.z - ground_local(top.x, top.y)))
    failures += antenna_checks(root, antenna, rows)
    for o in [root] + list(root.children_recursive):
        kit.check_export_name(o.name)
    os.makedirs(PARTS_DIR, exist_ok=True)
    kit.save_blend(os.path.join(PARTS_DIR, "iris.blend"))
    ws.rk.GODOT_IMPORT_SCRIPT = ws.GODOT_IMPORT_SCRIPT
    kit.export_part(root, os.path.join(EXPORT_DIR, "iris.glb"))
    gx, gz = IRIS_XZ
    rows.append("Godot: IRIS root at (%.2f, %.3f, %.2f), rotation y %.1f deg" % (gx, H0, gz, IRIS_YAW_DEG))
    if previews:
        kit.set_preview_colors(True)
        ws.set_preview_colors(True)
        for state, pose in (("parked", ANTENNA_PARKED), ("tracked", ANTENNA_TRACKED)):
            pose_antenna(antenna, pose)
            kit.render_view(root, os.path.join(previews, "iris_approach_%s.png" % state), (-0.5, 1.0, 0.45), 3.8, True,
                            11.0, (0.0, -0.2, 1.5))
        pose_antenna(antenna, ANTENNA_PARKED)
        for name, d in (("side", (1.0, 0.0, 0.0)), ("front", (0.0, 1.0, 0.0)), ("left", (-1.0, 0.0, 0.0)),
                        ("rear", (0.0, -1.0, 0.0)), ("top", (0.0, 0.0, 1.0))):
            kit.render_view(root, os.path.join(previews, "iris_%s.png" % name), d, 3.6, False, 1.0, (0.0, -0.2, 1.5))
        kit.render_view(root, os.path.join(previews, "iris_rear_left.png"), (-0.8, -1.0, 0.5), 3.8, True, 11.0, (0.0, -0.2, 1.4))
        kit.render_view(root, os.path.join(previews, "iris_service_panel.png"), (0.15, 1.0, 0.1), 1.2, True, 3.5, (-0.55, 0.5, 0.65))
        kit.render_view(root, os.path.join(previews, "iris_ports_close.png"), (0.9, 0.7, 0.35), 1.8, True, 4.5, (0.35, 0.70, 0.40))
        kit.set_preview_colors(False)
        ws.set_preview_colors(False)
    failures += module_checks(rows)
    failures += run_delivery_checks(rows, previews)
    rows.append("ALL CHECKS OK" if failures == 0 else "%d CHECK FAILURES" % failures)
    print("\n".join("IRIS_KIT iris " + r for r in rows))


if __name__ == "__main__":
    main()
