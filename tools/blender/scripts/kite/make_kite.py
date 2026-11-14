"""Generates Kite, the disabled rover (A05, KITE_KIT.md 6, 7), with its service port bracket, poses
it on the Apollo 12 terrain, checks the cartridge delivery against it (KITE_KIT.md 2, 8) and renders
previews.

    blender -b --factory-startup -P tools/blender/scripts/kite/make_kite.py [-- --previews DIR | --no-previews]

Writes tools/blender/parts/kite/kite.blend, game/res/models/kite_kit/kite.glb and previews in
tools/blender/previews/kite/. Needs the rover kit's .blend files (with cargo_mount and cartridge)
and game/res/terrain/moon_apollo12/play.f32.

Kite's frame: the rover frame, the GLB root on the ground under Kite's origin (Godot places it on
the terrain there, turned to KITE_YAW_DEG). The damaged pose, its tilt on the terrain and the
height are baked under the root:
    rear-left wheel off (lying 1.4 m behind and left, half buried), rear-left bracket bent, the
    left bogie down on its stub; mast bent 12 degrees, head panned and drooped; antenna stuck;
    arm sheared at the shoulder; no motor
    kite_port          the service port bracket on the front: box centre (0.08, 0.70), top z 0.46
                       (Kite frame), opening 0.28 x 0.17 m, 0.08 deep, a 10 mm lead-in
    kite_status_light  strip and dome on the port (ws_status)
    socket_cartridge, anchor_cartridge_seated  under kite_port
    colliders: body, five wheels, the fallen wheel, the port
"""

import itertools
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
import rover_kit_common as kit  # noqa: E402
import make_arm as arm_kit  # noqa: E402
import make_power_antenna_motor as pam  # noqa: E402
import workshop_kit_common as ws  # noqa: E402

PARTS_DIR = os.path.join(kit.REPO_ROOT, "tools", "blender", "parts", "kite")
EXPORT_DIR = os.path.join(kit.REPO_ROOT, "game", "res", "models", "kite_kit")
PLAY = os.path.join(kit.REPO_ROOT, "game", "res", "terrain", "moon_apollo12", "play.f32")

# KITE_KIT.md 7
KITE_XZ = (-204.0, 136.0)
KITE_YAW_DEG = 140.4                 # Godot rotation about Y: Kite's front faces azimuth 219.6
GROUND_Z = -0.10                     # the rover frame's ground at rest

PORT_CENTRE = Vector((0.08, 0.70))
PORT_TOP = 0.46
PORT_BOX = (0.17, 0.12, 0.12)        # half x, half y, height
# 0.28 x 0.17 m, 0.08 deep: the cartridge (0.262 m with its end grips, 0.154 with its stripe) with
# 9 mm a side, plus the 10 mm lead-in
OPENING = (0.14, 0.085, 0.08)        # half x, half y, depth
SEAT_GAP = 0.006                     # released 6 mm above the port floor (Kite tilts the port up to 3 mm across), then snapped onto the seat
LEAD_IN = 0.01
FALLEN_WHEEL = Vector((-1.0, -1.4))

BUDGET = 7000
# The delivery (KITE_KIT.md 8): parking window from the rescuer's arm yaw axis to the port
YAW_AXIS = Vector((-0.12, 0.53))
WINDOW_D = (0.45, 0.57)
WINDOW_BEARING = (-18.0, 13.0)
LIFT = {"J1": 0.0, "J2": 90.0, "J3": 60.0, "J4": 120.0, "J5": 0.0}
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


def kite_to_world(p) -> tuple:
    """Kite frame (x, y) to Godot world (x, z)."""
    t = math.radians(KITE_YAW_DEG)
    a, c = p[0], -p[1]
    return (KITE_XZ[0] + a * math.cos(t) + c * math.sin(t), KITE_XZ[1] - a * math.sin(t) + c * math.cos(t))


H0 = terrain(*KITE_XZ)


def ground_local(x: float, y: float) -> float:
    """Terrain height under a Kite-frame point, relative to the ground under Kite's origin."""
    return terrain(*kite_to_world((x, y))) - H0


# --- Building Kite -----------------------------------------------------------------------------

