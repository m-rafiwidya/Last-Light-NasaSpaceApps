"""Generates the astronaut (tools/blender/ASTRONAUT_KIT.md): one combined, flat-shaded mesh in a
modern hard-armour suit, its skeleton (Godot humanoid bone names), the weights, the three poses
(T-pose, seated at the console, empty on its stand), the checks and every export.

    blender -b --factory-startup -P tools/blender/scripts/astronaut/make_astronaut.py [-- --previews DIR | --no-previews]

Needs tools/blender/parts/workshop/{console,shell,suit_props}.blend (make_console.py,
make_shell.py, make_suit_props.py) for the seated and stand checks. Writes
tools/blender/parts/astronaut/astronaut.blend and astronaut_mixamo.fbx,
game/res/models/astronaut_kit/{astronaut,astronaut_seated,astronaut_rack}.glb and previews in
tools/blender/previews/astronaut/<pose>/.

Character space: origin on the ground between the feet, facing -Y, its left at +X.
"""

import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree

sys.path.append(os.path.dirname(__file__))
import astronaut_kit_common as ak  # noqa: E402

SHELL, FABRIC, METAL, DARK, VISOR, ACCENT, LAMP = (ak.SHELL, ak.FABRIC, ak.METAL, ak.DARK, ak.VISOR, ak.ACCENT,
                                                   ak.LAMP)
HEIGHT = 1.80
SPAN = 1.90
# Regions and their triangle budgets (ASTRONAUT_KIT.md 8)
BUDGETS = {
    "helmet": 520, "visor": 100, "neck_ring": 90, "torso": 420, "shoulders": 200, "waist": 100,
    "chest_box": 160, "backpack": 240, "arms": 680, "gloves": 1240, "legs": 760, "boots": 540,
}
REGIONS = list(BUDGETS)
TOTAL_BUDGET = 5000

# Helmet (ASTRONAUT_KIT.md 4, 5): an ellipsoid dome under a 12 mm ridge whose top is HEIGHT
RIDGE = 0.012
HELMET_RADII = Vector((0.17, 0.17, 0.165))
HELMET_CENTRE = Vector((0.0, -0.045, HEIGHT - RIDGE - 0.165))
HELMET_RINGS = [1.515, 1.535, 1.575, 1.62, 1.665, 1.715, 1.748, 1.772, 1.785]
VISOR_RINGS = (1, 5)            # ring indices: the visor runs from z 1.535 to 1.715
VISOR_HALF_SEGMENTS = 3         # 3 of the 16 segments each side of the front: 135 degrees
VISOR_PROUD = 0.008
HELMET_SIDES = 16
LAMP_LENS = Vector((0.1625, -0.087, 1.69))


def helmet_point(z: float, phi: float) -> Vector:
    c, r = HELMET_CENTRE, HELMET_RADII
    s = math.sqrt(max(0.0, 1.0 - ((z - c.z) / r.z) ** 2))
    return Vector((c.x + r.x * s * math.cos(phi), c.y + r.y * s * math.sin(phi), z))


def helmet_normal(p: Vector) -> Vector:
    d = p - HELMET_CENTRE
    r = HELMET_RADII
    return Vector((d.x / r.x ** 2, d.y / r.y ** 2, d.z / r.z ** 2)).normalized()


def build_helmet(b: ak.Builder) -> None:
    """Dome (16 sides, a vertex at the front) with the visor region raised and its side walls in
    suit_metal, a ridge from brow to nape and two lamp pods. Rigid on UpperChest: the helmet rides
    the torso, as on a hard suit (ASTRONAUT_KIT.md 6.3)."""
    w = "UpperChest"
    b.set_side("Left")
    b.set_region("helmet")
    b.begin("helmet", w, sided=False)
    n = HELMET_SIDES
    phis = [-math.pi / 2.0 + 2.0 * math.pi * k / n for k in range(n)]
    grid = [[b.vert(helmet_point(z, phi), w) for phi in phis] for z in HELMET_RINGS]
    top = b.vert(HELMET_CENTRE + Vector((0.0, 0.0, HELMET_RADII.z)), w)
    visor_segments = {k % n for k in range(-VISOR_HALF_SEGMENTS, VISOR_HALF_SEGMENTS)}   # face k joins k, k+1
    r0, r1 = VISOR_RINGS
    raised = {}
    for i in range(r0, r1 + 1):
        for k in range(-VISOR_HALF_SEGMENTS, VISOR_HALF_SEGMENTS + 1):
            k %= n
            p = grid[i][k].co
            raised[(i, k)] = b.vert(p + helmet_normal(p) * VISOR_PROUD, w)
    c = HELMET_CENTRE
    visor_faces = []
    for i in range(len(HELMET_RINGS) - 1):
        for k in range(n):
            kn = (k + 1) % n
            if r0 <= i < r1 and k in visor_segments:
                continue
            q = (grid[i][k], grid[i][kn], grid[i + 1][kn], grid[i + 1][k])
            b.face(q, SHELL, sum((v.co for v in q), Vector()) / 4.0 - c)
    for k in range(n):
        q = (grid[-1][k], grid[-1][(k + 1) % n], top)
        b.face(q, SHELL, sum((v.co for v in q), Vector()) / 3.0 - c)
    b.set_region("visor")
    b.begin("visor", w, sided=False)
    for i in range(r0, r1):
        for k in visor_segments:
            kn = (k + 1) % n
            q = (raised[(i, k)], raised[(i, kn)], raised[(i + 1, kn)], raised[(i + 1, k)])
            visor_faces.append(b.face(q, VISOR, sum((v.co for v in q), Vector()) / 4.0 - c))
    # Side walls round the raised visor (its frame), in suit_metal
    middle = sum((v.co for v in raised.values()), Vector()) / len(raised)
    edges = []
    for k in visor_segments:
        edges += [((r0, k), (r0, (k + 1) % n)), ((r1, k), (r1, (k + 1) % n))]
    for i in range(r0, r1):
        edges += [((i, -VISOR_HALF_SEGMENTS % n), (i + 1, -VISOR_HALF_SEGMENTS % n)),
                  ((i, VISOR_HALF_SEGMENTS), (i + 1, VISOR_HALF_SEGMENTS))]
    for e0, e1 in edges:
        q = (grid[e0[0]][e0[1]], grid[e1[0]][e1[1]], raised[e1], raised[e0])
        b.face(q, METAL, sum((v.co for v in q), Vector()) / 4.0 - middle)

    # Ridge: brow to nape over the top, along the dome's centre line, 40 mm wide, 12 mm proud
    b.set_region("helmet")
    b.begin("helmet ridge", w, sided=False)
    sections = []
    for psi in (42, 58, 74, 90, 106, 122, 138, 154, 170):
        a = math.radians(psi)
        d = Vector((0.0, -math.cos(a), math.sin(a)))
        p = c + Vector((0.0, d.y * HELMET_RADII.y, d.z * HELMET_RADII.z))
        nrm = helmet_normal(p)
        pts = [(0.02, -0.004), (0.02, RIDGE), (-0.02, RIDGE), (-0.02, -0.004)]
        sections.append((p, Vector((1.0, 0.0, 0.0)), nrm, pts, w))
    b.loft(sections, METAL)

    # Lamp pods on the temples, dark lenses facing forward
    for side in ("Left", "Right"):
        b.set_side(side)
        b.begin("lamp pod", w)
        b.cbox((0.163, -0.045, 1.69), (0.032, 0.06, 0.034), 0.006, SHELL, w)
        b.box((0.151, -0.087, 1.678), (0.175, -0.073, 1.702), DARK, w)
    b.set_side("Left")


