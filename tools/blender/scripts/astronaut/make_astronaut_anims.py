"""The first-person body (tools/blender/ASTRONAUT_KIT.md 13): the astronaut's mesh split into the
body and the helmet (the player's own camera never sees the helmet, it only casts its shadow), on
the same skeleton, with hand-authored animations in the stiff hard-suit style.

    blender -b --factory-startup -P tools/blender/scripts/astronaut/make_astronaut_anims.py [-- --no-previews]

Writes tools/blender/parts/astronaut/astronaut_fp.blend, game/res/models/astronaut_kit/astronaut_fp.glb
(Skeleton3D, `astronaut_body` and `astronaut_helmet`, the clips below) and previews in
tools/blender/previews/astronaut_fp/<clip>/.

The clips are posed by tables, like the kit's seated and rack poses. The legs are posed from foot
paths: every leg cycle is a stance (the boot rolls over its heel, lies flat, then rolls over its
toe while it travels back at exactly the clip's speed, so it stays planted on the ground) and a
swing; the hips sit as high as both planted legs allow, which gives the bob of a walk. Every
frame is keyed. All clips use full-size character space (1.80 m); the game scales the body to
0.95 (FP_SCALE), so a clip authored at speed v plays at v * 0.95 in the world.

Every clip is keyed at 60 frames a second (at 30 the planted boots wobbled about 1 mm between keys).

Clips (loops are a whole number of cycles; locomotion clips start with the left heel strike):
  idle, walk, sprint, crouch_idle, crouch_walk, turn_step (loops)
  air_rise, air_apex, air_fall, land (single poses, blended by the game)
"""

import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

sys.path.append(os.path.dirname(__file__))
import astronaut_kit_common as ak  # noqa: E402
import make_astronaut as ma  # noqa: E402

FPS = 120
FP_SCALE = 0.95                   # the game's scale for the first-person body (eyes at the 1.5 m camera)
WORLD_WALK, WORLD_SPRINT, WORLD_CROUCH = 2.0, 3.0, 1.0   # Player.SPEED_WALK / SPRINT / CROUCH (m/s)
# Crouched, the player's eye is 0.75 m over the ground: the camera drops 0.25 m and the capsule,
# shrinking 2.0 -> 1.0 m round a fixed centre, lets the player sink 0.5 m (Player.set_crouch).
# A 1.71 m suit only gets its eyes that low in a deep squat, leaning well forward.
CROUCH_EYE = 0.75 / FP_SCALE
EYE = Vector((0.0, -0.06, 1.58))       # between the eyes, inside the helmet (rides UpperChest)

THIGH = (ak.HIP - ak.KNEE).length
SHIN = (ak.KNEE - ak.ANKLE).length
LEG = THIGH + SHIN
# The rigid boot's sole edges, from the ankle: it rolls over the heel and over the toe
HEEL = Vector((0.0, 0.095, -ak.ANKLE.z))
TOE = Vector((0.0, -0.215, -ak.ANKLE.z))
HIPS_REST = ak.BONES["Hips"][1]


def rot(pitch: float = 0.0, roll: float = 0.0, yaw: float = 0.0) -> Matrix:
    """Degrees: pitch about X (positive leans forward, -Y), roll about Y (positive tips the top to
    the character's left, +X), yaw about Z. Applied roll, then pitch, then yaw."""
    return (Matrix.Rotation(math.radians(yaw), 3, "Z") @ Matrix.Rotation(math.radians(pitch), 3, "X")
            @ Matrix.Rotation(math.radians(roll), 3, "Y"))


def smooth(t: float) -> float:
    t = min(1.0, max(0.0, t))
    return t * t * (3.0 - 2.0 * t)


def lerp(a, b, t: float):
    return a + (b - a) * t


# --- A pose: everything the clips set, as plain numbers ---------------------------------------

