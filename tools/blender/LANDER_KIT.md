# Lander Kit Spec

The crew lander the player arrives in: the opening cutscene flies it down, and it stays near the
outpost as a set piece the player walks out of. It is fiction (the Surface Research Programme's
lander, 2058), our own design, not a real vehicle.

Same conventions as `IRIS_KIT.md` 3 (service hardware) unless this file says otherwise.

## 1. Conventions

- **Frame:** metres, origin on the ground under the middle, +Z up, the hatch side **+Y** (Godot -Z).
- **Materials:** the workshop's `ws_panel`, `ws_frame`, `ws_dark`, `ws_accent`, `ws_screen` (the
  windows) and one of its own, `ld_foil` (B8913A, metallic 0.85, roughness 0.4: gold foil).
  Nothing emissive in the GLB: the engine's glow and the hatch light are in the scene.
- **Generator:** `scripts/lander/make_lander.py` (run headless from the repo root, like the other
  kits). Writes `parts/lander/lander.blend`, `game/res/models/lander_kit/lander.glb` (imported with
  `workshop_kit_import.gd`) and previews in `previews/lander/` (front, side, rear, top, three
  quarter, hatch, underside, stowed). It prints its checks (`LANDER_KIT lander ...`).
- **Moving pieces** are separate objects with their origin on the hinge and zero rotation
  meaning shut or deployed as below. The GLB is exported stowed; `Lander` sets the angles.

| Object | Hinge (lander frame) | Angles |
|---|---|---|
| `lander_hatch_leaf` | vertical, (0.45, 1.385, 2.32), the hatch's +X jamb | 0 shut, -176 open (about Z; flat against the cabin) |
| `lander_ramp_upper` | along X, (0, 3.6, 1.891), the end of the porch's nose | +90 stowed (up), -30 deployed (about X) |
| `lander_ramp_lower` | along X, under the upper panel's end | -180 stowed (folded down its outer face), 0 deployed |

Anchors (empties): `anchor_hatch` (0, 1.95, 2.32), `anchor_engine` (0, 0, 0.5), `anchor_plume`
(0, 0, 0.35), `anchor_hatch_light` (0, 1.05, 4.22), `anchor_ramp_foot` (0, 7.41, -0.309).

## 2. Design

| Part | Shape |
|---|---|
| Size | **6.80 m tall** (antenna feed tip), **8.6 m across the footpads** (pad centres 3.85 m out on the diagonals) |
| Descent stage | Octagon 4.0 m across the flats, z 1.0-2.3, dark core. Diagonal faces: gold foil in six slightly tilted sub-panels (crinkled). Flat faces: light structure panels with an inspection plate. Corner posts and rims, a foil heat shield underneath. Three propellant tanks (0.88 m, white, orange band) in the side bays and aft. |
| Legs | Four, on the diagonals: a primary strut (white upper tube, metal shock strut) from the stage's top corner to a ball joint over the pad, two side struts and a downlock strut to its knee, a bracket at the top. Footpads 0.9 m across, dished, 4 cm into the ground. |
| Engine | Bell under the middle: throat 0.37 m at z 0.9, exit 0.75 m radius at z 0.35, dark inside; a mount cone up to the stage. |
| Porch | On the hatch side at z 2.32 (the deck is 2.30): flat for 1.25 m in front of the hatch, then a **curved nose** (3.2 m radius) down to the ramp's slope at its end. Grating, tread strips, orange curbs, railings 1.05 m high both sides (posts on the flat and the nose), two support struts each side. |
| Ramp | Two panels 1.2 x 2.2 m, 30 degrees, orange curbs, dark treads, a hinge tube at each end, a toe plate. Deployed, the foot is at (0, 7.41, -0.31); stowed, the upper panel stands up 2.2 m at the nose's end and the lower folds down its outer face (4.14 m high, 2.25 m in front of the hatch). |
| Cabin | 3.0 x 2.7 m, z 2.30-5.05, the front's top sloped back (the two small framed windows are on the slope). Hatch 0.9 x 2.1 m in a 0.6 m deep dark recess, a frame, a lamp hood over it, orange handrails beside it. Leaf: light panel with a frame, a porthole, an orange handle and two hinge knuckles. Docking tunnel on top, aft equipment bay (dark, foil panels), two ascent tanks along the sides. |
| RCS | Four quads at the cabin's corners on short arms: a box with four nozzles (up, down, out sideways, out fore or aft). |
| Antenna | Mast at the back right up to 6.22 m with a 0.84 m dish tilted 29 degrees to the lander's -X, which is east at its spot, towards Earth (61 degrees up); a VHF whip at the back left. |

Why the nose: walking (2 m/s) off a sharp flat-to-30-degree edge in the Moon's gravity throws the
player 2.4 m down the ramp, 0.39 m above it. On a convex curve the walker stays down while
v^2 / R < g cos(slope): R > 2.5 m at 30 degrees; 3.2 m leaves room.

## 3. In the game

- `src/field/lander.tscn` (`Lander`): the GLB under `Model`; the scene's interface is the
  placeholder's (origin at the base, `Hatch`, `EngineGlow`, `PlumePoint`, `HatchLight`, the
  `set_engine`, `set_plume`, `set_hatch_light` calls) plus `RampFoot`, so the cutscene data
  didn't change. `EngineGlow` holds the engine light and the glowing bell (an unshaded cone just
  inside the bell, open at the top).
- Colliders (layer 1, mask 0): the stage (a cylinder from 0.2 m, so nothing gets under it), the
  cabin and the aft bay (boxes; the recess is closed), the flat porch (box), the nose (convex,
  its curve), the railings (boxes), the pads (cylinders). The ramp panels are `AnimatableBody3D`s
  under `RampHinge` / `FoldHinge` with `sync_to_physics` off (on, they ignore the hinge's motion).
- **States:** away from where it stands (more than 0.5 m, the descent) the ramp is folded and the
  hatch shut; landed, it stays so until `set_hatch_light(true)`, which lowers the ramp over 3 s,
  then opens the hatch over 1.5 s. When a cutscene hands over (`GameState` leaves `CUTSCENE`) the
  motion finishes at once, so a skipped opening leaves the ramp down.
- **Placement** (`moon_level.tscn`, unchanged from the placeholder): (-307.6, -5.74, 211.8),
  rotation 190 degrees about Y (hatch towards the workshop). 44.7 m from the bay door, footprint
  on 0.45 degree ground (plane fit to 4.3 m), 26.8 m from the nearest of the IRIS lane and the
  M3 routes. The pads' bottoms are within 5 cm of the ground; the ramp's foot 3 cm above it.

## 4. As built

- 5,336 triangles (budget 6,000).
- `tests/test_lander.gd`: model, placement, the walk-out (from `Hatch` down the nose and ramp, on
  the floor throughout, boots within 4 cm of the ramp, the walk animation on, into the workshop),
  the stow and deploy.
