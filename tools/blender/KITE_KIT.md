# Kite Kit Spec

The first mission's other end (`ASSET_BRIEF.md`): **A05** the disabled Kite rover, **A06** the
diagnostic cartridge, and how the player's rover delivers one to the other.

1. The player loads the cartridge onto a cargo mount on the rover's deck, in the workshop's bay.
2. They drive out to Kite and scan it with the mast camera.
3. They park nose to nose with Kite and press E.
4. The arm picks the cartridge off the mount, reaches over and lowers it into Kite's service port.

Same conventions as `ROVER_KIT.md` (rover parts) and `WORKSHOP_KIT.md` (service hardware) unless
this file says otherwise.

Status: **approved 2026-10-09** with these answers:
- deliver with E;
- the scan must come before the insert;
- Kite's damage as proposed, at about 150 m;
- ROOK is our rover.

Changes from the proposal:
- **Lifting a rover:** the player can't pick up or throw a rover **on the Moon**. The test level
  keeps it, like its other sandbox behaviours (`RoverLevel.player_lifts_rovers`, default true; the
  Moon sets false).
- **Where the code goes:** `RoverVisuals` may change. `Robot.gd` gets small hooks only; the
  delivery and scanning logic lives in new nodes.

The cargo mount's rover kit changes are in ROVER_KIT.md section 9.

---

## 1. Decisions

| Topic | Decision |
|---|---|
| Kite | A static scene built from the rover kit's own meshes in a damaged, parked pose: rear-left wheel off and lying beside it, mast bent and its head drooped, arm sheared at the shoulder, antenna stuck, everything dusty. It's a `StaticBody3D` on layer 1, never a `Robot`, so it can't be driven, pushed or picked up. |
| Service port | A bolt-on bracket on Kite's front, carrying a **top-loading** cartridge port: the cartridge goes **straight down** into it. The arm's straight-ahead reach leaves only 7 cm of parking play for a horizontal insert; straight down leaves 0.12 m. |
| Cargo mount | A low cradle on the rover's deck, under the stowed arm's turret, at (-0.125, 0.20, 0.44). It's the only patch of deck the arm can reach pointing straight down (section 2). |
| Stowed pose | Moves from (0, 90, 90, 90, 0) to **(0, 90, 80, 100, 0)**, lifting the turret 57 mm so it clears a loaded cartridge. The old stowed pose becomes the **latch pose**: the turret's end meets the cartridge's top face. |
| Latch | The cartridge latches to the end of the arm-tool turret's hub, the face along the wrist. It needs no gripper, and works at any turret angle (J5), which the arm uses to match the port's heading. |
| Delivery key | **E**, the existing `interact_use`. In rover mode on the Moon, E does nothing else now (no mast pickup); in the test level, E delivers only while the rover is in a port's parking window, otherwise it picks up as before. The vehicle controller is unchanged. |
| Scanning | Mast view only: hold the crosshair on Kite within 30 m for 1.5 s. A progress line on the robot HUD, then a "Rover:" subtitle with what the scan found. It has to come before the insert. |
| Pickup rules | Section 10. On foot, never a rover. In rover mode on the Moon, no mast pickup: the rover carries only its cargo mount's load. |
| Site | Kite at (-204, 136) on the Apollo 12 terrain: 151 m from the workshop, on a bearing of 40 degrees (the bay door faces 30), about 300 m outside every 75 m keep-out zone, on ground under 2.3 degrees (section 7). |

---

## 2. What it's sized against (measured 2026-10-09)

### 2.1 The arm (ROVER_KIT 3.3, its own joint ranges)
Forward kinematics from the kit's joint positions and lengths:
- shoulder pitch axis (-0.09, 0.53, 0.345);
- upper arm 0.36, forearm 0.33, wrist 0.07, turret hub 0.05;
- yaw axis at (-0.12, 0.53).

They reproduce the kit's documented "reaching down" pose: the drill tip is 31 mm above flat ground.
"Hub end" below is the end face of the turret's hub, where the cartridge latches.