class Pose:
    def __init__(self):
        self.hips = Vector((0.0, 0.0, 0.0))        # Hips offset from rest (the hip joints move with it)
        self.hips_rot = (0.0, 0.0, 0.0)            # pitch, roll, yaw
        self.spine = [(0.0, 0.0, 0.0)] * 3         # Spine, Chest, UpperChest, each relative to the one below
        # Per side: ankle target and boot pitch (positive = toe down / heel up)
        self.ankle = {"Left": Vector((ak.ANKLE.x, 0.0, ak.ANKLE.z)), "Right": Vector((-ak.ANKLE.x, 0.0, ak.ANKLE.z))}
        self.foot_pitch = {"Left": 0.0, "Right": 0.0}
        # Per side arm: swing forward (degrees), out from the side, elbow bend, finger curl
        self.arm = {"Left": (0.0, 17.0, 12.0, 18.0), "Right": (0.0, 17.0, 12.0, 18.0)}
        self.knee_out = 0.12                       # how far out the knees point (pole x)

    def copy(self) -> "Pose":
        p = Pose()
        p.hips = self.hips.copy()
        p.hips_rot = self.hips_rot
        p.spine = list(self.spine)
        p.ankle = {k: v.copy() for k, v in self.ankle.items()}
        p.foot_pitch = dict(self.foot_pitch)
        p.arm = dict(self.arm)
        p.knee_out = self.knee_out
        return p


def apply_pose(arm, p: Pose) -> None:
    ma.reset_pose(arm)
    hips = rot(*p.hips_rot)
    ma.set_world(arm, "Hips", hips, head=HIPS_REST + p.hips)
    acc = hips
    for name, r in zip(("Spine", "Chest", "UpperChest"), p.spine):
        acc = acc @ rot(*r)
        ma.set_world(arm, name, acc)
    for side, s in (("Left", 1.0), ("Right", -1.0)):
        # Knees bend forward and a little out; legs keep their "up" (bone Z) forward
        ma.two_bone(arm, side + "UpperLeg", side + "LowerLeg", p.ankle[side], (s * p.knee_out, -1.0, 0.25),
                    (0.0, -1.0, 0.0), hips @ Vector((0.0, -1.0, 0.0)))
        ma.set_world(arm, side + "Foot", Matrix.Rotation(math.radians(p.foot_pitch[side]), 3, "X"))
        swing, out, elbow, curl = p.arm[side]
        down = Vector((0.0, 0.0, -1.0))
        upper = acc @ rot(pitch=-swing) @ Matrix.Rotation(math.radians(-s * out), 3, "Y") @ down
        fore = acc @ rot(pitch=-(swing + elbow)) @ Matrix.Rotation(math.radians(-s * out * 0.55), 3, "Y") @ down
        outward = acc @ Vector((s, 0.0, 0.0))
        ma.aim(arm, side + "UpperArm", upper, (0.0, 0.0, 1.0), outward)
        ma.aim(arm, side + "LowerArm", fore, (0.0, 0.0, 1.0), outward)
        ma.aim(arm, side + "Hand", fore, (0.0, 0.0, 1.0), outward)
        ma.curl(arm, side, curl, curl * 0.5)


# --- Legs from foot paths ---------------------------------------------------------------------

def boot_on_ground(flat: Vector, pitch: float) -> Vector:
    """The ankle of a boot whose flat position is `flat`, rolled by `pitch` degrees over its heel
    (pitch < 0, toe up) or its toe (pitch > 0, heel up)."""
    edge = HEEL if pitch < 0.0 else TOE
    pivot = flat + edge
    return pivot + Matrix.Rotation(math.radians(pitch), 3, "X") @ (flat - pivot)


