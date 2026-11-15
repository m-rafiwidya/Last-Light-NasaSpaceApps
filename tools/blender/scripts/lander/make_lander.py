"""Generates the crew lander (tools/blender/LANDER_KIT.md): octagonal descent stage with tanks and foil,
four legs with struts and footpads, the engine bell, the ascent cabin with windows, RCS quads and an
antenna, the porch, the hatch leaf (hinged) and the two-panel fold-down ramp (hinged).

    blender -b --factory-startup -P tools/blender/scripts/lander/make_lander.py [-- --previews DIR | --no-previews]

Writes tools/blender/parts/lander/lander.blend, game/res/models/lander_kit/lander.glb and previews in
tools/blender/previews/lander/. Checks the size, the budget and, at the lander's spot on the Apollo 12
terrain (game/res/terrain/moon_apollo12/play.f32), the footpads and the ramp's foot against the ground.

Lander frame: metres, origin on the ground under the middle, +Z up, the hatch side +Y (Godot -Z).
    lander                 root (empty)
      lander_body            everything that doesn't move
      lander_hatch_leaf      origin on its hinge (vertical, +X jamb), closed at 0, open at HATCH_OPEN
      lander_ramp_upper      origin on the porch edge hinge (along X), deployed at RAMP_DEPLOYED
        lander_ramp_lower      origin on the fold hinge, under the upper panel's end; 0 deployed
      anchor_hatch, anchor_engine, anchor_plume, anchor_ramp_foot, anchor_hatch_light
"""

import math
import os
import random
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

HERE = os.path.dirname(__file__)
sys.path.append(os.path.join(HERE, ".."))
sys.path.append(os.path.join(HERE, "..", "workshop"))
import rover_kit_common as kit  # noqa: E402
import workshop_kit_common as ws  # noqa: E402

ws.PALETTE.update({"ld_foil": "B8913A"})
ws.MATERIAL_SETTINGS.update({"ld_foil": (0.85, 0.4)})
ws.PREVIEW_COLORS.update({"ld_foil": "D9B05A"})

PARTS_DIR = os.path.join(kit.REPO_ROOT, "tools", "blender", "parts", "lander")
EXPORT_DIR = os.path.join(kit.REPO_ROOT, "game", "res", "models", "lander_kit")
PLAY = os.path.join(kit.REPO_ROOT, "game", "res", "terrain", "moon_apollo12", "play.f32")

MATS = ["ws_panel", "ws_frame", "ws_dark", "ws_accent", "ws_screen", "ld_foil"]
PANEL, FRAME, DARK, ACCENT, WINDOW, FOIL = range(6)

# Placement in the Moon level (moon_level.tscn, Lander): ground under the origin, yaw about Godot Y
PLACE_XZ = (-307.6, 211.8)
PLACE_YAW_DEG = -169.95

BUDGET = 6000
HEIGHT = 6.8
PAD_SPAN = 8.6
PAD_RADIUS = 0.45
PAD_CENTRE = (PAD_SPAN - 2 * PAD_RADIUS) / 2.0          # 3.85
LEG_AZIMUTHS = [45.0, 135.0, 225.0, 315.0]

STAGE_APOTHEM = 2.0
STAGE_Z = (1.0, 2.3)
BELL = (0.35, 1.0)                                       # exit and throat heights
BELL_EXIT_RADIUS = 0.75

DECK = 2.30
PORCH_TOP = 2.32
PORCH_X = 0.8
PORCH_Y = (0.75, 2.0)                                    # the flat part
# The porch's curved nose, from flat down to the ramp's slope: walking (2 m/s) stays on it in the
# Moon's gravity (v^2 / R < g cos 30 deg); a sharp edge throws the walker 2.4 m down the ramp
NOSE_RADIUS = 3.2
CABIN_X = 1.5
CABIN_Y = (-1.35, 1.35)
CABIN_TOP = 5.05
HATCH_X = 0.45
HATCH_TOP = 4.42
RECESS_Y = 0.75
JAMB = 0.035
HATCH_HINGE = Vector((HATCH_X, CABIN_Y[1] + JAMB, PORCH_TOP))
HATCH_OPEN = -176.0
HATCH_ANCHOR = Vector((0.0, 1.95, PORCH_TOP))

