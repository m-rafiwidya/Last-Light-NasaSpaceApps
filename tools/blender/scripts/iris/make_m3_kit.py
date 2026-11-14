"""Generates the M3 assets: Evan's far logger (A16), the thermal kit's cover and heater (A17), the arm tool
turret with the surface-temperature sensor (A14) and the far sample site on Head crater's east rim
(A15 far), checks them and renders previews.

    blender -b --factory-startup -P tools/blender/scripts/iris/make_m3_kit.py [-- --previews DIR | --no-previews]

Writes (blend in tools/blender/parts/, glb in game/res/models/<kit>/):
    rover_kit/field_logger.glb       the far logger: cargo on Kite's mount, like the cartridge
    rover_kit/thermal_cover.glb      the thermal kit's cover, on the deck's right rear
    rover_kit/thermal_heater.glb     the thermal kit's heater, on the deck in front of the cover
    rover_kit/arm_tool_thermal.glb   the arm tool turret with an IR radiometer in the sensor's place
    iris_kit/sample_site_far.glb     the far reference patch, in its own frame (see FAR_SITE)
Previews in tools/blender/previews/m3_kit/. Needs the rover kit's .blend files (with cargo_mount,
module_cradle and radio_module) and game/res/terrain/moon_apollo12/ (play.f32, rocks.f32, terrain.json).
Run it before make_sample_kit.py (whose bench preview shows the thermal kit on its low shelf).

Rover frame (ROVER_KIT.md 2; ground at z -0.10, front +Y). No mission logic: meshes, markers and checks.
    field_logger      0.21 x 0.12 x 0.07 m case (0.222 m with its end bumpers), origin the middle of its
                      bottom (its feet) at socket_cargo_item (-0.125, 0.20, 0.505), long side along X.
                      A short antenna stub at the +X end, a gold latch disc on the top's centre.
        anchor_latch  (0, 0, 0.07)   anchor_pickup (0, 0, 0.035)
        text_top      the top label plate's centre (Evan's first label; Godot: Label3D facing up)
        text_under    the underside label plate's centre (the second one, facing down)
    thermal_cover     an MLI blanket 0.175 x 0.40 m, 22 mm thick, quilted, origin the middle of its
                      bottom on the deck at COVER_AT (0.1225, -0.02, 0.44), mounted at COVER_SOCKET
                      (0.1225, -0.045, 0.44): over the electronics bay
                      between the mast, the low-gain antenna and the antenna, clear of the arm and mount
    thermal_heater    a 0.11 x 0.05 x 0.035 m finned heater, origin the middle of its bottom at
                      HEATER_AT (0.12, 0.225, 0.44), mounted at HEATER_SOCKET (0.10, -0.375, 0.44) turned
                      180 degrees about Z; its lead runs towards the cover (originally under its front edge)
    arm_tool_thermal  arm_tool (make_arm.py) with an IR radiometer in the plain sensor's place (198
                      degrees), inside the standard turret's envelope. J5 -72 points it down.
        pivot_reading      the aperture's centre: the reading is taken along the radiometer's axis
        pivot_reading_aim  0.10 m further out along that axis (the axis = aim - reading)
Far site (FAR_SITE): the frame's origin is on the ground at the patch's centre; its +Y (Kite's heading
when it parks to sample) points down the slope at the shade, its +Z up. The script prints the Godot
transforms for moon_level.tscn: SampleSiteFar, FarRimMarker (a ws_marker_post at anchor_marker_post,
the lit side of the shade boundary) and FarLogger (the logger resting on the ground at anchor_logger).
Budgets: logger 300, cover 250, heater 150, turret 240 (ROVER_KIT.md 6.2), site 300 triangles.
"""

import itertools
import json
import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

HERE = os.path.dirname(__file__)
sys.path.append(os.path.join(HERE, ".."))
sys.path.append(os.path.join(HERE, "..", "workshop"))
sys.path.append(HERE)
import rover_kit_common as kit  # noqa: E402
import make_arm as arm_kit  # noqa: E402
import make_mast as mast  # noqa: E402
import make_power_antenna_motor as pam  # noqa: E402
import make_cargo_mount as cm  # noqa: E402
import make_module as mm  # noqa: E402
import make_iris as iris_kit  # noqa: E402
import make_sample_kit as sk  # noqa: E402
import workshop_kit_common as ws  # noqa: E402

SOCKET, ITEM = cm.SOCKET, cm.ITEM
MIN_GAP = 0.020
BODY, DARK, METAL, GOLD = 0, 1, 2, 3
ROVER_MATS = ("rover_body", "rover_dark", "rover_metal", "rover_gold")
BUDGET = {"field_logger": 300, "thermal_cover": 250, "thermal_heater": 150, "arm_tool_thermal": 240, "site": 300}
# Masses (kg) and power (W) for the part scenes: estimates, see ASSET_PLAN.md A14, A16, A17
MASS = {"field_logger": 1.6, "thermal_cover": 0.9, "thermal_heater": 0.6, "arm_tool_thermal": 5.3}
POWER = {"thermal_heater": 12.0, "radiometer": 1.0}

# Logger (rover frame, from its origin at ITEM)
LOG_HX, LOG_HY, LOG_H = 0.105, 0.06, 0.07
LOG_CHAMFER = 0.010
LOG_FOOT = 0.003
BUMPER = 0.006
STUB_XY, STUB_R, STUB_TOP = (0.082, 0.032), 0.006, 0.098
TOP_LABEL = ((-0.097, -0.024), (-0.050, 0.050))          # x range, y range
UNDER_LABEL = ((-0.085, 0.085), (-0.046, 0.046))
LATCH_R = 0.018

# Thermal kit (rover frame)
DECK_Z = 0.44
DECK_HALF = (0.22, 0.42)            # the deck's flat top inside the 30 mm chamfer
LGA = (0.15, -0.30, 0.025)          # the low-gain antenna's post and disc radius (make_chassis.py)
COVER_X, COVER_Y, COVER_H = (0.035, 0.21), (-0.22, 0.18), 0.022
COVER_AT = Vector(((COVER_X[0] + COVER_X[1]) / 2.0, (COVER_Y[0] + COVER_Y[1]) / 2.0, DECK_Z))
QUILT = (3, 5)
HEATER_X, HEATER_Y, HEATER_H = (0.065, 0.175), (0.20, 0.25), 0.035
HEATER_AT = Vector(((HEATER_X[0] + HEATER_X[1]) / 2.0, (HEATER_Y[0] + HEATER_Y[1]) / 2.0, DECK_Z))
# Where robot.tscn's ThermalCoverSocket and HeaterSocket put the parts (the meshes are authored at COVER_AT / HEATER_AT
# around their origins): the sockets sit where a held part reaches them, the heater turned 180 degrees about Z
COVER_SOCKET = Vector((0.1225, -0.045, DECK_Z))
HEATER_SOCKET, HEATER_TURN = Vector((0.10, -0.375, DECK_Z)), math.pi