class Gait:
    """One leg cycle, the same for both legs half a cycle apart. `speed` in character units/s,
    `period` in frames. Forward is -Y; a planted boot travels back (+Y) at `speed`."""

    def __init__(self, speed: float, frames: int, duty: float, lift: float, heel: float, toe: float, hip: float,
                 width: float = ak.ANKLE.x, sway: float = 0.012, pelvis_yaw: float = 4.0, pelvis_roll: float = 2.0):
        self.speed, self.frames, self.duty, self.lift = speed, frames, duty, lift
        self.heel, self.toe, self.hip, self.width = heel, toe, hip, width
        self.sway, self.pelvis_yaw, self.pelvis_roll = sway, pelvis_yaw, pelvis_roll
        self.stance = speed * frames / FPS * duty      # how far a planted boot travels

    def leg(self, phase: float) -> tuple:
        """(ankle y and z, boot pitch, planted) at a leg's own phase (0 = heel strike)."""
        if phase < self.duty:
            u = phase / self.duty
            flat = Vector((0.0, -self.stance / 2.0 + self.stance * u, ak.ANKLE.z))
            if u < 0.18:
                pitch = -self.heel * (1.0 - smooth(u / 0.18))
            elif u > 0.72:
                pitch = self.toe * smooth((u - 0.72) / 0.28)
            else:
                pitch = 0.0
            a = boot_on_ground(flat, pitch)
            return a.y, a.z, pitch, True
        w = (phase - self.duty) / (1.0 - self.duty)
        start = boot_on_ground(Vector((0.0, self.stance / 2.0, ak.ANKLE.z)), self.toe)
        end = boot_on_ground(Vector((0.0, -self.stance / 2.0, ak.ANKLE.z)), -self.heel)
        # Forward along a Hermite curve that leaves and arrives at the stance's own speed (back,
        # +Y): a boot leaving or meeting the ground is still in the world, not dragged forward
        tangent = self.speed * self.frames * (1.0 - self.duty) / FPS
        w2, w3 = w * w, w * w * w
        y = ((2 * w3 - 3 * w2 + 1) * start.y + (w3 - 2 * w2 + w) * tangent + (-2 * w3 + 3 * w2) * end.y
             + (w3 - w2) * tangent)
        z = lerp(start.z, end.z, smooth(w)) + self.lift * math.sin(math.pi * w)
        pitch = lerp(self.toe, -self.heel, smooth(w * 1.3))
        return y, z, pitch, False

    def pose(self, frame: int, base: Pose) -> Pose:
        p = base.copy()
        phase = frame / self.frames
        legs = {}
        for side, offset in (("Left", 0.0), ("Right", 0.5)):
            legs[side] = self.leg((phase + offset) % 1.0)
        # The hips as high as every planted leg allows (slightly bent), at most `hip`
        hz = self.hip
        for side, s in (("Left", 1.0), ("Right", -1.0)):
            y, z, _, planted = legs[side]
            if planted:
                dx = self.width - ak.HIP.x
                reach = (LEG * 0.985) ** 2 - y * y - dx * dx
                hz = min(hz, z + math.sqrt(max(reach, 0.0)))
        # The base pose's hips height is replaced (the gait's `hip` is its standing height)
        p.hips = Vector((base.hips.x + self.sway * math.sin(2.0 * math.pi * phase), base.hips.y, hz - ak.HIP.z))
        yaw = -self.pelvis_yaw * math.cos(2.0 * math.pi * phase)
        roll = -self.pelvis_roll * math.sin(2.0 * math.pi * phase)
        p.hips_rot = (base.hips_rot[0], roll, yaw)
        # The chest stays square: the spine takes the pelvis's yaw and roll back
        sp = list(base.spine)
        sp[0] = (sp[0][0], sp[0][1] - roll, sp[0][2] - yaw)
        p.spine = sp
        for side, s in (("Left", 1.0), ("Right", -1.0)):
            y, z, pitch, _ = legs[side]
            p.ankle[side] = Vector((s * self.width, y, z))
            p.foot_pitch[side] = pitch
        return p, legs


def smooth_cyclic(values: list, passes: int = 2) -> list:
    for _ in range(passes):
        n = len(values)
        values = [(values[i - 1] + 2.0 * values[i] + values[(i + 1) % n]) / 4.0 for i in range(n)]
    return values


# --- Clips --------------------------------------------------------------------------------------

def standing() -> Pose:
    p = Pose()
    p.hips = Vector((0.0, 0.0, -0.008))          # knees a touch soft
    for side, s in (("Left", 1.0), ("Right", -1.0)):
        p.ankle[side] = Vector((s * 0.13, 0.0, ak.ANKLE.z))
    return p


def clip_idle() -> list:
    """4 s: a slow weight shift and a breath; arms hang out from the suit, fingers relaxed."""
    frames = 4 * FPS
    out = []
    for f in range(frames):
        t = f / frames
        p = standing()
        b = math.sin(2.0 * math.pi * t * 2.0)      # two breaths
        w = math.sin(2.0 * math.pi * t)            # one weight shift
        p.hips = p.hips + Vector((0.012 * w, 0.0, -0.004 * abs(w)))
        p.hips_rot = (0.0, -1.2 * w, 0.0)
        p.spine = [(0.5, 1.2 * w, 0.0), (0.4 * b, 0.0, 0.0), (0.6 * b, 0.0, 0.0)]
        for side, s in (("Left", 1.0), ("Right", -1.0)):
            p.arm[side] = (2.0 + 1.5 * b, 17.0 + 1.0 * b, 14.0 + 1.0 * b, 20.0)
        out.append(p)
    return out