def build_damaged_rover() -> dict:
    scene = pam.assemble()
    arm = scene["arm"]
    doomed = {o for key in ("yaw", "upper", "forearm", "wrist", "tool") for o in [arm[key]] + list(arm[key].children_recursive)}
    doomed |= {scene["motor"], *scene["motor"].children_recursive}
    for o in doomed:
        bpy.data.objects.remove(o)
    left = scene["sides"]["L"]
    # The rear-left wheel comes off; its bracket is bent outward and down
    wheel = left["rear_wheel"]
    kit.parent_keep_transform(wheel, scene["chassis"])
    wheel.parent = None
    wheel.matrix_world = Matrix.Identity(4)
    left["rear_bracket"].rotation_euler = (math.radians(-15.0), 0.0, math.radians(-25.0))
    # Mast bent towards the rear-left; head panned and drooped; antenna stuck
    scene["mast_base"].rotation_euler = (math.radians(8.5), math.radians(-8.5), 0.0)
    pam.pose_mast_head(scene, 70.0, -30.0)
    pam.pose_antenna(scene, 160.0, 50.0)
    bpy.context.view_layer.update()
    scene["fallen_wheel"] = wheel
    return scene


def contact_points(scene: dict) -> list:
    """Each remaining wheel's lowest point and the bent bracket's lowest point (rover frame)."""
    pts = []
    for side in ("L", "R"):
        parts = scene["sides"][side]
        for key in ("front_wheel", "middle_wheel", "rear_wheel"):
            if side == "L" and key == "rear_wheel":
                continue
            c = parts[key].matrix_world.translation
            pts.append(Vector((c.x, c.y, c.z - 0.15)))
    verts = kit.world_vertices(scene["sides"]["L"]["rear_bracket"])
    low = min(verts, key=lambda v: v.z)
    pts.append(low)
    return pts


def solve_pose(scene: dict) -> tuple:
    """Left bogie / rocker angles and the whole body's roll, pitch and height that put the five
    wheels and the bent bracket's stub on the terrain: nothing more than 10 mm in it, the gaps
    as small as possible. Returns (rocker, bogie, roll, pitch, dz, gaps)."""
    left = scene["sides"]["L"]
    best = None
    for rocker, bogie in itertools.product(np.arange(-10.0, 10.1, 2.0), np.arange(0.0, 15.1, 1.5)):
        pam.rb.pose(left, rocker, bogie, 0.0)
        pts = contact_points(scene)
        for roll, pitch in itertools.product(np.arange(-6.0, 6.01, 0.5), np.arange(-6.0, 6.01, 0.5)):
            rot = Matrix.Rotation(math.radians(pitch), 3, "X") @ Matrix.Rotation(math.radians(roll), 3, "Y")
            moved = [rot @ p for p in pts]
            ground = [ground_local(p.x, p.y) for p in moved]
            dz = max(g - p.z for p, g in zip(moved, ground))       # lift until nothing is in the ground
                                                                      # (root frame: ground under the origin at 0)
            gaps = [p.z + dz - g for p, g in zip(moved, ground)]
            score = sum(gaps)
            if best is None or score < best[0]:
                best = (score, rocker, bogie, roll, pitch, dz, gaps)
    _, rocker, bogie, roll, pitch, dz, gaps = best
    pam.rb.pose(left, rocker, bogie, 0.0)
    return rocker, bogie, roll, pitch, dz, gaps


def build_port() -> bpy.types.Object:
    """The service port bracket in the Kite frame (before the body's tilt)."""
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
    # Struts back to Kite's front face
    for x in (cx - 0.08, cx + 0.08):
        ws.box(bm, (x - 0.015, x + 0.015), (0.45, cy - hy), (z0 + 0.02, z0 + 0.07), 0)
    port = ws.make_object("kite_port", bm, ["ws_frame", "ws_dark", "ws_accent"], origin=(cx, cy, PORT_TOP))
    bm = bmesh.new()
    ws.trim(bm, (cx - 0.10, cx + 0.10), (cy + hy, cy + hy + 0.005), (z1 - 0.06, z1 - 0.03), 0, "-y")
    ws.dome(bm, (cx + hx - 0.04, cy - hy + 0.04, z1 - LEAD_IN), 0.025, 0, 8)
    ws.make_object("kite_status_light", bm, ["ws_status"], parent=port)
    ws.add_empty(port, "socket_cartridge", (cx, cy, PORT_TOP))
    ws.add_empty(port, "anchor_cartridge_seated", (cx, cy, PORT_TOP - depth + SEAT_GAP))
    ws.collision_box(port, "kite_port", (cx - hx, cx + hx), (cy - hy, cy + hy), (z0, z1))
    return port


def cylinder_collider(name: str, centre: Vector, axis: Vector, radius: float, half: float) -> bpy.types.Object:
    bm = bmesh.new()
    kit.cylinder(bm, lambda u, v, w: (u, v, w), -half, half, radius, 12)
    obj = kit.mesh_object(name + "-convcolonly", bm, [])
    z = Vector((0, 0, 1))
    obj.matrix_world = Matrix.Translation(centre) @ z.rotation_difference(axis).to_matrix().to_4x4()
    obj.display_type = "WIRE"
    obj.hide_render = True
    return obj