# Radiometer (in arm_kit.radial()'s frame: w out from the hub axis)
RADIO_BODY, RADIO_HOOD, RADIO_LENS = (0.016, 0.025, 0.066), (0.020, 0.066, 0.080), 0.011
APERTURE_W = 0.0805
READ_HEIGHT = 0.15                  # the aperture above the ground while reading (at 0.10 the patch is 12 mm out of reach)

# Far site. World (Godot x, z) of the patch's centre: Head crater's east rim, on the upper inner wall
# just above the shade the rim casts; found with the shade / slope / rock search in ASSET_PLAN.md A15
FAR_SITE = (2.0, -58.0)
LOGGER_OFFSET = (1.3, 0.0)          # the logger beside the patch, in the site frame (to Kite's right)
BASE_XZ = (-300.0, 252.0)
TERRAIN_JSON = os.path.join(kit.REPO_ROOT, "game", "res", "terrain", "moon_apollo12", "terrain.json")
ROCKS = os.path.join(kit.REPO_ROOT, "game", "res", "terrain", "moon_apollo12", "rocks.f32")


def materials():
    return [kit.get_material(m) for m in ROVER_MATS]


def decal(bm, corners: list, mat: int, normal) -> None:
    ws.quad(bm, corners, mat, Vector(normal))


# --- Field logger (A16) ----------------------------------------------------------------------

def make_logger():
    bm = bmesh.new()
    place = lambda z0: (lambda u, v, w: (ITEM.x + u, ITEM.y + v, ITEM.z + z0 + w))
    case = kit.prism(bm, mm.outline(LOG_HX, LOG_HY, LOG_CHAMFER), place(LOG_FOOT), 0.0, LOG_H - LOG_FOOT)
    for f in case:
        f.material_index = METAL
    bmesh.ops.recalc_face_normals(bm, faces=case)
    # Dark rubber bumpers on the ends (the grips) and four feet
    for sign in (-1.0, 1.0):
        xs = tuple(sorted((ITEM.x + sign * (LOG_HX - 0.014), ITEM.x + sign * (LOG_HX + BUMPER))))
        kit.box(bm, xs, (ITEM.y - LOG_HY + 0.012, ITEM.y + LOG_HY - 0.012), (ITEM.z + LOG_FOOT + 0.006, ITEM.z + LOG_H - 0.006), DARK)
        for sy in (-1.0, 1.0):
            x, y = ITEM.x + sign * (LOG_HX - 0.025), ITEM.y + sy * (LOG_HY - 0.02)
            kit.box(bm, (x - 0.01, x + 0.01), (y - 0.01, y + 0.01), (ITEM.z, ITEM.z + LOG_FOOT + 0.001), DARK)
    top = ITEM.z + LOG_H + 0.0005
    (x0, x1), (y0, y1) = TOP_LABEL
    decal(bm, [(ITEM.x + x0, ITEM.y + y0, top), (ITEM.x + x1, ITEM.y + y0, top), (ITEM.x + x1, ITEM.y + y1, top),
               (ITEM.x + x0, ITEM.y + y1, top)], BODY, (0, 0, 1))
    disc = [bm.verts.new((ITEM.x + LATCH_R * math.cos(a), ITEM.y + LATCH_R * math.sin(a), top))
            for a in [2 * math.pi * k / 8 for k in range(8)]]
    f = bm.faces.new(disc)
    f.material_index = GOLD
    under = ITEM.z + LOG_FOOT - 0.0005
    (x0, x1), (y0, y1) = UNDER_LABEL
    decal(bm, [(ITEM.x + x0, ITEM.y + y0, under), (ITEM.x + x1, ITEM.y + y0, under), (ITEM.x + x1, ITEM.y + y1, under),
               (ITEM.x + x0, ITEM.y + y1, under)], BODY, (0, 0, -1))
    # A data port on the -Y side
    side = ITEM.y - LOG_HY - 0.0005
    decal(bm, [(ITEM.x - 0.02, side, ITEM.z + 0.025), (ITEM.x + 0.02, side, ITEM.z + 0.025), (ITEM.x + 0.02, side, ITEM.z + 0.045),
               (ITEM.x - 0.02, side, ITEM.z + 0.045)], DARK, (0, -1, 0))
    # Antenna stub: a metal collar and a dark whip
    sx, sy = ITEM.x + STUB_XY[0], ITEM.y + STUB_XY[1]
    for faces, mat in ((kit.cylinder(bm, lambda u, v, w: (sx + u, sy + v, w), ITEM.z + LOG_H, ITEM.z + LOG_H + 0.008, 0.010, 6), METAL),
                       (kit.cylinder(bm, lambda u, v, w: (sx + u, sy + v, w), ITEM.z + LOG_H + 0.008, ITEM.z + STUB_TOP, STUB_R, 6), DARK)):
        for f in faces:
            f.material_index = mat
    bm.normal_update()
    for face in bm.faces:
        if face.material_index == GOLD and face.normal.z < 0.0:
            face.normal_flip()
    obj = kit.mesh_object("field_logger", bm, materials())
    obj.data.transform(Matrix.Translation(-ITEM))
    obj.location = ITEM
    bpy.context.view_layer.update()
    col = bmesh.new()
    kit.box(col, (ITEM.x - LOG_HX - BUMPER, ITEM.x + LOG_HX + BUMPER), (ITEM.y - LOG_HY, ITEM.y + LOG_HY), (ITEM.z, ITEM.z + LOG_H))
    kit.make_collision_child(obj, col)
    collider = obj.children[0]
    collider.data.transform(Matrix.Translation(-ITEM))
    collider.location = (0.0, 0.0, 0.0)
    kit.add_socket(obj, "anchor_latch", ITEM + Vector((0.0, 0.0, LOG_H)))
    kit.add_socket(obj, "anchor_pickup", ITEM + Vector((0.0, 0.0, LOG_H / 2.0)))
    kit.add_socket(obj, "text_top", ITEM + Vector(((TOP_LABEL[0][0] + TOP_LABEL[0][1]) / 2.0, 0.0, LOG_H + 0.001)))
    kit.add_socket(obj, "text_under", ITEM + Vector((0.0, 0.0, LOG_FOOT - 0.001)))
    return obj