def locomotion(gait: Gait, base: Pose, arm_swing: float, elbow: float, elbow_swing: float, out: float,
               curl: float, lean: float, chest_bounce: float = 0.0, arm_base: float = 0.0) -> list:
    poses = []
    hz = []
    for f in range(gait.frames):
        p, _ = gait.pose(f, base)
        hz.append(p.hips.z)
        phase = f / gait.frames
        c = math.cos(2.0 * math.pi * phase)        # +1 at the left heel strike
        # Arms swing against the legs: the right arm forward with the left leg
        p.arm = {"Left": (arm_base - arm_swing * c, out, elbow - elbow_swing * c, curl),
                 "Right": (arm_base + arm_swing * c, out, elbow + elbow_swing * c, curl)}
        sp = list(p.spine)
        sp[1] = (sp[1][0] + lean * 0.5, sp[1][1], sp[1][2])
        sp[2] = (sp[2][0] + lean * 0.5 + chest_bounce * math.cos(4.0 * math.pi * phase), sp[2][1], sp[2][2])
        sp[0] = (sp[0][0], sp[0][1], sp[0][2])
        p.spine = sp
        poses.append(p)
    # Smoothed, but never higher than the planted legs allow
    for p, z, raw in zip(poses, smooth_cyclic(hz), hz):
        p.hips.z = min(z, raw)
    return poses


WALK = Gait(WORLD_WALK / FP_SCALE, 80, duty=0.56, lift=0.075, heel=12.0, toe=14.0, hip=ak.HIP.z - 0.012)
SPRINT = Gait(WORLD_SPRINT / FP_SCALE, 72, duty=0.40, lift=0.15, heel=10.0, toe=18.0, hip=ak.HIP.z - 0.02,
              sway=0.008, pelvis_yaw=6.0)
CROUCH_HIP = 0.38
CROUCH_WIDTH = 0.28
# The deep squat folds the hips past what the hard suit allows: these touches are accepted there
CROUCH_ALLOWED = {"waist bearing / Left thigh", "waist bearing / Right thigh"}
CROUCH_WALK = Gait(WORLD_CROUCH / FP_SCALE, 108, duty=0.6, lift=0.04, heel=2.0, toe=0.0, hip=CROUCH_HIP + 0.05,
                   width=CROUCH_WIDTH, sway=0.02, pelvis_yaw=3.0, pelvis_roll=3.0)


def clip_walk() -> list:
    base = standing()
    base.spine = [(1.0, 0.0, 0.0), (1.0, 0.0, 0.0), (1.0, 0.0, 0.0)]
    return locomotion(WALK, base, arm_swing=13.0, elbow=18.0, elbow_swing=6.0, out=16.0, curl=24.0, lean=3.0)


def clip_sprint() -> list:
    base = standing()
    base.spine = [(3.0, 0.0, 0.0), (3.0, 0.0, 0.0), (2.0, 0.0, 0.0)]
    return locomotion(SPRINT, base, arm_swing=24.0, elbow=58.0, elbow_swing=14.0, out=17.0, curl=40.0, lean=6.0,
                      chest_bounce=1.0)


def crouching() -> Pose:
    """A deep squat: boots wide, knees turned well out, the pelvis tipped and the chest leaning
    about 60 degrees forward between the knees, arms hanging inside them: the eyes come down to
    CROUCH_EYE. The suit can't fold this far at the hips without its waist bearing pressing into
    the tops of the thighs (CROUCH_ALLOWED)."""
    p = Pose()
    p.hips = Vector((0.0, 0.10, CROUCH_HIP - ak.HIP.z))
    p.hips_rot = (28.0, 0.0, 0.0)
    p.spine = [(12.8, 0.0, 0.0), (11.2, 0.0, 0.0), (8.0, 0.0, 0.0)]
    p.ankle = {"Left": Vector((CROUCH_WIDTH, -0.03, ak.ANKLE.z)), "Right": Vector((-CROUCH_WIDTH, 0.05, ak.ANKLE.z))}
    p.knee_out = 0.9
    p.arm = {"Left": (80.0, 12.0, 40.0, 26.0), "Right": (80.0, 12.0, 40.0, 26.0)}
    return p