def build_neck_ring(b: ak.Builder) -> None:
    w = "UpperChest"
    b.set_region("neck_ring")
    b.begin("neck ring", w, sided=False)
    pts = [(0.0, -0.02, z) for z in (1.475, 1.485, 1.525, 1.535)]
    faces = b.tube(pts, [0.118, 0.128, 0.128, 0.112], 12, METAL, w, caps=(False, True))
    faces[-1].material_index = DARK    # the dark cap inside the ring (seen with the helmet off)


TORSO = [  # z, half width, half depth, centre y, weights, material of the band above
    (0.80, 0.12, 0.09, -0.005, "Hips", FABRIC),
    (0.85, 0.185, 0.125, -0.005, "Hips", FABRIC),
    (0.92, 0.20, 0.135, -0.005, "Hips", FABRIC),
    (0.99, 0.19, 0.13, -0.005, "Hips", FABRIC),
    (1.06, 0.185, 0.132, -0.005, "Spine", FABRIC),
    (1.13, 0.185, 0.14, -0.008, "Chest", FABRIC),
    # the hard upper torso starts with a 15 mm lip
    (1.135, 0.20, 0.156, -0.01, "UpperChest", SHELL),
    (1.24, 0.207, 0.162, -0.01, "UpperChest", SHELL),
    (1.35, 0.215, 0.162, -0.01, "UpperChest", SHELL),
    (1.43, 0.20, 0.155, -0.01, "UpperChest", SHELL),
    (1.48, 0.15, 0.12, -0.01, "UpperChest", SHELL),
    (1.50, 0.11, 0.10, -0.01, "UpperChest", SHELL),
]


def build_torso(b: ak.Builder) -> None:
    b.set_side("Left")
    b.set_region("torso")
    b.begin("torso", "Chest", sided=False)
    sections = [((0.0, yc, z), (1, 0, 0), (0, 1, 0), ak.superellipse(a, d, 16, 2.6), w)
                for z, a, d, yc, w, _ in TORSO]
    b.loft(sections, [row[5] for row in TORSO[:-1]])
    # Waist bearing, dark, on the Spine
    b.set_region("waist")
    b.begin("waist bearing", "Spine", sided=False)
    b.loft([((0.0, -0.005, z), (1, 0, 0), (0, 1, 0), ak.superellipse(a, d, 16, 2.6), "Spine")
            for z, a, d in ((1.005, 0.19, 0.132), (1.015, 0.203, 0.145), (1.065, 0.203, 0.146), (1.075, 0.192, 0.136))],
           DARK, caps=(False, False))
    # Shoulder cups: balls round the shoulder joints, so an arm leaves them cleanly at any angle
    b.set_region("shoulders")
    for side in ("Left", "Right"):
        b.set_side(side)
        b.begin("shoulder cup", "UpperChest")
        r = 0.095
        ts = (-0.085, -0.055, 0.0, 0.055, 0.085)
        b.tube([ak.SHOULDER + Vector((t, 0.0, 0.0)) for t in ts], [math.sqrt(r * r - t * t) for t in ts], 10, SHELL,
               "UpperChest")
    b.set_side("Left")
    # Chest control box: dark grey, two knobs, a T-lever and a small status window
    w = "UpperChest"
    b.set_region("chest_box")
    b.begin("chest box", w, sided=False)
    b.cbox((0.0, -0.205, 1.26), (0.30, 0.08, 0.15), 0.015, METAL, w, axis="y")
    for x in (-0.10, 0.10):
        b.tube([(x, -0.243, 1.30), (x, -0.262, 1.30)], [0.016, 0.016], 8, DARK, w, caps=(False, True))
    b.beam((0.0, -0.243, 1.215), (0.0, -0.268, 1.215), 0.012, 0.012, DARK, w)
    b.beam((-0.032, -0.274, 1.215), (0.032, -0.274, 1.215), 0.012, 0.014, ACCENT, w)
    b.box((-0.045, -0.247, 1.288), (0.045, -0.243, 1.318), LAMP, w)
    # Backpack: a big chamfered case, side ribs, a grab bar, a vent grille and one amber stripe
    b.set_region("backpack")
    b.begin("backpack", w, sided=False)
    b.cbox((0.0, 0.275, 1.305), (0.46, 0.25, 0.71), 0.03, SHELL, w)
    for side in ("Left", "Right"):
        b.set_side(side)
        b.box((0.229, 0.20, 1.00), (0.244, 0.34, 1.60), METAL, w)
        b.box((0.12, 0.31, 1.655), (0.14, 0.34, 1.70), METAL, w)
    b.set_side("Left")
    b.box((-0.15, 0.31, 1.70), (0.15, 0.34, 1.725), METAL, w)
    for z in (1.02, 1.06, 1.10):
        b.box((-0.15, 0.398, z), (0.15, 0.406, z + 0.02), DARK, w)
    b.box((-0.20, 0.398, 1.56), (0.20, 0.404, 1.59), ACCENT, w)


def along(x: float) -> Vector:
    """A point on the left arm's axis in the T-pose."""
    return Vector((x, 0.0, ak.SHOULDER.z))


def build_arm(b: ak.Builder, side: str) -> None:
    b.set_side(side)
    b.set_region("arms")
    b.begin("upper arm", "UpperArm")
    b.tube([along(x) for x in (0.22, 0.30, 0.43)], [0.066, 0.068, 0.062], 10, FABRIC, "UpperArm", caps=(False, False))
    b.tube([along(x) for x in (0.325, 0.33, 0.36, 0.365)], [0.066, 0.073, 0.073, 0.066], 10, ACCENT, "UpperArm",
           caps=(False, False))
    b.begin("elbow", "LowerArm")
    xs = (0.425, 0.445, 0.47, 0.49, 0.515, 0.535, 0.555)
    radii = (0.059, 0.068, 0.060, 0.068, 0.060, 0.067, 0.060)
    ts = (0.0, 0.2, 0.4, 0.55, 0.75, 0.9, 1.0)
    b.tube([along(x) for x in xs], list(radii), 10, DARK, [ak.blend("UpperArm", "LowerArm", t) for t in ts],
           caps=(False, False))
    b.begin("forearm", "LowerArm")
    b.tube([along(x) for x in (0.55, 0.66, 0.725)], [0.062, 0.063, 0.056], 10, FABRIC, "LowerArm", caps=(False, False))
    b.tube([along(x) for x in (0.715, 0.72, 0.755, 0.76)], [0.056, 0.066, 0.066, 0.058], 10, DARK, "LowerArm",
           caps=(False, False))


def octagon(hu: float, hv: float, ch: float) -> list:
    """A rectangle with its corners cut by `ch` (8 points, counter-clockwise)."""
    ch = min(ch, hu * 0.9, hv * 0.9)
    return [(hu, -hv + ch), (hu, hv - ch), (hu - ch, hv), (-hu + ch, hv), (-hu, hv - ch), (-hu, -hv + ch),
            (-hu + ch, -hv), (hu - ch, -hv)]


def segment(b: ak.Builder, rows: list, mats, w, up=(0.0, 0.0, 1.0)) -> list:
    """A glove segment: octagonal sections (point, half width, half height, chamfer) lofted along
    the line from the first to the last point, capped at both ends."""
    u, v = ak.frame(Vector(rows[-1][0]) - Vector(rows[0][0]), up)
    return b.loft([(p, u, v, octagon(hw, hh, ch), w) for p, hw, hh, ch in rows], mats)


def finger(b: ak.Builder, base: Vector, joint: Vector, tip: Vector, width: float, height: float, bones: tuple,
           up=(0.0, 0.0, 1.0)) -> list:
    """Two rounded segments, the far one tapering to a dark, rounded tip (the glove's grip pad)."""
    d0 = (joint - base).normalized()
    d1 = (tip - joint).normalized()
    hw, hh = width / 2.0, height / 2.0
    faces = segment(b, [(base, hw, hh, 0.007), (joint - d0 * 0.001, hw, hh, 0.007)], FABRIC, bones[0], up)
    faces += segment(b, [(joint + d1 * 0.001, hw * 0.96, hh * 0.92, 0.007),
                         (tip - d1 * 0.009, hw * 0.92, hh * 0.86, 0.007),
                         (tip, hw * 0.62, hh * 0.6, 0.005)], [FABRIC, DARK], bones[1], up)
    return faces