# --- Thermal kit (A17) -----------------------------------------------------------------------

def make_cover():
    bm = bmesh.new()
    (x0, x1), (y0, y1), z0 = COVER_X, COVER_Y, DECK_Z
    seam, crown = z0 + COVER_H - 0.006, z0 + COVER_H
    nx, ny = QUILT
    xs = [x0 + (x1 - x0) * i / nx for i in range(nx + 1)]
    ys = [y0 + (y1 - y0) * j / ny for j in range(ny + 1)]
    grid = [[bm.verts.new((x, y, seam)) for x in xs] for y in ys]
    # Quilted top: each cell pillows up to a crown in its middle (four triangles)
    for j in range(ny):
        for i in range(nx):
            c = bm.verts.new(((xs[i] + xs[i + 1]) / 2.0, (ys[j] + ys[j + 1]) / 2.0, crown))
            ring = (grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i])
            for k in range(4):
                bm.faces.new((ring[k], ring[(k + 1) % 4], c)).material_index = GOLD
    # Sides down to the deck along the grid's edge, and the bottom
    edge = [grid[0][i] for i in range(nx)] + [grid[j][nx] for j in range(ny)] + \
        [grid[ny][i] for i in range(nx, 0, -1)] + [grid[j][0] for j in range(ny, 0, -1)]
    low = [bm.verts.new((v.co.x, v.co.y, z0)) for v in edge]
    for k in range(len(edge)):
        n = (k + 1) % len(edge)
        bm.faces.new((edge[k], edge[n], low[n], low[k])).material_index = GOLD
    bm.faces.new(list(reversed(low))).material_index = GOLD
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    # A dark binding round the foot, four metal hold-down clips and the heater lead's socket at the front
    band = kit.prism(bm, [(x0 - 0.002, y0 - 0.002), (x1 + 0.002, y0 - 0.002), (x1 + 0.002, y1 + 0.002), (x0 - 0.002, y1 + 0.002)],
                     lambda u, v, w: (u, v, w), z0, z0 + 0.007, False, False)
    for f in band:
        f.material_index = DARK
    kit.orient(bm, band, kit.axis_outward(2, z0, z0 + 0.007, (COVER_AT.x, COVER_AT.y)))
    for x in (x0 + 0.03, x1 - 0.03):
        for y, sign in ((y0, -1.0), (y1, 1.0)):
            kit.box(bm, (x - 0.01, x + 0.01), tuple(sorted((y - sign * 0.012, y + sign * 0.006))), (z0, seam + 0.003), METAL)
    kit.box(bm, (HEATER_AT.x - 0.012, HEATER_AT.x + 0.012), (y1 - 0.004, y1 + 0.004), (z0, z0 + 0.012), DARK)
    obj = kit.mesh_object("thermal_cover", bm, materials())
    obj.data.transform(Matrix.Translation(-COVER_AT))
    obj.location = COVER_AT
    bpy.context.view_layer.update()
    col = bmesh.new()
    kit.box(col, (x0, x1), (y0, y1), (z0, crown))
    kit.make_collision_child(obj, col)
    obj.children[0].data.transform(Matrix.Translation(-COVER_AT))
    obj.children[0].location = (0.0, 0.0, 0.0)
    return obj


def make_heater():
    bm = bmesh.new()
    (x0, x1), (y0, y1), z0 = HEATER_X, HEATER_Y, DECK_Z
    kit.box(bm, (x0 - 0.008, x1 + 0.008), (y0 - 0.004, y1 + 0.004), (z0, z0 + 0.003), METAL)       # mounting flange
    kit.box(bm, (x0, x1), (y0, y1), (z0 + 0.003, z0 + HEATER_H - 0.012), DARK)                     # element block
    for k in range(5):                                                                                # cooling fins
        x = x0 + 0.008 + k * (x1 - x0 - 0.016) / 4.0
        kit.box(bm, (x - 0.003, x + 0.003), (y0 + 0.003, y1 - 0.003), (z0 + HEATER_H - 0.012, z0 + HEATER_H), METAL)
    decal(bm, [(HEATER_AT.x - 0.012, y1 + 0.0005, z0 + 0.008), (HEATER_AT.x + 0.012, y1 + 0.0005, z0 + 0.008),
               (HEATER_AT.x + 0.012, y1 + 0.0005, z0 + 0.018), (HEATER_AT.x - 0.012, y1 + 0.0005, z0 + 0.018)], GOLD, (0, 1, 0))
    # The lead back to the cover's socket (a flat cable on the deck)
    kit.box(bm, (HEATER_AT.x - 0.006, HEATER_AT.x + 0.006), (COVER_Y[1] + 0.004, y0), (z0, z0 + 0.008), DARK)
    obj = kit.mesh_object("thermal_heater", bm, materials())
    obj.data.transform(Matrix.Translation(-HEATER_AT))
    obj.location = HEATER_AT
    bpy.context.view_layer.update()
    col = bmesh.new()
    kit.box(col, (x0 - 0.008, x1 + 0.008), (y0 - 0.004, y1 + 0.004), (z0, z0 + HEATER_H))
    kit.make_collision_child(obj, col)
    obj.children[0].data.transform(Matrix.Translation(-HEATER_AT))
    obj.children[0].location = (0.0, 0.0, 0.0)
    return obj


# --- Surface-temperature sensor turret (A14) -------------------------------------------------

def radiometer(bm, place) -> None:
    """An IR radiometer: a metal body, a gold sun hood and the dark aperture (make_arm's material
    indices: 0 metal, 1 dark; 2 gold here)."""
    arm_kit.solid(bm, kit.circle_outline(RADIO_BODY[0], 8), place, RADIO_BODY[1], RADIO_BODY[2])
    arm_kit.solid(bm, kit.circle_outline(RADIO_HOOD[0], 8), place, RADIO_HOOD[1], RADIO_HOOD[2], 2)
    arm_kit.lens(bm, place, APERTURE_W, RADIO_LENS)