def clip_crouch_idle() -> list:
    frames = 2 * FPS
    out = []
    for f in range(frames):
        b = math.sin(2.0 * math.pi * f / frames)
        p = crouching()
        p.hips = p.hips + Vector((0.0, 0.0, 0.004 * b))
        p.spine = [p.spine[0], p.spine[1], (0.6 * b, 0.0, 0.0)]
        out.append(p)
    return out


def clip_crouch_walk() -> list:
    base = crouching()
    base.ankle = {k: Vector((v.x, 0.0, v.z)) for k, v in base.ankle.items()}
    return locomotion(CROUCH_WALK, base, arm_swing=3.0, elbow=40.0, elbow_swing=3.0, out=12.0, curl=26.0, lean=0.0,
                      arm_base=80.0)


def clip_turn_step() -> list:
    """Stepping on the spot while the lower body turns under the view: each boot lifts in turn."""
    frames = int(0.8 * FPS)
    out = []
    for f in range(frames):
        t = f / frames
        p = standing()
        for side, start in (("Left", 0.0), ("Right", 0.5)):
            u = (t - start) % 1.0
            lift = math.sin(math.pi * u / 0.4) if u < 0.4 else 0.0
            p.ankle[side] = p.ankle[side] + Vector((0.0, 0.0, 0.05 * lift))
            p.foot_pitch[side] = 4.0 * lift
        w = math.sin(2.0 * math.pi * t)
        p.hips = p.hips + Vector((-0.012 * w, 0.0, -0.01))
        p.hips_rot = (0.0, 1.5 * w, 0.0)
        p.spine = [(0.0, -1.5 * w, 0.0), (0.0, 0.0, 0.0), (0.0, 0.0, 0.0)]
        out.append(p)
    return out


def pose_air_rise() -> Pose:
    """Pushing off: legs long under the body, boots pointed, arms lifting."""
    p = standing()
    p.hips = Vector((0.0, 0.0, 0.0))
    p.ankle = {"Left": Vector((0.13, 0.05, 0.125)), "Right": Vector((-0.13, 0.09, 0.14))}
    p.foot_pitch = {"Left": 22.0, "Right": 26.0}
    p.spine = [(2.0, 0.0, 0.0), (1.0, 0.0, 0.0), (0.0, 0.0, 0.0)]
    p.arm = {"Left": (22.0, 26.0, 30.0, 16.0), "Right": (22.0, 26.0, 30.0, 16.0)}
    return p


def pose_air_apex() -> Pose:
    """The float: knees drawn up, one boot ahead, arms out for balance."""
    p = standing()
    p.hips = Vector((0.0, 0.0, 0.0))
    p.ankle = {"Left": Vector((0.14, -0.04, 0.30)), "Right": Vector((-0.14, 0.12, 0.26))}
    p.foot_pitch = {"Left": 8.0, "Right": 16.0}
    p.spine = [(3.0, 0.0, 0.0), (1.0, 0.0, 0.0), (0.0, 0.0, 0.0)]
    p.arm = {"Left": (12.0, 36.0, 26.0, 14.0), "Right": (8.0, 34.0, 22.0, 14.0)}
    return p


def pose_air_fall() -> Pose:
    """Reaching for the ground: legs long, the leading boot forward and toe up, arms out."""
    p = standing()
    p.hips = Vector((0.0, 0.0, 0.0))
    p.ankle = {"Left": Vector((0.14, -0.10, 0.15)), "Right": Vector((-0.14, 0.06, 0.17))}
    p.foot_pitch = {"Left": -6.0, "Right": 4.0}
    p.spine = [(-1.0, 0.0, 0.0), (0.0, 0.0, 0.0), (0.0, 0.0, 0.0)]
    p.arm = {"Left": (18.0, 32.0, 22.0, 16.0), "Right": (14.0, 32.0, 22.0, 16.0)}
    return p