def build_glove(b: ak.Builder, side: str) -> None:
    """Armoured gauntlet: a flared cuff, a boxy hand with a dark palm under a hard back plate and a
    dark knuckle guard, four two-segment fingers and a thumb, rounded, with dark grip tips."""
    b.set_side(side)
    b.set_region("gloves")
    b.begin("glove", "Hand")
    b.tube([along(x) for x in (0.75, 0.765, 0.80, 0.81)], [0.06, 0.071, 0.067, 0.055], 10, SHELL, "Hand",
           caps=(False, False))
    b.cbox((0.84, 0.0, 1.418), (0.09, 0.118, 0.062), 0.016, lambda nrm: DARK if nrm.z < -0.5 else FABRIC, "Hand",
           axis="x")
    # Back plate (hard shell) and the knuckle guard across the finger roots
    b.cbox((0.833, 0.0, 1.452), (0.068, 0.098, 0.014), 0.006, SHELL, "Hand", axis="z")
    b.cbox((0.871, 0.0, 1.436), (0.024, 0.124, 0.030), 0.008, DARK, "Hand", axis="y")
    for name, y in ak.FINGER_Y.items():
        z = ak.WRIST.z + 0.003
        b.begin(name.lower() + " finger", name + "Proximal")
        faces = finger(b, Vector((ak.KNUCKLE_X - 0.004, y, z)), Vector((ak.FINGER_JOINT_X, y, z)),
                       Vector((ak.FINGERTIP_X - 0.001, y, z - 0.002)), 0.027, 0.036,
                       (name + "Proximal", name + "Intermediate"))
        palm_side(b, faces)
    b.begin("thumb", "ThumbProximal")
    p1 = ak.THUMB_BASE + ak.THUMB_DIR * ak.THUMB_LENGTHS[0]
    p2 = p1 + ak.THUMB_DIR * ak.THUMB_LENGTHS[1]
    faces = finger(b, ak.THUMB_BASE, p1, p2, 0.031, 0.031, ("ThumbProximal", "ThumbDistal"))
    palm_side(b, faces)


def palm_side(b: ak.Builder, faces: list) -> None:
    """Dark palm-side faces on a glove piece (FABRIC faces only: the tips are dark already)."""
    b.bm.normal_update()
    for f in faces:
        if f.normal.z < -0.5 and f.material_index == FABRIC:
            f.material_index = DARK


def leg_point(z: float) -> Vector:
    """A point on the left leg's axis in the T-pose (hip x 0.11 down to ankle x 0.12)."""
    t = (ak.HIP.z - z) / (ak.HIP.z - ak.ANKLE.z)
    return Vector((ak.HIP.x + (ak.ANKLE.x - ak.HIP.x) * t, 0.0, z))


def build_leg(b: ak.Builder, side: str) -> None:
    b.set_side(side)
    b.set_region("legs")
    up = (0.0, -1.0, 0.0)
    b.begin("thigh", "UpperLeg")
    b.tube([leg_point(z) for z in (0.878, 0.87, 0.83)], [0.090, 0.096, 0.096], 12, DARK, "UpperLeg",
           caps=(False, False), up=up)
    b.tube([leg_point(z) for z in (0.90, 0.80, 0.68, 0.615)], [0.082, 0.083, 0.078, 0.071], 12, FABRIC, "UpperLeg",
           caps=(False, False), up=up, aspect=1.18)
    b.begin("knee", "LowerLeg")
    zs = (0.615, 0.595, 0.57, 0.545, 0.515)
    b.tube([leg_point(z) for z in zs], [0.072, 0.081, 0.073, 0.081, 0.073], 12, DARK,
           [ak.blend("UpperLeg", "LowerLeg", t) for t in (0.0, 0.25, 0.5, 0.75, 1.0)], caps=(False, False), up=up)
    b.begin("shin", "LowerLeg")
    b.tube([leg_point(z) for z in (0.52, 0.40, 0.28)], [0.072, 0.074, 0.064], 12, FABRIC, "LowerLeg",
           caps=(False, False), up=up, aspect=1.08)
    b.begin("knee cap", "LowerLeg")
    b.cbox(leg_point(0.50) + Vector((0.0, -0.078, 0.0)), (0.125, 0.06, 0.13), 0.022, SHELL, "LowerLeg", axis="y")
    b.begin("shin plate", "LowerLeg")
    shin_plate(b, 0.445, 0.30, 0.072, 0.087, 62.0, "LowerLeg")


def shin_plate(b: ak.Builder, z_top: float, z_bottom: float, r_in: float, r_out: float, half_angle: float,
               w: str, segments: int = 5) -> None:
    """A hard plate curving round the front of the shin: outer and inner arcs at two heights."""
    rings = {}
    for z in (z_top, z_bottom):
        c = leg_point(z)
        for r in (r_in, r_out):
            rings[(z, r)] = [b.vert(c + Vector((r * math.sin(a), -r * math.cos(a), 0.0)), w)
                             for a in (math.radians(-half_angle + 2 * half_angle * k / segments) for k in range(segments + 1))]
    centre = leg_point((z_top + z_bottom) / 2.0)

    def quad(a, bb, c, d, out):
        b.face((a, bb, c, d), SHELL, out)
    for k in range(segments):
        for r, sign in ((r_out, 1.0), (r_in, -1.0)):
            q = (rings[(z_top, r)][k], rings[(z_top, r)][k + 1], rings[(z_bottom, r)][k + 1], rings[(z_bottom, r)][k])
            fc = sum((v.co for v in q), Vector()) / 4.0
            radial = fc - b.m(centre)
            radial.z = 0.0
            quad(*q, radial * sign)
        for z, sign in ((z_top, 1.0), (z_bottom, -1.0)):
            quad(rings[(z, r_in)][k], rings[(z, r_in)][k + 1], rings[(z, r_out)][k + 1], rings[(z, r_out)][k],
                 Vector((0.0, 0.0, sign)))
    for k, sign in ((0, -1.0), (segments, 1.0)):
        a = math.radians(-half_angle + 2 * half_angle * k / segments)
        q = (rings[(z_top, r_in)][k], rings[(z_top, r_out)][k], rings[(z_bottom, r_out)][k], rings[(z_bottom, r_in)][k])
        quad(*q, b.m(Vector((math.cos(a), math.sin(a), 0.0)) * sign))


def build_boot(b: ak.Builder, side: str) -> None:
    b.set_side(side)
    b.set_region("boots")
    w = "Foot"
    b.begin("boot", w)
    x = ak.ANKLE.x
    b.tube([(x, 0.0, z) for z in (0.31, 0.22, 0.13)], [0.077, 0.08, 0.084], 12, SHELL, w, caps=(False, False),
           up=(0.0, -1.0, 0.0))
    sole = 0.035
    rows = [(0.10, 0.052, 0.07), (0.085, 0.065, 0.105), (0.0, 0.07, 0.11), (-0.12, 0.072, 0.085), (-0.19, 0.066, 0.065),
            (-0.222, 0.05, 0.04)]
    sections = [((x, y, sole + h / 2.0), (1, 0, 0), (0, 0, 1), ak.superellipse(a, h / 2.0, 12, 3.0), w)
                for y, a, h in rows]
    b.loft(sections, SHELL)
    b.cbox((x, -0.062, sole / 2.0), (0.15, 0.33, sole), 0.01, DARK, w)
    b.box((x - 0.012, 0.074, 0.255), (x + 0.012, 0.088, 0.315), ACCENT, w)


