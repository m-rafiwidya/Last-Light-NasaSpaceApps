"""Generates wheel_L and wheel_R for the rover kit (ROVER_KIT.md 3.1, 6.2).

    blender -b --factory-startup -P tools/blender/scripts/make_wheel.py [-- --previews DIR | --no-previews]

Writes tools/blender/parts/wheel.blend, game/res/models/rover_kit/wheel_L.glb / wheel_R.glb and
preview renders in tools/blender/previews/wheel/.

Wheel local axes (Blender): axle along X, origin at the wheel centre. wheel_R's inner face
(toward the chassis) is at -X; wheel_L is its mirror. Budget: 400 triangles per wheel:
    tread 128 (32-vertex rings: 16 grouser crests + 16 troughs, centre ring twisted = chevrons)
    drum lips 96 + drum inner surface 32 (open drum, 16 sides inside)
    6 curved spokes x 16 (two segments each)
    hub 20 (hexagonal) + keyed connector plug 28
"""

import math
import os
import sys

import bmesh
from mathutils import Vector

sys.path.append(os.path.dirname(__file__))
import rover_kit_common as kit  # noqa: E402

TRIANGLE_BUDGET = 400

# Tyre (physics radius 0.15 = grouser crest)
R_CREST = 0.15
R_TROUGH = 0.14
R_DRUM_INNER = 0.128
HALF_WIDTH = 0.12
SIDES = 16
# Chevron: the centre ring leads the edges by this angle. Negative phi is ahead when
# rolling forward (+Y), so the V points forward at the top of the wheel.
CHEVRON_SHIFT = math.radians(-10.0)

# Spokes: flat curved flexures near the outer face (+X on wheel_R)
SPOKE_COUNT = 6
SPOKE_X = (0.070, 0.086)
SPOKE_WIDTH = 0.014
# (radius, angle offset) along each spoke: from inside the hub to inside the drum wall
# Each spoke sweeps one way (bending about 25 degrees at the middle point) so it reads as a curve
SPOKE_PATH = ((0.028, 0.0), (0.085, math.radians(14.0)), (0.134, math.radians(36.0)))

# Hub (rover_metal), from the inner face to just proud of the spokes
HUB_RADIUS = 0.04
HUB_X = (-HALF_WIDTH, 0.09)

# Standard connector plug (ROVER_KIT.md 2.5): diameter 44 mm, 8 mm proud of the inner face,
# 8 mm key notch at +Z, 4 mm deep
PLUG_RADIUS = 0.022
PLUG_DEPTH = 0.008
KEY_HALF_WIDTH = 0.004
KEY_DEPTH = 0.004

DARK = 0
METAL = 1


def ring(bm, x: float, radii: list, angles: list, shift: float = 0.0) -> list:
    return [bm.verts.new((x,) + kit.polar(r, a + shift)) for r, a in zip(radii, angles)]


def build_tyre(bm) -> list:
    """Open drum with chevron grousers. Returns its faces."""
    faces = []
    count = SIDES * 2
    step = 2.0 * math.pi / count
    angles = [i * step for i in range(count)]
    radii = [R_CREST if i % 2 == 0 else R_TROUGH for i in range(count)]
    inner_side = ring(bm, -HALF_WIDTH, radii, angles)
    centre = ring(bm, 0.0, radii, angles, CHEVRON_SHIFT)
    outer_side = ring(bm, HALF_WIDTH, radii, angles)

    for a, b in ((inner_side, centre), (centre, outer_side)):
        for i in range(count):
            j = (i + 1) % count
            faces.append(bm.faces.new((a[i], a[j], b[j], b[i])))

    drum_angles = [k * 2.0 * math.pi / SIDES for k in range(SIDES)]
    drum_radii = [R_DRUM_INNER] * SIDES
    drum_in = ring(bm, -HALF_WIDTH, drum_radii, drum_angles)
    drum_out = ring(bm, HALF_WIDTH, drum_radii, drum_angles)
    for k in range(SIDES):
        n = (k + 1) % SIDES
        faces.append(bm.faces.new((drum_in[k], drum_out[k], drum_out[n], drum_in[n])))
        for edge, drum in ((inner_side, drum_in), (outer_side, drum_out)):
            faces.append(bm.faces.new((edge[2 * k], edge[2 * k + 1], edge[(2 * k + 2) % count], drum[n], drum[k])))
    return faces