def pose_land() -> Pose:
    """The deepest moment of a heavy landing: knees taking the load, chest forward, arms out."""
    p = standing()
    p.hips = Vector((0.0, 0.035, -0.14))
    p.hips_rot = (8.0, 0.0, 0.0)
    p.spine = [(4.0, 0.0, 0.0), (3.0, 0.0, 0.0), (0.0, 0.0, 0.0)]
    p.ankle = {"Left": Vector((0.14, -0.07, ak.ANKLE.z)), "Right": Vector((-0.14, 0.04, ak.ANKLE.z))}
    p.arm = {"Left": (26.0, 30.0, 34.0, 30.0), "Right": (26.0, 30.0, 34.0, 30.0)}
    return p


CLIPS = {
    "idle": (clip_idle, True),
    "walk": (clip_walk, True),
    "sprint": (clip_sprint, True),
    "crouch_idle": (clip_crouch_idle, True),
    "crouch_walk": (clip_crouch_walk, True),
    "turn_step": (clip_turn_step, True),
    "air_rise": (lambda: [pose_air_rise()], False),
    "air_apex": (lambda: [pose_air_apex()], False),
    "air_fall": (lambda: [pose_air_fall()], False),
    "land": (lambda: [pose_land()], False),
}
GAITS = {"walk": WALK, "sprint": SPRINT, "crouch_walk": CROUCH_WALK}


# --- Keying -----------------------------------------------------------------------------------

def key_clip(arm, name: str, poses: list, loop: bool) -> bpy.types.Action:
    """One action: every pose keyed on its frame. A loop gets its first pose again one frame after
    its last, so the clip's length is a whole cycle; a single pose is held for one frame."""
    arm.animation_data_create()
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    arm.animation_data.action = action
    frames = list(enumerate(poses))
    if loop:
        frames.append((len(poses), poses[0]))
    elif len(poses) == 1:
        frames.append((1, poses[0]))
    previous = {}
    for f, p in frames:
        apply_pose(arm, p)
        for pb in arm.pose.bones:
            q = pb.rotation_quaternion.copy()
            if pb.name in previous:
                q.make_compatible(previous[pb.name])
            pb.rotation_quaternion = q
            previous[pb.name] = q
            pb.keyframe_insert("location", frame=f, group=pb.name)
            pb.keyframe_insert("rotation_quaternion", frame=f, group=pb.name)
    action.use_frame_range = True
    action.frame_start, action.frame_end = 0, frames[-1][0]
    arm.animation_data.action = None
    return action


# --- Checks -----------------------------------------------------------------------------------

def sole_points(arm, side: str) -> list:
    """Points on the bottom of a boot (heel edge, middle, toe edge), posed, in character space."""
    a = Vector((side == "Left" and ak.ANKLE.x or -ak.ANKLE.x, 0.0, ak.ANKLE.z))
    return [ma.posed_point(arm, side + "Foot", a + d) for d in (HEEL, Vector((0.0, -0.06, -ak.ANKLE.z)), TOE)]


def check_gait(arm, name: str, poses: list, gait: Gait, rows: list) -> int:
    """Planted boots: a sole point that touches the ground on two frames in a row stays put in the
    world (the body moves forward at the clip's speed), and no boot goes into the ground."""
    worst_slide, lowest, worst_height = 0.0, 1.0, 0.0
    sole = {side: [] for side in ("Left", "Right")}
    for f, p in enumerate(poses):
        apply_pose(arm, p)
        for side in sole:
            sole[side].append([q + Vector((0.0, -gait.speed * f / FPS, 0.0)) for q in sole_points(arm, side)])
    for side, offset in (("Left", 0.0), ("Right", 0.5)):
        for f in range(len(poses)):
            pts = sole[side][f]
            lowest = min(lowest, min(q.z for q in pts))
            if gait.leg((f / gait.frames + offset) % 1.0)[3]:
                worst_height = max(worst_height, min(q.z for q in pts))
            if f == 0:
                continue
            for a, b in zip(sole[side][f - 1], pts):
                if a.z < 0.003 and b.z < 0.003:
                    worst_slide = max(worst_slide, (b - a).length)
    # In metres of the world (the body is scaled)
    slide = worst_slide * FP_SCALE
    ok = slide <= 0.004 and lowest >= -0.006 and worst_height <= 0.01
    rows.append("%s: a planted sole point moves at most %.1f mm a frame, contact %.1f mm off the ground, lowest sole %.1f mm%s" % (
        name, slide * 1000, worst_height * 1000, lowest * 1000, "" if ok else "  FAIL"))
    return 0 if ok else 1