RAMP_HALF_WIDTH = 0.6
RAMP_PANEL = 2.2
RAMP_THICK = 0.08
RAMP_DEPLOYED = -30.0
RAMP_HINGE = Vector((0.0, PORCH_Y[1] + NOSE_RADIUS * math.sin(math.radians(-RAMP_DEPLOYED)),
                     PORCH_TOP - NOSE_RADIUS * (1.0 - math.cos(math.radians(-RAMP_DEPLOYED)))))
RAMP_STOWED = 90.0
RAMP_LOWER_STOWED = -180.0


# --- geometry -------------------------------------------------------------------------------

def finish(bm, faces):
    bmesh.ops.recalc_face_normals(bm, faces=faces)
    return faces


def lathe(bm, profile, mat, sides=12, matrix=Matrix(), closed=False, mats=None):
    """A solid of revolution about local Z: `profile` [(r, z), ...]; open profiles get end caps
    where r > 0, closed ones (a loop, every r > 0) make a ring. `mats` per profile segment."""
    rings = []
    for r, z in profile:
        if r <= 1e-6:
            rings.append([bm.verts.new(matrix @ Vector((0.0, 0.0, z)))])
        else:
            rings.append([bm.verts.new(matrix @ Vector((r * math.cos(2 * math.pi * k / sides),
                                                           r * math.sin(2 * math.pi * k / sides), z)))
                          for k in range(sides)])
    faces = []
    count = len(profile) if closed else len(profile) - 1
    for i in range(count):
        a, b = rings[i], rings[(i + 1) % len(rings)]
        m = mats[i] if mats else mat
        for k in range(sides):
            n = (k + 1) % sides
            if len(a) == 1 and len(b) == 1:
                continue
            if len(a) == 1:
                f = bm.faces.new((a[0], b[k], b[n]))
            elif len(b) == 1:
                f = bm.faces.new((a[k], a[n], b[0]))
            else:
                f = bm.faces.new((a[k], a[n], b[n], b[k]))
            f.material_index = m
            faces.append(f)
    if not closed:
        for ring in (rings[0], rings[-1]):
            if len(ring) > 1:
                f = bm.faces.new(ring)
                f.material_index = mat
                faces.append(f)
    return finish(bm, faces)


def tube(bm, a, b, radius, mat, sides=6):
    a, b = Vector(a), Vector(b)
    axis = (b - a).normalized()
    m = axis.to_track_quat("Z", "Y").to_matrix().to_4x4()
    m.translation = a
    return lathe(bm, [(radius, 0.0), (radius, (b - a).length)], mat, sides, m)


def obox(bm, matrix, x, y, z, mat):
    """A box from local ranges, placed by `matrix`."""
    verts = [bm.verts.new(matrix @ Vector((xx, yy, zz))) for zz in z for yy in y for xx in x]
    quads = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    faces = [bm.faces.new([verts[i] for i in q]) for q in quads]
    for f in faces:
        f.material_index = mat
    return finish(bm, faces)


def box(bm, x, y, z, mat):
    return obox(bm, Matrix(), x, y, z, mat)


def prism_x(bm, outline_yz, x0, x1, mat):
    """A YZ polygon extruded along X."""
    faces = kit.prism(bm, outline_yz, lambda u, v, w: (w, u, v), x0, x1)
    for f in faces:
        f.material_index = mat
    return finish(bm, faces)


def face_frame(azimuth_deg, z=0.0):
    """Matrix for an octagon face: local +Y outward from the face's middle, +Z up."""
    a = math.radians(azimuth_deg)
    m = Matrix.Rotation(a - math.pi / 2.0, 4, "Z")
    m.translation = Vector((STAGE_APOTHEM * math.cos(a), STAGE_APOTHEM * math.sin(a), z))
    return m


def polar_xy(r, azimuth_deg, z):
    a = math.radians(azimuth_deg)
    return Vector((r * math.cos(a), r * math.sin(a), z))


# --- the body ---------------------------------------------------------------------------------