def make_thermal_tool():
    tool = kit.mesh_object("arm_tool_thermal", arm_kit.build_tool(radiometer),
                           [kit.get_material("rover_metal"), kit.get_material("rover_dark"), kit.get_material("rover_gold")])
    tool.location = arm_kit.TOOL
    kit.make_collision_child(tool, arm_kit.tool_collision())
    kit.add_socket(tool, "pivot_latch", arm_kit.TOOL + Vector((0.0, arm_kit.HUB_LENGTH, 0.0)))
    p = arm_kit.radial(arm_kit.TOOL_ANGLES["sensor"])
    kit.add_socket(tool, "pivot_reading", p(0.0, 0.0, APERTURE_W))
    kit.add_socket(tool, "pivot_reading_aim", p(0.0, 0.0, APERTURE_W + 0.10))
    return tool


def envelope(verts: list) -> tuple:
    """(largest distance from the hub axis, y range) of tool vertices in the rover frame."""
    axis = arm_kit.TOOL
    return (max(math.hypot(v.x - axis.x, v.z - axis.z) for v in verts), min(v.y for v in verts), max(v.y for v in verts))


# --- Terrain, sun, rocks ---------------------------------------------------------------------

with open(TERRAIN_JSON) as _f:
    _sun = json.load(_f)["sun"]
SUN_EL, SUN_AZ = math.radians(_sun["elevation"]), math.radians(_sun["azimuth"])
SUN_DX, SUN_DZ, SUN_T = math.sin(SUN_AZ), -math.cos(SUN_AZ), math.tan(SUN_EL)
_rocks = np.fromfile(ROCKS, dtype="<f4").reshape(-1, 6)       # x, ground_y, z, size, yaw, shape
terrain = iris_kit.terrain


def sun_clear(x: float, z: float, lift: float = 0.0) -> float:
    """How far (m) the ray toward the sun from `lift` above the ground at world (x, z) passes over the
    terrain at its closest; negative = in the terrain's shadow."""
    y = terrain(x, z) + lift
    worst = 1e9
    for s in np.arange(0.5, 400.0, 0.5):
        px, pz = x + s * SUN_DX, z + s * SUN_DZ
        if abs(px) > 510.0 or abs(pz) > 510.0:
            break
        worst = min(worst, y + s * SUN_T - terrain(px, pz))
    return worst


def rock_shadow(x: float, z: float, radius: float) -> float:
    """The biggest rock (size, m) whose shadow (its size tall, cast down-sun) reaches a disc at (x, z)."""
    worst = 0.0
    for rx, _, rz, size, _, _ in _rocks:
        dx, dz = rx - x, rz - z
        along = dx * SUN_DX + dz * SUN_DZ
        across = abs(-dx * SUN_DZ + dz * SUN_DX)
        if 0.0 < along <= size / SUN_T + radius and across <= size / 2.0 + radius:
            worst = max(worst, float(size))
    return worst


def rocks_near(x: float, z: float, radius: float, min_size: float = 0.0) -> int:
    d = np.hypot(_rocks[:, 0] - x, _rocks[:, 2] - z)
    return int(np.count_nonzero((d < radius + _rocks[:, 3] / 2.0) & (_rocks[:, 3] >= min_size)))


class SiteFrame:
    """The far site's frame: origin on the ground at world (x0, z0), +Y along the world direction
    `heading` (x, z), +Z up; Blender (x, y, z) here is Godot (x, z, -y) in the node's frame."""

    def __init__(self, x0: float, z0: float, heading: tuple):
        self.x0, self.z0 = x0, z0
        self.f = Vector((heading[0], heading[1])).normalized()
        self.r = Vector((-self.f.y, self.f.x))
        self.h0 = terrain(x0, z0)

    def world(self, x: float, y: float) -> tuple:
        return (self.x0 + x * self.r.x + y * self.f.x, self.z0 + x * self.r.y + y * self.f.y)

    def ground(self, x: float, y: float) -> float:
        return terrain(*self.world(x, y)) - self.h0

    def godot_basis(self) -> Matrix:
        """Columns: the node's X (right), Y (up), Z (back) in the world."""
        return Matrix(((self.r.x, 0.0, -self.f.x), (0.0, 1.0, 0.0), (self.r.y, 0.0, -self.f.y)))

    def godot(self, local: Matrix = None) -> str:
        """A Transform3D for moon_level.tscn: the frame, or a Blender-frame pose in it (4x4)."""
        b = self.godot_basis()
        t = Vector((self.x0, self.h0, self.z0))
        if local is not None:
            c = Matrix(((1, 0, 0), (0, 0, 1), (0, -1, 0)))             # Blender -> Godot axes
            rot = c @ local.to_3x3() @ c.inverted()
            p = local.translation
            t = t + b @ Vector((p.x, p.z, -p.y))
            b = b @ rot
        # A .tscn Transform3D lists the basis by rows (as the Iris node's yaw shows), then the origin
        return "Transform3D(%s, %s)" % (", ".join("%.6g" % v for i in range(3) for v in b[i]), ", ".join("%.6g" % v for v in t))


def downhill(x: float, z: float, radius: float = 2.6) -> tuple:
    """The fall line (world x, z), the slope (deg) and the worst distance (m) from the best-fit plane
    over a disc."""
    pts = [(x + r * math.cos(a), z + r * math.sin(a)) for r in (0.0, 0.55, 1.2, 2.0, radius)
           for a in np.linspace(0.0, 2.0 * math.pi, 16, endpoint=False)]
    a = np.array([[px, pz, 1.0] for px, pz in pts])
    b = np.array([terrain(px, pz) for px, pz in pts])
    sol = np.linalg.lstsq(a, b, rcond=None)[0]
    grad = Vector((sol[0], sol[1]))
    return tuple(-grad.normalized()), math.degrees(math.atan(grad.length)), float(np.abs(b - a @ sol).max())


def reach_window(hub_z: float, ahead_of_tip: float = 0.0) -> tuple:
    """Distances ahead of the turret's yaw axis where the hub end reaches `hub_z` pointing down (J1 0),
    for a point `ahead_of_tip` beyond the hub (the scoop's tip)."""
    ok = []
    for mm_ in range(150, 1100, 5):
        d = mm_ / 1000.0
        if iris_kit.ik_down(Vector((iris_kit.YAW_AXIS.x, iris_kit.YAW_AXIS.y + d - ahead_of_tip, hub_z))):
            ok.append(d)
    return (min(ok), max(ok)) if ok else (0.0, 0.0)


def plane_at(points: list, x: float, y: float) -> tuple:
    """Best-fit plane through (x, y, z) points: its height at (x, y), and its normal."""
    a = np.array([[p[0], p[1], 1.0] for p in points])
    sol = np.linalg.lstsq(a, np.array([p[2] for p in points]), rcond=None)[0]
    return float(sol[0] * x + sol[1] * y + sol[2]), Vector((-sol[0], -sol[1], 1.0)).normalized()