def check_clip_parts(obj, arm, name: str, poses: list, face_parts: list, parts: list, rows: list) -> int:
    """No part inside another on sampled frames (as the kit's poses)."""
    step = max(1, len(poses) // 6)
    sub = []
    for f in range(0, len(poses), step):
        apply_pose(arm, poses[f])
        ma.check_interpenetration(ma.baked_mesh(obj, "check", Matrix.Identity(4)), face_parts, parts,
                                              "%s frame %d" % (name, f), sub)
    allowed = CROUCH_ALLOWED if name.startswith("crouch") else set()
    hits = []
    for r in sub:
        if "FAIL:" in r:
            pairs = [h.strip() for h in r.split("FAIL:")[1].split(",")]
            bad = [h for h in pairs if h not in allowed]
            if bad:
                hits.append(r.split(":")[0] + ": " + ", ".join(bad))
    failures = len(hits)
    rows.append("%s: no part inside another on %d sampled frames%s" % (name, len(sub), "" if not hits else "  FAIL: " + "; ".join(hits)))
    return failures


# --- Export -----------------------------------------------------------------------------------

def split_skinned(obj, face_parts: list, parts: list) -> tuple:
    """Two skinned copies of the T-pose mesh: the body, and the helmet (helmet, visor, ridge, lamp
    pods and the neck ring) that the player's camera never draws."""
    import bmesh
    helmet_parts = ma.HELMET_PARTS | {"neck ring"}
    idx = {i for i, p in enumerate(parts) if p[0] in helmet_parts}
    out = []
    for name, keep_helmet in (("astronaut_body", False), ("astronaut_helmet", True)):
        mesh = obj.data.copy()
        mesh.name = name
        bm = bmesh.new()
        bm.from_mesh(mesh)
        bm.faces.ensure_lookup_table()
        doomed = [f for f in bm.faces if (face_parts[f.index] in idx) != keep_helmet]
        bmesh.ops.delete(bm, geom=doomed, context="FACES")
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
        bm.to_mesh(mesh)
        bm.free()
        ma.strip_attributes(mesh)
        copy = bpy.data.objects.new(name, mesh)
        bpy.context.scene.collection.objects.link(copy)
        for g in obj.vertex_groups:
            copy.vertex_groups.new(name=g.name)
        copy.parent = obj.parent
        modifier = copy.modifiers.new("Armature", "ARMATURE")
        modifier.object = obj.parent
        out.append(copy)
    return tuple(out)


def export_fp(arm, path: str) -> None:
    for o in [arm] + list(arm.children):
        ak.rk.check_export_name(o.name)
    bpy.ops.object.select_all(action="DESELECT")
    for o in [arm] + list(arm.children):
        o.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.context.scene.render.fps = FPS
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=True, export_yup=True, export_apply=True,
        export_skins=True, export_materials="EXPORT", export_animations=True, export_animation_mode="ACTIONS",
        export_force_sampling=True, export_frame_step=1, export_optimize_animation_size=False,
        export_reset_pose_bones=True, export_def_bones=False,
    )


# --- Previews ---------------------------------------------------------------------------------