def descent_stage(bm, rng):
    r = STAGE_APOTHEM / math.cos(math.pi / 8.0)
    outline = [(r * math.cos(math.radians(22.5 + 45 * k)), r * math.sin(math.radians(22.5 + 45 * k))) for k in range(8)]
    core = kit.prism(bm, outline, lambda u, v, w: (u, v, w), STAGE_Z[0], STAGE_Z[1])
    for f in core:
        f.material_index = DARK
    finish(bm, core)
    half = STAGE_APOTHEM * math.tan(math.pi / 8.0)
    height = STAGE_Z[1] - STAGE_Z[0]
    for k in range(8):
        az = 45.0 * k
        m = face_frame(az, STAGE_Z[0])
        if az % 90.0 == 45.0:
            # Foil: crinkled sub-panels, each tilted a little
            for i in range(3):
                for j in range(2):
                    x0 = -half + 0.1 + i * (2 * half - 0.2) / 3.0
                    x1 = x0 + (2 * half - 0.2) / 3.0 - 0.02
                    z0 = 0.12 + j * (height - 0.24) / 2.0
                    z1 = z0 + (height - 0.24) / 2.0 - 0.02
                    tilt = Matrix.Rotation(rng.uniform(-0.06, 0.06), 4, "X") @ Matrix.Rotation(rng.uniform(-0.06, 0.06), 4, "Z")
                    centre = Matrix.Translation(((x0 + x1) / 2.0, 0.02, (z0 + z1) / 2.0))
                    hx, hz = (x1 - x0) / 2.0, (z1 - z0) / 2.0
                    obox(bm, m @ centre @ tilt, (-hx, hx), (-0.015, 0.015), (-hz, hz), FOIL)
        else:
            # Structure bay: a light panel with a dark inspection plate
            obox(bm, m, (-half + 0.08, half - 0.08), (0.0, 0.03), (0.1, height - 0.1), PANEL)
            obox(bm, m, (-0.35, 0.35), (0.03, 0.045), (0.35, 0.8), FRAME)
    # Corner posts and rims
    for k in range(8):
        az = 22.5 + 45 * k
        p = polar_xy(r + 0.02, az, 0.0)
        tube(bm, (p.x, p.y, STAGE_Z[0] - 0.02), (p.x, p.y, STAGE_Z[1] + 0.02), 0.06, FRAME, 6)
    for z0, z1 in ((STAGE_Z[1] - 0.06, STAGE_Z[1] + 0.0), (STAGE_Z[0], STAGE_Z[0] + 0.06)):
        rim = kit.prism(bm, [(u * 1.03, v * 1.03) for u, v in outline], lambda u, v, w: (u, v, w), z0, z1)
        for f in rim:
            f.material_index = FRAME
        finish(bm, rim)
    # Deck plate and the heat shield underneath
    deck = kit.prism(bm, [(u * 0.98, v * 0.98) for u, v in outline], lambda u, v, w: (u, v, w), DECK - 0.01, DECK)
    for f in deck:
        f.material_index = FRAME
    finish(bm, deck)
    shield = kit.prism(bm, [(u * 0.92, v * 0.92) for u, v in outline], lambda u, v, w: (u, v, w), STAGE_Z[0] - 0.05, STAGE_Z[0])
    for f in shield:
        f.material_index = FOIL
    finish(bm, shield)
    # Propellant tanks in the side bays and aft
    tank = [(0.0, 1.12), (0.3, 1.16), (0.44, 1.3), (0.44, 2.0), (0.3, 2.14), (0.0, 2.18)]
    for x, y in ((2.18, 0.0), (-2.18, 0.0), (0.0, -2.18)):
        lathe(bm, tank, PANEL, 12, Matrix.Translation((x, y, 0.0)))
        lathe(bm, [(0.455, 1.55), (0.455, 1.65)], ACCENT, 12, Matrix.Translation((x, y, 0.0)))
        out = Vector((x, y, 0.0)).normalized()
        for z in (1.35, 1.95):
            tube(bm, out * 1.95 + Vector((0, 0, z)), out * 2.1 + Vector((0, 0, z)), 0.04, FRAME, 4)


def engine(bm):
    lathe(bm, [(0.62, STAGE_Z[0] - 0.05), (0.42, BELL[1] - 0.06), (0.36, BELL[1] - 0.12)], FRAME, 16)
    exit_z, throat_z = BELL
    loop = [(0.37, throat_z - 0.1), (0.46, 0.8), (0.6, 0.58), (BELL_EXIT_RADIUS, exit_z),
            (BELL_EXIT_RADIUS - 0.03, exit_z), (0.57, 0.6), (0.43, 0.8), (0.33, throat_z - 0.12)]
    lathe(bm, loop, FRAME, 16, closed=True, mats=[FRAME, FRAME, FRAME, FRAME, DARK, DARK, DARK, DARK])


