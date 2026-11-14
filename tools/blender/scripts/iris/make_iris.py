"""Generates the IRIS placeholder (A07, IRIS_KIT.md 6, 7): a body box, a 3 m mast with an indicator
and the service port bracket, on the Apollo 12 terrain where the port's pose is the one the delivery
was tuned to; checks the cartridge delivery against it (IRIS_KIT.md 2, 8) and renders previews.
The final IRIS model (about 2 x 1.5 x 1.3 m, ASSET_PLAN.md A07) replaces it later.

    blender -b --factory-startup -P tools/blender/scripts/iris/make_iris.py [-- --previews DIR | --no-previews]

Writes tools/blender/parts/iris/iris.blend, game/res/models/iris_kit/iris.glb and previews in
tools/blender/previews/iris/. Needs the rover kit's .blend files (with cargo_mount and cartridge)
and game/res/terrain/moon_apollo12/play.f32.

IRIS's frame: the rover frame (ground at z -0.10), the GLB root on the ground under IRIS's origin
(Godot places it on the terrain there, turned to IRIS_YAW_DEG). The tilt and height on the terrain
(PORT_POSE) are baked under the root:
    iris_body          1.0 x 1.2 x 0.5 m above the ground, a skirt into it; front face at y 0.45
    iris_mast          3 m above the ground, at the body's rear-left corner
    iris_indicator     a box on the mast's top (ws_status), lit with the port's status light
    iris_port          the service port bracket on the front: box centre (0.08, 0.70), top z 0.46
                       (rover frame), opening 0.28 x 0.17 m, 0.08 deep, a 10 mm lead-in
    iris_status_light  strip and dome on the port (ws_status)
    socket_cartridge, anchor_cartridge_seated  under iris_port
    colliders: body, port
"""

import itertools
import math
import os
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
# The placeholder body (rover frame) and mast
BODY_X = (-0.50, 0.50)
BODY_Y = (-0.75, 0.45)
BODY_HEIGHT = 0.50
SKIRT = 0.15                         # below the ground, for the terrain's slope under the box
MAST_XY = (-0.38, -0.63)
MAST_HEIGHT = 3.0
MAST_RADIUS = 0.035
INDICATOR = 0.10

BUDGET = 3000
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

def tilt_matrix() -> Matrix:
    """Rover frame to IRIS's root frame: what puts the port (origin at its top centre) on PORT_POSE."""
    loc, rot = PORT_POSE
    port_world = Matrix.Translation(loc) @ Quaternion(rot).to_matrix().to_4x4()
    return port_world @ Matrix.Translation((-PORT_CENTRE.x, -PORT_CENTRE.y, -PORT_TOP))