def build_mesh() -> tuple:
    b = ak.Builder(REGIONS)
    build_helmet(b)
    build_neck_ring(b)
    build_torso(b)
    for side in ("Left", "Right"):
        build_arm(b, side)
        build_glove(b, side)
        build_leg(b, side)
        build_boot(b, side)
    regions = [f[b.region_layer] for f in b.bm.faces]
    parts = list(b.parts)
    face_parts = [f[b.part_layer] for f in b.bm.faces]
    obj = ak.mesh_from_builder("astronaut", b)
    return obj, regions, parts, face_parts


# --- Checks ----------------------------------------------------------------------------------

def region_triangles(obj, regions: list) -> dict:
    counts = {r: 0 for r in REGIONS}
    for poly in obj.data.polygons:
        counts[REGIONS[regions[poly.index]]] += len(poly.vertices) - 2
    return counts


def check_mesh(obj, regions: list, rows: list) -> int:
    failures = 0
    counts = region_triangles(obj, regions)
    total = sum(counts.values())
    for r in REGIONS:
        ok = counts[r] <= BUDGETS[r]
        failures += 0 if ok else 1
        rows.append("triangles %-10s %4d (budget %d)%s" % (r, counts[r], BUDGETS[r], "" if ok else "  FAIL"))
    ok = total <= TOTAL_BUDGET
    failures += 0 if ok else 1
    rows.append("triangles total      %4d (cap %d)%s" % (total, TOTAL_BUDGET, "" if ok else "  FAIL"))
    lo, hi = bounds(obj)
    height_ok = abs(hi.z - HEIGHT) <= 0.001 and abs(lo.z) <= 0.001
    span_ok = abs((hi.x - lo.x) - SPAN) <= 0.001
    failures += (0 if height_ok else 1) + (0 if span_ok else 1)
    rows.append("height %.3f m (sole %.3f), span %.3f m, depth %.3f m (y %.3f to %.3f)%s" % (
        hi.z, lo.z, hi.x - lo.x, hi.y - lo.y, lo.y, hi.y, "" if height_ok and span_ok else "  FAIL"))
    return failures


def bounds(obj) -> tuple:
    pts = [obj.matrix_world @ v.co for v in obj.data.vertices]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return lo, hi




# --- Skeleton and weights (ASTRONAUT_KIT.md 6) -----------------------------------------------

def build_armature() -> bpy.types.Object:
    data = bpy.data.armatures.new("astronaut_rig")
    arm = bpy.data.objects.new("astronaut_rig", data)
    bpy.context.scene.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    for name, (parent, head, tail) in ak.BONES.items():
        eb = data.edit_bones.new(name)
        eb.head, eb.tail = head, tail
        d = (tail - head).normalized()
        # Bone Z: up for bones lying flat (arms, hands, fingers, feet), forward for upright ones
        eb.align_roll(Vector((0.0, 0.0, 1.0)) if abs(d.z) < 0.7 else Vector((0.0, -1.0, 0.0)))
        if parent:
            eb.parent = data.edit_bones[parent]
            eb.use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")
    data.display_type = "STICK"
    return arm


def skin(obj, arm) -> None:
    obj.parent = arm
    modifier = obj.modifiers.new("Armature", "ARMATURE")
    modifier.object = arm


def check_weights(obj, parts: list, face_parts: list, rows: list) -> int:
    """Every vertex weighted, at most 4 influences, normalised; rigid parts on exactly one bone."""
    failures = 0
    names = [g.name for g in obj.vertex_groups]
    bad = {"unweighted": 0, "over 4 influences": 0, "not normalised": 0}
    vertex_bones = []
    for v in obj.data.vertices:
        groups = [(names[g.group], g.weight) for g in v.groups if g.weight > 0.0]
        vertex_bones.append({n for n, _ in groups})
        if not groups:
            bad["unweighted"] += 1
        if len(groups) > 4:
            bad["over 4 influences"] += 1
        if abs(sum(w for _, w in groups) - 1.0) > 1e-4:
            bad["not normalised"] += 1
    for k, n in bad.items():
        failures += 1 if n else 0
    rows.append("weights: %d vertices, %s%s" % (len(obj.data.vertices), ", ".join("%s %d" % kv for kv in bad.items()),
                                                "" if not any(bad.values()) else "  FAIL"))
    part_bones = [set() for _ in parts]
    for poly in obj.data.polygons:
        for vi in poly.vertices:
            part_bones[face_parts[poly.index]] |= vertex_bones[vi]
    blended = [parts[i][0] for i, bones in enumerate(part_bones) if len(bones) > 1]
    wrong = [parts[i][0] for i, bones in enumerate(part_bones) if len(bones) == 1 and bones != {parts[i][1]}]
    expected = {"torso", "Left elbow", "Right elbow", "Left knee", "Right knee", "Left index finger",
                "Left middle finger", "Left ring finger", "Left little finger", "Left thumb", "Right index finger",
                "Right middle finger", "Right ring finger", "Right little finger", "Right thumb"}
    unexpected = sorted(set(blended) - expected)
    ok = not unexpected and not wrong
    failures += 0 if ok else 1
    rows.append("rigid parts: %d of %d on one bone; blended by design: torso, elbows, knees; two-bone: fingers, thumbs%s" % (
        len(parts) - len(blended), len(parts), "" if ok else "  FAIL (blended: %s, wrong bone: %s)" % (unexpected, wrong)))
    return failures


# --- Poses (ASTRONAUT_KIT.md 6.2) --------------------------------------------------------------

def update() -> None:
    bpy.context.view_layer.update()


def reset_pose(arm) -> None:
    for pb in arm.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    update()


def rest3(arm, name: str) -> Matrix:
    return arm.data.bones[name].matrix_local.to_3x3()


def set_world(arm, name: str, delta: Matrix, head=None) -> None:
    """Turns a bone by `delta` (a rotation in armature space, from its rest orientation), keeping
    its posed head unless `head` is given."""
    pb = arm.pose.bones[name]
    update()
    m = (delta @ rest3(arm, name)).to_4x4()
    m.translation = Vector(head) if head is not None else pb.head
    pb.matrix = m
    update()


def delta_of(arm, name: str) -> Matrix:
    return arm.pose.bones[name].matrix.to_3x3() @ rest3(arm, name).inverted()


def aim_delta(f_rest: Vector, up_rest: Vector, f_new: Vector, up_hint: Vector) -> Matrix:
    """The rotation taking a bone's rest direction and 'up' to a new direction, with its up as
    close to `up_hint` as possible (no twist beyond that)."""
    def basis(f, up):
        f = f.normalized()
        up = (up - f * up.dot(f)).normalized()
        return Matrix((f, up.cross(f), up)).transposed()
    return basis(Vector(f_new), Vector(up_hint)) @ basis(Vector(f_rest), Vector(up_rest)).transposed()


def bone_dir(arm, name: str) -> Vector:
    b = arm.data.bones[name]
    return (b.tail_local - b.head_local).normalized()


def aim(arm, name: str, f_new, up_rest, up_hint) -> None:
    set_world(arm, name, aim_delta(bone_dir(arm, name), Vector(up_rest), Vector(f_new), Vector(up_hint)))


def two_bone(arm, upper: str, lower: str, target, pole, up_rest, up_hint) -> None:
    """Analytic two-bone reach: the lower bone's tail to `target`, the joint bent towards `pole`."""
    update()
    h = arm.pose.bones[upper].head.copy()
    a, b = arm.data.bones[upper].length, arm.data.bones[lower].length
    t = Vector(target)
    d = max(abs(a - b) + 1e-4, min((t - h).length, a + b - 1e-4))
    direction = (t - h).normalized()
    along_ = (a * a - b * b + d * d) / (2.0 * d)
    height = math.sqrt(max(0.0, a * a - along_ * along_))
    p = Vector(pole)
    p = (p - direction * p.dot(direction)).normalized()
    knee = h + direction * along_ + p * height
    aim(arm, upper, knee - h, up_rest, up_hint)
    aim(arm, lower, h + direction * d - knee, up_rest, up_hint)