def legs(bm):
    for az in LEG_AZIMUTHS:
        pad = polar_xy(PAD_CENTRE, az, 0.0)
        lathe(bm, [(0.0, -0.04), (PAD_RADIUS, -0.04), (PAD_RADIUS, 0.03), (0.36, 0.11), (0.12, 0.16), (0.0, 0.16)],
              FRAME, 12, Matrix.Translation(pad))
        joint = pad + Vector((0.0, 0.0, 0.24))
        lathe(bm, [(0.0, 0.14), (0.09, 0.18), (0.1, 0.24), (0.07, 0.31), (0.0, 0.33)], FRAME, 6, Matrix.Translation(pad))
        top = polar_xy(STAGE_APOTHEM + 0.1, az, STAGE_Z[1] - 0.15)
        mid = top.lerp(joint, 0.55)
        tube(bm, top, mid, 0.11, PANEL, 8)
        tube(bm, top.lerp(joint, 0.45), joint, 0.075, FRAME, 8)
        obox(bm, Matrix.Translation(top) @ Matrix.Rotation(math.radians(az) - math.pi / 2, 4, "Z"),
             (-0.2, 0.2), (-0.15, 0.05), (-0.15, 0.15), FRAME)
        knee = top.lerp(joint, 0.66)
        for side in (-1.0, 1.0):
            foot = polar_xy(STAGE_APOTHEM + 0.03, az + side * 17.0, STAGE_Z[0] + 0.08)
            tube(bm, foot, knee, 0.045, FRAME, 6)
        tube(bm, polar_xy(1.5, az, STAGE_Z[0] - 0.02), knee, 0.035, FRAME, 6)


def nose(steps=7):
    """(y, z, angle) along the nose's top, from the flat porch to the ramp's hinge"""
    end = math.radians(-RAMP_DEPLOYED)
    return [(PORCH_Y[1] + NOSE_RADIUS * math.sin(a), PORCH_TOP - NOSE_RADIUS * (1.0 - math.cos(a)), a)
            for a in (end * k / (steps - 1) for k in range(steps))]


def porch(bm):
    box(bm, (-PORCH_X, PORCH_X), PORCH_Y, (PORCH_TOP - 0.1, PORCH_TOP), FRAME)
    top = [(y, z) for y, z, _ in nose()]
    under = [(y - 0.1 * math.sin(a), z - 0.1 * math.cos(a)) for y, z, a in nose()]
    prism_x(bm, top + under[::-1], -PORCH_X, PORCH_X, FRAME)
    for x in (-PORCH_X, PORCH_X):
        box(bm, (x - 0.02, x + 0.02), (PORCH_Y[0] + 0.6, PORCH_Y[1]), (PORCH_TOP, PORCH_TOP + 0.08), ACCENT)
        lip = [(y + 0.08 * math.sin(a), z + 0.08 * math.cos(a)) for y, z, a in nose()]
        prism_x(bm, top + lip[::-1], x - 0.02, x + 0.02, ACCENT)
    for y in (1.5, 1.75):
        box(bm, (-PORCH_X + 0.05, PORCH_X - 0.05), (y, y + 0.04), (PORCH_TOP, PORCH_TOP + 0.008), DARK)
    for y, z, a in nose(7)[1:-1]:
        m = Matrix.Translation((0.0, y, z)) @ Matrix.Rotation(-a, 4, "X")
        obox(bm, m, (-PORCH_X + 0.05, PORCH_X - 0.05), (-0.02, 0.02), (0.0, 0.008), DARK)
    for x in (-0.65, 0.65):
        tube(bm, (x, STAGE_APOTHEM + 0.02, STAGE_Z[0] + 0.45), (x, RAMP_HINGE.y - 0.15, RAMP_HINGE.z - 0.12), 0.045, FRAME, 6)
        tube(bm, (x, STAGE_APOTHEM + 0.02, STAGE_Z[0] + 1.05), (x, nose()[3][0], nose()[3][1] - 0.1), 0.035, FRAME, 6)
    for x in (-PORCH_X, PORCH_X):
        posts = [Vector((x, 1.45, PORCH_TOP))] + [Vector((x, y, z)) for y, z, _ in nose(3)]
        for p in posts:
            tube(bm, p, p + Vector((0, 0, 1.05)), 0.03, FRAME, 6)
        for h in (0.55, 1.05):
            for a, b in zip(posts, posts[1:]):
                tube(bm, a + Vector((0, 0, h)), b + Vector((0, 0, h)), 0.025, ACCENT, 6)