def build_port() -> bpy.types.Object:
    """The service port bracket in the IRIS frame (before the body's tilt)."""
    bm = bmesh.new()
    cx, cy = PORT_CENTRE
    hx, hy, h = PORT_BOX
    ox, oy, depth = OPENING
    z0, z1 = PORT_TOP - h, PORT_TOP
    zf = PORT_TOP - depth
    ws.box(bm, (cx - hx, cx + hx), (cy - hy, cy + hy), (z0, zf), 0)                        # floor block
    for x, y in (((cx - hx, cx - ox), (cy - hy, cy + hy)), ((cx + ox, cx + hx), (cy - hy, cy + hy)),
                 ((cx - ox, cx + ox), (cy - hy, cy - oy)), ((cx - ox, cx + ox), (cy + oy, cy + hy))):
        ws.box(bm, x, y, (zf, z1 - LEAD_IN), 0)
    # Lead-in: the rim's inner edge chamfered 10 mm (amber), the rim top
    outer = [(cx - hx, cy - hy), (cx + hx, cy - hy), (cx + hx, cy + hy), (cx - hx, cy + hy)]
    mid = [(cx - ox - LEAD_IN, cy - oy - LEAD_IN), (cx + ox + LEAD_IN, cy - oy - LEAD_IN),
           (cx + ox + LEAD_IN, cy + oy + LEAD_IN), (cx - ox - LEAD_IN, cy + oy + LEAD_IN)]
    inner = [(cx - ox, cy - oy), (cx + ox, cy - oy), (cx + ox, cy + oy), (cx - ox, cy + oy)]
    for k in range(4):
        n = (k + 1) % 4
        ws.quad(bm, [(outer[k][0], outer[k][1], z1 - LEAD_IN), (outer[n][0], outer[n][1], z1 - LEAD_IN),
                     (mid[n][0], mid[n][1], z1 - LEAD_IN), (mid[k][0], mid[k][1], z1 - LEAD_IN)], 0, (0, 0, 1))
        ws.quad(bm, [(mid[k][0], mid[k][1], z1 - LEAD_IN), (mid[n][0], mid[n][1], z1 - LEAD_IN),
                     (inner[n][0], inner[n][1], z1 - 2 * LEAD_IN), (inner[k][0], inner[k][1], z1 - 2 * LEAD_IN)], 2, (0, 0, 1))
    ws.floor_quad(bm, (cx - ox, cx + ox), (cy - oy, cy + oy), zf + 0.001, 1)                 # dark floor
    # Struts back to the body's front face
    for x in (cx - 0.08, cx + 0.08):
        ws.box(bm, (x - 0.015, x + 0.015), (0.45, cy - hy), (z0 + 0.02, z0 + 0.07), 0)
    port = ws.make_object("iris_port", bm, ["ws_frame", "ws_dark", "ws_accent"], origin=(cx, cy, PORT_TOP))
    bm = bmesh.new()
    ws.trim(bm, (cx - 0.10, cx + 0.10), (cy + hy, cy + hy + 0.005), (z1 - 0.06, z1 - 0.03), 0, "-y")
    ws.dome(bm, (cx + hx - 0.04, cy - hy + 0.04, z1 - LEAD_IN), 0.025, 0, 8)
    ws.make_object("iris_status_light", bm, ["ws_status"], parent=port)
    ws.add_empty(port, "socket_cartridge", (cx, cy, PORT_TOP))
    ws.add_empty(port, "anchor_cartridge_seated", (cx, cy, PORT_TOP - depth + SEAT_GAP))
    ws.collision_box(port, "iris_port", (cx - hx, cx + hx), (cy - hy, cy + hy), (z0, z1))
    return port


def build_iris(port) -> bpy.types.Object:
    """The body box with its collider, the mast and indicator, and the port, tilted onto the
    terrain under one root."""
    tilt = tilt_matrix()
    bm = bmesh.new()
    ws.box(bm, BODY_X, BODY_Y, (GROUND_Z - SKIRT, GROUND_Z + BODY_HEIGHT), 0)
    body = ws.make_object("iris_body", bm, ["ws_panel"], origin=(0.0, 0.0, GROUND_Z))
    ws.collision_box(body, "iris_body", BODY_X, BODY_Y, (GROUND_Z - SKIRT, GROUND_Z + BODY_HEIGHT))
    bm = bmesh.new()
    mx, my = MAST_XY
    kit.cylinder(bm, lambda u, v, w: (mx + u, my + v, w), GROUND_Z + BODY_HEIGHT, GROUND_Z + MAST_HEIGHT, MAST_RADIUS, 12)
    ws.make_object("iris_mast", bm, ["ws_frame"], origin=(mx, my, GROUND_Z + BODY_HEIGHT), parent=body)
    bm = bmesh.new()
    h = INDICATOR / 2.0
    ws.box(bm, (mx - h, mx + h), (my - h, my + h), (GROUND_Z + MAST_HEIGHT, GROUND_Z + MAST_HEIGHT + INDICATOR), 0)
    ws.make_object("iris_indicator", bm, ["ws_status"], origin=(mx, my, GROUND_Z + MAST_HEIGHT), parent=body)
    root = bpy.data.objects.new("iris", None)
    bpy.context.scene.collection.objects.link(root)
    for o in (body, port):
        o.matrix_world = tilt @ o.matrix_world
        bpy.context.view_layer.update()
        kit.parent_keep_transform(o, root)
    return root


