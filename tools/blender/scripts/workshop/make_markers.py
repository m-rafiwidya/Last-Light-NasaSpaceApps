"""Generates the navigation and dock markers (A07, WORKSHOP_KIT.md 6.4): a marker post with its
beacon, three 0.40 m signs, a floor chevron, a floor stripe and the sign over the bay door.
Checks and previews.

    blender -b --factory-startup -P tools/blender/scripts/workshop/make_markers.py [-- --previews DIR | --no-previews]

Writes tools/blender/parts/workshop/markers.blend, one GLB per marker in
game/res/models/workshop_kit/ and previews in tools/blender/previews/workshop/markers/.

Origins: the post at the middle of its foot on the ground; signs at the middle of their back
face (they mount on the post's anchor_sign or on a wall), facing +Y; floor markings at their
centre on the floor, the chevron pointing +Y, the stripe along X.
"""

import os
import sys

import bpy

sys.path.append(os.path.dirname(__file__))
import workshop_kit_common as ws  # noqa: E402

BUDGETS = {"ws_marker_post": 250, "ws_sign_route": 120, "ws_sign_base": 120, "ws_sign_heritage": 120,
           "ws_floor_chevron": 12, "ws_floor_stripe": 12, "ws_door_sign": 60}
SIGN_W, SIGN_H, SIGN_T = 0.40, 0.30, 0.012
POST_H, POST_W = 1.2, 0.06
SIGN_AT = 1.05


def sign_plate(bm, w: float, h: float, mat: int) -> None:
    ws.box(bm, (-w / 2.0, w / 2.0), (0.0, SIGN_T), (-h / 2.0, h / 2.0), mat)


def front_prism(bm, outline: list, mat: int) -> None:
    """A 5 mm raised shape (outline in x, z) on the sign's front face."""
    faces = ws.rk.prism(bm, outline, lambda u, v, w: (u, w, v), SIGN_T, SIGN_T + 0.005, cap0=False)
    for f in faces:
        f.material_index = mat
    ws.bmesh.ops.recalc_face_normals(bm, faces=faces)


def make_post():
    bm = ws.new_bmesh()
    h = POST_W / 2.0
    ws.box(bm, (-h, h), (-h, h), (0.0, POST_H), 0)
    ws.box(bm, (-0.05, 0.05), (-0.05, 0.05), (0.0, 0.04), 0)                       # foot plate
    ws.trim(bm, (-h - 0.003, h + 0.003), (-h - 0.003, h + 0.003), (0.95, 1.0), 1, "-z")   # reflective band
    root = ws.make_object("ws_marker_post", bm, ["ws_frame", "ws_accent"])
    bm = ws.new_bmesh()
    ws.dome(bm, (0.0, 0.0, POST_H), 0.045, 0, 8)
    ws.make_object("marker_beacon", bm, ["ws_status"], parent=root)
    bm = ws.new_bmesh()
    ws.cylinder(bm, (0.0, 0.0, 0.0), "z", 0.04, 0.0, POST_H, 0, 8)
    ws.collision_mesh(root, "ws_marker_post", bm)
    ws.add_empty(root, "anchor_sign", (0.0, h, SIGN_AT))
    return root


def make_sign_route():
    bm = ws.new_bmesh()
    sign_plate(bm, SIGN_W, SIGN_H, 0)
    # A chevron arrow pointing +X (along the route)
    s, t = 0.10, 0.06
    front_prism(bm, [(-s, -s), (-s + t, -s), (s, 0.0), (-s + t, s), (-s, s), (s - t, 0.0)], 1)
    root = ws.make_object("ws_sign_route", bm, ["ws_label", "ws_accent"])
    return root


def make_sign_base():
    bm = ws.new_bmesh()
    sign_plate(bm, SIGN_W, SIGN_H, 0)
    front_prism(bm, [(-0.07, -0.10), (0.07, -0.10), (0.07, 0.0), (0.0, 0.07), (-0.07, 0.0)], 1)   # a house
    root = ws.make_object("ws_sign_base", bm, ["ws_label", "ws_accent"])
    ws.add_empty(root, "label_sign", (0.0, SIGN_T + 0.006, -0.115))
    return root