# --- Checks ----------------------------------------------------------------------------------

class Report:
    def __init__(self):
        self.rows, self.failures = [], 0

    def check(self, ok: bool, text: str) -> None:
        self.failures += 0 if ok else 1
        self.rows.append(text + ("" if ok else "  FAIL"))

    def gap(self, name: str, value: float, need: float = MIN_GAP) -> None:
        self.check(value >= need - 1e-4, "%-66s %6.1f mm" % (name, value * 1000.0))

    def note(self, text: str) -> None:
        self.rows.append(text)


def part_checks(obj, budget: int, r: Report) -> None:
    tris = kit.triangle_count(obj)
    r.check(tris <= budget, "%s: %d triangles (budget %d)" % (obj.name, tris, budget))
    names = {m.name for m in obj.data.materials}
    r.check(names <= set(kit.PALETTE), "%s materials %s" % (obj.name, sorted(names)))
    for child in obj.children:
        kit.check_export_name(child.name)
        if child.type == "EMPTY":
            r.check(all(abs(a) < 1e-6 for a in child.rotation_euler), "%s: %s at %s from the origin" % (
                obj.name, child.name, tuple(round(c, 4) for c in child.location)))


def arm_grid(arm: dict, obstacles: list) -> tuple:
    """The arm over make_module's joint grid (12,870 poses) against `obstacles`: (worst gap, joints)."""
    moving = [arm[k] for k in ("yaw", "upper", "forearm", "wrist", "tool")]
    grid = {"J1": (-20, -10, 0, 8, 15), "J2": tuple(range(-30, 91, 15)), "J3": tuple(range(-90, 91, 15)),
            "J4": tuple(range(-110, 111, 22)), "J5": (0, 36)}
    tree = arm_kit.world_bvh(obstacles)
    worst = (1e9, None)
    for values in itertools.product(*grid.values()):
        joints = dict(zip(grid.keys(), values))
        arm_kit.pose_arm(arm, joints)
        g = arm_kit.gap(arm_kit.world_bvh(moving), tree)
        if g < worst[0]:
            worst = (g, joints)
    arm_kit.pose_arm(arm, arm_kit.STOWED)
    return worst


def deck_checks(scene: dict, load: list, label: str, r: Report, exclude_antenna: bool = False) -> None:
    """`load` (on the deck) against the stowed arm, the mast and its head at any pan and tilt, the
    antenna over its range and the power unit."""
    arm = scene["arm"]
    moving = [arm[k] for k in ("yaw", "upper", "forearm", "wrist", "tool")]
    arm_kit.pose_arm(arm, arm_kit.STOWED)
    r.gap("%s vs stowed arm" % label, arm_kit.gap(arm_kit.world_bvh(moving), arm_kit.world_bvh(load)))
    mast_parts = [scene["mast_base"], scene["mast_head"], scene["mast_camera"]]
    worst = 1e9
    for pan, tilt in itertools.product(range(0, 360, 15), (-30, 0, 30)):
        pam.pose_mast_head(scene, pan, tilt)
        worst = min(worst, arm_kit.gap(arm_kit.world_bvh(mast_parts), arm_kit.world_bvh(load)))
    pam.pose_mast_head(scene, 0, 0)
    r.gap("%s vs mast and head (any pan, tilt +-30)" % label, worst)
    worst = 1e9
    for pan, tilt in itertools.product(range(0, 360, 15), (-90, -45, 0, 45, 90)):
        pam.pose_antenna(scene, pan, tilt)
        worst = min(worst, arm_kit.gap(arm_kit.world_bvh([scene["antenna"], scene["antenna_dish"]]), arm_kit.world_bvh(load)))
    pam.pose_antenna(scene, 0, 0)
    r.gap("%s vs antenna (any pan, tilt +-90)" % label, worst)
    r.gap("%s vs power unit" % label, arm_kit.gap(arm_kit.world_bvh([scene["power_unit"]]), arm_kit.world_bvh(load)))
    in_view, margin = mast.camera_view_check(scene["mast_camera"], load)
    r.check(in_view == 0, "%s in the mast camera's view (head at rest): %d samples (closest %.1f deg outside)" % (label, in_view, margin))


def logger_on_kite(scene: dict, mount, cradle, logger, r: Report) -> None:
    arm = scene["arm"]
    load = [mount, cradle, logger]
    deck_checks(scene, load, "mount + cradle + logger", r)
    r.gap("logger vs chassis (deck)", arm_kit.gap(arm_kit.world_bvh([scene["chassis"]]), arm_kit.world_bvh([logger])))
    top = logger.matrix_world.translation + Vector((0.0, 0.0, LOG_H))
    r.gap("logger top vs stowed turret hub end", (cm._latch_point(arm) - top).length)
    # Between the cradle's rails (inner faces at mm.RAIL_Y[0]) and the mount's corner lips (inner faces
    # 20 mm in from the plate's ends)
    lips = cm.PLATE[0] - 0.02 - (LOG_HX + BUMPER)
    r.check(mm.RAIL_Y[0] - LOG_HY >= 0.003 and lips >= 0.003,
            "logger in the cradle: %.0f mm to each rail, %.0f mm to the corner lips along X" % ((mm.RAIL_Y[0] - LOG_HY) * 1000.0, lips * 1000.0))
    best = (1e9, None)
    for j2, j3, j4 in itertools.product(range(70, 95, 2), range(60, 101, 2), range(70, 111, 2)):
        joints = {"J1": 0.0, "J2": float(j2), "J3": float(j3), "J4": float(j4), "J5": 0.0}
        arm_kit.pose_arm(arm, joints)
        miss = (cm._latch_point(arm) - top).length
        if miss < best[0]:
            best = (miss, joints)
    arm_kit.pose_arm(arm, arm_kit.STOWED)
    j = best[1]
    r.check(best[0] < 0.003, "logger latch pose (hub end on anchor_latch): J1 %.0f J2 %.0f J3 %.0f J4 %.0f J5 %.0f, %.1f mm off" % (
        j["J1"], j["J2"], j["J3"], j["J4"], j["J5"], best[0] * 1000.0))


