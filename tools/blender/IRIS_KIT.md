# IRIS Kit Spec

The first mission's other end (`game/docs/ASSET_BRIEF.md`): **A07** IRIS, the research station,
**A06** the diagnostic cartridge, and how Kite, the player's rover, delivers
one to the other.

Renamed from `KITE_KIT.md` on 2026-10-14 (`docs/ASSET_PLAN.md` section 4): the player's rover,
called ROOK here before, is **Kite**; the disabled rover prop that was called Kite is retired, and
its spot, approach gate, service port and delivery are IRIS's. Section numbers are unchanged.

1. The player loads the cartridge onto a cargo mount on the rover's deck, in the workshop's bay.
2. They drive out to IRIS and scan it with the mast camera.
3. They park nose to nose with IRIS and press E.
4. The arm picks the cartridge off the mount, reaches over and lowers it into IRIS's service port.

Same conventions as `ROVER_KIT.md` (rover parts) and `WORKSHOP_KIT.md` (service hardware) unless
this file says otherwise.

Status: **approved 2026-10-09** with these answers:
- deliver with E;
- the scan must come before the insert;
- the target at about 150 m;
- Kite (then called ROOK) is our rover.

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
| IRIS | A static scene: the station of section 6 (body on four legs, service panel, diagnostic port, module socket, mast with indicator and antenna). Never a `Robot`, so it can't be driven, pushed or picked up (the disabled-rover prop this row described is retired). |
| Service port | A bolt-on bracket on IRIS's front, carrying a **top-loading** cartridge port: the cartridge goes **straight down** into it. The arm's straight-ahead reach leaves only 7 cm of parking play for a horizontal insert; straight down leaves 0.12 m. |
| Cargo mount | A low cradle on the rover's deck, under the stowed arm's turret, at (-0.125, 0.20, 0.44). It's the only patch of deck the arm can reach pointing straight down (section 2). |
| Stowed pose | Moves from (0, 90, 90, 90, 0) to **(0, 90, 80, 100, 0)**, lifting the turret 57 mm so it clears a loaded cartridge. The old stowed pose becomes the **latch pose**: the turret's end meets the cartridge's top face. |
| Latch | The cartridge latches to the end of the arm-tool turret's hub, the face along the wrist. It needs no gripper, and works at any turret angle (J5), which the arm uses to match the port's heading. |
| Delivery key | **E**, the existing `interact_use`. In rover mode on the Moon, E does nothing else now (no mast pickup); in the test level, E delivers only while the rover is in a port's parking window, otherwise it picks up as before. The vehicle controller is unchanged. |
| Scanning | Mast view only: hold the crosshair on IRIS within 30 m for 1.5 s. A progress line on the robot HUD, then a "Rover:" subtitle with what the scan found. It has to come before the insert. |
| Pickup rules | Section 10. On foot, never a rover. In rover mode on the Moon, no mast pickup: the rover carries only its cargo mount's load. |
| Site | IRIS at (-204, 136) on the Apollo 12 terrain: 151 m from the workshop, on a bearing of 40 degrees (the bay door faces 30), about 300 m outside every 75 m keep-out zone, on ground under 2.3 degrees (section 7). |

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
- **IRIS** is built in the rover frame (facing +Y, ground at z -0.10) and exported as one GLB,
  `iris.glb`, in `game/res/models/iris_kit/`. It's service hardware like the workshop: the
  workshop's materials (`ws_panel`, `ws_frame`, `ws_dark`, `ws_accent`, `ws_label`, `ws_screen`,
  `ws_status`) plus one of its own, `ir_dust` (8C8579, roughness 0.95), and
  `workshop_kit_import.gd`. Words on it are `Label3D`s on `text_*` anchors, as the decor kit does.
- Generators: `tools/blender/scripts/iris/` (`make_cartridge.py`, `make_cargo_mount.py`,
  `make_iris.py`), sources in `tools/blender/parts/iris/`, previews in
  `tools/blender/previews/iris/`.

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
| Catalog | name "Diagnostic cartridge"; description "IRIS's fault-log reader. The rover's arm delivers it to IRIS's service port."; mounts "Rides on the rover's cargo mount, on the deck" |
| Start | on the workshop rack, `slot_17` (top shelf, left, under CARTRIDGES), lying flat. 0.15 m deep on the 0.16 m usable shelf, 0.08 m tall under 0.18 m of clear height. |