def render_clip(arm, body, name: str, poses: list, previews: str) -> None:
    """A side view and a three-quarter view of a few frames of each clip (montaged outside Blender)."""
    folder = os.path.join(previews, name)
    os.makedirs(folder, exist_ok=True)
    step = max(1, len(poses) // 8)
    for k, f in enumerate(range(0, len(poses), step)):
        apply_pose(arm, poses[f])
        ak.render(body, os.path.join(folder, "side_%02d.png" % k), (1.0, 0.0, 0.05), 2.1, focus=(0.0, 0.0, 0.9), size=400)
        ak.render(body, os.path.join(folder, "front_%02d.png" % k), (0.55, -1.0, 0.25), 2.0, True, 6.5, (0.0, 0.0, 0.9),
                  size=400)


def render_eye(arm, body, name: str, pose: Pose, previews: str, pitch: float) -> None:
    """Roughly what the player sees looking down `pitch` degrees (helmet hidden; Workbench, 50 mm)."""
    apply_pose(arm, pose)
    eye = Vector((0.0, 0.0, 1.5 / FP_SCALE))
    view = Vector((0.0, -math.cos(math.radians(pitch)), -math.sin(math.radians(pitch))))
    focus = eye + view * 1.0
    ak.render(body, os.path.join(previews, "eye_%s_%d.png" % (name, pitch)), tuple(-view), 1.0, True, 1.0,
              tuple(focus), size=500)


# --- Main -------------------------------------------------------------------------------------

def main() -> None:
    args = ak.rk.script_args()
    ak.rk.reset_scene()
    bpy.context.scene.render.fps = FPS
    obj, regions, parts, face_parts = ma.build_mesh()
    arm = ma.build_armature()
    ma.skin(obj, arm)
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
    rows = []
    failures = 0
    clips = {}
    for name, (make, loop) in CLIPS.items():
        poses = make()
        clips[name] = poses
        key_clip(arm, name, poses, loop)
        rows.append("%s: %d frames (%.2f s)%s" % (name, len(poses), len(poses) / FPS, ", loop" if loop else ""))
        if name in GAITS:
            g = GAITS[name]
            rows.append("%s: %.2f m/s in the world, %.2f m a cycle (%.2f m a step), %.0f%% planted" % (
                name, g.speed * FP_SCALE, g.speed * g.frames / FPS * FP_SCALE, g.speed * g.frames / FPS * FP_SCALE / 2.0,
                g.duty * 100))
            failures += check_gait(arm, name, poses, g, rows)
        failures += check_clip_parts(obj, arm, name, poses, face_parts, parts, rows)
        apply_pose(arm, poses[0])
        eye = ma.posed_point(arm, "UpperChest", EYE)
        # The game keeps the eyes under the camera with each clip's average (PlayerBody.CLIP_EYE)
        ahead = 0.0
        for p in poses:
            apply_pose(arm, p)
            ahead += -ma.posed_point(arm, "UpperChest", EYE).y * FP_SCALE / len(poses)
        rows.append("%s: eye %.2f m over the ground in the world; on average %.3f m ahead of the origin" % (
            name, eye.z * FP_SCALE, ahead))
        if name == "crouch_idle":
            ok = abs(eye.z - CROUCH_EYE) <= 0.05
            failures += 0 if ok else 1
            rows.append("crouch_idle: eye within 5 cm of the crouched camera's %.2f m%s" % (0.75, "" if ok else "  FAIL"))

    body, helmet = split_skinned(obj, face_parts, parts)
    bpy.data.objects.remove(obj)
    ma.reset_pose(arm)
    export_fp(arm, os.path.join(ak.EXPORT_DIR, "astronaut_fp.glb"))
    rows.append("export: astronaut_fp.glb (astronaut_body %d triangles, astronaut_helmet %d, %d clips)" % (
        sum(len(p.vertices) - 2 for p in body.data.polygons), sum(len(p.vertices) - 2 for p in helmet.data.polygons),
        len(CLIPS)))

    if "--no-previews" not in args:
        previews = os.path.join(ak.REPO_ROOT, "tools", "blender", "previews", "astronaut_fp")
        ak.set_preview_colors(True)
        helmet.hide_render = True
        for name, poses in clips.items():
            render_clip(arm, body, name, poses, previews)
        for pitch in (30, 60, 80):
            render_eye(arm, body, "walk", clips["walk"][0], previews, pitch)
            render_eye(arm, body, "idle", clips["idle"][0], previews, pitch)
        helmet.hide_render = False
        ak.set_preview_colors(False)
        ma.reset_pose(arm)

    ak.rk.save_blend(os.path.join(ak.PARTS_DIR, "astronaut_fp.blend"))
    rows.append("ALL CHECKS OK" if failures == 0 else "%d CHECK FAILURES" % failures)
    print("\n".join("ASTRONAUT_FP " + line for line in rows))


if __name__ == "__main__":
    main()