def thermal_on_kite(scene: dict, mount, cradle, cover, heater, extras: dict, r: Report) -> None:
    kit_parts = [cover, heater]
    deck_checks(scene, kit_parts, "thermal kit", r)
    worst = arm_grid(scene["arm"], kit_parts)
    r.gap("arm over its joint grid (12,870 poses) vs the thermal kit", worst[0])
    r.note("    worst at %s" % worst[1])
    for name, cargo in extras.items():
        r.gap("thermal kit vs mount + cradle + %s" % name, arm_kit.gap(arm_kit.world_bvh([mount, cradle, cargo]), arm_kit.world_bvh(kit_parts)))
    # The low-gain antenna's disc and the deck's flat top
    lx, ly, lr = LGA
    c_lo, c_hi = ws.bounds([cover])
    dx = max(c_lo.x - lx, 0.0, lx - c_hi.x)
    dy = max(c_lo.y - ly, 0.0, ly - c_hi.y)
    r.gap("cover vs the low-gain antenna's disc", math.hypot(dx, dy) - lr)
    lo, hi = ws.bounds([cover, heater])
    inside = min(DECK_HALF[0] - max(abs(lo.x), abs(hi.x)), DECK_HALF[1] - max(abs(lo.y), abs(hi.y)))
    r.check(inside >= 0.005 and abs(lo.z - DECK_Z) < 1e-6, "thermal kit on the deck's flat top: %.0f mm inside its edge, bottom on the deck" % (inside * 1000.0))
    r.gap("heater vs cover (its lead points at the cover's rear edge)", arm_kit.gap(arm_kit.world_bvh([heater]), arm_kit.world_bvh([cover])), 0.0)


def reading_pose(scene: dict, thermal, r: Report, site_ahead: float) -> dict:
    """The radiometer pointing down at READ_HEIGHT over a point `site_ahead` in front of the yaw axis (the
    sample patch's centre from park_sample): its J5, then J1, J2, J3 with J4 = -(J2 + J3) (the hub axis level,
    as in REACH_DOWN)."""
    arm = scene["arm"]
    tool = arm["tool"]
    saved = tool.data
    tool.data = thermal.data
    reading = next(c for c in thermal.children if c.name == "pivot_reading").location.copy()
    aim = next(c for c in thermal.children if c.name == "pivot_reading_aim").location.copy()

    def ray(joints):
        arm_kit.pose_arm(arm, joints)
        m = tool.matrix_world
        return m @ reading, (m @ aim - m @ reading).normalized()

    j5 = min((-72.0, 72.0), key=lambda a: ray(dict(arm_kit.REACH_DOWN, J5=a))[1].z)
    target = Vector((iris_kit.YAW_AXIS.x, iris_kit.YAW_AXIS.y + site_ahead, iris_kit.GROUND_Z + READ_HEIGHT))
    best = (1e9, None)
    for step, span in ((3, None), (0.5, 4)):
        if span is None:
            j1s, j2s, j3s = (0.0,), np.arange(-30, 91, step), np.arange(-90, 91, step)
        else:
            j1s = np.arange(-2.0, 2.01, 0.25)
            j2s = np.arange(best[1]["J2"] - span, best[1]["J2"] + span + 0.01, step)
            j3s = np.arange(best[1]["J3"] - span, best[1]["J3"] + span + 0.01, step)
        for j1, j2, j3 in itertools.product(j1s, j2s, j3s):
            j4 = -(j2 + j3)
            if not (-30 <= j2 <= 90 and -90 <= j3 <= 90 and -110 <= j4 <= 110):
                continue
            joints = {"J1": float(j1), "J2": float(j2), "J3": float(j3), "J4": float(j4), "J5": j5}
            miss = (ray(joints)[0] - target).length
            if miss < best[0]:
                best = (miss, joints)
    point, axis = ray(best[1])
    lowest = min(v.z for o in (arm["upper"], arm["forearm"], arm["wrist"], tool) for v in kit.world_vertices(o))
    j = best[1]
    r.check(best[0] < 0.005 and axis.z < -0.998, "reading pose: J1 %.1f J2 %.1f J3 %.1f J4 %.1f J5 %.0f puts the aperture %.0f mm over the "
            "patch's centre (%.1f mm off), axis %.1f deg from straight down" % (
                j["J1"], j["J2"], j["J3"], j["J4"], j["J5"], READ_HEIGHT * 1000.0, best[0] * 1000.0, math.degrees(math.acos(min(1.0, -axis.z)))))
    r.gap("reading pose: the arm's lowest point above flat ground", lowest - iris_kit.GROUND_Z)
    tool.data = saved
    arm_kit.pose_arm(arm, arm_kit.STOWED)
    return best[1]


# --- Far site --------------------------------------------------------------------------------