def curl(arm, side: str, finger_degrees: float, thumb_degrees: float) -> None:
    """Curls the fingers towards the palm (both segments) and the thumb a little."""
    for finger in ak.FINGER_Y:
        for segment, share in (("Proximal", 1.0), ("Intermediate", 1.3)):
            name = side + finger + segment
            axis = bone_dir(arm, name).cross(Vector((0.0, 0.0, -1.0)))
            parent = arm.pose.bones[name].parent.name
            set_world(arm, name, delta_of(arm, parent) @ Matrix.Rotation(math.radians(finger_degrees * share), 3, axis))
    for segment in ("Proximal", "Distal"):
        name = side + "Thumb" + segment
        axis = bone_dir(arm, name).cross(Vector((0.0, 0.0, -1.0)))
        parent = arm.pose.bones[name].parent.name
        set_world(arm, name, delta_of(arm, parent) @ Matrix.Rotation(math.radians(thumb_degrees), 3, axis))


# Seated (character space, origin at the stool's centre on the floor, facing the console at -Y):
# hip joints over the seat so the pelvis rests 2 mm above it, knees under the desk, boots on the
# foot ring, gloves hovering over the deck's front edge
SEAT_HIP_Z = ak.ws.STOOL_SEAT_TOP + 0.10 + 0.002   # the pelvis bottom is 0.10 below the hip joints
SEAT_HIP_Y = -0.02
SEATED_ANKLE = Vector((0.125, -0.272, ak.ws.STOOL_RING_TOP + 0.002 + ak.ANKLE.z))
SEATED_WRIST = Vector((0.23, -0.33, 0.995))
SEATED_LEAN = (4.0, 7.0, 10.0)          # Spine, Chest, UpperChest, degrees forward


def pose_seated(arm) -> None:
    reset_pose(arm)
    hips_rest = ak.BONES["Hips"][1]
    set_world(arm, "Hips", Matrix.Identity(3),
              head=(0.0, SEAT_HIP_Y, SEAT_HIP_Z + (hips_rest.z - ak.HIP.z)))
    for name, degrees in zip(("Spine", "Chest", "UpperChest"), SEATED_LEAN):
        set_world(arm, name, Matrix.Rotation(math.radians(degrees), 3, "X"))
    for side, s in (("Left", 1.0), ("Right", -1.0)):
        ankle = Vector((s * SEATED_ANKLE.x, SEATED_ANKLE.y, SEATED_ANKLE.z))
        two_bone(arm, side + "UpperLeg", side + "LowerLeg", ankle, (0.0, -1.0, 0.3), (0.0, -1.0, 0.0), (0.0, -1.0, 0.0))
        set_world(arm, side + "Foot", Matrix.Identity(3))
        wrist = Vector((s * SEATED_WRIST.x, SEATED_WRIST.y, SEATED_WRIST.z))
        two_bone(arm, side + "UpperArm", side + "LowerArm", wrist, (s * 1.0, 0.4, -1.0), (0.0, 0.0, 1.0),
                 (s * 0.3, 0.0, 1.0))
        aim(arm, side + "Hand", (0.0, -1.0, -0.08), (0.0, 0.0, 1.0), (0.0, 0.0, 1.0))
        curl(arm, side, 12.0, 8.0)


def pose_rack(arm) -> None:
    """The empty suit on its stand: arms hanging 17 degrees out (clear of the torso's lip),
    forearms a little forward, palms in, fingers relaxed; legs straight."""
    reset_pose(arm)
    for side, s in (("Left", 1.0), ("Right", -1.0)):
        out = Vector((s, 0.0, 0.0))
        aim(arm, side + "UpperArm", (s * math.sin(math.radians(17)), 0.0, -math.cos(math.radians(17))),
            (0.0, 0.0, 1.0), out)
        forearm = Vector((s * 0.22, -0.22, -0.95)).normalized()
        aim(arm, side + "LowerArm", forearm, (0.0, 0.0, 1.0), out)
        aim(arm, side + "Hand", forearm, (0.0, 0.0, 1.0), out)
        curl(arm, side, 18.0, 10.0)


def keep_pose(arm, action_name: str) -> None:
    """Stores the current pose in the .blend as a one-key action (with a fake user)."""
    arm.animation_data_create()
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.keyframe_insert("location", frame=1, group=pb.name)
        pb.keyframe_insert("rotation_quaternion", frame=1, group=pb.name)
    action = arm.animation_data.action
    action.name = action_name
    action.use_fake_user = True
    arm.animation_data.action = None


def baked_mesh(obj, name: str, matrix: Matrix) -> bpy.types.Mesh:
    """The posed mesh (armature applied) as a new mesh, transformed by `matrix`."""
    update()
    depsgraph = bpy.context.evaluated_depsgraph_get()
    mesh = bpy.data.meshes.new_from_object(obj.evaluated_get(depsgraph), preserve_all_data_layers=True,
                                           depsgraph=depsgraph)
    mesh.transform(matrix)
    mesh.name = name
    return mesh


def posed_point(arm, bone: str, rest_point) -> Vector:
    pb = arm.pose.bones[bone]
    return pb.matrix @ arm.data.bones[bone].matrix_local.inverted() @ Vector(rest_point)


# --- Pose checks ------------------------------------------------------------------------------

def part_trees(mesh, face_parts: list, parts: list) -> list:
    verts = [v.co.copy() for v in mesh.vertices]
    polys = [[] for _ in parts]
    for poly in mesh.polygons:
        polys[face_parts[poly.index]].append(list(poly.vertices))
    trees = []
    for i in range(len(parts)):
        used = sorted({vi for p in polys[i] for vi in p})
        remap = {vi: k for k, vi in enumerate(used)}
        trees.append(BVHTree.FromPolygons([verts[vi] for vi in used], [[remap[vi] for vi in p] for p in polys[i]]))
    return trees


TORSO_BONES = {"Hips", "Spine", "Chest", "UpperChest"}
# Bones that carry no vertices: a part on a child of one of these is adjacent to its parent's part
EMPTY_BONES = {"Root", "Neck", "Head"} | {s + n for s in ("Left", "Right") for n in ("Shoulder", "ThumbMetacarpal", "Toes")}


def bone_parent(name: str) -> str:
    parent = ak.BONES[name][0]
    while parent in EMPTY_BONES:
        parent = ak.BONES[parent][0]
    return parent


def adjacent(a: tuple, b: tuple) -> bool:
    """Parts that may touch: the same bone, parent and child (through bones without vertices),
    and the torso (blended over the spine bones) with any part on those bones or their children."""
    ba, bb = a[1], b[1]
    if ba == bb or bone_parent(ba) == bb or bone_parent(bb) == ba:
        return True
    for x, y in ((a, b), (b, a)):
        if x[0] == "torso" and (y[1] in TORSO_BONES or bone_parent(y[1]) in TORSO_BONES):
            return True
    # The fingers' own segments and the knuckle line: neighbouring fingers on one hand
    return False


def check_interpenetration(mesh, face_parts: list, parts: list, pose: str, rows: list) -> int:
    trees = part_trees(mesh, face_parts, parts)
    hits = []
    for i in range(len(parts)):
        for j in range(i + 1, len(parts)):
            if adjacent(parts[i], parts[j]):
                continue
            if trees[i].overlap(trees[j]):
                hits.append("%s / %s" % (parts[i][0], parts[j][0]))
    rows.append("%s: no part inside another (%d non-adjacent pairs checked)%s" % (
        pose, sum(1 for i in range(len(parts)) for j in range(i + 1, len(parts)) if not adjacent(parts[i], parts[j])),
        "" if not hits else "  FAIL: " + ", ".join(hits)))
    return 1 if hits else 0


