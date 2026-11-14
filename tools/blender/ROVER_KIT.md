# Rover Kit Spec

Modular low-poly kit for the drivable rover in `game/src/robot/`, inspired by NASA's Curiosity
(reference: `tools/blender/reference/curiosity.jpg`). The kit becomes the rover's visual body,
replacing the placeholder box. Swappable parts use the existing `HotswapSocket` / `HotswapPart`
system. **Every part follows this spec.**

Status: approved 2026-10-07. Revised 2026-10-07 while building the steer bracket: renamed the
bracket's `socket_wheel` to `socket_wheel_hub` and added the Godot name rules (2.2); fixed the
connector recess position (2.5). Revised again while building the rocker and bogie: their
budgets are 230 each (were 250 / 200), since round pivot housings and every keyed recess need
about 228 per part (6.2). Added: keys on moving joints only mark the rest pose (2.5), and the
clearance-checked pose range that the visuals must clamp to (5). Revised while building the
chassis: socket_motor moves to the hatch floor (0.12, 0.33, 0.30) so the drive unit can sit flush
and still mate at its origin; chassis wheel sockets are named socket_wheel_<front|middle|rear>_L/R;
the hazcams set the lowest chassis point (3.3, 3.4). Revised while integrating the kit: the
collider import script lives in the game project (7); measured visual wheel offsets (5). Revised for wheel types: a fixed wheel envelope (radius 0.15 m,
width may only grow outboard) and wheel variants that differ by tread, colour and stats (3.1, 4).
Revised while building the mast: the mast head is two objects in one GLB, the panning yoke
`mast_head` and the tilting `mast_head_camera`; pan / tilt range and camera view checks (3.3, 5).

---

## 1. Decisions

| Topic | Decision |
|---|---|
| Size | Keep the physics footprint: track 1.0 m, wheelbase 1.0 m (front to rear), wheel radius 0.15 m. The kit is a chunky, stylised Curiosity at about 0.45 scale. |
| Wheels | 6 physics wheels (front, middle, rear per side) at y = +0.5 / 0 / -0.5 (Blender). Each is an independent raycast spring in `RunningGear`. |
| Suspension | Rocker-bogie linkage is **visual only**. It is posed every frame from the physics wheel heights and never affects the physics. |
| Steering | Front wheels steer, rear wheels counter-steer, middle wheels fixed. Max 30 degrees. |
| Drive | All 6 wheels driven. Total motor torque unchanged. |
| Motor slot | Kept, as a drive unit in a hatch on the chassis front face. |
| Power slot | The power unit (RTG look) uses the existing battery slot (`BatteryPart`). |

---

## 2. Conventions

### 2.1 Units and axes
- 1 Blender unit = 1 m. Apply all transforms (rotation 0, scale 1) before export.
- The rover faces **+Y** in Blender. With the glTF exporter's "+Y Up", Blender (x, y, z) becomes
  Godot (x, z, -y), so the rover faces **-Z in Godot**, its driving direction.
- **Blender world origin = the rover's physics origin** (the `Robot` RigidBody3D origin), so empty
  positions copy straight into `robot.tscn`.
- At rest the ground is at **Blender z = -0.10**. Keep a reference ground plane there (excluded from export).
- `_L` = the rover's left = **-X** in both Blender and Godot. `_R` = +X.

### 2.2 Naming
- Lowercase and underscores only. No Blender `.001` suffixes.
- Part root object: the part name from section 4 (e.g. `rocker_L`, `wheel_R`, `mast_head`).
- Variants of a swappable part: `<part>_<variant>`, e.g. `wheel_grouser`, `arm_tool_drill`.
- `socket_*` empties: attach points where another part's origin goes.
- `pivot_*` empties: animation or camera reference points that are not attach points.
- No Godot import suffixes (`-col`, `-rigid`, `-noimp`, ...) except `-convcolonly` (section 7).
  Godot also reads them after `_`, so **no node name may end in** `_wheel`, `_col`, `_colonly`,
  `_convcol`, `_convcolonly`, `_rigid`, `_vehicle`, `_navmesh`, `_occ`, `_occonly`, `_noimp`,
  `_loop` or `_cycle` (e.g. `socket_wheel` would import as a `VehicleWheel3D`). The exporter
  rejects such names.