def body_ground_gaps(root) -> tuple:
    """The body's bottom below the ground (smallest, m) and its top above it (smallest, m), at its
    corners and edge middles."""
    tilt = tilt_matrix()
    buried, height = 1e9, 1e9
    for x, y in itertools.product((BODY_X[0], 0.0, BODY_X[1]), (BODY_Y[0], 0.0, BODY_Y[1])):
        bottom = tilt @ Vector((x, y, GROUND_Z - SKIRT))
        top = tilt @ Vector((x, y, GROUND_Z + BODY_HEIGHT))
        buried = min(buried, ground_local(bottom.x, bottom.y) - bottom.z)
        height = min(height, top.z - ground_local(top.x, top.y))
    return buried, height


# --- Delivery checks ---------------------------------------------------------------------------

def port_in_iris(root) -> tuple:
    """The port's top centre and its axes (x, z) in the IRIS frame, after the tilt."""
    sock = next(o for o in root.children_recursive if o.name == "socket_cartridge")
    port = sock.parent
    return sock.matrix_world.translation.copy(), port.matrix_world.to_3x3() @ Vector((1, 0, 0)), port.matrix_world.to_3x3() @ Vector((0, 0, 1))


def rescuer_pose(port_iris: Vector, d: float, bearing_deg: float, heading_offset_deg: float) -> Matrix:
    """Where IRIS goes in the rescuer's frame (the rescuer at the origin, facing +Y) so that the
    port is d from the rescuer's yaw axis at the bearing. The rescuer faces IRIS head on,
    turned by heading_offset."""
    b = math.radians(bearing_deg)
    target = Vector((YAW_AXIS.x - d * math.sin(b), YAW_AXIS.y + d * math.cos(b)))   # bearing + = left (-X)
    yaw = math.radians(180.0 + heading_offset_deg)
    rot = Matrix.Rotation(yaw, 4, "Z")
    p = rot @ Vector((port_iris.x, port_iris.y, 0.0))
    # IRIS's ground under its origin vs the rescuer's: the terrain at the parking spot
    dz = H0 - terrain(-205.1, 137.3)
    return Matrix.Translation((target.x - p.x, target.y - p.y, GROUND_Z + dz)) @ rot


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


# --- Main --------------------------------------------------------------------------------------

def main() -> None:
    previews = kit.preview_dir("iris")
    rows = []
    failures = 0
    port = build_port()
    root = build_iris(port)
    bpy.context.view_layer.update()
    buried, height = body_ground_gaps(root)
    ok = buried >= 0.02 and height >= BODY_HEIGHT - 0.06
    failures += 0 if ok else 1
    rows.append("body: skirt %.0f mm in the ground at least, top %.0f mm above it at least%s" % (
        buried * 1000.0, height * 1000.0, "" if ok else "  FAIL"))
    tris = sum(kit.triangle_count(o) for o in root.children_recursive if o.type == "MESH" and "convcolonly" not in o.name)
    ok = tris <= BUDGET
    failures += 0 if ok else 1
    rows.append("IRIS: %d triangles (budget %d)%s" % (tris, BUDGET, "" if ok else "  FAIL"))
    top, _, _ = port_in_iris(root)
    rows.append("port's top centre in the IRIS frame (tilted): (%.3f, %.3f, %.3f), %.3f m above the ground under it" % (
        top.x, top.y, top.z, top.z - ground_local(top.x, top.y)))
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
        for name, d in (("approach", (-0.5, 1.0, 0.45)), ("side", (1.0, 0.0, 0.0)), ("front", (0.0, 1.0, 0.0)),
                        ("rear_left", (-0.8, -1.0, 0.5))):
            kit.render_view(root, os.path.join(previews, "iris_%s.png" % name), d, 3.8, name in ("approach", "rear_left"),
                            8.0, (0.0, -0.1, 1.4))
        kit.render_view(root, os.path.join(previews, "iris_port_close.png"), (0.9, 0.7, 0.35), 1.6, True, 4.0, (0.08, 0.70, 0.40))
        kit.set_preview_colors(False)
        ws.set_preview_colors(False)
    failures += run_delivery_checks(rows, previews)
    rows.append("ALL CHECKS OK" if failures == 0 else "%d CHECK FAILURES" % failures)
    print("\n".join("IRIS_KIT iris " + r for r in rows))


if __name__ == "__main__":
    main()
