# Workshop Kit Spec

Modular low-poly kit for the lunar workshop in `game/docs/ASSET_BRIEF.md` (LAST LIGHT): **A01** the workshop
(operator area and rover service bay), **A02** the charging/service pad, **A03** the mission
console, **A04** the parts rack and its labels, **A07** the navigation and dock markers. Same
conventions as `ROVER_KIT.md` unless this file says otherwise. **Every workshop part follows
this spec.**

Status: **approved 2026-10-09**, with these answers and changes:
- door facing azimuth 30;
- 3.0 m ceiling;
- the player stays inside on the Moon;
- driving starts from the console;
- the cartridge reader's spot is reserved now and modelled with A06;
- the workshop is one scene used by both levels;
- the dock zone is 0.4 m, with guide lines, an on-screen hint and a probe that finds the rover;
- bigger rack labels.

**Built 2026-10-09.** Models: `tools/blender/scripts/workshop/` (every generator's checks pass);
game: `game/src/workshop/` (game README, "The workshop"); test: `game/tests/test_workshop.gd`
(Moon level and test level, all pass). Where the build differs from the text below, this list
wins:

- **Heights.** Walls 3.45 m (a 5 cm parapet over the roof, so no roof face lies in a wall face);
  roof slab 3.25-3.40 m with the beams below it, 3.00-3.25 (clear height 3.0 m under the beams,
  3.25 m between them); the partition reaches the slab, 3.25 m.
- **Plinth:** against the wall face (y 0 to 0.05 out), z -0.30 to +0.05, no collision.
- **Bay door leaf:** 3.95 x 2.475 m, 25 mm from the jamb plates and the header (the swing check:
  20 mm least, at full open). Open, it reaches 2.40 m out. Its bottom edge turns through a slot in
  the threshold (inside the floor slab, out of sight). Its 25 mm gaps let thin lines of low
  sunlight into the bay, so Godot adds a shadow-only panel behind the closed leaf.
- **Personnel door leaf:** on the operator face 20 mm off the trims, pivot (2.21, -2.0, 0.0);
  the partition's fastener heads are on the bay face only (the leaf slides over the operator face).
- **Lamps and lights:** wall lamps at the rack (-1.8, -3.8, 2.3), over the door inside
  (1.6, 3.8, 2.6) and on the operator area's east wall (4.8, 0.0, 2.6); `light_rack` (-1.8, -3.45,
  2.15), `light_door` (1.6, 3.45, 2.45), `light_operator` (4.45, 0.0, 2.45). Energies, set in
  renders (`game/tools/render_workshop_previews.gd`): bay key 6, rack lamp 2.2, door lamp 1.6,
  operator lamp 1.4, exterior flood 2; reflection probe ambient 0.75. The bay key light leaves
  the ground (terrain chunks and rock field, render layer 10) out of its shadow casters.
- **Console screen:** bottom edge z 0.966, top 1.314 (0.36 m tall at 15 degrees).
- **Rack labels:** 65 mm capitals, except MAST CAMERA (63 mm) and TOOL TURRET (55 mm), shrunk to
  fit their plates.
- **Stepped rack.** Level depths from the bottom up: 0.48, 0.40, 0.28, 0.18 m (fronts at y -3.32,
  -3.40, -3.52, -3.62); the uprights step back with them. Each part stands 2 cm behind its own
  level's front, so it sits 60-100 mm in front of the shelf above it: in view and in reach from the
  walkway at any distance (`make_rack.py` checks the sight lines from 0.3-2.5 m, standing and
  crouched; `test_workshop.gd` reaches every part from 0.45, 1.2 and 2.0 m). The battery lies on
  its side turned so its 0.355 m side runs across the shelf. The restock button is beside the
  east upright at shelf 1's step, (1.21, -3.41, 0.90). The rack's footprint is unchanged (0.48 m
  deep at the floor), so it doesn't change the U-turn's margin (5.2).
- **Markers:** the stripes round the bay door's swing outside are left out (the regolith there
  isn't flat); the 0.30 m tall sign plate is 16 px tall at 10 m (22 px wide). The Moon level has a
  base sign on a post at the apron's end; route and heritage posts wait for the route work.
- **Rover turning, measured** as speed over yaw rate in steady full-lock turns (an earlier note
  here gave 0.66-0.78 m at a crawl: that came from averaging distances to the centroid of a part
  circle, which reads too small, and is wrong): Moon 1.02-1.30 m at 0.55-0.90 m/s; Earth gravity
  1.13 m at 0.42 m/s, 1.15 m at 0.72 m/s, 1.22 m at 1.63 m/s. Slower than about 0.4 m/s it
  widens again (1.36 m at 0.19 m/s on Earth gravity). The bay is checked over 1.0-1.3 m.
- **Spawn:** unrotated (the player moves along its pivot's own basis, so a turned spawn would walk
  off its view); the console turns the player to face the screen.
- **Triangles:** 6,720 for the assembled workshop, 102 part instances (`make_layout.py`). Per
  part: wall panel 196, window 274, bay door frame and leaf 256, roof tile 40, partition 96-168,
  pad 182, charger 136, rack 384, console 328, marker post 58.
- **Frame rate** (MacBook Pro M4, 1920 x 1080, vsync off, `measure_moon_fps.gd`): standing in the
  bay facing the docked rover 148.6 fps (6.73 ms), against 164.6 fps (6.08 ms) facing the rover
  outside in the same run: +0.65 ms. p99 14.5 ms (14.6-18.1 ms in the other phases of that run).
- **Astronaut** (`ASTRONAUT_KIT.md`, 2026-10-10):
  - `ws_suit_stand` (122 triangles), with the empty suit, in the operator area's south-east
    corner: origin (4.0, -3.8), collision x 3.55 to 4.45, y -3.80 to -3.00.
  - `anchor_seat` (3.22, -0.30) in `ws_layout`, for `ws_stool` (172) and the seated operator,
    which `Workshop` shows only while the console drives the rover. Neither has collision.
  - The layout now has 103 part instances and 6,914 triangles.
  - The walkway and reach checks are unchanged, plus "walking past the suit stand" (0.18 m
    clear).
- **p99 frame times are not a workshop regression.** Measured back to back, three runs each,
  alternating with the commit before the workshop (8761955): in the runs that kept the window's
  focus the old commit's p99 was 12.5-18.0 ms against 10.1-17.3 ms now, phase for phase; the
  README's earlier chase-camera p99 was 12-14 ms. The spread is the machine (other apps using CPU,
  the window losing focus and being throttled to 30 fps). The tool's "on foot" phase had moved
  inside the workshop with the spawn; it walks outdoors again from the old spawn spot.