def cabin(bm):
    y0, y1 = CABIN_Y
    full = [(y0, DECK), (y1, DECK), (y1, 4.5), (0.95, CABIN_TOP), (y0, CABIN_TOP)]
    recess = [(y0, DECK), (RECESS_Y, DECK), (RECESS_Y, HATCH_TOP), (y1, HATCH_TOP), (y1, 4.5), (0.95, CABIN_TOP), (y0, CABIN_TOP)]
    for x0, x1 in ((-CABIN_X, -HATCH_X), (HATCH_X, CABIN_X)):
        faces = prism_x(bm, full, x0, x1, PANEL)
        for f in faces:
            c = f.calc_center_median()
            if abs(abs(f.normal.x) - 1.0) < 1e-3 and abs(abs(c.x) - HATCH_X) < 1e-3:
                f.material_index = DARK
    for f in prism_x(bm, recess, -HATCH_X, HATCH_X, PANEL):
        c = f.calc_center_median()
        if (f.normal.y > 0.9 and c.y < y1 - 0.01) or (f.normal.z < -0.9 and c.z > DECK + 0.1):
            f.material_index = DARK
    # Hatch frame
    for x0, x1 in ((-HATCH_X - 0.1, -HATCH_X), (HATCH_X, HATCH_X + 0.1)):
        box(bm, (x0, x1), (y1, y1 + JAMB), (PORCH_TOP, HATCH_TOP + 0.1), FRAME)
    box(bm, (-HATCH_X - 0.1, HATCH_X + 0.1), (y1, y1 + JAMB), (HATCH_TOP, HATCH_TOP + 0.1), FRAME)
    box(bm, (-0.25, 0.25), (y1, y1 + 0.12), (HATCH_TOP + 0.1, HATCH_TOP + 0.18), FRAME)
    box(bm, (-0.15, 0.15), (y1 + 0.02, y1 + 0.1), (HATCH_TOP + 0.09, HATCH_TOP + 0.1), PANEL)
    # Handrails beside the hatch
    for x in (-HATCH_X - 0.25, HATCH_X + 1.05):
        tube(bm, (x, y1 + 0.02, 2.9), (x, y1 + 0.12, 2.9), 0.02, FRAME, 4)
        tube(bm, (x, y1 + 0.02, 3.9), (x, y1 + 0.12, 3.9), 0.02, FRAME, 4)
        tube(bm, (x, y1 + 0.12, 2.88), (x, y1 + 0.12, 3.92), 0.025, ACCENT, 6)
    # Windows on the sloped front, with frames
    edge0, edge1 = Vector((0.0, y1, 4.5)), Vector((0.0, 0.95, CABIN_TOP))
    normal = Vector((0.0, CABIN_TOP - 4.5, y1 - 0.95)).normalized()
    for xc in (-0.85, 0.85):
        for inset, mat, lift in ((0.0, FRAME, 0.01), (0.05, WINDOW, 0.02)):
            a0, a1 = edge0.lerp(edge1, 0.18 + inset), edge0.lerp(edge1, 0.78 - inset)
            hw = 0.32 - inset
            corners = [a0 + Vector((xc - hw, 0, 0)), a0 + Vector((xc + hw, 0, 0)),
                       a1 + Vector((xc + hw * 0.8, 0, 0)), a1 + Vector((xc - hw * 0.8, 0, 0))]
            ws.quad(bm, [c + normal * lift for c in corners], mat, normal)
    # Docking tunnel on top, the aft equipment bay, the ascent tanks
    lathe(bm, [(0.55, CABIN_TOP), (0.5, CABIN_TOP + 0.3), (0.5, CABIN_TOP + 0.36), (0.38, CABIN_TOP + 0.38), (0.0, CABIN_TOP + 0.38)],
          FRAME, 12, Matrix.Translation((0.0, -0.25, 0.0)))
    box(bm, (-1.2, 1.2), (y0 - 0.65, y0), (2.5, 4.2), DARK)
    for i in range(3):
        for j in range(2):
            box(bm, (-1.15 + i * 0.78, -0.43 + i * 0.78), (y0 - 0.69, y0 - 0.65), (2.55 + j * 0.82, 3.33 + j * 0.82), FOIL)
    for x in (-CABIN_X - 0.38, CABIN_X + 0.38):
        m = Matrix.Translation((x, -0.35, 3.15)) @ Matrix.Rotation(math.pi / 2, 4, "X")
        lathe(bm, [(0.0, -0.8), (0.28, -0.76), (0.38, -0.6), (0.38, 0.6), (0.28, 0.76), (0.0, 0.8)], PANEL, 12, m)
        for y in (-0.8, 0.1):
            box(bm, (min(x, math.copysign(CABIN_X, x)), max(x, math.copysign(CABIN_X, x))), (y - 0.05, y + 0.05), (3.1, 3.2), FRAME)