def make_sign_heritage():
    bm = ws.new_bmesh()
    sign_plate(bm, SIGN_W, SIGN_H, 0)
    for x, z in (((-0.20, 0.20), (0.13, 0.15)), ((-0.20, 0.20), (-0.15, -0.13))):
        ws.trim(bm, x, (SIGN_T, SIGN_T + 0.003), z, 1, "-y")                      # dark rules top and bottom
    root = ws.make_object("ws_sign_heritage", bm, ["ws_label", "ws_dark"])
    ws.add_empty(root, "label_sign", (0.0, SIGN_T + 0.002, 0.0))
    return root


def make_floor_chevron():
    bm = ws.new_bmesh()
    ws.floor_polygon(bm, [(-0.20, -0.15), (0.0, 0.05), (0.20, -0.15), (0.20, -0.07), (0.0, 0.13), (-0.20, -0.07)],
                     0.002, 0)
    return ws.make_object("ws_floor_chevron", bm, ["ws_accent"])


def make_floor_stripe():
    bm = ws.new_bmesh()
    ws.floor_quad(bm, (-1.0, 1.0), (-0.05, 0.05), 0.002, 0)
    return ws.make_object("ws_floor_stripe", bm, ["ws_accent"])


def make_door_sign():
    bm = ws.new_bmesh()
    sign_plate(bm, 1.2, 0.30, 0)
    for x in ((-0.60, -0.56), (0.56, 0.60)):
        ws.trim(bm, x, (SIGN_T, SIGN_T + 0.003), (-0.15, 0.15), 1, "-y")          # hazard ends
    root = ws.make_object("ws_door_sign", bm, ["ws_label", "ws_accent"])
    ws.add_empty(root, "label_sign", (0.0, SIGN_T + 0.002, 0.0))
    return root


MAKERS = [make_post, make_sign_route, make_sign_base, make_sign_heritage, make_floor_chevron, make_floor_stripe,
          make_door_sign]
SIZES = {"ws_sign_route": (SIGN_W, None, SIGN_H), "ws_sign_base": (SIGN_W, None, SIGN_H),
         "ws_sign_heritage": (SIGN_W, None, SIGN_H), "ws_floor_chevron": (0.40, 0.28, None),
         "ws_floor_stripe": (2.0, 0.10, None), "ws_door_sign": (1.2, None, 0.30)}


def main() -> None:
    previews = ws.preview_dir("markers")
    ws.rk.reset_scene()
    roots = {}
    x = 0.0
    for maker in MAKERS:
        root = maker()
        roots[root.name] = root
        root.location = (x, 0.0, 0.0)
        x += 1.5 if root.name != "ws_floor_stripe" else 2.5
    bpy.context.view_layer.update()
    rows = []
    failures = 0
    for name, root in roots.items():
        failures += ws.check_part(root, BUDGETS[name], SIZES.get(name), rows)
        ws.export(root)
    rows.append("sign plate %.2f m wide: %.0f px tall at 10 m on a 1080p screen (FOV 90)" % (SIGN_W, SIGN_H * 540.0 / 10.0))
    ws.add_references()
    if previews:
        ws.set_preview_colors(True)
        # Post with a route sign on its anchor, as Godot mounts it
        post, sign = roots["ws_marker_post"], roots["ws_sign_route"]
        saved = sign.location.copy()
        anchor = next(o for o in post.children if o.name == "anchor_sign")
        sign.location = anchor.matrix_world.translation
        bpy.context.view_layer.update()
        ws.render(post, os.path.join(previews, "post_with_route_sign.png"), (0.6, 1.0, 0.3), 1.6, True, 3.5,
                  (0.0, 0.0, 0.7), keep_visible=(sign,))
        sign.location = saved
        bpy.context.view_layer.update()
        for name in ("ws_sign_route", "ws_sign_base", "ws_sign_heritage", "ws_door_sign"):
            ws.render(roots[name], os.path.join(previews, name + "_front.png"), (0.0, 1.0, 0.0),
                      1.4 if name == "ws_door_sign" else 0.5)
        for name in ("ws_floor_chevron", "ws_floor_stripe"):
            ws.render(roots[name], os.path.join(previews, name + "_above.png"), (0.0, 0.0, 1.0),
                      2.2 if name == "ws_floor_stripe" else 0.6)
        ws.set_preview_colors(False)
    ws.save("markers")
    rows.append("ALL CHECKS OK" if failures == 0 else "%d CHECK FAILURES" % failures)
    ws.report("markers", rows)


if __name__ == "__main__":
    main()