def far_site(r: Report, previews) -> dict:
    fall, slope, residual = downhill(*FAR_SITE)
    heading = (round(math.degrees(math.atan2(fall[1], fall[0]))))
    frame = SiteFrame(FAR_SITE[0], FAR_SITE[1], (math.cos(math.radians(heading)), math.sin(math.radians(heading))))
    r.note("far site: centre at world (%.2f, %.3f, %.2f); Kite heads down the fall line, world bearing %d deg from +X" % (
        FAR_SITE[0], frame.h0, FAR_SITE[1], heading))
    r.check(slope <= 9.0 and residual <= 0.04, "far site: ground over a 5.2 m disc %.1f deg, %.0f mm from a plane at worst" % (slope, residual * 1000.0))
    # Kite parks up the slope from the patch, facing it: the scoop's tip reaches the patch's centre
    near, far = sk.site_reach()
    d_mid = (near + far) / 2.0
    park = Vector((-iris_kit.YAW_AXIS.x, -(iris_kit.YAW_AXIS.y + d_mid)))
    wheels = [(park.x + sx * 0.5, park.y + sy * 0.5, frame.ground(park.x + sx * 0.5, park.y + sy * 0.5))
              for sx in (-1, 1) for sy in (-1, 0, 1)]
    at_centre, normal = plane_at(wheels, 0.0, 0.0)
    pitch = math.degrees(math.atan2(normal.y, normal.z))
    roll = math.degrees(math.atan2(normal.x, normal.z))
    r.check(abs(at_centre - frame.ground(0.0, 0.0)) <= 0.02 and abs(roll) <= 2.0,
            "far site: the patch's centre %+.0f mm from Kite's wheel plane at park_sample (pitch %.1f, roll %.1f deg); "
            "the scoop's tip reaches %.2f-%.2f m ahead of the yaw axis" % (
                (frame.ground(0.0, 0.0) - at_centre) * 1000.0, pitch, roll, near, far))
    # Sun and shade: the patch and Kite lit, the shade boundary a few metres down the fall line
    patch = [(0.55 * math.cos(a), 0.55 * math.sin(a)) for a in np.linspace(0, 2 * math.pi, 12, endpoint=False)] + [(0.0, 0.0)]
    patch_clear = min(sun_clear(*frame.world(x, y), 0.02) for x, y in patch)
    body = [(park.x + sx * 0.3, park.y + sy * 0.45) for sx in (-1, 1) for sy in (-1, 1)]
    body_clear = min(sun_clear(*frame.world(x, y), 0.44 + 0.10) for x, y in body)
    r.check(patch_clear > 0.0 and body_clear > 0.0, "far site: the patch lit (the sun's ray clears the ground by %.2f m at worst), "
            "Kite's deck lit at park_sample (%.2f m)" % (patch_clear, body_clear))
    shade = next(s for s in np.arange(0.25, 30.0, 0.25) if sun_clear(*frame.world(0.0, s)) < 0.0)
    marker = (0.0, shade - 0.5)
    # The shade line grazes this slope, so test_iris looks for it 2 m past the marker, 20 mm up
    deep = sun_clear(*frame.world(0.0, marker[1] + 2.0), 0.02)
    r.check(3.0 <= shade <= 8.0 and sun_clear(*frame.world(*marker), 0.05) > 0.0 and deep < 0.0,
            "far site: the shade starts %.2f m down the fall line from the patch's centre; the far-rim marker 0.5 m before it, lit; "
            "2 m past the marker the shade is %.2f m deep" % (shade, -deep))
    worst_rock = max(rock_shadow(*frame.world(x, y), 0.6) for x, y in [(0.0, 0.0), (park.x, park.y)])
    r.check(worst_rock == 0.0, "far site: no rock's shadow on the patch or Kite (largest reaching %.2f m)" % worst_rock)
    # The logger beside the patch, and where Kite stops to pick it up
    lx, ly = LOGGER_OFFSET
    foot = [(lx + sx * (LOG_HX + BUMPER), ly + sy * LOG_HY, frame.ground(lx + sx * (LOG_HX + BUMPER), ly + sy * LOG_HY))
            for sx in (-1, 0, 1) for sy in (-1, 0, 1)]
    rest, log_normal = plane_at(foot, lx, ly)
    log_dev = max(abs(p[2] - plane_at(foot, p[0], p[1])[0]) for p in foot)
    pick = reach_window(iris_kit.GROUND_Z + LOG_H)
    d_pick = (pick[0] + pick[1]) / 2.0
    park_logger = Vector((lx - iris_kit.YAW_AXIS.x, ly - (iris_kit.YAW_AXIS.y + d_pick)))
    r.check(pick[1] - pick[0] >= 0.15 and log_dev <= 0.01 and sun_clear(*frame.world(lx, ly), 0.02) > 0.0,
            "far logger: lit, its footprint %.0f mm from flat; Kite's hub end reaches its latch %.2f-%.2f m ahead of the yaw axis" % (
                log_dev * 1000.0, pick[0], pick[1]))
    clutter = {name: rocks_near(*frame.world(x, y), radius) for name, (x, y), radius in (
        ("patch", (0.0, 0.0), 2.5), ("park_sample", tuple(park), 1.0), ("logger", (lx, ly), 1.5), ("park_logger", tuple(park_logger), 1.0),
        ("marker", marker, 0.5))}
    r.check(not any(clutter.values()), "far site: no rocks on the patch, the logger, the marker or where Kite stops %s" % clutter)
    for name, (x, y) in (("base", BASE_XZ), ("IRIS", iris_kit.IRIS_XZ)):
        r.note("far site: %.0f m from %s" % (math.hypot(FAR_SITE[0] - x, FAR_SITE[1] - y), name))
    # The patch, its markers and the transforms for moon_level.tscn
    kit.reset_scene()
    site = sk.make_site(park, "sample_site_far", Vector((0.0, 0.0)), frame.ground, marker)
    ws.add_empty(site, "anchor_logger", (lx, ly, rest))
    ws.add_empty(site, "park_logger", (park_logger.x, park_logger.y, frame.ground(park_logger.x, park_logger.y)))
    r.failures += ws.check_part(site, BUDGET["site"], None, r.rows)
    ws.rk.GODOT_IMPORT_SCRIPT = ws.GODOT_IMPORT_SCRIPT
    kit.GODOT_IMPORT_SCRIPT = ws.GODOT_IMPORT_SCRIPT
    os.makedirs(iris_kit.EXPORT_DIR, exist_ok=True)
    kit.export_part(site, os.path.join(iris_kit.EXPORT_DIR, "sample_site_far.glb"))
    kit.save_blend(os.path.join(iris_kit.PARTS_DIR, "sample_site_far.blend"))
    kit.GODOT_IMPORT_SCRIPT = "res://src/robot/kit/rover_kit_import.gd"
    tilt = Vector((0.0, 0.0, 1.0)).rotation_difference(log_normal).to_matrix().to_4x4()
    logger_pose = Matrix.Translation((lx, ly, rest + 0.002)) @ tilt
    mx, mz = frame.world(*marker)
    r.note("Godot SampleSiteFar  transform = %s" % frame.godot())
    r.note("Godot FarRimMarker   transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %.3f, %.3f, %.3f)" % (mx, terrain(mx, mz), mz))
    r.note("Godot FarLogger      transform = %s" % frame.godot(logger_pose))
    r.note("park_sample (site frame) (%.2f, %.2f), %.2f m from the centre; park_logger (%.2f, %.2f)" % (
        park.x, park.y, park.length, park_logger.x, park_logger.y))
    if previews:
        before = set(bpy.data.objects)
        logger = arm_kit.load("field_logger.blend", "field_logger")
        logger.matrix_world = logger_pose
        bpy.context.view_layer.update()
        bpy.ops.import_scene.gltf(filepath=os.path.join(ws.EXPORT_DIR, "ws_marker_post.glb"))
        post = next(o for o in bpy.data.objects if o not in before and o.parent is None and o is not logger)
        post.location = (marker[0], marker[1], frame.ground(*marker))
        bpy.context.view_layer.update()
        keep = tuple(o for o in bpy.data.objects if o not in before and o.type == "MESH" and "convcolonly" not in o.name.lower())
        ws.set_preview_colors(True)
        kit.set_preview_colors(True)
        ws.render(site, os.path.join(previews, "far_site_top.png"), (0.0, 0.0, 1.0), 3.4, False, 1.0, (0.65, -0.3, 0.0), keep_visible=keep)
        ws.render(site, os.path.join(previews, "far_site_three_quarter.png"), (1.0, -0.9, 0.6), 3.0, True, 11.0, (0.4, 2.6, 0.0), keep_visible=keep)
        ws.set_preview_colors(False)
        kit.set_preview_colors(False)
    return {"d_mid": d_mid}