def build_spokes(bm) -> list:
    faces = []
    for s in range(SPOKE_COUNT):
        base = math.radians(30.0) + s * 2.0 * math.pi / SPOKE_COUNT
        points = [Vector(kit.polar(r, base + offset)) for r, offset in SPOKE_PATH]
        sections = []
        for i, p in enumerate(points):
            if i == 0:
                tangent = points[1] - p
            elif i == len(points) - 1:
                tangent = p - points[i - 1]
            else:
                tangent = (points[i + 1] - points[i - 1])
            tangent.normalize()
            side = Vector((-tangent.y, tangent.x)) * (SPOKE_WIDTH / 2.0)
            a, b = p - side, p + side
            sections.append([
                bm.verts.new((SPOKE_X[0], a.x, a.y)),
                bm.verts.new((SPOKE_X[1], a.x, a.y)),
                bm.verts.new((SPOKE_X[1], b.x, b.y)),
                bm.verts.new((SPOKE_X[0], b.x, b.y)),
            ])
        for a, b in zip(sections, sections[1:]):
            for c in range(4):
                d = (c + 1) % 4
                faces.append(bm.faces.new((a[c], a[d], b[d], b[c])))
    return faces


def build_hub(bm) -> list:
    angles = [math.radians(90.0 + 60.0 * k) for k in range(6)]
    radii = [HUB_RADIUS] * 6
    near = ring(bm, HUB_X[0], radii, angles)
    far = ring(bm, HUB_X[1], radii, angles)
    faces = [bm.faces.new(near), bm.faces.new(far)]
    for k in range(6):
        n = (k + 1) % 6
        faces.append(bm.faces.new((near[k], near[n], far[n], far[k])))
    return faces


def plug_profile() -> list:
    """(y, z) outline of the keyed plug: circle of 8 points with a notch cut at the top."""
    top_angle = math.asin(KEY_HALF_WIDTH / PLUG_RADIUS)
    top_z = PLUG_RADIUS * math.cos(top_angle)
    start = math.pi / 2.0 + top_angle
    arc = 2.0 * math.pi - 2.0 * top_angle
    outline = [kit.polar(PLUG_RADIUS, start + arc * k / 7.0) for k in range(8)]
    outline += [(KEY_HALF_WIDTH, top_z - KEY_DEPTH), (-KEY_HALF_WIDTH, top_z - KEY_DEPTH)]
    return outline


def build_plug(bm) -> list:
    outline = plug_profile()
    base = [bm.verts.new((-HALF_WIDTH, y, z)) for y, z in outline]
    tip = [bm.verts.new((-HALF_WIDTH - PLUG_DEPTH, y, z)) for y, z in outline]
    faces = [bm.faces.new(tip)]
    for k in range(len(outline)):
        n = (k + 1) % len(outline)
        faces.append(bm.faces.new((base[k], base[n], tip[n], tip[k])))
    return faces


def orient(bm, faces: list, outward) -> int:
    """Points every face away from its island's inside, using `outward(face)` (a vector
    that should agree with the normal). Returns how many faces had to be flipped."""
    flipped = [f for f in faces if f.normal.dot(outward(f)) < 0.0]
    bmesh.ops.reverse_faces(bm, faces=flipped)
    return len(flipped)


def radial(f) -> Vector:
    c = f.calc_center_median()
    return Vector((0.0, c.y, c.z))


def build_wheel_r_bmesh():
    bm = bmesh.new()
    tyre = build_tyre(bm)
    spokes = build_spokes(bm)
    hub = build_hub(bm)
    plug = build_plug(bm)
    bm.normal_update()

    def tyre_out(f):
        c = f.calc_center_median()
        if abs(abs(c.x) - HALF_WIDTH) < 1e-6 and abs(f.normal.x) > 0.9:  # lip
            return Vector((c.x, 0.0, 0.0))
        r = radial(f)
        # Tread faces sit outside the drum radius, the drum surface inside
        return r if r.length > R_DRUM_INNER + 0.005 else -r

    def cylinder_out(x_min, x_max):
        def out(f):
            c = f.calc_center_median()
            if abs(f.normal.x) > 0.9:
                return Vector((c.x - (x_min + x_max) / 2.0, 0.0, 0.0))
            return radial(f)
        return out

    flips = orient(bm, tyre, tyre_out)
    flips += orient(bm, hub, cylinder_out(*HUB_X))
    flips += orient(bm, plug, cylinder_out(-HALF_WIDTH - PLUG_DEPTH, -HALF_WIDTH))
    # Spokes: recalculating per island is reliable for these simple open tubes
    bmesh.ops.recalc_face_normals(bm, faces=spokes)

    for f in tyre + spokes:
        f.material_index = DARK
    for f in hub + plug:
        f.material_index = METAL
    return bm, flips