- In an `_L` / `_R` file, Blender needs unique names, so each side's empties carry the side
  suffix (`socket_wheel_hub_R`). The exporter strips it, so both GLBs have the same socket names.

### 2.3 Origins and empties
- Every part's origin is at its own connection point: the centre of its connector's mating face.
- **Exception: wheels.** The origin is the wheel centre (on the axle, 0.12 m outboard of the inner
  face, i.e. mid-width of the standard 0.24 m wheel), because the physics places wheels by their
  centre and spins them about it. The hub connector sits on the axle at the wheel's inner face.
- `socket_*` and `pivot_*` empties have **zero rotation and scale 1**.
- Parts are modelled in their **assembled rest pose** (rover at rest on flat ground, wheels straight,
  arm stretched straight forward). In Godot a part attaches with `part.position = socket.position`
  and no rotation.
- Empties must be visible at export (the exporter's "visible only" option drops hidden ones).
  Display type does not matter.

### 2.4 Left / right
- Left and right parts are **separate meshes, mirrored in Blender with the mirror applied**.
- **Never use negative scale**, in Blender or in Godot (it flips normals).
- Front and rear steer brackets share a mesh (`steer_bracket_L` / `steer_bracket_R`).

### 2.5 Standard connector (every joint)
- **Parent side (at the socket):** recessed collar, outer diameter 60 mm, recess diameter 44 mm,
  8 mm deep. The recess opening is flush with the mating plane at the socket empty, and the
  recess floor is 8 mm inside the parent, so the child's plug fills it exactly.
- **Child side (at the origin):** plug, diameter 44 mm, sticking out 8 mm from the mating face
  toward the parent. The mating face is at the origin.
- **Key:** an 8 mm wide notch on the plug and a matching tab in the collar. The key points **+Y**;
  if the connector's axis runs along Y, the key points **+Z**. Wheel hubs face along X, key at +Z.
- Joints read as round actuator bosses; a collar may be wider than the beam it sits on.
- **Moving joints** (rocker pivot, bogie pivot, steering): the key only marks the rest pose. In
  use the plug rotates inside the recess, hidden inside the joint.

### 2.6 Clearance
- **At least 20 mm** between any two parts that are not joined at a connector, in the rest pose and
  over the full motion: steering +-30 degrees, rocker and bogie rotation, suspension travel.
- Section 3.4 lists the checked clearances.

---

## 3. Layout (Blender coordinates, metres, rover at rest)

Values are for the right side (+X). The left side mirrors x.

### 3.1 Wheels (match the physics exactly)

| Wheel | Centre (x, y, z) | Steers | Mounted on |
|---|---|---|---|
| front | (0.50, +0.50, 0.05) | yes, +-30 degrees | front steer bracket (rocker) |
| middle | (0.50, 0.00, 0.05) | no | bogie front end |
| rear | (0.50, -0.50, 0.05) | yes, counter-steer | rear steer bracket (bogie) |

- Radius 0.15 m, width 0.24 m. Inner face at x = 0.38, outer face at x = 0.62.
- **Wheel envelope (every wheel, every variant):**
  - **Radius is exactly 0.15 m.** The kit leaves 20 mm above the wheel top (bracket arm), 21 mm
    to the rocker in the steering sweep, and 0.20 m between neighbouring wheels, and the physics
    does not raise the rover for a bigger wheel. A larger wheel clips into the brackets, horns,
    chassis and its neighbours and sinks into the ground visually; a smaller one floats. Measured
    with 0.3 m wheels: 149 mm into the ground, 130 mm through the bracket arm, 100 mm overlap
    between neighbours.
  - **Width may only grow outboard.** The inner face (x = 0.38, against the hub stub) and the
    origin (x = 0.50) stay where they are; extra width goes past x = 0.62, where nothing else is.
  - Wheel sockets refuse a wheel outside the envelope and tell the player why.
- **Wheel variants** differ by tread, colour and stats (grip now; more stats later), never by
  radius. Each variant is a wheel_<variant>_L / _R mesh pair from make_wheel.py within the
  envelope; a variant may reuse the standard mesh until its own exists.
- Rest centre height z = 0.05 (physics rest is about 0.049). Physics travel: centre z from 0.00 (full
  extension) to 0.19 (full compression).
- A steered wheel sweeps down to **x = 0.321** at 30 degrees (corner of the 0.30 x 0.24 plan footprint).

### 3.2 Lateral bands (x, right side)

| Band | x from | x to | Width |
|---|---|---|---|
| Chassis body side | - | 0.25 | chassis width 0.50 |
| gap | 0.25 | 0.27 | 20 mm (rocker pivot boss / connector) |
| Rocker beam | 0.27 | 0.30 | 30 mm |
| gap | 0.30 | 0.32 | 20 mm (bogie pivot boss / connector) |
| Bogie beam | 0.32 | 0.36 | 40 mm |
| gap | 0.36 | 0.38 | 20 mm (middle axle stub / connector) |
| Wheel | 0.38 | 0.62 | 240 mm |

Rocker and bogie each sit in their own band, so they can cross in y and z without touching.
All linkage rotation is about the X axis, so x bands never change.

### 3.3 Parts and sockets

| Part | Origin (connection point) | Empties carried |
|---|---|---|
| `chassis` | world origin (0, 0, 0) | `socket_rocker_L/R` (+-0.25, 0.00, 0.27), `socket_mast` (0.15, 0.35, 0.44), `socket_arm` (-0.12, 0.45, 0.32), `socket_motor` (0.12, 0.33, 0.30) on the hatch floor, `socket_power` (0.00, -0.45, 0.36), `socket_antenna` (-0.15, -0.25, 0.44), `socket_wheel_<front|middle|rear>_L/R` at the six wheel centres |
| `rocker_R` | (0.25, 0.00, 0.27), mating face on the chassis side | `socket_steer_front` (0.50, 0.50, 0.30), `socket_bogie` (0.30, -0.25, 0.20) |
| `bogie_R` | (0.30, -0.25, 0.20), mating face on the rocker | `socket_wheel_mid` (0.50, 0.00, 0.05), `socket_steer_rear` (0.50, -0.50, 0.30) |
| `steer_bracket_R` | top of the steering actuator, on the steer axis: (0.50, +-0.50, 0.30) | `socket_wheel_hub` at the wheel centre (0.50, +-0.50, 0.05) |
| `wheel_R` | wheel centre (section 3.1) | none |
| `mast_base` | (0.15, 0.35, 0.44) on the deck | `socket_mast_head` (0.15, 0.35, 0.95) |
| `mast_head` (yoke, pans) | (0.15, 0.35, 0.95), the connector on the mast top; pans about the vertical axis through it | child object `mast_head_camera`; collider `mast_head-convcolonly` |
| `mast_head_camera` (camera box, tilts) | (0.15, 0.35, 1.05), on the horizontal tilt axis (along X); child of `mast_head` | `pivot_camera` (0.15, 0.42, 1.05), the game camera position, 22 mm in front of the lens |
| `arm_shoulder` | (-0.12, 0.45, 0.32) on the front face | `pivot_shoulder_yaw` at the origin, `socket_arm_upper` (-0.12, 0.53, 0.32) |
| `arm_upper` | (-0.12, 0.53, 0.32) | `socket_arm_forearm` (-0.12, 0.83, 0.32) |
| `arm_forearm` | (-0.12, 0.83, 0.32) | `socket_arm_wrist` (-0.12, 1.11, 0.32) |
| `arm_wrist` | (-0.12, 1.11, 0.32) | `socket_arm_tool` (-0.12, 1.19, 0.32) |
| `arm_tool` | (-0.12, 1.19, 0.32) | none |
| `motor` (drive unit) | (0.12, 0.33, 0.30), its back face on the hatch floor | none |
| `power_unit` | (0.00, -0.45, 0.36) on the rear face | none |
| `antenna` | (-0.15, -0.25, 0.44) on the deck | none |

Shape notes:
- **Chassis:** body 0.50 (W) x 0.90 (L, y -0.45 to +0.45) x 0.24 (H, z 0.20 to 0.44). Ground
  clearance 0.30 m at rest. The rocker pivots sit on the body sides, 70 mm above the bottom.
- **Rocker:** from its pivot, the front leg rises to about (0.285, 0.33, 0.32), then a horizontal horn
  runs out over the front wheel to the steering actuator top at x = 0.50 (horn z 0.30 to 0.34). The
  rear leg descends to the bogie pivot.
- **Bogie:** the front arm descends from its pivot to the middle axle stub. The rear arm rises to
  z >= 0.30 by y = -0.36, then a horn runs out to the rear steering actuator top (z 0.30 to 0.34).
- **Steer bracket:** vertical actuator (diameter about 0.08) from z 0.22 to 0.30 on the steer axis.
  An arm runs inboard over the wheel top (z 0.22 to 0.25), then a leg goes down the wheel's inner
  side (x 0.33 to 0.36) to an axle stub (x 0.36 to 0.38). Arm and leg are 36 mm deep, so the
  leg's outer corners stay within 0.171 m of the steer axis (sweep to x = 0.329).
- **Arm:** rest pose stretched straight forward (+Y). Lengths: shoulder 0.08, upper 0.30, forearm
  0.28, wrist 0.08, tool about 0.12. The shoulder yaws about Z; the shoulder, elbow and wrist pitch
  about X. Godot poses it stowed by default.
- **Power unit:** finned dark cylinder (diameter about 0.14, length about 0.35), angled up and back
  from its rear-face connector. The angle is modelled into the mesh.
- **Antenna:** flat hexagonal high-gain dish (about 0.22 across) on a small gimbal, gold accent.
- **Mast base:** keyed plug into the deck, a 60 mm foot, a 40 mm pole and a 60 mm top collar
  with the keyed recess at z 0.95; two small sensor booms, toward the rover's centre (-X) at
  z 0.78 and to the rear (-Y) at z 0.72, out of the camera's forward view. All rover_metal.
- **Mast head:** two objects in one GLB so Godot can pan and tilt it. `mast_head` is the yoke
  (rover_metal): keyed plug, base and crossbar resting on the mast's top collar (the pan joint),
  and two arms at 0.080 to 0.092 m either side of the mast axis. `mast_head_camera` is a
  0.12 x 0.08 x 0.08 m camera box (rover_body) between the arms, held by axle stubs on the tilt
  axis, with one large hooded lens and two small stereo cameras below it (rover_dark lenses).
  In Godot: pan = rotate `mast_head` about its Y, tilt = rotate `mast_head_camera` about its X.
- **Motor:** drive unit box about 0.16 x 0.14 x 0.12 that sits flush in a recessed hatch on the
  chassis front face, to the right of the arm shoulder. The hatch is a 0.16 x 0.14 pocket
  (x 0.04 to 0.20, z 0.23 to 0.37) from the front face back to y 0.33, with the connector recess
  on its floor; the motor's origin and plug are on its back face.
- **Chassis details:** 30 mm chamfer on the top edges; 3 mm inset panels (two per side, two at
  the rear, one on the deck); hazcam pairs on bars under the front and rear edges (lowest point
  z 0.16); low-gain antenna post at (0.15, -0.30) on the deck.

### 3.4 Clearance check (20 mm minimum)

| Pair | Closest approach | Gap |
|---|---|---|
| Chassis side (0.25) vs rocker beam (0.27) | x | 20 mm |
| Rocker beam (0.30) vs bogie beam (0.32) | x | 20 mm |
| Bogie beam (0.36) vs middle wheel inner face (0.38) | x | 20 mm |
| Rocker beam (0.30) vs steered wheel sweep (0.321) | x | 21 mm |
| Chassis side (0.25) vs steered wheel sweep (0.321) | x | 71 mm |
| Chassis side (0.25) vs steer bracket leg sweep (0.329) | x | 79 mm |
| Front/rear wheel top (0.20) vs bracket arm bottom (0.22) | z | 20 mm |
| Bracket arm top (0.25) vs rocker/bogie horn bottom (0.30) | z | 50 mm |
| Bogie rear arm vs rear wheel and bracket sweep (y -0.37 to -0.63, x >= 0.32) | z (arm >= 0.30 there; bracket top 0.25) | >= 50 mm |
| Rocker front leg (z >= 0.29 near y 0.31) vs front wheel top (0.20) | z | >= 90 mm |
| Chassis bottom (0.20) vs ground (-0.10) | z | 300 mm |
| Hazcams (lowest chassis point, z 0.16) vs ground | z | 260 mm |

Connector joints (chassis-rocker, rocker-bogie, bogie/bracket-wheel stubs, bracket-horn) touch by
design; the 20 mm rule applies everywhere else.

---

## 4. Parts and swapping

| Part | Count | Swappable | Hotswap type | Notes |
|---|---|---|---|---|
| `chassis` | 1 | fixed | - | Root part. Carries the rover collision. |
| `rocker_L/R` | 2 | fixed | - | Visual only, animated. |
| `bogie_L/R` | 2 | fixed | - | Visual only, animated. |
| `steer_bracket_L/R` | 4 | fixed | - | Visual only, animated (follows linkage, turns with steering). |
| `wheel_L/R` | 6 | **yes** | `WHEEL` (`WheelPart`) | Fixed 0.15 m radius (3.1); variants change grip and other stats. |
| `mast_base` | 1 | fixed | - | |
| `mast_head` | 1 | **yes** | new `MAST_HEAD` | The rover camera follows its `pivot_camera`. |
| `arm_shoulder`, `arm_upper`, `arm_forearm`, `arm_wrist` | 1 each | fixed | - | Posed in Godot. |
| `arm_tool` | 1 | **yes** | new `ARM_TOOL` | Cosmetic until it gets gameplay stats. |
| `motor` | 1 | **yes** | `MOTOR` (`MotorPart`) | Front hatch. |
| `power_unit` | 1 | **yes** | `BATTERY` (`BatteryPart`) | Rear face. |
| `antenna` | 1 | **yes** | new `ANTENNA` | Cosmetic until it gets gameplay stats. |

Integration rules (implemented later, see section 8):
- Each swappable slot is a `HotswapSocket` in `robot.tscn`, placed at the matching `socket_*` empty.
  Wheel sockets are at the wheel centres in the chassis frame with **zero rotation** (the wheel
  scene's collision cylinder is rotated to lie along X).
- `MountPoint` offsets and `HotswapPart.mount_offset` are 0 for kit parts, since origins are at the
  connectors. `PartCapture` size becomes a per-socket export, because deck sockets sit close together.

---

## 5. Animation (visual only)

A script on the rover poses the linkage every physics frame from the physics wheel centres:
- **Bogie angle** (about X at its pivot) from the middle and rear wheel heights.
- **Rocker angle** (about X at its pivot) as the best fit for the front wheel and the bogie pivot.
- **Steer brackets** follow their rocker/bogie socket and turn about the vertical axis by the
  wheel's steering angle.
- **Wheels** spin about their axle from the physics angular velocity.

The six physics wheels are independent springs and the linkage is rigid, so on rough ground a
visual wheel may sit a few cm off its physics contact. Measured in the game: 1 mm on flat ground,
up to 33 mm driving over an abrupt 8 cm step, up to 41 mm climbing a 15 cm ramp. The wheel parts
follow the linkage (their hub sockets), not the physics contact.

**Verified pose range.** The section 3.4 clearances were checked for every combination of:

| Joint | Range |
|---|---|
| Rocker (about X, at its pivot) | +-10 degrees |
| Bogie (about X, at its pivot) | +-15 degrees |
| Steering (front, rear counter-steers) | +-30 degrees |
| Mast head pan (`mast_head`, about the vertical) | any angle (checked every 15 degrees) |
| Mast head tilt (`mast_head_camera`, about X) | +-30 degrees |

`rover_visuals.gd` must clamp the rocker and bogie angles to this range (steering is already
limited to +-30 degrees by the physics), so the visuals never reach a pose that was not
clearance-checked. Widening a range means re-running the check in
`tools/blender/scripts/make_rocker_bogie.py` first (`make_mast.py` for the mast head). The mast head
check also confirms that no head geometry is ever inside the game camera's view from
`pivot_camera` (90 degree vertical field of view, checked for a 21:9 screen).

---

## 6. Look

### 6.1 Style
- Low-poly, **flat-shaded** (Shade Flat; the exporter writes split normals).
- Curiosity silhouette from the reference: high clearance, rocker-bogie side profile, mast at the
  front of the deck, arm folded at the front, finned power unit at the rear.
- Wheels: 6 curved spokes, chevron treads, visible hub.

### 6.2 Triangle budget (about 8,000 for the whole rover)

| Part | Triangles |
|---|---|
| chassis | 1,300 |
| rockers | 2 x 230 |
| bogies | 2 x 230 |
| steer brackets | 4 x 150 |
| wheels | 6 x 400 |
| mast_base | 300 |
| mast_head | 500 |
| arm_shoulder / upper / forearm / wrist | 150 / 150 / 150 / 120 |
| arm_tool | 300 |
| motor | 200 |
| power_unit | 400 |
| antenna | 250 |
| **Total** | **7,740** (260 spare) |

Swappable variants keep to their slot's budget.

### 6.3 Materials (shared, tintable)

| Material | Colour | Used for |
|---|---|---|
| `rover_body` | off-white `#E6E2D8` | chassis body, mast head shell |
| `rover_metal` | dark grey `#4A4D52` | linkage, brackets, mast, arm, connectors |
| `rover_dark` | near-black `#1C1D20` | wheels, power unit, motor, lenses |
| `rover_gold` | gold `#C9A227` | small accent on the antenna only |

- Use only these four materials, with these exact names, in every file.
- A `HotswapPart.tint` recolours only the part's main material (`rover_body`, or `rover_dark` for
  wheels, motor and power unit). It must not override the whole mesh.

---

## 7. Collision

- Swappable parts and the chassis carry one simple convex child mesh named `<part>-convcolonly`.
- Suspension parts, the mast base and arm segments have no collision.
- Godot imports `-convcolonly` as a `StaticBody3D`, which cannot live inside the rover's
  `RigidBody3D` (it collides with the rover itself and throws it around). The post-import script
  `game/src/robot/kit/rover_kit_import.gd` replaces it with a plain `CollisionShape3D` named
  `Collision` (Godot only runs import scripts from inside the project). The exporter sets
  `import_script/path` in each GLB's `.import` file. The physics body that uses a part copies
  that shape onto itself; the chassis collider replaces the current `BodyCollision`.

---

## 8. Files and export

- Sources: `tools/blender/parts/<part>.blend`, one part per file. An `_L` / `_R` pair shares one
  file with both roots.
- Exports: `game/res/models/rover_kit/<part>.glb`.
- Exporter: glTF Binary (`.glb`), +Y Up, Apply Modifiers on, no animations, empties visible,
  reference ground plane and helpers excluded.
- In Godot each empty imports as a `Node3D` with the same name; find sockets with
  `find_child("socket_...")`.

### Code changes (after the models, as separate commits)
1. `RunningGear` and `Robot` to 6 wheels (`MIDDLE_LEFT`, `MIDDLE_RIGHT`): spring stiffness per wheel
   x 4/6 (about 2670 N/m) and tyre stiffnesses x 4/6 so rest height and grip stay the same; rear
   counter-steer (`STEER_BIAS` -1); all 6 driven.
2. New `PartType`s (`MAST_HEAD`, `ARM_TOOL`, `ANTENNA`), socket anchors at the kit empties, zero
   mount offsets, per-socket capture size, tint by material.
3. Linkage and wheel-spin animation script; rover camera follows the mast head's `pivot_camera`.
4. Collider import post-script; chassis collision replaces `BodyCollision`.
5. Friction circles from a 2 x 2 to a 2 x 3 layout.