def mesh_tree(objects: list, skip=None) -> BVHTree:
    """One BVH of world-space polygons from several objects (skip(obj, poly) leaves faces out)."""
    verts, polys = [], []
    for o in objects:
        if o.type != "MESH" or "-convcolonly" in o.name:
            continue
        m = o.matrix_world
        base = len(verts)
        verts += [m @ v.co for v in o.data.vertices]
        for p in o.data.polygons:
            if skip is None or not skip(o, p):
                polys.append([base + vi for vi in p.vertices])
    return BVHTree.FromPolygons(verts, polys)


def least_distance(points: list, tree: BVHTree) -> tuple:
    best = (1e9, None)
    for p in points:
        hit = tree.find_nearest(p)
        if hit[0] is not None and hit[3] < best[0]:
            best = (hit[3], p)
    return best


def world_points(obj) -> list:
    m = obj.matrix_world
    return [m @ v.co for v in obj.data.vertices]


def part_points(obj, face_parts: list, parts: list, names: set) -> list:
    m = obj.matrix_world
    idx = {i for i, p in enumerate(parts) if p[0] in names}
    vs = {vi for poly in obj.data.polygons if face_parts[poly.index] in idx for vi in poly.vertices}
    return [m @ obj.data.vertices[vi].co for vi in vs]


def tree_of(obj) -> BVHTree:
    return mesh_tree([obj])


# --- Workshop placements (ASTRONAUT_KIT.md 7) ---------------------------------------------------

ws = ak.ws
SEATED_MATRIX = ak.rotation_z(-90.0)    # character -Y (its front) to kit -X (the console)
RACK_MATRIX = ak.rotation_z(180.0)      # character -Y to kit +Y (out of the stand)
HELMET_PARTS = {"helmet", "visor", "helmet ridge", "Left lamp pod", "Right lamp pod"}
WORKSHOP_BLENDS = {"console": ["ws_console"], "suit_props": ["ws_suit_stand", "ws_stool"],
                   "shell": ["ws_partition_window", "ws_partition_solid", "ws_partition_door"]}


def load_workshop() -> dict:
    """The console, stool, stand and partition modules at their kit positions."""
    out = {}
    for blend, names in WORKSHOP_BLENDS.items():
        for root in ws.rk.append_objects(os.path.join(ws.PARTS_DIR, blend + ".blend"), names):
            out[root.name] = root
    # The partition modules sit at the origin in shell.blend; place one of each where the layout does
    for name in ("ws_partition_window", "ws_partition_solid", "ws_partition_door"):
        out[name].hide_render = True
        for o in out[name].children_recursive:
            o.hide_render = True
    copies = []
    for part, y, _ in ws.PARTITION_MODULES:
        source = out[part]
        mapping = {}
        for o in [source] + list(source.children_recursive):
            dup = o.copy()
            bpy.context.scene.collection.objects.link(dup)
            dup.hide_render = False
            mapping[o] = dup
        for o, dup in mapping.items():
            if o.parent in mapping:
                dup.parent = mapping[o.parent]
                dup.matrix_parent_inverse = o.matrix_parent_inverse.copy()
        mapping[source].matrix_world = Matrix.Translation((ws.PARTITION_X, y, 0.0))
        copies.append(mapping[source])
    out["partition"] = copies
    update()
    return out


def all_objects(root) -> list:
    return [root] + list(root.children_recursive)


def check_seated(seated, wsparts: dict, face_parts: list, parts: list, rows: list) -> int:
    failures = 0
    suit_points = world_points(seated)
    suit_tree = tree_of(seated)
    console = all_objects(wsparts["ws_console"])
    console_tree = mesh_tree(console)
    gap, where = least_distance(suit_points, console_tree)
    crossing = bool(suit_tree.overlap(console_tree))
    ok = gap >= 0.02 and not crossing
    failures += 0 if ok else 1
    rows.append("seated: %.0f mm from the console (desk, deck, switches, screen housing), at (%.2f, %.2f, %.2f)%s" % (
        gap * 1000, *where, "" if ok else "  FAIL"))
    stool = wsparts["ws_stool"]
    stool_tree = tree_of(stool)
    touching = [p[0] for i, p in enumerate(parts) if tree_of_parts(seated, face_parts, parts, {p[0]}).overlap(stool_tree)]
    crossing = bool(touching)
    pelvis = min(p.z for p in part_points(seated, face_parts, parts, {"torso"})) - ws.STOOL_SEAT_TOP
    soles = min(p.z for p in part_points(seated, face_parts, parts, {"Left boot", "Right boot"})) - ws.STOOL_RING_TOP
    ok = not crossing and 0.0 <= pelvis <= 0.005 and 0.0 <= soles <= 0.005
    failures += 0 if ok else 1
    rows.append("seated: pelvis %.1f mm over the seat, soles %.1f mm over the foot ring, nothing inside the stool%s" % (
        pelvis * 1000, soles * 1000, "" if ok else "  FAIL (inside the stool: %s)" % ", ".join(touching)))
    lo, hi = ws.bounds([seated])
    rows.append("seated: x %.2f to %.2f (desk front 2.80), y %.2f to %.2f, helmet top %.2f m" % (lo.x, hi.x, lo.y, hi.y, hi.z))
    # Seen from the bay: rays at the mast camera's height (1.15 m) to the visor's middle, blocked by
    # the console and the partition's opaque faces (the glazing lets them through)
    visor = part_points(seated, face_parts, parts, {"visor"})
    target = sum(visor, Vector()) / len(visor)
    glass = bpy.data.materials.get("ws_glass")

    def see_through(o, p):
        return o.material_slots and glass is not None and o.material_slots[p.material_index].material == glass
    blockers = mesh_tree(console + [o for r in wsparts["partition"] for o in all_objects(r)], see_through)
    seen, total = 0, 0
    for x in (-2.0, -1.0, 0.0, 1.0):
        for y in (-2.0, -1.0, 0.0, 1.0, 2.0):
            eye = Vector((x, y, 1.15))
            d = target - eye
            total += 1
            if blockers.ray_cast(eye, d.normalized(), d.length - 0.01)[0] is None:
                seen += 1
    ok = seen > 0
    failures += 0 if ok else 1
    rows.append("seated: visor seen through the partition window from %d of %d bay points at 1.15 m (visor centre z %.2f)%s" % (
        seen, total, target.z, "" if ok else "  FAIL"))
    return failures


