"""Generates the diagnostic cartridge (A06, KITE_KIT.md 4), a rover kit part, checks it and renders
previews.

    blender -b --factory-startup -P tools/blender/scripts/kite/make_cartridge.py [-- --previews DIR | --no-previews]

Writes tools/blender/parts/cartridge.blend, game/res/models/rover_kit/cartridge.glb and previews in
tools/blender/previews/cartridge/.

Rover frame, modelled where it rides: on the cargo mount, origin (the middle of its bottom face)
at socket_cargo_item (-0.125, 0.20, 0.505); long side along X.
    cartridge      0.25 x 0.15 x 0.08 m case, chamfered corners, ribbed grips on the ends, a
                   rover_gold stripe, a flush latch disc and a label panel on the top
    anchor_latch   (0, 0, 0.08) from the origin: the arm turret's pivot_latch meets it here
    anchor_pickup  (0, 0, 0.04): its middle
Budget 250 triangles.
"""

import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

sys.path.append(os.path.join(os.path.dirname(__file__), ".."))
import rover_kit_common as kit  # noqa: E402

BUDGET = 250
ORIGIN = Vector((-0.125, 0.20, 0.505))
HX, HY, H = 0.125, 0.075, 0.08
CHAMFER = 0.012
SIZE = (2 * HX, 2 * HY, H)


def outline(hx: float, hy: float, c: float) -> list:
    """Octagon: a rectangle with chamfered corners, counter-clockwise."""
    return [(hx - c, -hy), (hx, -hy + c), (hx, hy - c), (hx - c, hy), (-hx + c, hy), (-hx, hy - c), (-hx, -hy + c),
            (-hx + c, -hy)]


def place_at(z0: float):
    return lambda u, v, w: (ORIGIN.x + u, ORIGIN.y + v, ORIGIN.z + z0 + w)


def make_cartridge():
    bm = bmesh.new()
    case = kit.prism(bm, outline(HX, HY, CHAMFER), place_at(0.0), 0.0, H)
    for f in case:
        f.material_index = 0
    bmesh.ops.recalc_face_normals(bm, faces=case)
    # Gold stripe round the middle, 2 mm proud
    band = kit.prism(bm, outline(HX + 0.002, HY + 0.002, CHAMFER), place_at(0.0), 0.035, 0.045, False, False)
    for f in band:
        f.material_index = 2
    bmesh.ops.recalc_face_normals(bm, faces=band)
    # Ribbed grips on the two short ends
    for sign in (-1.0, 1.0):
        x = ORIGIN.x + sign * HX
        for k in (-1, 0, 1):
            y = ORIGIN.y + k * 0.03
            xs = (x, x + 0.006) if sign > 0 else (x - 0.006, x)
            kit.box(bm, xs, (y - 0.008, y + 0.008), (ORIGIN.z + 0.012, ORIGIN.z + 0.068), 1)
    # Flush latch disc and label panel on the top (decals 0.5 mm proud)
    top = ORIGIN.z + H + 0.0005
    disc = [bm.verts.new((ORIGIN.x + 0.03 * math.cos(a), ORIGIN.y + 0.03 * math.sin(a), top))
            for a in [2 * math.pi * k / 8 for k in range(8)]]
    f = bm.faces.new(disc)
    f.material_index = 1
    label = [bm.verts.new((ORIGIN.x + x, ORIGIN.y + y, top)) for x, y in ((0.045, -0.045), (0.115, -0.045), (0.115, 0.045), (0.045, 0.045))]
    f = bm.faces.new(label)
    f.material_index = 3
    bm.normal_update()
    for face in bm.faces:
        if abs(face.calc_center_median().z - top) < 1e-5 and face.normal.z < 0.0:
            face.normal_flip()
    obj = kit.mesh_object("cartridge", bm, [kit.get_material(m) for m in ("rover_dark", "rover_metal", "rover_gold", "rover_body")])
    # Mesh built in the rover frame: move the origin to the bottom face's centre
    obj.data.transform(__import__("mathutils").Matrix.Translation(-ORIGIN))
    obj.location = ORIGIN
    bpy.context.view_layer.update()
    col = bmesh.new()
    kit.box(col, (ORIGIN.x - HX, ORIGIN.x + HX), (ORIGIN.y - HY, ORIGIN.y + HY), (ORIGIN.z, ORIGIN.z + H))
    kit.make_collision_child(obj, col)
    collider = obj.children[0]
    collider.data.transform(__import__("mathutils").Matrix.Translation(-ORIGIN))
    collider.location = (0.0, 0.0, 0.0)
    kit.add_socket(obj, "anchor_latch", ORIGIN + Vector((0.0, 0.0, H)))
    kit.add_socket(obj, "anchor_pickup", ORIGIN + Vector((0.0, 0.0, H / 2.0)))
    return obj


def run_checks(obj, rows: list) -> int:
    failures = 0
    tris = kit.triangle_count(obj)
    ok = tris <= BUDGET
    failures += 0 if ok else 1
    rows.append("cartridge: %d triangles (budget %d)%s" % (tris, BUDGET, "" if ok else "  FAIL"))
    verts = kit.world_vertices(obj)
    lo = Vector((min(v.x for v in verts), min(v.y for v in verts), min(v.z for v in verts)))
    hi = Vector((max(v.x for v in verts), max(v.y for v in verts), max(v.z for v in verts)))
    case = (2 * HX, 2 * HY, H)
    rows.append("case %.3f x %.3f x %.3f m (spec 0.250 x 0.150 x 0.080); with grips, stripe and decals %.3f x %.3f x %.4f" % (
        case + (hi.x - lo.x, hi.y - lo.y, hi.z - lo.z)))
    ok = abs(lo.z - ORIGIN.z) < 1e-6 and hi.z - ORIGIN.z <= H + 0.001
    failures += 0 if ok else 1
    rows.append("origin on the bottom face, top at +%.4f m%s" % (hi.z - ORIGIN.z, "" if ok else "  FAIL"))
    for child in obj.children:
        kit.check_export_name(child.name)
        if child.type == "EMPTY":
            rows.append("%s at %s from the origin" % (child.name, tuple(round(c, 3) for c in child.location)))
    names = {m.name for m in obj.data.materials}
    ok = names <= set(kit.PALETTE)
    failures += 0 if ok else 1
    rows.append("materials %s%s" % (sorted(names), "" if ok else "  FAIL"))
    return failures


def main() -> None:
    previews = kit.preview_dir("cartridge")
    kit.reset_scene()
    obj = make_cartridge()
    rows = []
    failures = run_checks(obj, rows)
    kit.save_blend(os.path.join(kit.PARTS_DIR, "cartridge.blend"))
    kit.export_part(obj, os.path.join(kit.EXPORT_DIR, "cartridge.glb"))
    if previews:
        kit.set_preview_colors(True)
        for name, d in (("three_quarter", (0.8, -1.0, 0.7)), ("top", (0.0, 0.0, 1.0)), ("end", (1.0, 0.0, 0.0)),
                        ("side", (0.0, -1.0, 0.0))):
            kit.render_view(obj, os.path.join(previews, "cartridge_%s.png" % name), d, 0.36, name == "three_quarter", 1.0,
                            (0.0, 0.0, 0.04))
        kit.set_preview_colors(False)
    rows.append("ALL CHECKS OK" if failures == 0 else "%d CHECK FAILURES" % failures)
    print("\n".join("KITE_KIT cartridge " + r for r in rows))


if __name__ == "__main__":
    main()