def rcs_quads(bm):
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            c = Vector((sx * 1.82, sy * 1.42, 4.62))
            tube(bm, Vector((sx * CABIN_X, sy * 1.1, 4.62)), c, 0.05, FRAME, 4)
            box(bm, (c.x - 0.13, c.x + 0.13), (c.y - 0.13, c.y + 0.13), (c.z - 0.13, c.z + 0.13), PANEL)
            for d in (Vector((0, 0, 1)), Vector((0, 0, -1)), Vector((sx, 0, 0)), Vector((0, sy, 0))):
                m = d.to_track_quat("Z", "Y").to_matrix().to_4x4()
                m.translation = c + d * 0.13
                lathe(bm, [(0.035, 0.0), (0.07, 0.13), (0.055, 0.13)], DARK, 6, m, closed=True)


def antenna(bm):
    base = Vector((0.85, -0.95, CABIN_TOP))
    top = Vector((0.85, -0.95, 6.22))
    tube(bm, base, top, 0.05, FRAME, 6)
    tilt = Matrix.Translation(top) @ Matrix.Rotation(math.radians(-29.0), 4, "Y")
    lathe(bm, [(0.03, 0.0), (0.22, 0.05), (0.42, 0.2), (0.4, 0.22), (0.21, 0.08), (0.03, 0.04)], PANEL, 16, tilt, closed=True)
    lathe(bm, [(0.025, 0.04), (0.025, 0.6), (0.04, 0.6), (0.0, 0.66)], FRAME, 6, tilt)
    tube(bm, Vector((-0.9, -1.0, CABIN_TOP)), Vector((-0.9, -1.0, 6.0)), 0.015, FRAME, 4)


def hatch_leaf():
    bm = bmesh.new()
    width = 2 * HATCH_X
    box(bm, (-width + 0.01, -0.01), (-0.06, 0.0), (0.0, HATCH_TOP - PORCH_TOP - 0.01), PANEL)
    box(bm, (-width + 0.08, -0.08), (0.0, 0.015), (0.08, HATCH_TOP - PORCH_TOP - 0.09), FRAME)
    lathe(bm, [(0.13, 0.0), (0.13, 0.025)], FRAME, 12,
          Matrix.Translation((-HATCH_X, 0.0, 1.55)) @ Matrix.Rotation(-math.pi / 2, 4, "X"))
    lathe(bm, [(0.1, 0.02), (0.1, 0.03)], WINDOW, 12,
          Matrix.Translation((-HATCH_X, 0.0, 1.55)) @ Matrix.Rotation(-math.pi / 2, 4, "X"))
    box(bm, (-width + 0.12, -width + 0.16), (0.015, 0.06), (0.85, 1.25), ACCENT)
    for z in (0.25, 1.85):
        lathe(bm, [(0.035, z - 0.12), (0.035, z + 0.12)], FRAME, 6, Matrix.Translation((0.0, 0.01, 0.0)))
    return bm


def ramp_panel(lower: bool):
    bm = bmesh.new()
    z = (0.0, RAMP_THICK) if lower else (-RAMP_THICK, 0.0)
    top = z[1]
    box(bm, (-RAMP_HALF_WIDTH, RAMP_HALF_WIDTH), (0.0, RAMP_PANEL), z, FRAME)
    for x in (-RAMP_HALF_WIDTH, RAMP_HALF_WIDTH - 0.05):
        box(bm, (x, x + 0.05), (0.0, RAMP_PANEL), (top, top + 0.06), ACCENT)
    for k in range(int((RAMP_PANEL - 0.25) / 0.32) + 1):
        y = 0.15 + k * 0.32
        box(bm, (-RAMP_HALF_WIDTH + 0.08, RAMP_HALF_WIDTH - 0.08), (y, y + 0.06), (top, top + 0.015), DARK)
    hinge_z = z[0]
    tube(bm, (-RAMP_HALF_WIDTH + 0.1, 0.0, hinge_z), (RAMP_HALF_WIDTH - 0.1, 0.0, hinge_z), 0.045, FRAME, 6)
    if lower:
        box(bm, (-RAMP_HALF_WIDTH, RAMP_HALF_WIDTH), (RAMP_PANEL - 0.12, RAMP_PANEL), (-0.03, top), DARK)
    return bm