# --- Main ------------------------------------------------------------------------------------

def render_part(obj, previews: str, name: str, views: tuple, scale: float, focus: tuple) -> None:
    kit.set_preview_colors(True)
    for view, d in views:
        kit.render_view(obj, os.path.join(previews, "%s_%s.png" % (name, view)), d, scale, view == "three_quarter", scale * 3.0, focus)
    kit.set_preview_colors(False)


def main() -> None:
    previews = kit.preview_dir("m3_kit")
    r = Report()
    # The parts on their own
    built = {}
    for name, make, focus, scale in (("field_logger", make_logger, (0.0, 0.0, 0.04), 0.3),
                                     ("thermal_cover", make_cover, (0.0, 0.0, 0.01), 0.48),
                                     ("thermal_heater", make_heater, (0.0, 0.0, 0.02), 0.2),
                                     ("arm_tool_thermal", make_thermal_tool, (0.0, 0.025, 0.0), 0.26)):
        kit.reset_scene()
        obj = make()
        part_checks(obj, BUDGET[name], r)
        sk.export_rover(obj, name)
        built[name] = [v.copy() for v in kit.world_vertices(obj)]
        if previews:
            views = (("three_quarter", (0.8, -1.0, 0.7)), ("top", (0.0, 0.0, 1.0)), ("side", (0.0, -1.0, 0.0)), ("end", (1.0, 0.0, 0.0)))
            if name == "field_logger":
                views += (("under", (0.0, 0.0, -1.0)),)
            render_part(obj, previews, name, views, scale, focus)
    v = built["field_logger"]
    size = Vector((max(p.x for p in v) - min(p.x for p in v), max(p.y for p in v) - min(p.y for p in v), max(p.z for p in v) - min(p.z for p in v)))
    r.check(min(p.z for p in v) >= ITEM.z - 1e-6 and size.y <= 0.136, "logger %.3f x %.3f x %.3f m with bumpers and stub, origin on its feet; "
            "%.0f mm deep for the 140 mm top shelf" % (size.x, size.y, size.z, size.y * 1000.0))
    kit.reset_scene()
    standard = kit.mesh_object("arm_tool_standard", arm_kit.build_tool(), [])
    standard.location = arm_kit.TOOL
    bpy.context.view_layer.update()
    std, own = envelope(kit.world_vertices(standard)), envelope(built["arm_tool_thermal"])
    r.check(own[0] <= std[0] + 1e-6 and own[1] >= std[1] - 1e-6 and own[2] <= std[2] + 1e-6,
            "thermal turret inside the standard turret's envelope: %.1f mm from the hub axis (standard %.1f), y %.3f to %.3f "
            "(standard %.3f to %.3f): the arm's clearances carry over" % (own[0] * 1000, std[0] * 1000, own[1], own[2], std[1], std[2]))
    # On Kite
    scene = pam.assemble()
    mount = arm_kit.load("cargo_mount.blend", "cargo_mount")
    cradle = arm_kit.load("module_cradle.blend", "module_cradle")
    for o in (mount, cradle):
        o.location = SOCKET
    logger = arm_kit.load("field_logger.blend", "field_logger")
    module = arm_kit.load("radio_module.blend", "radio_module")
    cover = arm_kit.load("thermal_cover.blend", "thermal_cover")
    heater = arm_kit.load("thermal_heater.blend", "thermal_heater")
    thermal = arm_kit.load("arm_tool_thermal.blend", "arm_tool_thermal")
    logger.location, module.location, cover.location, heater.location = ITEM, ITEM, COVER_SOCKET, HEATER_SOCKET
    heater.rotation_euler = (0.0, 0.0, HEATER_TURN)
    thermal.location = arm_kit.TOOL + Vector((0.0, 0.0, -5.0))           # out of the way; its mesh is borrowed
    bpy.context.view_layer.update()
    logger_on_kite(scene, mount, cradle, logger, r)
    thermal_on_kite(scene, mount, cradle, cover, heater, {"logger": logger, "module": module}, r)
    sk_near, sk_far = sk.site_reach()
    joints = reading_pose(scene, thermal, r, (sk_near + sk_far) / 2.0)
    if previews:
        module.location.z -= 5.0
        bpy.context.view_layer.update()
        kit.set_preview_colors(True)
        chassis = scene["chassis"]
        ground = pam.rb.ground_plane(0.0, 2.2)
        keep = (mount, cradle, logger, cover, heater, ground)
        for name, d in (("installed_chase", (-0.6, -1.0, 0.75)), ("installed_rear", (0.7, -1.0, 0.9))):
            kit.render_view(chassis, os.path.join(previews, name + ".png"), d, 2.2, True, 4.2, (0.0, 0.0, 0.35), keep_visible=keep)
        kit.render_view(chassis, os.path.join(previews, "installed_top.png"), (0.0, 0.0, 1.0), 1.3, focus=(0.0, 0.0, 0.4), keep_visible=keep)
        kit.render_view(chassis, os.path.join(previews, "installed_side.png"), (-1.0, 0.0, 0.0), 1.6, focus=(0.0, 0.2, 0.55), keep_visible=keep)
        tool = scene["arm"]["tool"]
        saved = tool.data
        tool.data = thermal.data
        arm_kit.pose_arm(scene["arm"], joints)
        kit.render_view(chassis, os.path.join(previews, "reading_pose_side.png"), (1.0, 0.0, 0.0), 2.0, focus=(0.0, 0.5, 0.2), keep_visible=(ground,))
        tool.data = saved
        arm_kit.pose_arm(scene["arm"], arm_kit.STOWED)
        kit.set_preview_colors(False)
    far_site(r, previews)
    r.note("masses for the part scenes (kg, estimates): %s; power (W): heater %.0f, radiometer %.0f while reading" % (
        ", ".join("%s %.1f" % kv for kv in MASS.items()), POWER["thermal_heater"], POWER["radiometer"]))
    r.note("ALL CHECKS OK" if r.failures == 0 else "%d CHECK FAILURES" % r.failures)
    print("\n".join("IRIS_KIT m3_kit " + row for row in r.rows))


if __name__ == "__main__":
    main()