def check_rack(body, helmet, wsparts: dict, rows: list) -> int:
    failures = 0
    stand = wsparts["ws_suit_stand"]
    plate_top = ws.SUIT_STAND_PLATE
    pad_front = ws.SUIT_ON_STAND.y - 0.40

    def contact(o, p):
        c = o.matrix_world @ p.center
        n = o.matrix_world.to_3x3() @ p.normal
        return ((n.z > 0.9 and abs(c.z - plate_top) < 1e-3) or (n.y > 0.9 and abs(c.y - pad_front) < 0.005)
                or (n.z > 0.9 and abs(c.z - ws.SUIT_STAND_SHELF) < 1e-3))
    others = mesh_tree(all_objects(stand), contact)
    everything = mesh_tree(all_objects(stand))
    points = world_points(body) + world_points(helmet)
    gap, where = least_distance(points, others)
    crossing = bool(tree_of(body).overlap(everything)) or bool(tree_of(helmet).overlap(everything))
    ok = gap >= 0.02 and not crossing
    failures += 0 if ok else 1
    rows.append("stand: suit and helmet %.0f mm from the stand away from the plate, clamp pads and shelf, at (%.2f, %.2f, %.2f); nothing inside it%s" % (
        gap * 1000, *where, "" if ok else "  FAIL"))
    soles = min(p.z for p in world_points(body)) - plate_top
    # The clamp pads' faces: rays from them towards the suit (+Y) to the backpack's back face
    body_tree = tree_of(body)
    pad_z = plate_top + 1.25
    pads = min(body_tree.ray_cast(Vector((ws.SUIT_STAND.x + dx, pad_front - 0.002 - 1e-4, pad_z)),
                                  Vector((0.0, 1.0, 0.0)), 0.5)[3] or 1.0 for dx in (-0.115, 0.115))
    shelf = min(p.z for p in world_points(helmet)) - ws.SUIT_STAND_SHELF
    ok = all(0.0 <= g <= 0.005 for g in (soles, pads, shelf))
    failures += 0 if ok else 1
    rows.append("stand: boots %.1f mm over the plate, backpack %.1f mm from the clamp pads, helmet %.1f mm over its shelf%s" % (
        soles * 1000, pads * 1000, shelf * 1000, "" if ok else "  FAIL"))
    lo, hi = ws.bounds([body, helmet])
    box = [o for o in stand.children if o.name.startswith("ws_suit_stand-convcolonly")][0]
    blo, bhi = ws.bounds([box])
    inside = all(blo[i] - 1e-6 <= lo[i] and hi[i] <= bhi[i] + 1e-6 for i in range(3))
    walls = lo.y - (-ws.INNER_Y) >= 0.02 and ws.INNER_X - hi.x >= 0.02
    ok = inside and walls
    failures += 0 if ok else 1
    rows.append("stand: suit x %.2f to %.2f, y %.2f to %.2f, helmet top %.2f; %.0f mm to the south wall, %.0f mm to the east wall, inside the stand's collision box%s" % (
        lo.x, hi.x, lo.y, hi.y, hi.z, (lo.y + ws.INNER_Y) * 1000, (ws.INNER_X - hi.x) * 1000, "" if ok else "  FAIL"))
    return failures


# --- Mixamo pre-flight and FBX ---------------------------------------------------------------

def check_mixamo(obj, face_parts: list, parts: list, rows: list) -> int:
    failures = 0
    pts = [v.co for v in obj.data.vertices]
    tree = KDTree(len(pts))
    for i, p in enumerate(pts):
        tree.insert(p, i)
    tree.balance()
    worst = max(tree.find(Vector((-p.x, p.y, p.z)))[2] for p in pts)
    ok = worst <= 0.001
    failures += 0 if ok else 1
    rows.append("mixamo: mirror-symmetric to %.2f mm%s" % (worst * 1000, "" if ok else "  FAIL"))
    left = [p for p in part_points(obj, face_parts, parts, {"Left thigh"}) if p.z < 0.82]
    right = [p for p in part_points(obj, face_parts, parts, {"Right thigh"}) if p.z < 0.82]
    thighs = min(p.x for p in left) - max(p.x for p in right)
    torso = tree_of_parts(obj, face_parts, parts, {"torso", "waist bearing"})
    arm_pts = part_points(obj, face_parts, parts, {"Left upper arm", "Left elbow", "Left forearm", "Left glove"})
    arm_gap = least_distance([p for p in arm_pts if p.x > ak.SHOULDER.x + 0.095], torso)[0]
    ok = thighs >= 0.06 - 1e-4 and arm_gap >= 0.04
    failures += 0 if ok else 1
    rows.append("mixamo: T-pose arms level, %.0f mm between the thighs below the hip bearings, arms %.0f mm clear of the torso beyond the shoulder cups%s" % (
        thighs * 1000, arm_gap * 1000, "" if ok else "  FAIL"))
    return failures


def tree_of_parts(obj, face_parts: list, parts: list, names: set) -> BVHTree:
    idx = {i for i, p in enumerate(parts) if p[0] in names}
    verts = [obj.matrix_world @ v.co for v in obj.data.vertices]
    polys = [list(p.vertices) for p in obj.data.polygons if face_parts[p.index] in idx]
    return BVHTree.FromPolygons(verts, polys)


def export_fbx(obj, path: str, rows: list) -> int:
    """The T-pose mesh alone (no armature, no weights) for Mixamo's auto-rigger, then a re-import
    check: one mesh, 1.80 m tall, facing -Y."""
    mesh = obj.data.copy()
    copy = bpy.data.objects.new("astronaut", mesh) if "astronaut" not in bpy.data.objects else None
    if copy is None:
        copy = bpy.data.objects.new("astronaut_mixamo", mesh)
    bpy.context.scene.collection.objects.link(copy)
    for name in ("region", "part"):
        if name in mesh.attributes:
            mesh.attributes.remove(mesh.attributes[name])
    bpy.ops.object.select_all(action="DESELECT")
    copy.select_set(True)
    bpy.context.view_layer.objects.active = copy
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.fbx(filepath=path, use_selection=True, object_types={"MESH"},
                             apply_scale_options="FBX_SCALE_UNITS", axis_forward="-Z", axis_up="Y",
                             bake_space_transform=False, use_mesh_modifiers=False, mesh_smooth_type="FACE",
                             add_leaf_bones=False)
    bpy.data.objects.remove(copy)
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=path)
    imported = [o for o in bpy.data.objects if o not in before]
    meshes = [o for o in imported if o.type == "MESH"]
    update()
    lo, hi = ws.bounds(meshes)
    visor = bpy.data.materials.get("suit_visor")
    front = None
    if meshes:
        m = meshes[0]
        vz = [m.matrix_world @ p.center for p in m.data.polygons
              if m.material_slots[p.material_index].material and m.material_slots[p.material_index].material.name.startswith("suit_visor")]
        front = sum(vz, Vector()) / len(vz) if vz else None
    ok = len(meshes) == 1 and abs(hi.z - lo.z - HEIGHT) <= 0.002 and front is not None and front.y < 0.0
    for o in imported:
        bpy.data.objects.remove(o)
    for m in [m for m in bpy.data.materials if m.users == 0]:
        bpy.data.materials.remove(m)
    del visor
    rows.append("fbx: %s, re-imported: %d mesh, %.3f m tall, visor at y %.2f (faces -Y)%s" % (
        os.path.relpath(path, ak.REPO_ROOT), len(meshes), hi.z - lo.z, front.y if front else float("nan"),
        "" if ok else "  FAIL"))
    return 0 if ok else 1


# --- Export ------------------------------------------------------------------------------------

def strip_attributes(mesh) -> None:
    for name in ("region", "part"):
        if name in mesh.attributes:
            mesh.attributes.remove(mesh.attributes[name])


def static_object(name: str, mesh, location) -> bpy.types.Object:
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = location
    for poly in mesh.polygons:
        poly.use_smooth = False
    return obj


def split_helmet(mesh, face_parts: list, parts: list) -> tuple:
    """(body mesh, helmet mesh) from a baked mesh: the helmet's parts come off for the stand."""
    idx = {i for i, p in enumerate(parts) if p[0] in HELMET_PARTS}
    out = []
    for keep_helmet in (False, True):
        bm = bmesh.new()
        bm.from_mesh(mesh)
        bm.faces.ensure_lookup_table()
        doomed = [f for f in bm.faces if (face_parts[f.index] in idx) != keep_helmet]
        bmesh.ops.delete(bm, geom=doomed, context="FACES")
        loose = [v for v in bm.verts if not v.link_faces]
        bmesh.ops.delete(bm, geom=loose, context="VERTS")
        m = mesh.copy()
        bm.to_mesh(m)
        bm.free()
        out.append(m)
    return tuple(out)


def export_static(root, path: str) -> None:
    saved = root.location.copy()
    root.location = (0.0, 0.0, 0.0)
    update()
    ak.export_glb(root, path)
    root.location = saved
    update()


# --- Previews ----------------------------------------------------------------------------------