# --- assembly -------------------------------------------------------------------------------

def mesh(name, bm, parent=None, location=(0.0, 0.0, 0.0)):
    obj = kit.mesh_object(name, bm, ws.materials(*MATS))
    obj.location = location
    if parent:
        obj.parent = parent
    return obj


def anchor(root, name, location):
    empty = bpy.data.objects.new(name, None)
    empty.empty_display_size = 0.2
    bpy.context.scene.collection.objects.link(empty)
    empty.parent = root
    empty.location = location
    return empty


def build():
    rng = random.Random(20261112)
    root = bpy.data.objects.new("lander", None)
    bpy.context.scene.collection.objects.link(root)
    bm = bmesh.new()
    descent_stage(bm, rng)
    engine(bm)
    legs(bm)
    porch(bm)
    cabin(bm)
    rcs_quads(bm)
    antenna(bm)
    mesh("lander_body", bm, root)
    leaf = mesh("lander_hatch_leaf", hatch_leaf(), root, HATCH_HINGE)
    upper = mesh("lander_ramp_upper", ramp_panel(False), root, RAMP_HINGE)
    lower = mesh("lander_ramp_lower", ramp_panel(True), upper, (0.0, RAMP_PANEL, -RAMP_THICK))
    anchor(root, "anchor_hatch", HATCH_ANCHOR)
    anchor(root, "anchor_engine", (0.0, 0.0, 0.5))
    anchor(root, "anchor_plume", (0.0, 0.0, BELL[0]))
    anchor(root, "anchor_hatch_light", (0.0, 1.05, HATCH_TOP - 0.2))
    anchor(root, "anchor_ramp_foot", ramp_foot(RAMP_DEPLOYED))
    return root, leaf, upper, lower


def ramp_foot(angle_deg):
    a = math.radians(angle_deg)
    return RAMP_HINGE + Vector((0.0, 2 * RAMP_PANEL * math.cos(a), 2 * RAMP_PANEL * math.sin(a)))


def pose(leaf, upper, lower, deployed: bool):
    leaf.rotation_euler = (0.0, 0.0, math.radians(HATCH_OPEN if deployed else 0.0))
    upper.rotation_euler = (math.radians(RAMP_DEPLOYED if deployed else RAMP_STOWED), 0.0, 0.0)
    lower.rotation_euler = (math.radians(0.0 if deployed else RAMP_LOWER_STOWED), 0.0, 0.0)
    bpy.context.view_layer.update()


# --- checks ---------------------------------------------------------------------------------

def ground():
    h = np.fromfile(PLAY, dtype="<f4").reshape(513, 513)

    def at(x, z):
        fx, fz = (x + 512) / 2.0, (z + 512) / 2.0
        j, i = int(fx), int(fz)
        tx, tz = fx - j, fz - i
        return (h[i, j] * (1 - tx) + h[i, j + 1] * tx) * (1 - tz) + (h[i + 1, j] * (1 - tx) + h[i + 1, j + 1] * tx) * tz

    yaw = math.radians(PLACE_YAW_DEG)
    bx = Vector((math.cos(yaw), -math.sin(yaw)))
    bz = Vector((math.sin(yaw), math.cos(yaw)))
    ox, oz = PLACE_XZ
    h0 = at(ox, oz)

    def local(x, y):
        p = Vector((ox, oz)) + bx * x + bz * (-y)
        return at(p.x, p.y) - h0
    return local