The brief overrides earlier asset plans. Its delivery contract applies to every part here:
`.blend` source plus `.glb` export, metres, applied transforms, separately named moving pieces,
marked pivots and anchors, collision proxies kept apart from the visible meshes, blank screens
for Godot UI, and a provenance note. Every part in this kit is an original design built by
script, with no borrowed meshes or textures.

---

## 1. Decisions

| Topic | Decision |
|---|---|
| Size | Outer footprint 10.0 x 8.0 m (the brief's figure). Interior clear height 3.0 m, roof top 3.4 m. |
| Split | Rover service bay on the west side (6.85 m wide inside), operator area on the east side (2.65 m), with a partition between them: a glazed upper half and a sliding personnel door. |
| Rover flow | The rover drives in through a 4.0 m bay door, U-turns inside the bay, and stops on the pad facing the door. It always leaves by driving forwards, with no reversing. |
| Driving | **Starts from the console** (E). The player's body stays at the console while the rover is driven, and Esc returns the view there. No drive trigger beside the rover. |
| The player stays inside | On the Moon the player never leaves the workshop. An invisible pressure curtain across the bay door stops the player (collision layer 8, in the player's mask only) but not the rover or parts. The test level turns the curtain off (`airlock_barrier = false`) so its on-foot play can walk in and out. |
| Bay door | Fold-down ramp: it hinges at the floor and lies flat outside when it's open. This is the abstracted airlock. It opens only for a driven rover coming or going, and closes once the doorway is empty. |
| Pad | Flush with the floor: no lip for the wheels or the player. **Dock zone: the rover's origin within 0.4 m of the dock point, at any heading, stopped.** The charge probe travels under a 1.0 m contact plate to wherever the rover's belly is, then rises to it (6.1). Guide lines on the pad and a dock hint on the rover HUD. |
| Charger status | One status material on the cabinet beacon and the pad edge strips. Godot sets its colour and blink pattern. |
| Console | Faces the bay through the partition window. Its screen is one blank 16:9 quad, and Godot draws what's on it. The cartridge reader's spot and anchor are reserved; the reader is modelled with A06. |
| Rack | On the bay's back wall, directly behind the docked rover. The existing part pickups sit on numbered slots. Each shelf has a full-width label rail. Labels are blank plates for `Label3D` text with a 65 mm cap height. |
| Markers | Floor markings with no collision, and posts with one thin collider each. |
| Reuse | One Godot scene, `workshop.tscn`, in the Moon level and in the test level. The level places the rover; the workshop owns the rack stock. |
| Site | On the graded Apollo 12 base, with the door facing azimuth 30 (north-north-east, towards the EVA routes). Over 435 m outside every 75 m keep-out zone (section 4). |
| Lighting | One shadowed light inside and four without shadows. The interior fill comes from a reflection probe (section 8). |

---

## 2. What the layout is sized against (measured 2026-10-09)

### 2.1 Rover (assembled kit, `game/res/models/rover_kit/*.glb` at their sockets)

| | Value | Source |
|---|---|---|
| Width | **1.26 m** (wheel outer faces at x +-0.628, including the 8 mm hub plug) | wheel GLBs at x +-0.50 |
| Length, arm stowed | **1.55 m**: front tyres at y +0.65, power unit fins at y -0.896 | wheel and power_unit GLBs |
| Length, arm deployed | 2.24 m (tool turret to y +1.34) | arm pose `0, 0, -45, 45, 0` |
| Height above ground | **1.22 m** (mast head 1.19 m at rest, up to about 1.22 m with the camera tilted); antenna dish up to 0.85 m | mast GLBs |
| Ride height | origin 0.10 m above ground (Moon: 10.2 cm), chassis belly 0.30 m, hazcams 0.26 m | README Level gravity, ROVER_KIT 3.4 |
| Clear zone under the belly | x +-0.25, y +-0.45 (relative to the origin), down to the ground: no linkage there | ROVER_KIT 3.2 |
| Tightest turn | **1.07 m** path radius for the origin (30% throttle, full lock, Moon); 1.15 m on Earth | README Level gravity table |
| Turn centre | on the middle-axle line (y = 0), because the rear wheels counter-steer | ROVER_KIT 1 |
| Swept radius in that turn | **1.82 m** (outer tyre corners, stowed or deployed arm alike); power unit 1.48 m | computed from the above |
| Kit triangles | 6,308 | ROVER_KIT 6.2 |

A faster turn is wider. A player who overshoots can make a three-point turn (`S` reverses). The
keep-clear zone (5.2) has room for the tightest U-turn plus at least 0.48 m on every side.

### 2.2 Player (`game/src/player/player.tscn`)

| | Value |
|---|---|
| Capsule | radius 0.25 m (0.50 m wide), height 2.0 m standing, 1.0 m crouched |
| Eye height | 1.5 m standing, 1.25 m crouched |
| Interact / pickup reach | 3 m ray from the eye (layers 1, 3, 5, 6) |
| Camera | FOV 90 (vertical), 1920 x 1080 |
| Moon jump | 1.2 m, so the capsule top reaches 3.2 m. The 3.0 m ceiling stops it: a harmless bump, and nothing in the bay needs a jump. |
| Walk | 2.0 m/s, which crosses the workshop in 5 s |

Walkway rule for this kit: **at least 1.0 m clear** wherever the player has to walk past the
docked rover or a fixture, and at least 0.8 m at any pinch point. That's twice the capsule.
The rover can stop anywhere in the 0.4 m dock zone, so the walkways are checked with the rover
at the worst edge of the zone.

---

## 3. Conventions (differences from ROVER_KIT section 2)

### 3.1 Units, axes, origin
- 1 Blender unit = 1 m, with transforms applied (rotation 0, scale 1). Never negative scale.
- **Kit origin = the middle of the footprint, on the finished floor top (z = 0).** The bay door
  is in the **+Y** wall. glTF "+Y Up" makes that **-Z in Godot**, the same as the rover's
  forwards direction, so a rover modelled facing the door is facing out.
- Every part's GLB has its root at its own origin (listed per part). `ws_layout` places it in
  the kit frame.
- Each `.blend` has a 1 m `ref_cube`, the player capsule (r 0.25, h 2.0), and the rover's
  footprint box (1.26 x 1.55 x 1.22 m) docked at `dock_point`. They're named `ref_*` and left out
  of the export.

### 3.2 Naming
- Lowercase and underscores only, no `.001` suffixes, and none of Godot's import suffixes except
  `-convcolonly` (section 9). As in ROVER_KIT 2.2: **no name may end in** `_wheel`, `_col`,
  `_colonly`, `_convcol`, `_convcolonly`, `_rigid`, `_vehicle`, `_navmesh`, `_occ`, `_occonly`,
  `_noimp`, `_loop` or `_cycle`. That's why rack slots are numbered (`slot_01`) and never named
  after their part (`slot_wheel` would import as a `VehicleWheel3D`).
- Module parts: `ws_<module>`. Moving pieces have their own names (`bay_door`,
  `personnel_door`, `charge_probe`).
- Empty prefixes. Empties have zero rotation and scale 1, and are visible at export. The one
  exception is `place_*`, which turns about Z by a multiple of 90 degrees.

| Prefix | Meaning |
|---|---|
| `pivot_*` | hinge or slide reference for a moving piece, or a camera point |
| `anchor_*` | a gameplay point: charging contact, pickup or service position |
| `slot_NN` | where a loose part's origin rests on the rack |
| `label_NN` | the centre of a blank label plate (`Label3D` goes 2 mm in front of it) |
| `trigger_*` | the centre of a Godot `Area3D`. Its size is in section 9.2. |
| `light_*` | where a Godot light goes. Its aim and settings are in section 8. |
| `place_<part>_NN` | in `ws_layout`: where an instance of `<part>.glb` goes, with its turn about Z |
| `dock_point` | where the docked rover's origin goes |
| `spawn_player` | the player's spawn in the operator area |

### 3.3 Grid
- Exterior walls, floor and roof are on a **2.0 m grid**: x at -5, -3, -1, 1, 3, 5 and y at
  -4, -2, 0, 2, 4. Walls are 0.20 m thick (exterior face on the grid line, interior face 0.20 m
  in), so the interior runs x -4.8 to +4.8 and y -3.8 to +3.8.
- The partition is off the grid, at x 2.05 to 2.15 (section 5.3).

### 3.4 Clearances
- At least **0.48 m** between the rover's swept U-turn envelope and any fixture, and 0.30 m
  between a rover driving straight from the dock point and the door frame.
- At least 20 mm between moving pieces and anything they pass (ROVER_KIT 2.6), over their full
  motion: the bay door's swing, the personnel door's slide and the probe's travel.

---

## 4. Placement on the Moon (Apollo 12 base patch)

The base is the graded 46 x 32 m patch at (-300, 252), x -323 to -277 and z 236 to 268 in
Godot. It sits on a 0.46 degree plane falling to azimuth 146 and has no rocks
(`terrain.json` `authored_changes`, `spots`).

| | Value |
|---|---|
| Kit origin in Godot | **(-302.0, -5.37, 260.0)**, rotation **y = -30 degrees** (the door faces azimuth 30) |
| Floor top | **y = -5.37**: 13 mm above the highest ground under the footprint (-5.383) so the terrain never shows through the floor. Recompute at integration from `play.f32` (Jolt's triangle split) if the terrain changes. |
| Ground under the footprint | -5.383 to -5.491. The plinth (5.1) reaches 0.30 m below the floor and covers the gap, which is 12 cm at most. |
| Door threshold | ground -5.416, so the floor is 4.6 cm above the ground outside. The open ramp door bridges it (5.4). |
| Apron (door to 12.5 m out) | ground -5.43 to -5.36, inside the base, lit by the sun |
| Corners in Godot | NW (-304.3, 254.0), NE (-295.7, 259.0), SW (-308.3, 261.0), SE (-299.7, 266.0). All inside the base. |
| `dock_point` / `spawn_player` in Godot | (-302.58, 260.01) / (-297.71, 260.17) |
| Keep-out (75 m) | the nearest point of the building or apron is **510 m from the LM** (435 m margin), 516 m from the ALSEP (441 m) and 556 m from Surveyor 3 (481 m) |
| Sun (EVA 2: 16.72 degrees up, azimuth 90.62) | lights the door facade at 60.6 degrees off its normal (cos 0.47, so it reads in sunlight). The east wall (operator side) is fully lit. The building's shadow (11.3 m, to the west) stays inside the base. Very little sun reaches the bay through the door. |

Why azimuth 30 rather than due north: a door facing north would sit 0.6 degrees behind the sun's
plane, a black facade over a lit apron. A door facing east would let the 16.7 degree sun shine
8 m into the bay and blind the rover camera on its way out. At 30 degrees the facade is lit, the
EVA routes leave towards the north-east (LM at azimuth 50, Head crater at 42), and the bay keeps
its own lighting.

The Moon level's outdoor base layout goes:
- `SpawnPoint` moves to `spawn_player`;
- `ReadyRover` moves onto `dock_point`;
- the parts go on the rack;
- `ReadyRoverTrigger`, the outdoor `PartsPile` and `RespawnPartsTrigger` are removed.

`terrain.json` `spots` (the lost-zone return points) stay as they are: on the Moon the player
can't leave the workshop.

---

## 5. A01: workshop layout (kit coordinates, metres)

### 5.1 Shell modules

| Module | Size (x, y, z) | Origin | Where | Count |
|---|---|---|---|---|
| `ws_wall_panel` | 2.0 x 0.20 x 3.4 | middle of the exterior face's bottom edge | the perimeter, except the door and the window | 15 |
| `ws_wall_window` | 2.0 x 0.20 x 3.4, window 1.2 x 0.6 m, sill at 1.2 m | same | east wall, y 0 to 2 (operator area) | 1 |
| `ws_wall_bay_door` | 4.0 x 0.20 x 3.4, opening 4.0 x 2.5 m | same | north wall (+Y), x -3 to +1 | 1 |
| `ws_corner` | 0.20 x 0.20 post, 3.7 tall (z -0.30 to 3.4) | the post's outer corner, floor level | 4 corners | 4 |
| `ws_floor_tile` | 2.0 x 2.0, top at z 0, slab 0.25 thick | tile centre, top | the whole footprint | 20 |
| `ws_plinth` | 2.0 long skirt from z 0 to -0.30, 0.05 thick, set 0.05 m out from the wall face | middle of its top edge | the perimeter, not under the door | 16 |
| `ws_roof_tile` | 2.0 x 2.0, ceiling at 3.0, roof top at 3.4, one exposed beam | tile centre, floor level | the whole footprint | 20 |
| `ws_work_lamp` | 0.35 x 0.20 x 0.15 wall lamp, amber lens | its back face | section 8 | 3 |
| `ws_door_panel` | 0.30 x 0.08 x 0.40 control panel | its back face | north wall interior, (-3.6, 3.8, 1.2) | 1 |

- Wall modules are modelled in the north-wall pose (exterior face toward +Y), and `place_*`
  turns them.
- Walls are double-sided: pale panels outside and in, dark frame members at both module edges,
  and modelled fastener heads along the frames every 0.5 m (the brief's "visible fasteners").
  The bay door frame has hazard-striped jambs (`ws_accent`).

### 5.2 Rover service bay (x -4.8 to +2.05)

Revised after the build: the dock point moved 0.4 m west (to x -0.5), so a rover docked anywhere
in its zone drives straight out with at least 0.47 m to the door's east jamb (it was 0.07 m from
the zone's east edge); the way in drifts west inside the bay before the U-turn.

| Item | Position / extent | Notes |
|---|---|---|
| Bay door opening | x -3.0 to +1.0, z 0 to 2.5 | 4.0 m: 2.74 m wider than the rover |
| The way in | through the door on x = -2.2 heading -Y, drifting west inside the bay to x = -2.8 by y 0.2, then a U-turn on full lock round a centre on y = -0.8, then forwards onto the pad | the rover spans x -2.83 to -1.57 in the door (0.17 m from the west jamb), 0.32 m from the door frame where the drift starts |
| U-turn | full-lock radius 1.0-1.3 m (measured, below) about (-2.8 + radius, -0.8) | it ends 0.00-0.30 m across from the dock point, inside the zone, and a short creep forwards docks it |
| **Keep-clear zone** | x -3.6 to +1.0, y -2.85 to +3.8 | no fixtures; floor chevrons mark the way in and out, stripes the zone's west edge (A07) |
| `dock_point` | **(-0.5, -0.3, 0.10)**, heading +Y | the rover spans x -1.13 to +0.13, y -1.20 to +0.35 |
| Dock zone | a circle of 0.4 m radius round the dock point (for the rover's origin) | any heading |
| Pad (A02) | x -2.0 to +1.0, y -2.3 to +1.7 (3.0 x 4.0 m) | flush with the floor |
| Rack (A04) | x -1.35 to +1.15, y -3.8 to -3.32 (stepped, 6.3), z 0 to 1.8 | back wall, behind the pad |
| Charger cabinet (A02) | x 1.65 to 2.05, y 2.7 to 3.5, z 0 to 1.6 | on the partition's bay face, next to the door |
| Bay door control panel | `ws_door_panel`, centre (-3.6, 3.76, 1.2) | north wall, west of the door |
| Bay key light | `light_bay_key` (-0.5, -0.8, 2.95) | over the pad, pointing down |
| Work lamps | `light_rack` (-1.8, -3.45, 2.15), `light_door` (1.6, 3.45, 2.45) | amber |

Clearance check (`make_layout.py`; nominal, then worst with the rover anywhere in the 0.4 m zone):

| Pair | Gap | Rule |
|---|---|---|
| Docked rover right flank to partition (2.05) | **1.92 m**, worst 1.52 m square to the pad, 1.25 m at any heading | >= 1.0 |
| Docked rover rear to rack front (-3.32) | **2.12 m**, worst 1.70 m | >= 1.0 |
| Docked rover left flank to west wall (-4.8) | 3.67 m, open floor | >= 1.0 |
| Docked rover front to door wall (3.8) | 3.45 m, worst 3.05 m | |
| Docked rover front-right corner to cabinet | 2.80 m, worst 2.25 m | >= 1.0 |
| U-turn envelope to the rack | 0.81 / 0.64 / **0.49 m** at radius 1.0 / 1.15 / 1.3 m | >= 0.48 |
| Rover driving out straight from the dock point, to the east jamb (+1.0) / west jamb (-3.0) | 0.87 m / 1.87 m | >= 0.30 |
| Same from the zone's east / west edge | **0.47 m** / 1.27 m | >= 0.30 |
| Door control panel to the rover in the door | 0.62 m | |

No route the player needs goes between a tyre and a fixture with less than 1.25 m.

### 5.3 Partition (x 2.05 to 2.15, y -3.8 to +3.8)

From south to north, all 0.10 m thick and 3.0 m tall. Each module's origin is in the middle of
its bottom edge, on the partition's centre plane (x 2.10).

| Module | y range | Contents |
|---|---|---|
| `ws_partition_solid` | -3.8 to -2.6 | solid wall |
| `ws_partition_door` | -2.6 to -1.4 | opening 1.0 x 2.1 m (y -2.5 to -1.5) and the moving `personnel_door` leaf |
| `ws_partition_window` | -1.4 to +0.6 | solid to 1.0 m, glazing 1.0 to 2.4 m, solid above |
| `ws_partition_window` | +0.6 to +2.6 | same |
| `ws_partition_solid` | +2.6 to +3.8 | carries the charger cabinet on its bay face |

- The personnel door opens onto the space between the rover's rear and the rack: rack, rear
  socket and pad are all within 2 m of it.
- The 2.1 m door head leaves 0.10 m above the standing capsule.

### 5.4 Moving pieces

| Piece | In | Pivot (kit) | Motion | Range | Godot |
|---|---|---|---|---|---|
| `bay_door` | `ws_wall_bay_door.glb` (child) | `pivot_bay_door` (-1.0, 3.92, 0.0): hinge along X at the floor, on the leaf's inner bottom edge | rotates about X; open = **-90 degrees** (top swings out to +Y) | 0 to -90 | rotate about X by the same angle |
| `personnel_door` | `ws_partition_door.glb` (child) | `pivot_personnel_door` (2.18, -2.0, 0.0) | slides along -Y on the operator face, 1.0 m | 0 to 1.0 m | +Z by the same distance |
| `charge_probe` | `ws_pad.glb` (child) | `pivot_charge_probe` (-0.5, -0.3, 0.0) | moves in x and y up to 0.4 m (under the contact plate), then rises along +Z 0.28 m | 0.4 m radius, 0 to 0.28 | x, -z, +y |

- **Bay door:** a 4.0 x 2.5 x 0.08 m leaf with ribs on its outer face. Open, it lies flat
  outside from y 3.92 to 6.42 with its ribbed (outer) face down, its smooth top flush with the
  floor (z 0) at the hinge, and its free end chamfered to a 10 mm edge. That edge sits 3.7 cm
  above the regolith there, which the rover's 0.15 m wheels drive over easily.
- The door's swing sweeps 2.5 m outside: A07 floor markings fence that strip.
- Status lights on separate meshes so Godot can blink them: `bay_door_light` (above the opening)
  and `personnel_door_light`.
- **Pressure curtain** (the player-only barrier): no mesh. Godot adds a 4.0 x 0.10 x 2.5 m box
  on layer 8 across the door opening, at y 3.85.

### 5.5 Operator area (x 2.15 to 4.8)

| Item | Position | Notes |
|---|---|---|
| Console (A03) | desk x 2.15 to 2.80, y -0.9 to +0.3, against the partition | the operator stands at x about 3.2 and looks west over the screen, through the window, at the docked rover |
| `spawn_player` | (3.8, 2.0, 0.0), facing -X | |
| Operator light | `light_operator` (3.4, 0.0, 2.95) | |
| `anchor_bench` | (4.2, 2.6, 0.9) | the sample bench (`ws_sample_bench`, 0.70 x 0.40 m, tray top at 0.90 m; IRIS_KIT.md 4.1) stands here: the scoop and two sample containers lie on its tray at `slot_sample_a`, `slot_sample_b`, `slot_sample_scoop`, and the M3 thermal kit on its low shelf (top 0.25 m) at `slot_thermal_cover`, `slot_heater`; its colliders are the top, the low shelf and the legs. Placed by `Workshop`, not by `ws_layout` |

Clearance: console front (2.80) to east wall (4.8) is **2.00 m**: 0.8 m to stand at the console
and 1.2 m to walk behind the operator.

---

## 6. Parts, pivots and anchors per asset

### 6.1 A02 charging / service pad

Origin of `ws_pad`: the dock point on the floor, (-0.5, -0.3, 0.0).

| Object | Shape | Material |
|---|---|---|
| `ws_pad` | 3.0 x 4.0 plates, 2 mm proud of the floor (visual only; the floor carries the collision). Edge chevrons, and **guide lines**: a dashed centre line along the pad (the way in and out) and two wheel-track lines at +-0.5 m from it, 0.05 m wide. A **1.0 x 1.0 m contact plate** (grating) round the dock point with an amber border, and a 0.80 m dock-zone circle painted on it. | `ws_floor`, `ws_accent`, `ws_frame` |
| `pad_status_light` (child) | two 3.6 m strips along the pad's long edges (0.04 wide, flush) | `ws_status` |
| `charge_probe` (child) | a carriage foot, a telescoping post 0.12 m in diameter and a 0.10 m contact head. At rest it's hidden under the contact plate (its top at z 0.002). Raised, the top stops at z 0.28, **20 mm under the rover's belly**. | `ws_frame`, contact head `ws_accent` |
| `ws_charger` | the cabinet, 0.40 x 0.80 x 1.6 m: vents, a cable gland, and a 0.12 m beacon dome on top. Origin: the middle of its back face's bottom edge, (2.05, 3.1, 0.0). | `ws_panel`, `ws_frame` |
| `charger_status_light` (child) | the beacon dome plus a 0.30 x 0.06 strip on the cabinet front | `ws_status` |
| `ws_cable_cover` | a flush floor strip, 0.12 wide and 5 mm high, from the cabinet (1.65, 3.1) to the contact plate's corner (0.4, 0.2), at an angle across the lane. Origin at the cabinet end. | `ws_frame` |

Empties: `dock_point` (-0.5, -0.3, 0.10), `anchor_charge` (-0.5, -0.3, 0.30) (the belly contact
point for a rover exactly docked), `pivot_charge_probe`, `trigger_dock`, `trigger_charger`.

**Docking rule (Godot, `charging_pad.gd`):**
- The rover's origin is within **0.4 m** of `dock_point` horizontally, at any heading, slower
  than 0.05 m/s, with a battery mounted.
- The probe slides under the contact plate to the point below the rover's origin (0.6 s), then
  rises (0.8 s). Below the origin it's always inside the belly's clear zone: 0.25 - 0.06 =
  0.19 m to the chassis edge at any heading.
- If the rover moves more than 0.05 m from where the probe met it, the probe drops back (fault
  for 2 s, then it tries again).
- Charging calls `BatteryPart.add_charge()`. The rate is an export, `charge_power` (default 2000
  W: a flat 100 Wh battery is full in 3 minutes).

**Dock hint** (`DockHint` on the robot HUD, like `BoundaryHint`), while the driven rover is
within 3 m of a pad. It shows one of:
- "Charging pad: 0.8 m ahead, 0.3 m to the right": the offset to the zone, in the rover's own
  frame, while it's outside the zone;
- "Stop here to charge": inside the zone and still moving;
- "Charging 63%" / "Charged 100%";
- "No battery to charge".

**Status light states** (colour and pattern, so colour-blind players can tell them apart):

| State | Colour | Pattern |
|---|---|---|
| Idle, pad empty | dim white | steady |
| Rover on the pad, not in the dock zone | amber | slow blink, 1 Hz |
| Connected, charging | green | pulse, 0.5 Hz |
| Full | green | steady |
| Fault (no battery, or the rover moved) | red | fast blink, 4 Hz |

### 6.2 A03 mission console

Desk 1.2 x 0.65 x 0.9 m (the brief's figure). The top is at 0.9 m and the operator stands.
Origin: the middle of the desk's back edge on the floor, (2.15, -0.3, 0.0).

| Object | Shape | Material |
|---|---|---|
| `ws_console` | a dark steel frame and a pale desk top. The front edge has a sloped control deck (15 degrees) with modelled toggle switches (8), two rotary dials and a T-handle. A screen housing sits on the back edge. The cartridge reader's spot is a flat blank panel on the deck's right side (0.16 x 0.10 m). | `ws_panel`, `ws_frame`, `ws_dark`, `ws_accent` |
| `console_screen` (child) | **one quad, 0.64 x 0.36 m (16:9), 2 triangles**, UVs exactly 0-1 (u along the screen's width, v down), centre (2.30, -0.3, 1.14), tilted back 15 degrees, facing +X (the operator). Bottom edge 1.05 m, top 1.31 m, just under the 1.5 m eye, so the operator looks over it through the window. | `ws_screen` (near-black, which Godot replaces) |

- No text or UI in any texture. Godot puts a `SubViewport` texture on `ws_screen`. For now it's
  a plain status page: rover, battery and dock state, and "E: drive". The mission UI belongs to
  the UI work.
- Empties:
  - `trigger_console` (2.55, -0.3, 1.1): E drives the workshop's rover;
  - `pivot_console_view` (2.85, -0.3, 1.30), the camera point for a zoom onto the screen, 0.60 m
    from it, looking at its centre;
  - `anchor_prompt_console` (2.30, -0.3, 1.40), just above the screen, where a world-space E
    prompt can go if the crosshair tooltip isn't enough;
  - `anchor_cartridge` (2.62, 0.05, 0.93), the cartridge reader slot. Reserved; the reader is
    modelled with A06;
  - `anchor_operator` (3.2, -0.3, 0.0), where the player stands while driving.

### 6.3 A04 parts rack and labels

Wall rack 2.5 x 0.5 x 1.8 m (the brief's figure). Origin: the middle of its back edge on the
floor, (-0.1, -3.8, 0.0).
- The back panel is pale (`ws_panel`), so the near-black wheels, motor and power unit stand out
  against it. The frame is `ws_frame`.
- **Each level has a full-width label rail**: a 0.14 m tall front board under the shelf top,
  with the label plates on it.

| Level | Shelf top (z) | Label rail (z) | Clear above | Depth (front at y) |
|---|---|---|---|---|
| Floor tray | 0.16 | 0.02 to 0.16 | 0.38 m | 0.48 m (-3.32) |
| Shelf 1 | 0.68 | 0.54 to 0.68 | 0.38 m | 0.40 m (-3.40) |
| Shelf 2 | 1.20 | 1.06 to 1.20 | 0.28 m | 0.28 m (-3.52) |
| Shelf 3 | 1.62 | 1.48 to 1.62 | 0.18 m to the top rail | 0.18 m (-3.62) |

The rack is **stepped** (revised after the build): each level is shallower than the one below and
each part stands 2 cm behind its own level's front, so it sits in front of the shelf above it and
is in view from the walkway at any distance. Slot y = the level's front - 0.02 - half the part's
depth.

Wheel cradles (two 15 mm rails, 0.18 m apart) sit on the floor tray and shelf 1, so wheels
stand on their tread.

**Slots.** x is in kit coordinates (the rack spans -1.35 to +1.15). Each slot's empty is on its
shelf at y -3.55.

| Slot | Level | x | Part (the current pile) | Rest orientation (Godot) |
|---|---|---|---|---|
| `slot_01`-`slot_06` | tray | -0.98, -0.63, -0.28, +0.08, +0.43, +0.78 | standard wheel x 6 | standing on its tread, axle along the rack's depth |
| `slot_07`-`slot_10` | 1 | -1.12, -0.78, -0.44, -0.10 | high-grip wheel x 4 | same |
| `slot_11` | 1 | +0.30 | motor | back face down |
| `slot_12` | 1 | +0.78 | battery (power unit) | on its side: its 0.22 m fin diameter vertical |
| `slot_13` | 2 | -0.90 | mast camera | upright |
| `slot_14` | 2 | -0.45 | arm tool turret | upright |
| `slot_15` | 2 | +0.25 | antenna | upright, dish up |
| `slot_16` | 2 | +0.80 | light battery (`power_unit_light`, on its side like `slot_12`); A10 module goes elsewhere | |
| `slot_17`, `slot_18` | 3 | -0.60, +0.40 | cartridge; radio-power module (`radio_module`, lying flat, 0.134 m deep on the 0.14 m the shelf leaves) | upright / flat |
| `slot_19` | 2 | -0.20 | thermal sensor turret (`arm_tool_thermal`, M3), 40 mm from the standard one | upright |

**Labels.** One plate per group of slots, on the rail under them. Godot puts a `Label3D` 2 mm in
front of each plate (crisp at any distance, and the text can change).

| Label | Plate (x from, to) | Rail | Text |
|---|---|---|---|
| `label_01` | -1.30 to +0.95 | tray | WHEELS |
| `label_02` | -1.30 to +0.08 | 1 | HIGH-GRIP WHEELS |
| `label_03` | +0.08 to +0.54 | 1 | MOTOR |
| `label_04` | +0.54 to +1.10 | 1 | BATTERY |
| `label_05` | -1.30 to -0.62 | 2 | MAST CAMERA |
| `label_06` | -0.62 to -0.05 | 2 | TOOL TURRETS |
| `label_07` | -0.05 to +0.53 | 2 | ANTENNA |
| `label_08` | +0.53 to +1.10 | 2 | SPARE |
| `label_09` | -1.30 to +1.10 | 3 | CARTRIDGES AND MODULE |

- Plates are 0.12 m tall. Gaps between plates are 0.02 m.
- **Text cap height 65 mm**: 35 px at 1.0 m, 23 px at 1.5 m and 18 px at 2.0 m on a 1080p
  screen (FOV 90). That's comfortable from anywhere on the walkway between the rover and the
  rack (1.0-1.7 m).
- Godot shrinks a label that wouldn't fit its plate, but never below 50 mm.
- The crosshair `PartTooltip` still names each part.

**Parts are separate, selectable objects:**
- The rack is static. Each part is the existing pickup scene (`WheelPart`, `MotorPart`, ...,
  `RigidBody3D` on layer 3), placed on its slot.
- The player's 3 m ray selects them and the `PartTooltip` describes them.
- The rack has a "Restock rack" button (`trigger_restock` on the rack's east upright at 1.2 m).
  It does what `RespawnPartsTrigger` does for a pile.
- No new part meshes are needed.

### 6.4 A07 navigation and dock markers

| Part | Shape | Collision | Material |
|---|---|---|---|
| `ws_marker_post` | a 1.2 m post (0.06 m wide), reflective band at 1.0 m, `marker_beacon` dome on top (child, emissive, can blink), `anchor_sign` at 1.05 m | one cylinder, r 0.04 | `ws_frame`, `ws_accent`, `ws_status` |
| `ws_sign_route` | sign plate 0.40 x 0.30 m with a modelled chevron arrow (geometry, not a texture), mounts on `anchor_sign` | none | `ws_label`, `ws_accent` |
| `ws_sign_base` | plate 0.40 x 0.30 m with a modelled house outline; `label_sign` for an optional `Label3D` | none | `ws_label`, `ws_accent` |
| `ws_sign_heritage` | plate 0.40 x 0.30 m, blank, `label_sign` for a `Label3D` ("Apollo 12 LM: 75 m preservation boundary") | none | `ws_label`, `ws_dark` |
| `ws_floor_chevron` | 0.40 x 0.30 m floor chevron, 2 mm proud | none | `ws_accent` |
| `ws_floor_stripe` | 2.0 x 0.10 m floor stripe, 2 mm proud | none | `ws_accent` |
| `ws_door_sign` | a 1.2 x 0.30 m plate over the bay door, `label_sign` for "SERVICE BAY" | none | `ws_label` |

Placement:
- In the workshop scene: floor chevrons from the door to the pad along the entry lane, stripes
  along the keep-clear zone's long sides and round the door's 2.5 m swing outside, and the door
  sign.
- In the Moon level: a base sign at the apron's end. Route posts and heritage signs wait for the
  route work: posts every 25-50 m along the chosen routes, at least 1.5 m from a route's
  centreline, and heritage signs where a route meets a 75 m circle.

Readability: the 0.40 m plate is 22 px tall at 10 m on a 1080p screen (vertical FOV 90), and the
chevron reads as a shape well past that. The beacon is emissive only (no light), so a dozen posts
cost nothing in lighting.

---

## 7. Look

### 7.1 Style
- Low-poly and **flat-shaded**, like the rover kit, which is the brief's "existing rover's
  design language".
- Pale panels, dark structural frames, modelled fastener heads, amber work lamps, labelled
  equipment.
- No textures in the first pass (the rover kit has none). Detail is geometry and material
  colour. A shared 1k trim texture can come later if the panels look too clean; its normal map
  then follows the existing material convention and stays shading only.

### 7.2 Materials (shared, tintable, `ws_` prefix)

| Material | Colour | Used for |
|---|---|---|
| `ws_panel` | pale metal `#CFCBC2` | wall and roof panels, rack back panel, cabinet, desk top |
| `ws_frame` | dark structural grey `#3A3D42` | frames, posts, beams, rack frame, probe |
| `ws_floor` | mid grey `#6B6E72` | floor, pad plates |
| `ws_accent` | safety amber `#E0A030` | hazard stripes, chevrons, guide lines, contact head, switch caps |
| `ws_dark` | near-black `#1C1D20` | seals, console deck, bezels |
| `ws_label` | off-white matte `#EDEBE4` | label rails' plates and sign plates (Godot draws the text) |
| `ws_glass` | `#9FB4C0`, alpha 0.25 | partition glazing, wall window |
| `ws_screen` | `#0B0E10` | `console_screen` only (Godot replaces it) |
| `ws_lamp` | emissive amber `#FFB347` | work lamp lenses |
| `ws_status` | emissive white (Godot sets the colour) | every status light mesh |

- The panels are a shade darker than `rover_body` (`#E6E2D8`), so the white rover reads against
  the walls.
- Use only these ten, with these names, in every workshop file. Every status light shares
  `ws_status`, and each status object gets its own material override in Godot, so the lights
  change independently.
- There's no glow in the Moon environment, so emissive surfaces are just bright and flat. That's
  deliberate.

### 7.3 Triangle budgets

The brief's soft targets: small props 1-5k, a station 10-20k, base modules modest.

| Asset | Part | Triangles |
|---|---|---|
| A01 | `ws_wall_panel` (with fasteners) | 300 x 15 = 4,500 |
| | `ws_wall_window` | 400 |
| | `ws_wall_bay_door` + `bay_door` + `bay_door_light` | 500 + 400 + 40 |
| | `ws_corner` | 60 x 4 = 240 |
| | `ws_floor_tile` | 30 x 20 = 600 |
| | `ws_plinth` | 24 x 16 = 384 |
| | `ws_roof_tile` (with beam) | 120 x 20 = 2,400 |
| | partition: solid x 2, door (+ leaf, light), window x 2 | 2 x 150 + 250 + 150 + 40 + 2 x 250 = 1,240 |
| | `ws_work_lamp` | 120 x 3 = 360 |
| | `ws_door_panel` | 120 |
| | **A01 total** | **11,184** (target 12,000) |
| A02 | pad (plates, guide lines, contact plate) + status light, probe, charger + beacon, cable cover | 500 + 40, 150, 600 + 80, 40 = **1,410** (target 1,500) |
| A03 | console desk, controls, screen housing, screen | 450 + 800 + 150 + 2 = **1,402** (target 1,500) |
| A04 | rack frame, shelves and rails, cradles, label plates (9 x 12) | 700 + 250 + 200 + 108 = **1,258** (target 1,500) |
| A07 | post + beacon, sign, floor chevron, stripe | 120 + 60, 60, 4, 12 per piece (target 250 per assembled marker) |
| | **Workshop total (one of each marker kind)** | **about 15,500** |

What the camera sees inside: about 15.5k for the workshop, plus 6.3k for the docked rover and
about 5.0k for the parts on the rack (they're the existing pickups). That's under 30k, about
0.5% of the 5.3 M triangles the Moon level already draws per frame (with shadow passes). On a
laptop the triangles don't matter; draw calls and lights do (section 8):
- The 15 wall panels are 15 `MeshInstance3D`s of one imported mesh.
- About 90 instances in all, three to four materials each.
- If that shows up in the measurement, the static shell is merged per material at integration.

---

## 8. Lighting (laptop targets)

Measured baseline (MacBook Pro M4, 1920 x 1080, vsync off): chase camera 141-144 fps, on foot
facing the rover with both lights 120-136 fps. The rover's headlights and the helmet light, both
shadowed, cost about 1.4 ms together. Shadowed lights are the expensive part, so:

| Light (Godot) | At | Type | Range | Shadows | Colour |
|---|---|---|---|---|---|
| Bay key | `light_bay_key`, aimed straight down | SpotLight3D, 70 degree cone | 5 m | **yes** (the only one) | neutral 4500 K |
| Rack work lamp | `light_rack` | OmniLight3D | 4 m | no | amber |
| Door work lamp | `light_door` | OmniLight3D | 4 m | no | amber |
| Operator ceiling | `light_operator` | OmniLight3D | 4 m | no | warm white |
| Exterior door flood | `light_exterior` (-1.0, 4.4, 2.9), aimed 30 degrees down onto the apron | SpotLight3D | 12 m | no | amber-white |

- **Interior fill:** one `ReflectionProbe` covering the interior, `interior = true`, ambient
  colour mode, updated once. The Moon's sky fill (0.074) is tuned for open ground and would
  leave a roofed room nearly black. No SDFGI or VoxelGI: too heavy for the brief's laptop.
- **Readability:** the key light and probe fill are set so the rack and pad read under the
  level's sunlit auto-exposure (1.39). Part silhouettes stay visible against the pale back
  panel, as the brief asks. The light energies get set in renders, not here.
- **Sun:** the roof and 0.20 m walls are closed solids (no single-sided faces), so the sun's
  first cascade (0-10 m, about 1 cm per texel) can't leak light in at 16.7 degrees. Sun enters
  only through the open bay door and the east window.
- **Cost check:** `tools/measure_moon_fps.gd` gets a phase standing in the bay facing the
  docked rover (lights on). Target: at most 1 ms slower than the "on foot facing the rover"
  phase, and p99 under 12 ms. The workshop lights only reach the terrain near the door.

---

## 9. Collision and triggers

### 9.1 Collision proxies
- Static parts carry simple boxes named `<part>-convcolonly`. Godot imports each one as a
  `StaticBody3D` on layer 1.
- Walls: one box per module, or several for a module with an opening (no box crosses an
  opening), glazing included. Floor tile: one box (0.25 thick, top at z 0). Roof tile: one box.
- Rack: one box per shelf (rails included), the back panel, two uprights, and the wheel cradle
  rails. Parts rest on these.
- Console: desk box plus a box for the screen housing. The `console_screen` quad has no
  collision.
- Charger cabinet: one box. Marker post: one cylinder.
- **Moving pieces:** `bay_door` and `personnel_door` each carry one box. The workshop import
  script (`game/src/workshop/workshop_kit_import.gd`, set by the exporter like the rover kit's)
  turns those two into `AnimatableBody3D`s, so they push the player instead of passing through.
- **No collision:** the `charge_probe` (it would lift the rover off its wheels; its contact is
  visual), floor markings, pad plates, status lights, labels, lamps.
- Floor and pad: one flat surface at z 0. The wheels' ground check (layers 1 and 3) sees no
  lips. The 2 mm decals have no collision, which is well inside `test_wheel_contact`'s 1 cm
  allowance.
- **Collision layer 8 (Player barrier):** only the pressure curtain is on it. Only the player's
  mask includes it.

### 9.2 Triggers (Godot `Area3D`s at the empties; sizes here)

| Trigger | Centre | Size (x, y, z) | Layer / detects | Purpose |
|---|---|---|---|---|
| `trigger_dock` | (-0.5, -0.3, 0.75) | 3.0 x 4.0 x 1.5 | monitors layer 3 (rovers) | rover on the pad: amber, and the dock hint |
| `trigger_charger` | (1.85, 3.1, 1.0) | 0.6 x 1.0 x 1.2 | layer 5 (`InteractTrigger`) | tooltip: charge state and percentage |
| `trigger_console` | (2.55, -0.3, 1.1) | 0.6 x 1.2 x 0.6 | layer 5 | E: drive the rover |
| `trigger_bay_door` | (-3.6, 3.70, 1.2) | 0.4 x 0.2 x 0.5 | layer 5 | E: open / close the bay door (not while a rover is in the doorway) |
| `trigger_restock` | (1.12, -3.25, 1.2) | 0.2 x 0.2 x 0.3 | layer 5 | E: restock the rack |
| `trigger_door_auto` | (-1.0, 5.0, 1.0) | 6.0 x 8.0 x 2.0 (y 1.0 to 9.0, outside the docked rover) | monitors layer 3 | while a rover is being driven, a rover in here opens the bay door; it closes 3 s after the doorway is empty |
| `trigger_personnel` | (2.1, -2.0, 1.0) | 2.0 x 1.2 x 2.0 | monitors layer 2 (player) | slides the personnel door open |

Interact triggers follow the README recipe: `InteractTrigger`, `collision_layer = 16`,
`collision_mask = 0`.

---

## 10. Files and export

| | Path |
|---|---|
| Generators | `tools/blender/scripts/workshop/make_<asset>.py`, shared helpers in `workshop_kit_common.py` (reuses `rover_kit_common.py`'s geometry, name check and preview code). The layout numbers live in `workshop_kit_common.py` only. |
| Sources | `tools/blender/parts/workshop/<asset>.blend`, an asset's parts and moving children in one file |
| Exports | `game/res/models/workshop_kit/<part>.glb` |
| Previews | `tools/blender/previews/workshop/<asset>/` (git-ignored): front, side, top and inner faces. `make_layout.py` adds an assembled plan view with the rover footprint, the U-turn envelope, the keep-clear zone, the dock zone and the player capsule at the rack, pad and console. |
| Provenance | `game/res/models/workshop_kit/PROVENANCE.md`: one line per part (original, generated by `<script>`, no borrowed assets). `CREDITS.md` gets one line pointing to it. |

- Exporter settings are the rover kit's: glTF binary, +Y Up, apply modifiers, no animations,
  empties visible, `ref_*` objects left out.
- Run headless from the repo root, e.g.
  `blender -b --factory-startup -P tools/blender/scripts/workshop/make_rack.py`.

| Script | Parts (one GLB each) |
|---|---|
| `make_shell.py` (A01) | `ws_wall_panel`, `ws_wall_window`, `ws_wall_bay_door`, `ws_corner`, `ws_floor_tile`, `ws_plinth`, `ws_roof_tile`, `ws_partition_solid`, `ws_partition_door`, `ws_partition_window`, `ws_work_lamp`, `ws_door_panel` |
| `make_pad.py` (A02) | `ws_pad`, `ws_charger`, `ws_cable_cover` |
| `make_rack.py` (A04) | `ws_rack` |
| `make_console.py` (A03) | `ws_console` |
| `make_markers.py` (A07) | `ws_marker_post`, `ws_sign_route`, `ws_sign_base`, `ws_sign_heritage`, `ws_floor_chevron`, `ws_floor_stripe`, `ws_door_sign` |
| `make_layout.py` | `ws_layout`: empties only. `dock_point`, `spawn_player`, `anchor_*`, `light_*`, `trigger_*`, and one `place_<part>_NN` per instance. Runs the assembled checks (section 12). |

Order of work, one asset at a time: A01 shell, A02 pad, A04 rack, A03 console, A07 markers, then
the layout.

---

## 11. Godot integration (separate commits)

1. `game/src/workshop/`:
   - `workshop.tscn` / `workshop.gd`: builds the shell, pad, rack, console and markers from
     `ws_layout`'s `place_*` empties, and adds the lights, the reflection probe, the triggers,
     the pressure curtain and the rack stock. Exports: `rover` (the `Robot` it serves) and
     `airlock_barrier`.
   - `workshop_kit_import.gd`.
2. `charging_pad.gd`: the docking rule, probe motion, status states (6.1) and
   `BatteryPart.add_charge()`. It doesn't change the vehicle controller (brief).
3. Bay door and personnel door (`AnimatableBody3D`, 2.5 s / 0.8 s).
4. Rack stock: the slot table, `Label3D`s on the plates, restock. The pile's record and restock
   code moves from `RoverLevel` into a small shared helper both use.
5. Console: E drives `rover`; when driving starts the player is moved to `anchor_operator`,
   facing the screen, so Esc returns the view to the console. The screen shows a `SubViewport`
   status page.
6. `DockHint` on the robot HUD (one line in `robot_hud.gd`; the UI session is told first).
7. Player mask gains layer 8.
8. Moon level: the workshop at section 4's transform, `ReadyRover` docked, `SpawnPoint` at
   `spawn_player`; the outdoor trigger, pile and respawn trigger removed; a base sign at the
   apron's end.
9. Test level: a workshop on free ground with its own docked `WorkshopRover` and
   `airlock_barrier = false`. Everything already there stays as it is.
10. Tests:
    - `tests/test_workshop.gd`, new. In both levels:
      - a scripted rover drives in, U-turns and docks, keeping 0.3 m from every fixture;
      - docking at the zone's edge and at odd headings;
      - charging, and the probe staying under the belly;
      - console drive and return;
      - the curtain holds the player on the Moon and not in the test level;
      - the player capsule walks spawn, then console, rack, pad and rear socket without
        touching the docked rover, each target within 3 m of the eye;
      - the rack labels fit their plates;
      - the wheel checks from `test_wheel_contact.gd` on the door threshold and ramp.
    - Tests that rely on the Moon's outdoor pile and triggers are updated.
11. Frame rate phase (section 8) and a README section.

---

## 12. Checks before each part is done

- Previews from the front, side, top and inner faces; dimensions match this file to 1 mm.
- Names pass the exporter's suffix check; the empties are present, visible and unrotated
  (except `place_*`).
- Triangle count against 7.3; only the materials in 7.2; every mesh closed where it casts
  shadows (walls and roof).
- Moving pieces: the 20 mm clearance over their full range (5.4), checked in the generator, as
  the rover kit's scripts do.
- Assembled checks in `make_layout.py`: the rover footprint at the dock point and at the dock
  zone's edge, over the U-turn envelope and the exit lane; the player capsule at the walkway
  points; every gap in 5.2 and 5.5.