def bake_kite(scene: dict, port, pose: tuple) -> bpy.types.Object:
    """Copies Kite's visible meshes under one root with clean names, the tilt and height baked;
    removes everything else."""
    rocker, bogie, roll, pitch, dz, gaps = pose
    # Rover frame (ground at z -0.10) to Kite's root frame (ground under its origin at 0): the
    # solved tilt, then the lift that rests it on the terrain
    tilt = (Matrix.Translation((0.0, 0.0, dz)) @ Matrix.Rotation(math.radians(pitch), 4, "X") @
            Matrix.Rotation(math.radians(roll), 4, "Y"))
    root = bpy.data.objects.new("kite", None)
    bpy.context.scene.collection.objects.link(root)
    names = {scene["chassis"]: "kite_chassis", scene["mast_base"]: "kite_mast", scene["mast_head"]: "kite_mast_head",
             scene["mast_camera"]: "kite_mast_camera", scene["antenna"]: "kite_antenna",
             scene["antenna_dish"]: "kite_antenna_dish", scene["power_unit"]: "kite_power_unit",
             scene["arm"]["mount"]: "kite_arm_stub"}
    for side in ("L", "R"):
        for key, label in (("rocker", "rocker"), ("bogie", "bogie"), ("front_bracket", "bracket_front"),
                           ("rear_bracket", "bracket_rear"), ("front_wheel", "wheel_front"), ("middle_wheel", "wheel_middle"),
                           ("rear_wheel", "wheel_rear")):
            obj = scene["sides"][side].get(key)
            if obj is not None and not (side == "L" and key == "rear_wheel"):
                names[obj] = "kite_%s_%s" % (label, side)
    keep = []
    for src, name in names.items():
        dup = bpy.data.objects.new(name, src.data)
        bpy.context.scene.collection.objects.link(dup)
        dup.matrix_world = tilt @ src.matrix_world
        keep.append(dup)
    # The fallen wheel: on its side behind and left, half buried
    fw = scene["fallen_wheel"]
    g = ground_local(*FALLEN_WHEEL)
    fallen = bpy.data.objects.new("kite_wheel_fallen", fw.data)
    bpy.context.scene.collection.objects.link(fallen)
    fallen.matrix_world = (Matrix.Translation((FALLEN_WHEEL.x, FALLEN_WHEEL.y, g + 0.124 - 0.05)) @
                           Matrix.Rotation(math.radians(90), 4, "Y") @ Matrix.Rotation(math.radians(20), 4, "X"))
    keep.append(fallen)
    port.matrix_world = tilt @ port.matrix_world
    keep.append(port)
    # Colliders: the body box, the five wheels, the fallen wheel (the port carries its own)
    bm = bmesh.new()
    kit.box(bm, (-0.25, 0.25), (-0.45, 0.45), (0.20, 0.44))
    body = kit.mesh_object("kite_body-convcolonly", bm, [])
    body.matrix_world = tilt.copy()
    body.display_type, body.hide_render = "WIRE", True
    colliders = [body]
    for src, name in names.items():
        if name.startswith("kite_wheel_"):
            c = (tilt @ src.matrix_world).translation
            axis = (tilt @ src.matrix_world).to_3x3() @ Vector((1, 0, 0))
            colliders.append(cylinder_collider(name + "_col_shape", c, axis, 0.15, 0.12))
    colliders.append(cylinder_collider("kite_wheel_fallen_shape", fallen.matrix_world.translation,
                                       fallen.matrix_world.to_3x3() @ Vector((1, 0, 0)), 0.15, 0.12))
    for o in keep + colliders:
        if o is port:
            continue
        kit.parent_keep_transform(o, root)
    kit.parent_keep_transform(port, root)
    # Everything else goes
    wanted = {root, *root.children_recursive}
    for o in [o for o in bpy.data.objects if o not in wanted]:
        bpy.data.objects.remove(o)
    return root


# --- Delivery checks ---------------------------------------------------------------------------

def port_in_kite(root) -> tuple:
    """The port's top centre and its axes (x, z) in the Kite frame, after the tilt."""
    sock = next(o for o in root.children_recursive if o.name == "socket_cartridge")
    port = sock.parent
    return sock.matrix_world.translation.copy(), port.matrix_world.to_3x3() @ Vector((1, 0, 0)), port.matrix_world.to_3x3() @ Vector((0, 0, 1))