def checks(root, leaf, upper, lower):
    rows, failures = [], 0
    pose(leaf, upper, lower, True)
    meshes = [o for o in root.children_recursive if o.type == "MESH"]
    tris = sum(kit.triangle_count(o) for o in meshes)
    lo, hi = ws.bounds([o for o in meshes if not o.name.startswith("lander_ramp")])
    ok = tris <= BUDGET
    failures += 0 if ok else 1
    rows.append("%d triangles (budget %d)%s" % (tris, BUDGET, "" if ok else "  FAIL"))
    span = 2.0 * max(Vector((p.x, p.y)).length for o in meshes if not o.name.startswith("lander_ramp") for p in kit.world_vertices(o) if p.z < 0.05)
    ok = abs(hi.z - HEIGHT) < 0.03 and abs(span - PAD_SPAN) < 0.03
    failures += 0 if ok else 1
    rows.append("%.2f m tall, %.2f m across the footpads%s" % (hi.z, span, "" if ok else "  FAIL"))
    g = ground()
    buried = [0.04 + g(*polar_xy(PAD_CENTRE, az, 0.0).to_2d()) for az in LEG_AZIMUTHS]
    ok = all(-0.06 <= b <= 0.12 for b in buried)
    failures += 0 if ok else 1
    rows.append("footpads: bottoms %s m from the ground (+ = into it)%s" % (", ".join("%.3f" % b for b in buried), "" if ok else "  FAIL"))
    foot = ramp_foot(RAMP_DEPLOYED)
    gap = foot.z - g(foot.x, foot.y)
    ok = -0.08 <= gap <= 0.06
    failures += 0 if ok else 1
    rows.append("ramp at %.0f deg: foot (%.2f, %.2f, %.3f), %.3f m above the ground there%s" % (RAMP_DEPLOYED, foot.x, foot.y, foot.z, gap, "" if ok else "  FAIL"))
    pose(leaf, upper, lower, False)
    _, stowed_hi = ws.bounds([upper, lower])
    rows.append("Godot: ramp hinge (0, %.4f, %.4f), foot (0, %.4f, %.4f); nose top (y, z): %s" % (
        RAMP_HINGE.z, -RAMP_HINGE.y, foot.z, -foot.y, ", ".join("(%.4f, %.4f)" % (z, -y) for y, z, _ in nose())))
    rows.append("stowed: the folded ramp stands %.2f m high, in front of the hatch" % stowed_hi.z)
    ok = stowed_hi.z < CABIN_TOP
    failures += 0 if ok else 1
    pose(leaf, upper, lower, True)
    return rows, failures


def main():
    previews = kit.preview_dir("lander")
    kit.reset_scene()
    root, leaf, upper, lower = build()
    rows, failures = checks(root, leaf, upper, lower)
    for o in [root] + list(root.children_recursive):
        kit.check_export_name(o.name)
    pose(leaf, upper, lower, False)
    os.makedirs(PARTS_DIR, exist_ok=True)
    kit.save_blend(os.path.join(PARTS_DIR, "lander.blend"))
    ws.rk.GODOT_IMPORT_SCRIPT = ws.GODOT_IMPORT_SCRIPT
    kit.export_part(root, os.path.join(EXPORT_DIR, "lander.glb"))
    if previews:
        ws.set_preview_colors(True)
        pose(leaf, upper, lower, True)
        for name, d in (("front", (0.0, 1.0, 0.0)), ("side", (1.0, 0.0, 0.0)), ("rear", (0.0, -1.0, 0.0)),
                        ("top", (0.0, 0.0, 1.0))):
            kit.render_view(root, os.path.join(previews, "lander_%s.png" % name), d, 15.0, False, 1.0, (0.0, 1.5, 3.2), 900)
        kit.render_view(root, os.path.join(previews, "lander_three_quarter.png"), (0.8, 1.0, 0.35), 0, True, 34.0, (0.0, 1.5, 2.8), 900)
        kit.render_view(root, os.path.join(previews, "lander_hatch.png"), (0.35, 1.0, 0.25), 0, True, 14.0, (0.0, 2.2, 3.2), 900)
        kit.render_view(root, os.path.join(previews, "lander_under.png"), (0.6, 0.5, -0.25), 0, True, 24.0, (0.0, 0.0, 1.0), 900)
        pose(leaf, upper, lower, False)
        kit.render_view(root, os.path.join(previews, "lander_stowed.png"), (0.8, 1.0, 0.35), 0, True, 30.0, (0.0, 0.0, 3.2), 900)
        ws.set_preview_colors(False)
    rows.append("ALL CHECKS OK" if failures == 0 else "%d CHECK FAILURES" % failures)
    print("\n".join("LANDER_KIT lander " + r for r in rows))


if __name__ == "__main__":
    main()