| Reach | Result |
|---|---|
| Hub end pointing straight down over the deck | only x -0.24 to -0.04, y 0.2 to 0.4, z 0.58 to 0.72 (the patch behind the shoulder). The lowest is the old stowed pose: (-0.125, 0.20, 0.585). |
| Hub end pointing straight ahead (horizontal insert) at z 0.2-0.45 | 0.60-0.81 m in front of the yaw axis. With the 0.13 m insert stroke inside that, only **0.07 m** of parking play. Not used. |
| Hub end pointing straight down in front (top-loading port, top at z 0.46, 0.10 m stroke) | **0.43-0.59 m** in front of the yaw axis. 0.45-0.57 m with joint-limit margins: **0.12 m** of parking play. |
| Sideways | yaw J1 -20 to +15 degrees (positive = left). With 2 degrees of margin, the port may be **-18 to +13 degrees** off straight ahead: about 0.3 m of sideways play at 0.51 m. |
| Turning the load | J5 turns the turret (any angle) about the hub axis. Pointing down, that's the vertical axis, so the cartridge can be turned to the port's heading whatever the rover's heading. |

Key poses (J1, J2, J3, J4 in degrees; J1 aims and J5 turns separately):

| Pose | Joints | Hub end (rover frame) |
|---|---|---|
| Stowed (new) | 0, 90, 80, 100 | (-0.125, 0.205, 0.642), pointing down |
| Latch | 0, 90, 90, 90 | (-0.125, 0.200, 0.585), pointing down, on the cartridge's top face |
| Over the port, 0.51 m out (approach) | 59.8, -55.7, -94.1 | 0.10 m above the port's top, pointing down |
| Seated, 0.51 m out | 58.5, -71.1, -77.4 | at the port's top (the cartridge's top face flush) |
| Seated, at the window's near / far edge (0.43 / 0.59 m) | 71.0, -89.6, -71.4 / 43.7, -46.1, -87.6 | J3 and J4 within 1-2 degrees of their limits there, hence the 0.45-0.57 m window |

### 2.2 The rover
- Width 1.26 m and length 1.55 m (WORKSHOP_KIT 2.1).
- Ride height 0.10 m, so a rover-frame z is 0.10 m more above the ground.
- The mast camera is at (0.15, 0.42, 1.05).

### 2.3 Turning (for the route and the parking)
Full-lock radius 1.02-1.30 m on the Moon (WORKSHOP_KIT as built). A driver who misses the
parking window backs up and tries again; the hint (8.2) tells them which way.

---

## 3. Conventions

- **Cartridge and cargo mount** are rover kit parts and follow ROVER_KIT 2: rover frame, origin at
  the connection point, `socket_*` / `pivot_*` / `anchor_*` empties with zero rotation, only the four
  `rover_*` materials, `-convcolonly` colliders, `rover_kit_import.gd`, exports in
  `game/res/models/rover_kit/`. The cartridge gets one accent stripe in `rover_gold` (now used by
  the antenna and the cartridge).
- **Kite** is built from rover kit meshes (unchanged) in its own frame, the rover frame (origin at
  where its physics origin would be, facing +Y). It's exported as one GLB, `kite.glb`, in
  `game/res/models/kite_kit/`.
- **Kite's port bracket** is service hardware: workshop materials (`ws_frame`, `ws_panel`,
  `ws_dark`, `ws_accent`, `ws_status`), `workshop_kit_import.gd`.
- Generators: `tools/blender/scripts/kite/` (`make_cartridge.py`, `make_cargo_mount.py`,
  `make_kite.py`), sources in `tools/blender/parts/kite/`, previews in
  `tools/blender/previews/kite/`.

---

## 4. A06 diagnostic cartridge