### 4.1 A10 radio-power module, A11 cradle, and the M2 sampling parts (2026-10-14)

Generated by `scripts/iris/make_module.py` (module, cradle) and `scripts/iris/make_sample_kit.py` (scoop,
containers, sample bench, near site). Previews in `tools/blender/previews/radio_module/` and `sample_kit/`.
No mission logic: assets, markers and catalog only.

| | Radio-power module | Module cradle |
|---|---|---|
| File | `rover_kit/radio_module.glb` | `rover_kit/module_cradle.glb` |
| Size | 0.27 x 0.13 x 0.11 m case, 0.282 m with end grips (long side along X) | two rails 0.23 m long, 12 mm thick, 45 mm tall + 4 mm gold caps, 80-92 mm either side of the mount's centre line |
| Origin | middle of the bottom face; on the mount, at `socket_cargo_item` (-0.125, 0.20, 0.505) | `socket_cargo` (-0.125, 0.20, 0.44), like `cargo_mount` |
| Look | `rover_body` case, `rover_dark` plinth, `rover_gold` power band, `rover_metal` grips and latch disc, dark label panel and a gold chevron on top | `rover_metal`, gold caps |
| Markers | `anchor_latch` (0, 0, 0.11), `anchor_pickup` (0, 0, 0.055), `anchor_connector` (0, 0, 0) | none (the mount's `socket_cargo_item` is used) |
| Collision | one box `radio_module-convcolonly` | none |
| Triangles | 142 (budget 350) | 44 (budget 120) |
| Mass (part scene) | **12 kg**: a transceiver, amplifier and power converter in a sealed case; 2.4 x the standard battery, 15 % of Kite. An estimate: `SCIENCE_AND_DATA.md` has the mass sum (`chassis + parts + tools + cargo`) but no part masses | 0.8 kg (not a part scene: it is on Kite) |
| Game | `RadioModulePart` (`radio_module_part.tscn`, CARGO, catalog `radio_module`, tooltip "Radio-power module"); `slot_18` on the workshop rack; `RoverVisuals` attaches the cradle | |

**How it fits IRIS's socket (6.2.1).** The module is as tall as the socket is deep (0.12 m) less 10 mm, so
seated (origin on `anchor_module_seated`, 6 mm over the floor) its hub end is 4 mm under the rim. IRIS's
module socket is on its left side, so Kite parks facing IRIS's +X and the socket's long side (0.32 m) runs
along IRIS's side, which is across Kite: **in the rover frame the module does not turn** (J5 stays within
+-10 degrees for the window's heading range), but **in IRIS's frame it is turned 90 degrees from the
cartridge's pose** (the port's long side is along IRIS's X). The kit's empties never rotate, so
`Iris.module_seat_transform()` returns `anchor_module_seated` turned 90 degrees about up: a seated module
goes there. In the opening it has 19 mm a side along and 43 mm across (needs 10).
`make_module.py` runs the real window: all 27 corners of the socket's parking window reach the approach
(0.10 m above) and the seat with the hub pointing down, the module clear of IRIS by 52 mm and of the rover by
220 mm on the way down.

**On Kite.** Loaded module, mount and cradle: 26.8 mm from the stowed arm (the hub end is 27.8 mm above the
module's top, against the cartridge's 57 mm), 61.7 mm from the mast head at any pan and tilt, 232 mm from the
antenna, out of the mast camera's view (57 degrees outside). The arm over its 12,870-pose joint grid keeps
32.8 mm from the mount with the cradle. The latch pose (hub end on `anchor_latch`) is **J1 0, J2 82, J3 94,
J4 70, J5 0** (the cartridge's is 0 90 90 90 0): `CargoDelivery` needs its own latch and lift poses for the
module, because its top is 30 mm higher.

**On the rack.** Lying flat on the top shelf at `slot_18` (x +0.40), 134 mm deep on the 140 mm the shelf
leaves between its back panel and label rail, 45 mm under the top rail. Its plate reads CARTRIDGES AND MODULE.

| Sampling part | File | Notes |
|---|---|---|
| Scoop (A12) | `rover_kit/sample_scoop.glb`, 0.4 kg | 0.37 m long; origin the grip's centre; handle along +Y, bowl bent 25 degrees down; `anchor_grip`, `anchor_tip` (0, 0.22, -0.046), `anchor_pour`; held by the arm tool, assisted pose only. `sample_scoop_part.tscn`, catalog `sample_scoop` |
| Containers (A13) | `rover_kit/sample_container.glb` (0.5 kg, gauge at 8 %) and `sample_container_full.glb` (0.8 kg, gauge at 90 %) | 90 mm jar, 0.12 m with its lid; origin the middle of the bottom; `container_lid` (its origin is the hinge: turn about X), `container_fill` (the gauge bar, origin at the gauge's bottom: scale its Z), `anchor_pickup`, `anchor_fill`, `anchor_stow`. Part scenes `sample_container_part.tscn` (S-1, near) and `sample_container_far_part.tscn` (S-2, blue stripe via the tint) |
| Lab tray (A12) | `workshop_kit/ws_sample_bench.glb` | 0.70 x 0.40 m bench, tray top at 0.90 m, at `anchor_bench` (4.2, 2.6): the scoop and the two containers lie on the tray; `slot_sample_a`, `slot_sample_b`, `slot_sample_scoop`. `Workshop.sample_bench`, `bench_stock` |
| Near site (A15) | `iris_kit/sample_site_near.glb` | 1.1 m dark patch built in IRIS's frame (instance it with the Iris node's transform) on the terrain, 2 cm proud in the middle and 4 mm at the edge; `anchor_sample` (IRIS frame (2.4, 2.6)), `anchor_marker_post`, `park_sample`. `moon_level.tscn`: `SampleSiteNear` and `SampleSitePost` (a `ws_marker_post`). Kite parks at `park_sample` heading +X (IRIS frame), 1.28 m from the centre: the scoop's tip reaches the ground 0.64 to 0.85 m ahead of the turret's yaw axis, so the patch's centre is at the middle of a 0.21 m window |

### 4.2 M3: the far logger (A16), the far site (A15), the thermal sensor turret (A14), the thermal kit (A17) (2026-10-14)

Generated and checked by `scripts/iris/make_m3_kit.py` (run it before `make_sample_kit.py`, whose bench
preview shows the thermal kit); previews in `tools/blender/previews/m3_kit/`. No mission logic. Masses
and power are estimates (ASSET_PLAN.md A14-A17).

| | File | Notes |
|---|---|---|
| Far logger | `rover_kit/field_logger.glb`, 152 tris (budget 300), 1.6 kg | 0.21 x 0.12 x 0.07 m case on 3 mm feet, origin the middle of its feet at `socket_cargo_item`, long side along X; `anchor_latch` (0, 0, 0.07), `anchor_pickup`, `text_top`, `text_under`. Evan's two labels are `Label3D`s in `field_logger_part.tscn` (Caveat 500, pen blue, 2 degrees crooked, as 6.6). In the cradle: 20 mm to each rail, 14 mm to the corner lips; 56.7 mm from the stowed arm; latch pose J1 0 J2 94 J3 88 J4 100 J5 0 |
| Far site | `iris_kit/sample_site_far.glb`, 176 tris | Head crater's east rim at world (2.0, -58.0); its own frame (origin on the ground at the patch's centre, +Y down the fall line, world bearing 172 degrees from +X). `anchor_sample`, `anchor_marker_post` (the far-rim marker, 6.0 m down the fall line, 0.5 m before the shade), `park_sample` (0.12, -1.27), `anchor_logger` (1.3, 0), `park_logger` (1.42, -1.06). `moon_level.tscn`: `SampleSiteFar`, `FarRimMarker`, `FarLogger` (asleep, tilted to the slope); the script prints their transforms |
| Thermal sensor turret | `rover_kit/arm_tool_thermal.glb`, 236 tris (budget 240), 5.3 kg | `make_arm.build_tool(radiometer)`: the plain sensor at 198 degrees becomes a radiometer reaching 80.5 mm from the hub axis (the drill reaches 95). `pivot_reading` (aperture), `pivot_reading_aim`. J5 -72 points it down; reading pose from `park_sample`: J1 -0.5 J2 -25 J3 14 J4 11 J5 -72, aperture 150 mm over the patch, the arm 149 mm above the ground |
| Thermal kit | `rover_kit/thermal_cover.glb` (174 tris, 0.9 kg), `thermal_heater.glb` (98 tris, 0.6 kg, 12 W) | Origins on the deck at (0.1225, -0.02, 0.44) and (0.12, 0.225, 0.44). Checked against the stowed arm, the arm's 12,870-pose grid, mast and head, antenna, power unit, cargo mount with the logger or module, the low-gain antenna and the camera's view (ASSET_PLAN.md A17) |

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

## 6. A07 IRIS

`make_iris.py` builds the station (2026-10-14; it replaced the box-and-mast placeholder). Fictional,
NASA-inspired equipment (a lander-style instrument box on footpads, like an ALSEP central station
grown up), not a copy of any real station. Its diagnostic port keeps the placeholder's pose exactly
(`PORT_POSE`), so the parking window, the approach route and `tests/test_iris.gd` are unchanged.

### 6.1 The station (IRIS frame = rover frame, heights above the ground)

| Part | IRIS |
|---|---|
| `iris_body` | 2.0 (x) x 1.5 (y) m, **1.3 m tall**: x -1..1, y -1.05..0.45 (the front face where the placeholder's was), from 0.24 to 1.30 m, its vertical edges chamfered 60 mm, a dark lid, base and top rails. Four legs on footpads (0.11 m radius) at (+-0.86, -0.90 / 0.30), **each cut to the terrain under it**, the pads 30 mm in the ground. Right side (+x): a finned radiator. Left side: a handle rail and a vent. Rear: a cable gland. Top: a solar plate on the rear half, facing up and back. Front: panel seams and a name plate (`text_name`, "IRIS"). |
| `iris_service_panel` | **M1's photo target**, on the front's left (x -0.90..-0.20, 0.30-1.17 m), straight under the mast and antenna. A framed `service_door` (hinged on its left edge, its origin on the hinge line, so code can swing it about its local Z) with a stencilled title plate (`text_panel_title`, "SERVICE PANEL S-1") and Evan's handwritten service tag (`text_service_label`). Under the door a connector strip: J1 radio power (the empty socket's), J2 data, J3 heater, **each labelled twice**, a plate above and one below (`text_conn_j1_a` / `_b` ...). `scan_point`: 50 mm in front of the panel's middle. |
| `iris_port` | the diagnostic port bracket (6.2), unchanged |
| `iris_module_socket` | **M2**: the replacement radio-power module's bay, on IRIS's **left side** (beside the service panel), see 6.2.1. Empty: a dark bay with a bare connector on its floor. |
| `iris_mast` | 40 mm, from the lid to 2.62 m at (-0.55, -0.20), with a base flange and a cable duct. |
| `iris_indicator` | the station's lamp, a 0.10 m tall lens on the mast at 2.30-2.40 m between two collars (`ws_status`). |
| `iris_antenna_pan` | pan head on the mast's top: housing, yoke and a fixed axle. Turns about its local Z (Godot Y). |
| `iris_antenna` | the tilting part (hub and boom) with `iris_antenna_dish` (0.26 m radius, a feed): tilts about its local X, + = up. Axle at 2.80 m; the whole station is 2.95 m tall parked. |
| `iris_dust` | four years unattended: drifts banked round the footpads, a ragged dusty band round the body's foot, patches on the lid, a film over the solar plate's lower half (`ir_dust`). In Godot `Iris` also turns every `ws_*` / `rover_*` material (except the lights and the cells) 25% towards dust grey, rougher. |
| Tilt | the port's pose (`PORT_POSE`) sets the whole station's tilt and height: about 1 degree pitch and 1.5 degrees roll; the legs take up the terrain under them. |

### 6.1.1 States (`Iris.set_online(online, instant = false)`)

| | Offline (start) | Online |
|---|---|---|
| `iris_indicator` | dark | green, steady (emissive) |
| Antenna (pan, tilt) | parked (0, -25): the dish nodding down | tracking (35, 40), reached in 3 s (smoothstep) |

- `Iris.is_online`, signal `online_changed(online)`, export `start_online` (for after M2).
- The GLB is exported parked; `ANTENNA_PARKED` / `ANTENNA_TRACKED` are the same numbers in
  `make_iris.py` and `iris.gd`.
- `make_iris.py` sweeps the dish from parked to tracked: it keeps 41.5 mm from the rest of IRIS
  (needs 20).
- The port's status light (6.2) is separate: it tells the cartridge delivery's state.

### 6.2 Service port bracket (`iris_port`)
- **Bracket:** a bracket on IRIS's front face, reaching forward to y 0.82.
- **Port:** a box 0.32 (x) x 0.24 (y) x 0.12 (z) m, top at z 0.46, centred at **(0.08, 0.70)**.
- **Opening:** in its top, 0.26 x 0.16 m, 0.08 m deep, with a 10 mm chamfered lead-in (it
  accepts the cartridge 15 mm off and 8 degrees off).
- Empties:
  - `socket_cartridge` (0.08, 0.70, 0.46), the opening's centre, top;
  - `anchor_cartridge_seated` (0.08, 0.70, 0.38), the cartridge's origin when it's in, long side
    along IRIS's x.
- **Status light:** `iris_status_light`, a 0.20 x 0.03 m strip on the bracket's front face plus a
  small dome on top, `ws_status`. States:
  - red slow blink (1 Hz): fault, waiting;
  - amber pulse for 3 s: the cartridge is reading;
  - green steady: done.
  Its emission makes it visible from the route.
- Collision: the box (`iris_port-convcolonly`). The seated cartridge is frozen and adds none.
- Budget 350 triangles.

### 6.2.1 Module socket (`iris_module_socket`, M2)
- On the **left side**, beside the service panel: a bracket like the port's, 0.35 (along the side,
  IRIS's y) x 0.25 m, sticking out of the side as far as the port sticks out of the front.
- Opening 0.32 x 0.22 m, 0.12 m deep (for A10's ~0.3 x 0.2 m module), 10 mm lead-in, **long side
  along IRIS's y** (a `CargoPort` there needs its X turned 90 degrees to match).
- Its top sits 0.09 m higher on IRIS than the port's, because the ground on that side is higher:
  for a rover parked there it's at z 0.46 in the rover's frame, like the port. So the same arm
  reach and parking window (8.1) apply, the rover facing IRIS's +X.
- Empties: `socket_module` (opening's top centre), `anchor_module_seated` (6 mm over its floor).
- Parking markers: `park_cartridge` and `park_module`, where Kite's origin stops (on the ground)
  for the middle of each window, facing IRIS's -Y and +X.
- Why not on the front beside the port: any bracket there is hit by the parked rover's front
  corner when it stands turned in the window (69 mm, needs 150).
- Collision: the box (`iris_module_socket-convcolonly`).

### 6.3 Scan target
- IRIS's node is in the group `scan_target`, with `scan_name` "IRIS" and `scan_report` (the
  subtitle text).
- Scanned in the mast view only: a ray from the mast camera's centre, 30 m long, against layers 1
  and 2 (IRIS's collision; the terrain in front of it blocks it, as it should). The crosshair has
  to stay on IRIS for 1.5 s, and the progress resets after 0.3 s off target.
- HUD, while aiming (`ScanHint`, a label under the crosshair, like `DockHint`):
  - "SCANNING  IRIS  60%";
  - then "SCANNED  IRIS" for 3 s;
  - when the scan completes, a subtitle through `DialogServer`: "Kite: IRIS. Research station,
    silent: no signal on any band. Diagnostic port open on its front bracket."
- `Iris.scanned(rover)` is emitted once.

### 6.4 Collision
- Three boxes: the body (`iris_body-convcolonly`, from 0.15 m into the ground to its lid, legs
  included, so nothing drives under it), the port and the module socket. The mast and antenna
  have none (above the body).
- Static, layer 2, mask 0 (17).

### 6.5 Budget
2,138 triangles (budget 6,000; ASSET_PLAN A07 says 3-6k, this needs fewer).

### 6.6 Words (`Iris.TEXTS`, `Label3D` on the `text_*` anchors)

| Anchor | Words | Style |
|---|---|---|
| `text_name` | IRIS | stencil (default font, ink) |
| `text_panel_title` | SERVICE PANEL S-1 | stencil |
| `text_service_label` | Radio pwr: J1 / Seals checked / - Evan | handwritten: Caveat (OFL), blue-black pen, 2 degrees crooked |
| `text_conn_j1_a`, `_b` | J1 RADIO PWR (both) | handwritten |
| `text_conn_j2_a`, `_b` | J2 DATA | handwritten |
| `text_conn_j3_a`, `_b` | J3 HEATER | handwritten |

The handwriting is Caveat 500 (`game/res/fonts/caveat-latin-500-normal.woff2`, from
`@fontsource/caveat` 5.3.0; licence in `LICENSE-caveat.txt`). Each label is sized to its plate.

### 6.7 Light on the panel (M1 relies on Kite's headlights)

IRIS's front faces south-west and the sun is in the east, so **the service panel is in IRIS's own
shadow** (7). IRIS stays where it is. M1's photo of the panel, and Evan's labels on it, need Kite's
headlights (**L**). So the M1 objective/hint must prompt **"L  Lights"** once Kite is near IRIS
(within about 15 m, or when the panel is the scan/photo target), and the mission system should
not count a photo of a dark panel as readable if that is ever checked.

---

## 7. Where IRIS sits (Apollo 12 terrain)

| | |
|---|---|
| IRIS's origin | **(-204, 136)** in Godot, ground -3.256 m; its front faces azimuth **219.6** (back towards the workshop) |
| Ground | under 2.3 degrees within 5 m of it (2 m posts, 4 m baseline); no colliding rock (0.2 m and up) within 7 m (the nearest is a 0.48 m rock 7.5 m away) |
| Parking spot (the rover's origin, nose to nose) | (-205.1, 137.3), 1.74 m from IRIS's origin, ground -3.239 |
| Route from the workshop | from the apron's end (-294.6, 245.2) straight to the parking spot: 140 m on a bearing of 39.7 degrees. Slopes 2.0 degrees mean, 4.6 max. One 0.22 m rock 1.4 m off the line. |
| Keep-out | 374 m from the nearest artifact (the LM): about 300 m outside its 75 m zone |
| The terrain test's drive | its route passes 36-46 m from IRIS. IRIS's collision is off it. |
| Light | the port faces south-west and the sun is in the east (16.7 degrees up), so the port's side is in IRIS's shadow. The status light's emission and the rover's headlights (L) light it, which suits the scene. |
| Approach gate (A07) | two `ws_marker_post` posts with a `ws_sign_route` chevron, 1.5 m either side of the approach line, 4 m out from the parking spot. Driving between them lines the rover up. |

Story: IRIS stands 150 m from base, near the north rim of Sharp crater.

---

## 8. The delivery

### 8.1 Parking window
The rover is in position when, measured from **its arm's yaw axis** (rover frame (-0.12, 0.53)) to
the port's centre:
- the horizontal distance is **0.45-0.57 m** (2.1);
- the port's bearing off the rover's heading is **-18 to +13 degrees** (positive = left);
- the rover is stopped (under 0.05 m/s).

Both rovers stand on near-level ground here; `make_iris.py` checks that the port's height in the
rover's frame, with IRIS's actual tilt, stays inside the reach in 2.1.

At the window's middle the rover's front tyres are 0.45 m from IRIS's, and its front face 0.41 m
from the port bracket. `make_iris.py` checks the whole window: the rover's footprint stays 0.15 m
or more from IRIS.

### 8.2 Hint (`CargoHint`, robot HUD)
Within 4 m of a port and carrying matching cargo, the HUD says one of:
- "Scan IRIS first" (until it's scanned);
- "IRIS's port: 0.30 m closer, 0.10 m to the left";
- "IRIS's port: back up 0.10 m";
- "IRIS's port: turn 10 degrees left" (bearing out of range);
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
| 3. Transit | joint-space moves through (0, 90, 70, 110), then aim J1 at the port and turn J5 so the cartridge's long side matches the port's, then the approach pose (the hub end 0.10 m above the port's top) | about 3.5 s |
| 4. Insert | straight down 0.10 m (IK every frame, pointing down) | 1.5 s |
| 5. Release | the cartridge is reparented to IRIS's `anchor_cartridge_seated`, frozen. The port's light turns amber, then green after 3 s. `CargoPort.cargo_inserted` is emitted. | - |
| 6. Retract | up 0.10 m, transit back, stowed | about 4 s |

The keyframes are fixed, so `make_iris.py` checks them in Blender before anything runs in the game:
- the transit and both strokes, sampled every degree, at the parking window's corners;
- the arm and the held cartridge keep 20 mm from the rover itself, the mast head at any pan, the
  cargo mount, IRIS and its port;
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
| `IRIS` (group `iris`) | `scanned(rover)`; `cartridge_inserted(cartridge, rover)` (once, after the green light) |
| `CargoPort` (group `cargo_port`, on IRIS's port) | `cargo_inserted(part, rover)`; `accepts` "cartridge" (a catalog id), so A10's module can use the same port type at IRIS |
| `CargoDelivery` (on the rover) | `delivery_started(port)`, `delivery_aborted(port, reason)`, `delivery_finished(port)` |

The mission console's status page shows "IRIS: not scanned / scanned / cartridge delivered".

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
| Human: IRIS | never (static) | - (no IRIS) |
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
| `kite/kite.gd`, `kite.tscn`, `cargo_port.gd` | new: IRIS, its port, status light, dust materials, signals |
| `ui/` | `CargoHint`, `ScanHint` labels like `DockHint`, and the `CARGO` line: two or three `add_child` lines in `robot_hud.gd` (told to the UI session first) |
| `workshop/workshop.gd` | the cartridge on `slot_17` |
| `moon_level.tscn` | IRIS, the approach gate, `rover_pickup = false` |

---

## 12. Budgets

| Asset | Triangles |
|---|---|
| A06 cartridge | 250 |
| Cargo mount | 120 |
| A07 IRIS (body, panel, mast, antenna, module socket, dust) | about 1,800 |
| IRIS's port bracket and light | 350 |
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
- **`make_iris.py`:**
  - IRIS on the terrain: every footpad in the ground (5 mm or more) with its top above it, the
    body 0.15 m or more above it;
  - the antenna's swing, parked to tracked, 20 mm from everything else;
  - the module socket from its own window: in reach at all 27 corners, the footprint 150 mm away;
  - the port's reach window (2.1) from the actual pose;
  - the delivery path (8.3) at the window's corners, against the rover, the mast head, IRIS and
    the ground;
  - the rover's footprint against IRIS over the window;
  - the approach gate's posts 1.2 m or more from the approach line.

Previews: IRIS from the approach, from above and from the port side; the rover parked with the arm
at the approach and seated poses; the cartridge on the mount, from the chase camera's height.

---

## 14. Test: `tests/test_iris.gd` (headless, Moon)

1. **Load:** the player takes the cartridge from `slot_17`, carries it to the docked rover and lets
   go over the deck. The cargo socket takes it; the HUD's `CARGO` line names it.
2. **Rules:** in rover mode on the Moon, E in the mast view at a loose part picks nothing up; the
   player can't pick up the rover (in the test level both still work).
3. **Drive:** from the console, out of the bay (the door opens), along the route to the approach
   gate. The wheel checks of `test_wheel_contact.gd` run every tick; the rover never touches IRIS.
4. **Scan:** the mast view aimed at IRIS from 15 m, the crosshair held 1.5 s. `IRIS.scanned` fires
   once; the subtitle shows.
5. **Park:** creep into the window, steered by the hint's offsets. The hint says "In position".
6. **Interrupted insert:** E, then throttle 2 s later. The sequence aborts, the cartridge is back
   on the mount, the arm stows, `delivery_aborted` fires.
7. **Insert:** E again. `cargo_inserted` fires once within 15 s; the cartridge is at
   `anchor_cartridge_seated` within 5 mm; IRIS's light goes green; the arm ends stowed.
   Throughout: the arm's ground clearance stays at 20 mm or more; no arm or cartridge point comes
   within 10 mm of IRIS's collision (shape queries every frame).
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
4. **Names (resolved 2026-10-14):** the brief's rover is Kite, the player's rover; the damaged
   twin is retired and its role goes to IRIS (`docs/ASSET_PLAN.md` section 4).
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
   keeps that: the cartridge travels as a frozen child of the turret, and IRIS's port accepts it
   by script, not by physics. The arm can't push anything.
9. **The workshop rack's slot_17** was reserved for "A06 cartridges"; this uses it.
10. **`rover_gold`** is "a small accent on the antenna only" in ROVER_KIT 6.3. The cartridge's
    stripe would make it the antenna and the cartridge; otherwise the stripe can be `rover_body`.

---

## 16. Open questions

1. **E** for delivery (recommended), or a separate **G**?
2. Must the scan come **before** the insert (recommended: the hint says "Scan IRIS first"), or is
   it optional?
3. (Retired with the disabled rover prop.)
4. Is 150 m right for the first sortie (about a minute's drive), or further out?

---

## 17. As built (2026-10-09; IRIS placeholder 2026-10-14)

Where the build differs from the sections above, this wins.

| | Spec | Built | Why |
|---|---|---|---|
| Port box | 0.32 x 0.24 m | **0.34 x 0.24 m** | room for the wider opening |
| Opening | 0.26 x 0.16 m | **0.28 x 0.17 m** | the cartridge's grips are 0.262 m across; at 0.26 the stroke hit the lead-in |
| Release | on the seat | **6 mm over the seat** (`SEAT_GAP`), then `CargoPort.accept` puts it on the seat | a release exactly on the floor counted as touching it |
| IRIS's colliders | layer 1 | **layer 2, mask 0** | on layer 1 the wheels' ground check (layers 1, 3) would drive up IRIS's body and the arm's ground check (layer 1) would see the port as terrain and stop the stroke. Rovers (mask 71) still collide with it; the player's mask leaves layer 2 out, which doesn't matter on the Moon, where the player stays inside. The wheels also don't climb the fallen wheel now; it's off the approach |
| Lift pose | (0, 90, 60, 120, 0) | **(0, 90, 70, 110, 0)** | J4's range is +-110: the visuals clamped 120 and tilted the cartridge 10 degrees. The latch still points straight down; the cartridge rises 113 mm off the mount |
| IRIS triangles | about 6,600 (the retired prop) | **2,138** (budget 6,000) | the placeholder had 204 |
| Cartridge, cargo mount | 250, 120 triangles | **124, 84** | |

**Checks** (`make_iris.py` on the station, 2026-10-14; the same numbers as on the placeholder; all 27 corners of the parking window, each pose sampled along the
whole path: latch, lift, transit, turn, stroke, release): all OK. Arm vs IRIS 31.1 mm (need 20),
cartridge vs IRIS 60.5 mm, cartridge vs the port before the stroke 25.6 mm, during the stroke
6.7 mm (need 3), at the release 3.7 mm over the floor; cartridge vs the rescuer 37.8 mm; the arm
357 mm and the cartridge 472 mm over the ground; the rescuer's wheels and body 157.8 mm from IRIS
(need 150); the cartridge squared to the port within 0.5 degrees. The station: footpads 30 mm in
the ground, their tops 20 mm above it, the body 180 mm above it; the dish 41.5 mm from the rest
over its swing; the module socket in reach at 27 of 27 corners of its window (its top at z 0.460
in the rover's frame), the footprint 154.8 mm from IRIS there.

**Game** (`tests/test_iris.gd`, all 20 checks pass; 2026-10-14 adds IRIS offline then online, and its 9 labels): loading from the rack, the Moon's pickup rules,
the drive out of the bay and 150 m to IRIS (route right of the base sign), the scan (once), parking
by the hint (the test's controller stops 8 cm short and then creeps the distance the hint asks for,
like a driver), an insert interrupted by throttle (cartridge back on the mount, arm stowed), the
insert (seated 0.0 mm off, `cargo_inserted` then `cartridge_inserted` once each, green light, arm
stowed; the arm about 360 mm above the terrain at its lowest and never inside IRIS outside the port's opening;
the rover never touched IRIS and tilted at most 5 degrees), and the test level's sandbox rules
(the player lifts a rover; the mast camera picks a part up). Every other suite passes unchanged.

**Previews** in the game's lighting: `game/tools/render_iris_previews.gd` (window) writes
`tools/previews/iris/`: IRIS from the gate (offline), its service panel, the module socket, the
mast view scanning, parked with the hint, from above, the carry and the stroke from beside, IRIS's
green light, and IRIS online. Blender previews (`tools/blender/previews/iris/`, git-ignored):
parked and tracked, front, sides, rear, top, the service panel and the ports close.