def rescuer_pose(port_kite: Vector, d: float, bearing_deg: float, heading_offset_deg: float) -> Matrix:
    """Where Kite goes in the rescuer's frame (the rescuer at the origin, facing +Y) so that the
    port is d from the rescuer's yaw axis at the bearing. The rescuer faces Kite nose to nose,
    turned by heading_offset."""
    b = math.radians(bearing_deg)
    target = Vector((YAW_AXIS.x - d * math.sin(b), YAW_AXIS.y + d * math.cos(b)))   # bearing + = left (-X)
    yaw = math.radians(180.0 + heading_offset_deg)
    rot = Matrix.Rotation(yaw, 4, "Z")
    p = rot @ Vector((port_kite.x, port_kite.y, 0.0))
    # Kite's ground under its origin vs the rescuer's: the terrain at the parking spot
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
    kite_root = kit.append_objects(os.path.join(PARTS_DIR, "kite.blend"), ["kite"])[0]
    bpy.context.view_layer.update()
    port_top, port_x, port_z = port_in_kite(kite_root)
    kite_meshes = [o for o in kite_root.children_recursive if o.type == "MESH" and "convcolonly" not in o.name]
    port_obj = next(o for o in kite_meshes if o.name.startswith("kite_port"))
    kite_other = [o for o in kite_meshes if o is not port_obj and not o.name.startswith("kite_status")]
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
        kite_root.matrix_world = place
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
            note("arm vs Kite", arm_kit.gap(arm_tree, arm_kit.world_bvh(kite_other + [port_obj])), where)
            note("cartridge vs Kite (not the port)", arm_kit.gap(cart_tree, arm_kit.world_bvh(kite_other)), where)
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
        # The rescuer's wheels and body against Kite
        note("rescuer wheels and body vs Kite (footprint, needs 150 mm)",
             arm_kit.gap(arm_kit.world_bvh(wheels + [scene["chassis"]]), arm_kit.world_bvh(kite_meshes)), where)
        if previews and d == sum(WINDOW_D) / 2 and bearing == 0.0 and turn == 0.0:
            kit.set_preview_colors(True)
            ws.set_preview_colors(True)
            keep = tuple(kite_meshes) + (cart, mount)
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
    previews = kit.preview_dir("kite")
    rows = []
    failures = 0
    scene = build_damaged_rover()
    pose = solve_pose(scene)
    rocker, bogie, roll, pitch, dz, gaps = pose
    rows.append("pose on the terrain: left rocker %+.0f, left bogie %+.1f deg; body roll %+.1f, pitch %+.1f deg; lift %+.3f m" % (
        rocker, bogie, roll, pitch, dz))
    rows.append("contact gaps (5 wheels, bent bracket's stub), mm: %s" % ", ".join("%.0f" % (g * 1000.0) for g in gaps))
    ok = min(gaps) >= -0.0005 and max(gaps) <= 0.04
    failures += 0 if ok else 1
    rows.append("everything rests on the ground (none in it, none over 40 mm above)%s" % ("" if ok else "  FAIL"))
    port = build_port()
    root = bake_kite(scene, port, pose)
    bpy.context.view_layer.update()
    tris = sum(kit.triangle_count(o) for o in root.children_recursive if o.type == "MESH" and "convcolonly" not in o.name)
    ok = tris <= BUDGET
    failures += 0 if ok else 1
    rows.append("Kite: %d triangles (budget %d)%s" % (tris, BUDGET, "" if ok else "  FAIL"))
    top, _, _ = port_in_kite(root)
    rows.append("port's top centre in the Kite frame (tilted): (%.3f, %.3f, %.3f), %.3f m above the ground under it" % (
        top.x, top.y, top.z, top.z - ground_local(top.x, top.y)))
    for o in [root] + list(root.children_recursive):
        kit.check_export_name(o.name)
    os.makedirs(PARTS_DIR, exist_ok=True)
    kit.save_blend(os.path.join(PARTS_DIR, "kite.blend"))
    ws.rk.GODOT_IMPORT_SCRIPT = ws.GODOT_IMPORT_SCRIPT
    kit.export_part(root, os.path.join(EXPORT_DIR, "kite.glb"))
    gx, gz = KITE_XZ
    rows.append("Godot: Kite root at (%.2f, %.3f, %.2f), rotation y %.1f deg" % (gx, H0, gz, KITE_YAW_DEG))
    if previews:
        kit.set_preview_colors(True)
        ws.set_preview_colors(True)
        for name, d in (("approach", (-0.5, 1.0, 0.45)), ("above", (0.0, 0.0, 1.0)), ("port_side", (0.9, 0.7, 0.35)),
                        ("rear_left", (-0.8, -1.0, 0.5))):
            kit.render_view(root, os.path.join(previews, "kite_%s.png" % name), d, 3.4, name != "above", 6.5, (0.0, -0.2, 0.35))
        kit.set_preview_colors(False)
        ws.set_preview_colors(False)
    failures += run_delivery_checks(rows, previews)
    rows.append("ALL CHECKS OK" if failures == 0 else "%d CHECK FAILURES" % failures)
    print("\n".join("KITE_KIT kite " + r for r in rows))


if __name__ == "__main__":
    main()