| | |
|---|---|
| Size | **0.25 (x) x 0.15 (y) x 0.08 (z) m**, lying flat, long side across the rover |
| Origin | the middle of its bottom face, the face that seats on the mount and in the port |
| Look | a `rover_dark` case with chamfered edges, two ribbed grip strips on the ends, a `rover_gold` stripe round the middle, and a 60 mm `rover_metal` latch disc on top. A recessed `rover_body` label panel on the top for a `Label3D` ("KITE DIAG"). |
| Empties | `anchor_latch` (0, 0, 0.08): the top face's centre, where the arm's hub end meets it. `anchor_pickup` (0, 0, 0.04): its middle, where a hand holds it (the player's hold point). |
| Collision | one box, `cartridge-convcolonly`, 0.25 x 0.15 x 0.08 |
| Budget | 250 triangles |
| Game | `CartridgePart` (`cartridge_part.tscn`, a `HotswapPart`), new `PartType.CARGO`, `catalog_id` "cartridge", mass 2 kg |
| Catalog | name "Diagnostic cartridge"; description "Kite's fault-log reader. The rover's arm delivers it to Kite's service port."; mounts "Rides on the rover's cargo mount, on the deck" |
| Start | on the workshop rack, `slot_17` (top shelf, left, under CARTRIDGES), lying flat. 0.15 m deep on the 0.16 m usable shelf, 0.08 m tall under 0.18 m of clear height. |

---

## 5. Cargo mount (rover kit part)

### 5.1 Where
- On the deck at **`socket_cargo` (-0.125, 0.20, 0.44)**, a new empty on the chassis.
- That's under the stowed arm's turret, left of centre and behind the arm's shoulder.
- It's the only deck patch the arm reaches pointing straight down (2.1), and nothing else uses it:

| Neighbour | Clearance to a loaded cartridge (x -0.25 to 0.0, y 0.125 to 0.275, z 0.505 to 0.585) |
|---|---|
| Mast base (0.15, 0.35), 30 mm radius | 0.12 m in x |
| Mast head, any pan / tilt | over 0.3 m (it's at z 0.95 and up) |
| Antenna, its swept envelope round (-0.15, -0.25) | 0.25 m in y |
| Low-gain antenna post (0.15, -0.30) | 0.4 m |
| Stowed arm (new pose): wrist housing, turret | hub end 57 mm above the cartridge's top; the tools radiate in a plane about 80 mm above it |
| Stowed arm: forearm over the deck (z 0.705) | 0.12 m |
| Upper arm (standing at y 0.53) | 0.22 m in y |
| Mast camera's forward view | behind the mast, out of view; the chase camera sees it |

`make_cargo_mount.py` checks each of these at 20 mm or more, and checks the arm over its whole
range against the empty mount (section 5.4).

### 5.2 Shape (`cargo_mount`, fixed part, built by RoverVisuals like `mast_base`)
- Origin `socket_cargo`.
- A 0.29 x 0.19 m frame on four short legs: the cartridge's bottom face sits at z 0.505, 65 mm
  above the deck, with 20 mm corner lips.
- `socket_cargo_item` (-0.125, 0.20, 0.505): where the cartridge's origin goes.
- `rover_metal`, 120 triangles, no collision (the cartridge's own collider rides with it).

### 5.3 Loading and unloading (human mode, in the bay)
- A `HotswapSocket` on the rover, `CargoSocket`:
  - `accepted_type` CARGO, `anchor` `socket_cargo_item`, zero mount offset;
  - capture box 0.40 x 0.25 x 0.30 m above the cradle, trigger box over it.
- Loading works like the wheel sockets: carry the cartridge to the rover and let go of it over
  the deck (or throw it in); the socket snaps it in.
- E on the mount takes it out, as for any part.
- The tooltip says "Cargo mount: empty. Diagnostic cartridge goes here" or "Press E to take out
  Diagnostic cartridge".
- The robot HUD shows a `CARGO` line under `BATTERY`: "CARGO  Diagnostic cartridge" or
  "CARGO  empty".

### 5.4 The arm with cargo
- While the cargo mount holds something, manual arm control (R, 1-5, Z / X) is off and the HUD's
  arm line says "ARM  cargo loaded: automatic only". The arm stays stowed except during a
  delivery.
- This keeps the turret out of the cartridge: the existing full-range check has no cartridge in
  it, and the manual joints can reach the latch pose.
- The empty mount stays in the full-range check (`make_arm.py` gets it as an obstacle). If any
  pose comes within 20 mm, the mount gets lower, not the ranges smaller.

---

## 6. A05 Kite

### 6.1 Pose and damage (Kite frame = rover frame, rover kit meshes unchanged)

| Part | Kite |
|---|---|
| Chassis, linkage, five wheels | as the rover. The rear-left wheel is gone, so its bogie end rests on the ground: the chassis rolls about 4 degrees left and pitches about 3 degrees nose-up. The exact pose comes from the terrain under each wheel (`make_kite.py` reads `play.f32`), wheels touching the ground. |
| Rear-left wheel | `wheel_L`, lying on its side 1.2 m behind and left of Kite, half buried (0.05 m) |
| Rear-left steer bracket | bent: turned 25 degrees outward about its steer axis and 15 degrees down |
| Mast | `mast_base` tilted 12 degrees towards the rear-left; head panned 70 degrees, camera tilted down 30 degrees (dead) |
| Arm | sheared at the shoulder: only `arm_shoulder`'s fixed mount remains (no yaw turntable, no arm) |
| Antenna | dish stuck at 50 degrees tilt, pan 160 |
| Motor | gone (failed drive unit); the hatch is behind the port bracket |
| Power unit | as the rover |
| Dust | Godot swaps Kite's `rover_*` materials for dusty copies (lighter, greyer, rougher). Nothing new is modelled. |

### 6.2 Service port bracket (`kite_port`)
- **Bracket:** a bracket bolted to Kite's front face over the motor hatch, reaching forward to
  y 0.82.
- **Port:** a box 0.32 (x) x 0.24 (y) x 0.12 (z) m, top at z 0.46, centred at **(0.08, 0.70)**
  (clear of the arm stub at x -0.12).
- **Opening:** in its top, 0.26 x 0.16 m, 0.08 m deep, with a 10 mm chamfered lead-in (it
  accepts the cartridge 15 mm off and 8 degrees off).
- Empties:
  - `socket_cartridge` (0.08, 0.70, 0.46), the opening's centre, top;
  - `anchor_cartridge_seated` (0.08, 0.70, 0.38), the cartridge's origin when it's in, long side
    along Kite's x.
- **Status light:** `kite_status_light`, a 0.20 x 0.03 m strip on the bracket's front face plus a
  small dome on top, `ws_status`. States:
  - red slow blink (1 Hz): fault, waiting;
  - amber pulse for 3 s: the cartridge is reading;
  - green steady: done.
  Its emission makes it visible from the route.
- Collision: the box (`kite_port-convcolonly`). The seated cartridge is frozen and adds none.
- Budget 350 triangles.

### 6.3 Scan target
- Kite's node is in the group `scan_target`, with `scan_name` "KITE" and `scan_report` (the
  subtitle text).
- Scanned in the mast view only: a ray from the mast camera's centre, 30 m long, against layer 1
  (Kite's collision; the terrain in front of it blocks it, as it should). The crosshair has to
  stay on Kite for 1.5 s, and the progress resets after 0.3 s off target.
- HUD, while aiming (`ScanHint`, a label under the crosshair, like `DockHint`):
  - "SCANNING  KITE  60%";
  - then "SCANNED  KITE" for 3 s;
  - when the scan completes, a subtitle through `DialogServer`: "Rover: Kite. Survey rover,
    disabled: drive unit failed, arm lost, rear-left wheel off. Diagnostic port open on its front
    bracket."
- `Kite.scanned(rover)` is emitted once.

### 6.4 Collision
- Chassis box and five wheel cylinders (convex), the port box, and the fallen wheel (cylinder).
- Static, layer 1. The rover's wheels drive over the fallen wheel if they hit it (0.30 m: a big
  step; it's off the approach).

### 6.5 Budget
About 6,600 triangles: the kit's meshes (about 6,000 without the arm and motor, plus the fallen
wheel), the port bracket 350, and the arm stub. Inside the brief's 10-20k for a station-sized
object.

---

## 7. Where Kite sits (Apollo 12 terrain)

| | |
|---|---|
| Kite's origin | **(-204, 136)** in Godot, ground -3.256 m; its front faces azimuth **219.6** (back towards the workshop) |
| Ground | under 2.3 degrees within 5 m of it (2 m posts, 4 m baseline); no colliding rock (0.2 m and up) within 7 m (the nearest is a 0.48 m rock 7.5 m away) |
| Parking spot (the rover's origin, nose to nose) | (-205.1, 137.3), 1.74 m from Kite's origin, ground -3.239 |
| Route from the workshop | from the apron's end (-294.6, 245.2) straight to the parking spot: 140 m on a bearing of 39.7 degrees. Slopes 2.0 degrees mean, 4.6 max. One 0.22 m rock 1.4 m off the line. |
| Keep-out | 374 m from the nearest artifact (the LM): about 300 m outside its 75 m zone |
| The terrain test's drive | its route passes 36-46 m from Kite. Kite's collision is off it. |
| Light | the port faces south-west and the sun is in the east (16.7 degrees up), so the port's side is in Kite's shadow. The status light's emission and the rover's headlights (L) light it, which suits the scene. |
| Approach gate (A07) | two `ws_marker_post` posts with a `ws_sign_route` chevron, 1.5 m either side of the approach line, 4 m out from the parking spot. Driving between them lines the rover up. |

Story: Kite stopped 150 m from base, near the north rim of Sharp crater, on the last leg home.

---

## 8. The delivery

### 8.1 Parking window
The rover is in position when, measured from **its arm's yaw axis** (rover frame (-0.12, 0.53)) to
the port's centre:
- the horizontal distance is **0.45-0.57 m** (2.1);
- the port's bearing off the rover's heading is **-18 to +13 degrees** (positive = left);
- the rover is stopped (under 0.05 m/s).

Both rovers stand on near-level ground here; `make_kite.py` checks that the port's height in the
rover's frame, with Kite's actual tilt, stays inside the reach in 2.1.

At the window's middle the rover's front tyres are 0.45 m from Kite's, and its front face 0.41 m
from the port bracket. `make_kite.py` checks the whole window: the rover's footprint stays 0.15 m
or more from Kite and its fallen wheel.

### 8.2 Hint (`CargoHint`, robot HUD)
Within 4 m of a port and carrying matching cargo, the HUD says one of:
- "Scan Kite first" (until it's scanned);
- "Kite's port: 0.30 m closer, 0.10 m to the left";
- "Kite's port: back up 0.10 m";
- "Kite's port: turn 10 degrees left" (bearing out of range);
- "In position: press E to insert the cartridge";
- "Inserting the cartridge" / "Cartridge inserted";
- "Insert interrupted: the rover moved. Park again and press E.";
- "Mount the arm tool turret" (the latch is on the turret).

It's the same kind of label as `DockHint`, and shows the offset to the window's middle in the
rover's own frame.

### 8.3 The sequence (`CargoDelivery`, a node on the rover)
E in the window starts it. The arm moves at up to 45 degrees/s, the stroke at 0.07 m/s:

| Phase | Arm | Time |
|---|---|---|
| 1. Latch | stowed, then the latch pose (the hub end meets the cartridge's top) | 0.5 s |
| 2. Lift | the cartridge leaves the mount: it's reparented from the cargo socket to the turret's `pivot_latch` | - |
| 3. Transit | joint-space moves through (0, 90, 60, 120), then aim J1 at the port and turn J5 so the cartridge's long side matches the port's, then the approach pose (the hub end 0.10 m above the port's top) | about 3.5 s |
| 4. Insert | straight down 0.10 m (IK every frame, pointing down) | 1.5 s |
| 5. Release | the cartridge is reparented to Kite's `anchor_cartridge_seated`, frozen. The port's light turns amber, then green after 3 s. `CargoPort.cargo_inserted` is emitted. | - |
| 6. Retract | up 0.10 m, transit back, stowed | about 4 s |

The keyframes are fixed, so `make_kite.py` checks them in Blender before anything runs in the game:
- the transit and both strokes, sampled every degree, at the parking window's corners;
- the arm and the held cartridge keep 20 mm from the rover itself, the mast head at any pan, the
  cargo mount, Kite and its port;
- the cartridge is never lower than 0.10 m above the ground.

### 8.4 Ground safety
- The path stays well above the ground: the insert happens at the port's top, 0.56 m above the
  ground.
- `RoverVisuals`' ground check (rays down from the forearm, wrist and turret) stays on. If a step
  would bring the arm within 20 mm of the terrain, the sequence aborts (8.5) instead of pressing
  on.

### 8.5 Interruptions
- **The rover moves** (its origin drifts 0.03 m or turns 2 degrees from where the sequence
  started, or throttle or steering input arrives): the sequence aborts.
  - Before the stroke: the arm carries the cartridge back to the latch pose, the cargo socket
    takes it back, and the arm stows.
  - Mid-stroke: it lifts straight out first.
  - The hint says "Insert interrupted". Nothing is lost.
- **The driver leaves the rover (Esc):** the sequence runs on; the parked rover doesn't move.
- **Another E while it runs:** ignored.
- **The level unloads:** everything goes with it; nothing to undo.
- **No tool turret on the arm:** the sequence doesn't start ("Mount the arm tool turret").

### 8.6 Signals for the mission system

| Where | Signal |
|---|---|
| `Kite` (group `kite`) | `scanned(rover)`; `cartridge_inserted(cartridge, rover)` (once, after the green light) |
| `CargoPort` (group `cargo_port`, on Kite's port) | `cargo_inserted(part, rover)`; `accepts` "cartridge" (a catalog id), so A10's module can use the same port type at IRIS |
| `CargoDelivery` (on the rover) | `delivery_started(port)`, `delivery_aborted(port, reason)`, `delivery_finished(port)` |

The mission console's status page shows "KITE: not scanned / scanned / cartridge delivered".

---

## 9. Input
The current bindings:

| Key | Action |
|---|---|
| W, A, S, D | move / drive |
| Space, Ctrl, Shift | jump, crouch, sprint |
| E | `interact_use` |
| Left / right mouse | throw / rotate |
| R, 1-5, Z, X | arm |
| F | reset rover |
| C | camera |
| L | lights |
| = / - and the wheel | zoom |
| ` | console |
| Esc | leave / pause |

Free letters include Q, T, G, V, B, H.

- **E** delivers (8.3), so no new key: E is already "interact".
- On the Moon, E in rover mode has nothing else to do.
- In the test level, E picks up as before unless the rover is in a port's window, where
  delivering wins.
- If the team would rather have a separate key, `cargo_deliver` on **G** is free; it would need
  one action in `project.godot` and one line in `RobotController`, which is the controller edit
  the brief asks to avoid.
- Scanning needs no key (hold the crosshair).

---

## 10. What can be picked up or moved

| | Moon | Test level |
|---|---|---|
| **Human (on foot)**: loose parts and the cartridge | pick up, carry, drop, throw | same |
| Human: parts on a rover | mount and take out at its sockets (in the bay) | same (anywhere) |
| Human: the cargo mount | load (drop or throw the cartridge into it) and unload (E) | same |
| Human: a rover | **never** (new) | pick up and throw, as now (sandbox) |
| Human: Kite | never (static) | - (no Kite) |
| Human: workshop fixtures, rack, doors, console | never (static); doors and console by their triggers | same |
| Human: test props (Box, Text, Sphere, see-saw plank) | - | pick up, as now |
| **Rover mode**: mast camera | look, zoom, **scan**; **no pickup** | look, zoom, scan, and pickup, hold and throw as now (for testing) |
| Rover: cargo | carries only what's on its cargo mount; the arm delivers it to a matching port (E) | same, where a port exists |
| Rover: physics | pushes loose things it drives into (wheels and body) | same |

`RoverLevel.rover_pickup` (default true) turns the mast pickup on; the Moon sets false.

The mast camera's catalog description changes from "The rover's eyes. Required to pick things up
from the rover." to **"The rover's eyes: drive by it, look around and scan things."**

---

## 11. Code changes (as small as possible)

`RobotController` (the vehicle controller) is **not** touched: the delivery uses its existing
`interact` signal and reads `desired_speed` / `steer` to notice driving.

| File | Change |
|---|---|
| `socket/hotswap_part.gd` | `PartType.CARGO` appended |
| `socket/part_catalog.gd` | "cartridge" entry, CARGO's default, the mast camera's text |
| `socket/cartridge_part.gd` / `.tscn` | new: a `HotswapPart` with the cartridge GLB |
| `robot.tscn` | `CargoSocket` (a `HotswapSocket`), `CargoDelivery`, `RoverScanner` nodes |
| `robot.gd` | about 10 lines: the mast pickup only if the level allows it; E goes to `CargoDelivery` first when it's in a window |
| `kit/rover_visuals.gd` | `ARM_STOWED` to the new pose; builds `cargo_mount`; `set_arm_override(joints)` / `clear_arm_override()` for scripted poses (about 30 lines); manual arm control off while cargo is loaded or an override is on |
| `kit/cargo_delivery.gd` | new: parking window, IK (2-link, from the arm's own socket positions), phases, abort, signals |
| `kit/rover_scanner.gd` | new: the mast scan ray, progress, `scan_target` |
| `player/player.gd` | 2 lines: no `Robot` pickup where the level forbids it |
| `levels/rover_level.gd` | `rover_pickup` and `player_lifts_rovers` exports (both default true; the Moon sets both false) |
| `kite/kite.gd`, `kite.tscn`, `cargo_port.gd` | new: Kite, its port, status light, dust materials, signals |
| `ui/` | `CargoHint`, `ScanHint` labels like `DockHint`, and the `CARGO` line: two or three `add_child` lines in `robot_hud.gd` (told to the UI session first) |
| `workshop/workshop.gd` | the cartridge on `slot_17` |
| `moon_level.tscn` | Kite, the approach gate, `rover_pickup = false` |

---

## 12. Budgets

| Asset | Triangles |
|---|---|
| A06 cartridge | 250 |
| Cargo mount | 120 |
| A05 Kite (kit meshes, without the arm and motor, plus the fallen wheel) | about 6,000 |
| Kite's port bracket and light | 350 |
| Approach gate (2 posts, 1 sign) | about 150 |
| **Total new on the Moon** | **about 6,900** |

That's about 0.1% of the 5.3 M the Moon level draws a frame. No new lights: the status light is
emissive, and the rover's headlights already exist.

---

## 13. Checks before each part is done

- **`make_cartridge.py`:** size to 1 mm, budget, names, the empties, the collider.
- **`make_cargo_mount.py`:**
  - the mount and a loaded cartridge keep 20 mm from the stowed arm (new pose), the mast, the
    antenna (swept) and the deck parts;
  - the arm over its whole range against the empty mount (`make_arm.py`'s product check);
  - the new stowed pose stays out of the mast camera's view (the existing view check).
- **`make_kite.py`:**
  - Kite's pose on the terrain (every remaining wheel touching, nothing in the ground);
  - the port's reach window (2.1) from the actual pose;
  - the delivery path (8.3) at the window's corners, against the rover, the mast head, Kite and
    the ground;
  - the rover's footprint against Kite over the window;
  - the approach gate's posts 1.2 m or more from the approach line.

Previews: Kite from the approach, from above and from the port side; the rover parked with the arm
at the approach and seated poses; the cartridge on the mount, from the chase camera's height.

---

## 14. Test: `tests/test_kite.gd` (headless, Moon)

1. **Load:** the player takes the cartridge from `slot_17`, carries it to the docked rover and lets
   go over the deck. The cargo socket takes it; the HUD's `CARGO` line names it.
2. **Rules:** in rover mode on the Moon, E in the mast view at a loose part picks nothing up; the
   player can't pick up the rover (in the test level both still work).
3. **Drive:** from the console, out of the bay (the door opens), along the route to the approach
   gate. The wheel checks of `test_wheel_contact.gd` run every tick; the rover never touches Kite.
4. **Scan:** the mast view aimed at Kite from 15 m, the crosshair held 1.5 s. `Kite.scanned` fires
   once; the subtitle shows.
5. **Park:** creep into the window, steered by the hint's offsets. The hint says "In position".
6. **Interrupted insert:** E, then throttle 2 s later. The sequence aborts, the cartridge is back
   on the mount, the arm stows, `delivery_aborted` fires.
7. **Insert:** E again. `cargo_inserted` fires once within 15 s; the cartridge is at
   `anchor_cartridge_seated` within 5 mm; Kite's light goes green; the arm ends stowed.
   Throughout: the arm's ground clearance stays at 20 mm or more; no arm or cartridge point comes
   within 10 mm of Kite's collision (shape queries every frame).
8. **Test level:** the mast pickup still works there; E at a loose part picks it up.

`test_level_switch.gd` changes: on the Moon its rover picks up a rack part, which the new rules
forbid. It will load the cargo mount instead.

---

## 15. Conflicts with the brief and the existing code

1. **The player can pick up the rover.** README 15.5 and `Player._on_controller_interact` say so:
   "the player can pick up and throw the robot like any other prop (mass 80)". Your rules say
   never; the player change (11) ends it in both levels, and the README line goes.
2. **The mast camera's job.** Its catalog text says it's "required to pick things up from the
   rover", and README 15.4 says picking up aims with the mast camera. On the Moon that's gone (10).
   The test level keeps it, so the text gets the neutral wording above.
3. **"Do not edit the vehicle controller."** `RobotController` stays as it is. `Robot.gd` (the
   body) gets about 10 lines and `RoverVisuals` about 30: gameplay code, not an art task. If those
   count as "the vehicle controller" for the brief, the delivery has to live entirely in new
   nodes. That's possible, but the pickup gate would then have to sit in `ObjectHolder`.
4. **The brief calls the rover "ROOK"** ("Reuse ROOK model"); nothing in the code or the specs
   does. I've taken ROOK to be the existing rover kit and Kite to be its damaged twin. Please
   confirm the names.
5. **The stowed pose changes.** ROVER_KIT 5's stowed pose and its checks (clearance, 357 mm above
   the ground, out of the mast camera's view) were measured for (0, 90, 90, 90, 0). The new pose
   is within the checked ranges, so the clearances hold, but the camera-view and ground figures get
   re-measured. `test_wheel_contact`, `test_level_switch` and anything else posing the arm keep
   working; nothing asserts the stowed angles.
6. **The arm tool is optional.** The latch is on the turret, which the player can take off. The
   delivery then refuses with a hint (8.2). The alternative, a latch on the wrist, would put the
   cartridge on the wrong side of the turret's tools.
7. **The brief's second sortie** (A10, "cargo mount and matching service socket") is this same cargo
   mount and port type, so it's built once here. A10's module needs its own port at IRIS and a
   catalog entry.
8. **The arm is visual only** (ROVER_KIT 5, README 15.3c): it has no collision. The delivery
   keeps that: the cartridge travels as a frozen child of the turret, and Kite's port accepts it
   by script, not by physics. The arm can't push anything.
9. **The workshop rack's slot_17** was reserved for "A06 cartridges"; this uses it.
10. **`rover_gold`** is "a small accent on the antenna only" in ROVER_KIT 6.3. The cartridge's
    stripe would make it the antenna and the cartridge; otherwise the stripe can be `rover_body`.

---

## 16. Open questions

1. **E** for delivery (recommended), or a separate **G**?
2. Must the scan come **before** the insert (recommended: the hint says "Scan Kite first"), or is
   it optional?
3. Kite's damage: the rear-left wheel off and the arm sheared, as proposed, or something lighter?
4. Is 150 m right for the first sortie (about a minute's drive), or further out?