def render_t_pose(obj, previews: str) -> None:
    focus = (0.0, 0.0, 0.9)
    for name, direction in (("front", (0.0, -1.0, 0.0)), ("side", (1.0, 0.0, 0.0)), ("back", (0.0, 1.0, 0.0)),
                            ("top", (0.0, 0.0, 1.0))):
        ak.render(obj, os.path.join(previews, name + ".png"), direction, 2.1, focus=focus if name != "top" else (0, 0, 0))
    ak.render(obj, os.path.join(previews, "three_quarter.png"), (0.7, -1.0, 0.35), 2.0, True, 6.5, focus)
    ak.render(obj, os.path.join(previews, "back_three_quarter.png"), (-0.7, 1.0, 0.35), 2.0, True, 6.5, focus)
    ak.render(obj, os.path.join(previews, "helmet.png"), (0.6, -1.0, 0.25), 0.6, True, 2.2, (0.0, -0.05, 1.55))
    ak.render(obj, os.path.join(previews, "glove.png"), (0.3, -1.0, 0.6), 0.3, True, 1.4, (0.84, 0.0, 1.42))
    ak.render(obj, os.path.join(previews, "knee.png"), (0.5, -1.0, 0.2), 0.5, True, 1.8, (0.11, 0.0, 0.5))


def render_seated(seated, wsparts: dict, previews: str) -> None:
    keep = tuple(all_objects(wsparts["ws_console"])) + (wsparts["ws_stool"],)
    focus = (-0.25, 0.0, 0.85)
    ak.render(seated, os.path.join(previews, "from_operator_area.png"), (1.0, 0.8, 0.45), 2.0, True, 5.0, focus, keep)
    ak.render(seated, os.path.join(previews, "side.png"), (0.0, -1.0, 0.05), 1.9, focus=focus, keep_visible=keep)
    ak.render(seated, os.path.join(previews, "from_bay.png"), (-1.0, -0.35, 0.25), 2.0, True, 5.0, focus, keep)
    ak.render(seated, os.path.join(previews, "hands.png"), (0.4, -0.9, 0.9), 0.8, True, 2.4, (-0.38, 0.0, 0.98), keep)


def render_rack(body, wsparts: dict, previews: str) -> None:
    keep = tuple(all_objects(wsparts["ws_suit_stand"]))
    focus = (0.0, -0.2, 1.05)
    ak.render(body, os.path.join(previews, "front.png"), (0.0, 1.0, 0.1), 2.4, focus=focus, keep_visible=keep)
    ak.render(body, os.path.join(previews, "three_quarter.png"), (0.7, 1.0, 0.35), 2.4, True, 6.5, focus, keep)
    ak.render(body, os.path.join(previews, "side.png"), (1.0, 0.0, 0.05), 2.4, focus=focus, keep_visible=keep)
    ak.render(body, os.path.join(previews, "helmet_on_shelf.png"), (0.4, 1.0, 0.5), 0.8, True, 2.6, (0.0, -0.25, 1.95), keep)


# --- Main --------------------------------------------------------------------------------------

def main() -> None:
    args = ak.rk.script_args()
    previews = None if "--no-previews" in args else True
    ak.rk.reset_scene()
    obj, regions, parts, face_parts = build_mesh()
    arm = build_armature()
    skin(obj, arm)
    rows = []
    failures = check_mesh(obj, regions, rows)
    failures += check_weights(obj, parts, face_parts, rows)
    failures += check_mixamo(obj, face_parts, parts, rows)
    wsparts = load_workshop()

    # T-pose
    reset_pose(arm)
    failures += check_interpenetration(baked_mesh(obj, "check_t", Matrix.Identity(4)), face_parts, parts, "T-pose", rows)

    # Seated at the console (kit frame: origin at the stool's centre, facing -X)
    pose_seated(arm)
    seated_mesh = baked_mesh(obj, "astronaut_seated", Matrix.Identity(4))
    failures += check_interpenetration(seated_mesh, face_parts, parts, "seated", rows)
    seated_mesh.transform(SEATED_MATRIX)
    lights = [SEATED_MATRIX @ posed_point(arm, "UpperChest", Vector((s * LAMP_LENS.x, LAMP_LENS.y, LAMP_LENS.z)))
              for s in (1.0, -1.0)]
    keep_pose(arm, "pose_seated")
    seated = static_object("astronaut_seated", seated_mesh, ws.SEAT)
    for side, p in zip(("L", "R"), lights):
        ws.add_empty(seated, "pivot_helmet_light_" + side, Vector(ws.SEAT) + p.to_3d())
    failures += check_seated(seated, wsparts, face_parts, parts, rows)

    # Empty on the stand (kit frame: origin at anchor_suit, facing +Y), the helmet on its shelf
    pose_rack(arm)
    rack_mesh = baked_mesh(obj, "astronaut_rack", Matrix.Identity(4))
    failures += check_interpenetration(rack_mesh, face_parts, parts, "rack", rows)
    keep_pose(arm, "pose_rack")
    body_mesh, helmet_mesh = split_helmet(rack_mesh, face_parts, parts)
    body_mesh.transform(RACK_MATRIX)
    helmet_mesh.transform(RACK_MATRIX)
    # The helmet's own origin: its centre, sitting on the shelf's middle
    hp = [v.co for v in helmet_mesh.vertices]
    centre = Vector(((min(p.x for p in hp) + max(p.x for p in hp)) / 2.0, (min(p.y for p in hp) + max(p.y for p in hp)) / 2.0,
                     min(p.z for p in hp)))
    helmet_mesh.transform(Matrix.Translation(-centre))
    body = static_object("astronaut_rack", body_mesh, ws.SUIT_ON_STAND)
    helmet = static_object("astronaut_helmet", helmet_mesh, (ws.SUIT_STAND.x, ws.SUIT_STAND.y + 0.20, ws.SUIT_STAND_SHELF + 0.002))
    update()
    ws.rk.parent_keep_transform(helmet, body)
    failures += check_rack(body, helmet, wsparts, rows)
    reset_pose(arm)

    # Exports
    for m in (seated_mesh, body_mesh, helmet_mesh):
        strip_attributes(m)
    os.makedirs(ak.EXPORT_DIR, exist_ok=True)
    ak.export_glb(arm, os.path.join(ak.EXPORT_DIR, "astronaut.glb"), skins=True)
    export_static(seated, os.path.join(ak.EXPORT_DIR, "astronaut_seated.glb"))
    export_static(body, os.path.join(ak.EXPORT_DIR, "astronaut_rack.glb"))
    failures += export_fbx(obj, os.path.join(ak.PARTS_DIR, "astronaut_mixamo.fbx"), rows)
    rows.append("exports: astronaut.glb (rigged T-pose, %d bones), astronaut_seated.glb, astronaut_rack.glb (with astronaut_helmet)" % len(ak.BONES))

    if previews:
        ak.set_preview_colors(True)
        ws.set_preview_colors(True)
        render_t_pose(obj, ak.preview_dir("t_pose"))
        render_seated(seated, wsparts, ak.preview_dir("seated"))
        render_rack(body, wsparts, ak.preview_dir("rack"))
        ak.set_preview_colors(False)
        ws.set_preview_colors(False)

    # The .blend keeps the rig, the T-pose mesh, the two pose actions and the baked statics
    for root in list(wsparts.values()):
        for r in (root if isinstance(root, list) else [root]):
            for o in reversed(all_objects(r)):
                bpy.data.objects.remove(o)
    for o in [o for o in bpy.data.objects if o.type == "MESH" and o.users == 0]:
        bpy.data.objects.remove(o)
    ak.rk.save_blend(os.path.join(ak.PARTS_DIR, "astronaut.blend"))
    rows.append("ALL CHECKS OK" if failures == 0 else "%d CHECK FAILURES" % failures)
    print("\n".join("ASTRONAUT_KIT " + line for line in rows))


if __name__ == "__main__":
    main()