def collision_bmesh():
    bm = bmesh.new()
    sides = 12
    angles = [k * 2.0 * math.pi / sides for k in range(sides)]
    radii = [R_CREST] * sides
    a = ring(bm, -HALF_WIDTH, radii, angles)
    b = ring(bm, HALF_WIDTH, radii, angles)
    bm.faces.new(list(reversed(a)))
    bm.faces.new(b)
    for k in range(sides):
        n = (k + 1) % sides
        bm.faces.new((a[k], a[n], b[n], b[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def check_normals(obj) -> int:
    """Counts tread faces whose normal points toward the axle instead of away from it."""
    bad = 0
    mesh = obj.data
    for p in mesh.polygons:
        c, n = p.center, p.normal
        r = math.hypot(c.y, c.z)
        # Tread faces only: spokes end at r 0.134 and lips face along X
        if p.material_index == DARK and abs(n.x) < 0.9 and r > 0.136:
            radial_dir = Vector((0.0, c.y, c.z)).normalized()
            if n.dot(radial_dir) < 0.0:
                bad += 1
    return bad


def main() -> None:
    preview_dir = kit.preview_dir("wheel")

    kit.reset_scene()
    materials = [kit.get_material("rover_dark"), kit.get_material("rover_metal")]

    report = []
    wheels = {}
    for side in ("R", "L"):
        bm, flips = build_wheel_r_bmesh()
        if side == "L":
            kit.mirror_bmesh_x(bm)
        wheel = kit.mesh_object("wheel_" + side, bm, materials)
        wheel.location = (0.5 if side == "R" else -0.5, 0.5, 0.05)  # front wheel, rest pose
        kit.make_collision_child(wheel, collision_bmesh())
        wheels[side] = wheel

        tris = kit.triangle_count(wheel)
        xs = [v.co.x for v in wheel.data.vertices]
        ys = [v.co.y for v in wheel.data.vertices]
        zs = [v.co.z for v in wheel.data.vertices]
        report.append(
            "wheel_%s: %d triangles (budget %d), flipped while orienting: %d, bad tread normals: %d, "
            "bounds x [%.3f, %.3f] y [%.3f, %.3f] z [%.3f, %.3f]"
            % (side, tris, TRIANGLE_BUDGET, flips, check_normals(wheel), min(xs), max(xs),
               min(ys), max(ys), min(zs), max(zs))
        )
        if tris > TRIANGLE_BUDGET:
            raise RuntimeError("wheel_%s is over budget: %d" % (side, tris))

    kit.save_blend(os.path.join(kit.PARTS_DIR, "wheel.blend"))
    for side, wheel in wheels.items():
        kit.export_part(wheel, os.path.join(kit.EXPORT_DIR, "wheel_%s.glb" % side))

    if preview_dir:
        kit.set_preview_colors(True)
        right, left = wheels["R"], wheels["L"]
        views = [
            (right, "wheel_R_side_outer", (1.0, 0.0, 0.0), False, 0.0),
            (right, "wheel_R_inner", (-1.0, 0.0, 0.0), False, 0.0),
            (right, "wheel_R_front", (0.0, 1.0, 0.0), False, 0.0),
            (right, "wheel_R_three_quarter", (0.55, 0.75, 0.45), True, 1.3),
            (right, "wheel_R_plug_closeup", (-1.0, 0.35, 0.5), True, 0.35),
            (left, "wheel_L_inner", (1.0, 0.0, 0.0), False, 0.0),
            (left, "wheel_L_three_quarter", (-0.55, 0.75, 0.45), True, 1.3),
        ]
        plug_focus = (-HALF_WIDTH - PLUG_DEPTH, 0.0, 0.0)
        for obj, name, direction, perspective, distance in views:
            focus = plug_focus if name.endswith("plug_closeup") else (0.0, 0.0, 0.0)
            kit.render_view(obj, os.path.join(preview_dir, name + ".png"), direction, 0.36,
                            perspective, distance, focus)
        kit.set_preview_colors(False)
        kit.render_view(wheels["R"], os.path.join(preview_dir, "wheel_R_palette.png"),
                        (0.55, 0.75, 0.45), 0.36, True, 1.3)

    print("\n".join(["ROVER_KIT " + line for line in report]))


main()
