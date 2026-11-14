# Decor Kit Spec

Set dressing for the lunar workshop (`WORKSHOP_KIT.md`), following `game/docs/ASSET_BRIEF.md`'s visual
direction: a small, used research workshop with pale metal panels, dark structural frames, visible
fasteners, a few amber work lights and clearly labelled equipment. It also covers the brief's
**A12** (paper and service-note props near their equipment) and its optional **historical image
cards**. The conventions are `WORKSHOP_KIT.md`'s unless this file says otherwise.

Status: **approved 2026-10-10**, with these answers:
- the budget is fine;
- the technical service notes stay as placeholders, with every word in one file
  (`game/res/decor/decor_texts.json`), drawn as text in Godot, never baked into an image;
- two history cards; a third only with a confirmed NASA source and ID;
- tracks only on the Moon.

**Built 2026-10-10.** Models: `tools/blender/scripts/decor/` (every generator's checks pass);
game: `game/src/workshop/workshop_decor.gd` (game README, "The workshop"); test:
`game/tests/test_workshop.gd` section 7 (Moon level and test level, all pass). Where the build
differs from the text below, this list wins:

- **No HC3.** NASA's Image and Video Library has no picture taken by Surveyor 3's own camera
  (its "Surveyor 3" results are Apollo 12 frames, artists' concepts and later orbital views), so
  there are two cards, as approved.
- **Wall pieces** stand 35 mm off the wall face (`WALL_GAP`), clear of the walls' 30 mm frame
  members and 20 mm kick plate. Every placement is in `decor_kit_common.py`.
- **Moves:** the second extinguisher (EX2) is at x 3.30, since the ration crate (CR4) takes x 2.20
  to 2.80; S2 and N2 are at x 1.35, 8.5 cm outside the charger's trigger. The mug is on the
  operator's right of the screen (+Y) and the tablet on the left, **propped on a kickstand at 60
  degrees**: lying flat, it hid behind the console's control deck. The plant lab sits under the
  east window's sill (top at 1.18 m); the low sun passes over it, not onto it.
- **Materials:** one `dc_photo` for both photo quads (Godot puts each card's photo on it as a
  material override) instead of `dc_card_a12` / `dc_card_s3`.
- **Words** (`decor_texts.json`; `text_<style>_<key>` empties, children of their piece's
  `place_` / `outside_` empty): notes have a 16 mm title and a 12 mm body that wraps (both may
  shrink to 8 mm) starting under the clip; signs 18 mm, wrapped; labels fill their plate (crate
  labels and the paper tags wrap); the cards have a 15 mm title, a 10.5 mm caption and an 8 mm
  credit. All fit (the test checks it). The Surveyor 3 caption says "About 570 m
  east-north-east of this bay": 572 m from the workshop's centre at bearing 65.5 degrees
  (`terrain.json`), 556 m from its nearest corner.
- **Text keys** that end like a Godot import hint are renamed: `label_wheel_tag`, not
  `label_tag_wheel` (the exporter refused `_wheel`).
- **Cable:** built by Godot along `path_cable_*` (a 3 cm amber square tube, 56 triangles), so its
  points can rest on the ground.
- **Tracks:** 15 decals (three tracks, five segments each); texture 256 x 1024 for a 1.2 x 2.5 m
  decal.
- **Triangles** (each generator reports them): tool chest 232, crate 78, cable reel 152, spare
  panels 80, spare wheel 270, ladder 174, oxygen rack 408, extinguisher 138, threshold band 40,
  signs 16 / 32 / 17, mug 122, tablet 26, plant lab 256, service note 36, history card 38,
  junction box 80. Merged interior 2,669 (with the photos), exterior pieces 404, cable 56:
  **3,129 in all** (cap 3,500).
- **Draw calls:** the interior is 10 surfaces plus the two photo quads; 33 Label3Ds; 15 decals.
- **Collision:** 12 static boxes: the tool chest, four crates, the reel, the spare panels, the
  oxygen rack and the plant lab inside; two crates and the reel outside.
- **Shadows:** the merged interior is one mesh, so all of it casts (splitting off the flat pieces
  would add draw calls for nothing measurable). Labels and decals don't.
- **Checks as built** (`make_decor_layout.py`): every workshop check passes with the decor in the
  room (the closest decor to the U-turn is the tool chest, 0.76 m, needs 0.48); nothing in the
  keep-clear zone, on the pad or in the exterior lane (wall pieces above the rover's 1.22 m don't
  count, e.g. the ramp sign on the facade); least gap to a trigger 0.050 m (the ration crate to
  the charger's trigger, through the partition); 68 sight lines clear.
- **Light:** no lights were added. The bay's west wall and the door's west side are the
  workshop's dimmest corners (mean brightness 0.14 in `tools/previews/decor/`), so the tool
  chest, tanks and extinguisher there read as silhouettes with legible signs. A fourth unshadowed
  amber lamp on the west wall would lift them, if wanted.
- **Frame rate** (`game/tools/measure_moon_fps.gd -- unthrottled decor_ab`: decor off / on pairs
  in the same run, the decor hidden, not freed; MacBook Pro M4, 1920 x 1080, vsync off; four
  runs, 2026-10-10):
  - The render's CPU time: bay 0.54 ms off, 0.59 ms on (**+0.05 ms**); apron 0.49 ms off,
    0.57 ms on (**+0.08 ms**).
  - Draw calls (all passes: depth, main, the sun's four cascades, the bay light's shadow): about
    +180 in the bay (about 1,250 to 1,430) and +250 on the apron, far more than 7.2's "about 50",
    which counted the main pass only. Triangles: +0.02-0.05 M a frame.
  - Frame time: the measuring window couldn't keep the focus (the machine was in use), and macOS
    then holds an unfocused window at about 145 fps. In every phase held there, decor on and off
    both stay at 6.90 ms, so the decor never pushes a frame past it. The one pair measured in
    focus in the bay: median 5.75 ms off, 5.92 ms on (mean 6.04 / 6.36 ms). Pairs differ by up to
    0.3 ms on this machine, more than section 8's 0.15 ms limit, so **the limit is not yet
    confirmed on frame time**: run `decor_ab` once with the window in front (about 3 minutes).
    `unthrottled` (`main.gd`'s unfocused cap off) and the per-phase median, CPU render time and
    draw calls were added to the tool for this.

Every piece is an original design built by script, with no borrowed meshes. The only third-party
content is two NASA photographs (section 6), credited on the cards and in `CREDITS.md`.

---

## 1. Rules

| Rule | How it's kept |
|---|---|
| **Nothing blocks the walkways, the dock, the bay door or the rover's U-turn** | Every decor footprint goes into `make_layout.py`'s checks: the rover's entry lane, U-turn, dock zone and way out, the 1.0 m walkway and 0.8 m pinch rules, and the player capsule at every walkway point. Each footprint is checked from the floor to its top, **whether or not it has collision**. A piece that fails gets moved, not the rule relaxed. No decor goes inside the keep-clear zone (x -3.6 to +1.0, y -2.85 to +3.8), on the pad, in the door's swing, or in the exterior rover lane (4.1). |
| **Decor can't be picked up and has no tooltip** | Decor is static: `MeshInstance3D`s, plus `StaticBody3D` boxes where it has collision. It never uses `RigidBody3D`, `InteractTrigger`, `HotswapPart` or `CargoPort`, and it's never in the groups `scan_target`, `charging_pad`, `iris` or `cargo_port`. The HUD only lights the crosshair, and `PartTooltip` only describes something, for a `RigidBody3D` or an `InteractTrigger` (game README 6.6), so looking at decor shows the plain crosshair and no panel. |
| **Decor never hides a mission part or trigger** | Decor stays outside every `InteractTrigger` box by at least 5 cm. The one exception is the mug and tablet on the console desk, inside `trigger_console`: looking at them shows the console's own prompt, which is right because they sit on the console. The player's interact ray hits layer 1, so a decor collider must not cross the line from any walkway point to any reach target in `make_layout.py` (rack slots, console, charger, restock button, door panel, the rover's sockets). That check is added. |
| **Nothing reads as a mission part** | Decor doesn't reuse a rover-kit mesh or a part name. The spare wheel (3.2) is a different, older design: larger, open-spoked and worn. It hangs on a wall hook with a "NOT FOR FITTING" tag, far from the rack. No decor label names a rover part. |
| **Simple or no collision** | At most one box per floor-standing piece, with `-convcolonly` like the workshop kit: layer 1, mask 0. Wall-mounted, desk-top, flat and floor-decal pieces get none (4.3). |
| **No new lights** | The three amber lamps and the bay key light stay the only interior lights. The plant chamber's grow strip is emissive only. |
| **Small budget** | About 3,000 triangles in all (section 7), and the interior merges into one mesh (7.2). |
| **No regression in frame rate** | The workshop phase stays within its current cost (section 8). |

---

## 2. Plan

Kit coordinates, metres: the origin is the middle of the footprint on the floor, the bay door is
in the +Y wall, the interior runs x -4.8 to +4.8 and y -3.8 to +3.8, and the partition is at
x 2.05 to 2.15. Plan view, north (+Y, the bay door) up:

```
 y  3.8 +-----------[====== BAY DOOR x -3..+1 ======]-------+--------------------------+
        | EX1 N1                 threshold band ST    S2 N2 |CH S3    EX2   CR4        |
        | O2  S1                                            |                    (bench|
        |                                                   |    spawn            kept |
        | LAD           KEEP-CLEAR ZONE                     |                     free)|
        | WHL           (nothing here)                      |W                         |
        |                                                   |I                  PLANT  |
        | PNL                   [ pad + dock ]              |N   [console]      N5     |
        |                                                   |D   mug, tablet           |
        | CHEST                                             |O                  HC1    |
        |                                                   |W                  HC2    |
        | CR1                                             N3|door               N4     |
        | CR2/3  REEL1  [========= rack =========]          |              SUIT STAND  |
 y -3.8 +---------------------------------------------------+--------------------------+
       x -4.8                                            x 2.05                    x 4.8
```

---

## 3. Interior pieces (kit coordinates)

### 3.1 Work clutter

| ID | Piece | Size (m) | Where | Collision | Notes |
|---|---|---|---|---|---|
| CHEST | `dc_tool_chest` | 0.90 x 0.50 x 1.00 | against the west wall, x -4.80 to -4.30, y -2.40 to -1.50 | one box | a rolling chest with locked casters, five drawers with pull bars, a dark frame, pale drawer fronts and fastener heads on the corners; a `Label3D` plate reads "TOOLS - BAY" |
| CR1-3 | `dc_crate` x 3 | 0.60 x 0.40 x 0.40 | SW corner: CR1 on the floor at x -4.78 to -4.18, y -3.78 to -3.38; CR2 stacked on CR1, turned 8 degrees; CR3 on the floor at x -4.10 to -3.50, y -3.78 to -3.38 | one box each | ribbed sides, a dark lid and a label plate. Labels: "SEALS & GASKETS", "FILTERS", "FASTENERS M5 / M6" |
| CR4 | `dc_crate` | same | operator area, NW corner, x 2.20 to 2.80, y 3.35 to 3.75 | one box | label "RATIONS - 14 DAYS" (a sign of the crew) |
| REEL1 | `dc_cable_reel` | 0.50 diameter x 0.30 | on the floor against the south wall, axle along X, x -3.05 to -2.75, y -3.80 to -3.30 | one box | 12-sided flanges, cable wound in an amber band, a crank handle |
| PNL | `dc_spare_panels` | two 1.00 x 1.80 x 0.03 panels | leaning on the west wall, y -1.10 to -0.10, feet 0.32 m out (x -4.80 to -4.48) | one thin box | `ws_panel` faces and `ws_frame` edges with fastener holes, matching the walls; one panel has a "DENTED - SCRAP" tag (`Label3D`) |
| WHL | `dc_wheel_spare` | 0.44 diameter x 0.18 | on a wall hook, west wall, centre (-4.66, 0.75, 1.55) | none | **An older design, not a rover part:** six open spokes, a worn mesh tread, 0.44 m (the rover's wheels are 0.30 m and solid). A paper tag reads "WORN - NOT FOR FITTING". The name avoids the `_wheel` suffix, which Godot would import as a `VehicleWheel3D`. |
| LAD | `dc_ladder` | 0.45 x 0.10 x 1.25, folded | hung on two wall hooks, west wall, y 1.20 to 1.65, bottom at z 0.35 | none | a folded three-step aluminium step ladder (`ws_frame` rails, amber step edges) |

### 3.2 Life support and safety

| ID | Piece | Size (m) | Where | Collision | Notes |
|---|---|---|---|---|---|
| O2 | `dc_o2_rack` | tray 0.32 x 1.00, three cylinders 0.23 diameter x 1.45 | west wall, near the bay door: tray x -4.80 to -4.48, y 1.85 to 2.85; cylinders at y 2.05, 2.35, 2.65 | one box | pale cylinders (`ws_label`), a green shoulder band (`dc_green`), valves and caps, and a strap bar at 1.0 m with fasteners. Sign S1 above it. |
| EX1 | `dc_extinguisher` | 0.16 diameter x 0.60 | on a bracket on the north wall, x -4.45, z 0.45 to 1.05, 0.18 m out from the wall | none | red body (`dc_red`), dark hose and handle. A red "FIRE EXTINGUISHER" plate sits above it at z 1.35. |
| EX2 | `dc_extinguisher` | same | operator area, north wall, x 2.55 | none | the same mesh, a second instance |
| ST | `dc_threshold_band` | 4.00 x 0.20, 2 mm proud | floor inside the bay door, x -3.0 to +1.0, y 3.60 to 3.80 | none | diagonal amber and black hazard stripes (10 bands). It stops short of the entry chevron at (-2.2, 3.4), which reaches y 3.55. Like the other floor markings, it's well inside `test_wheel_contact`'s 1 cm allowance. |
| S1 | `dc_hazard_sign` | 0.30 x 0.30 | above the O2 rack, west wall, (-4.79, 2.35, 2.00) | none | a modelled triangle with a flame-over-circle glyph (geometry, not a texture), with `Label3D` "OXYGEN - NO OIL, NO FLAME" |
| S2 | `dc_hazard_sign` | same | north wall inside, east of the door, (1.40, 3.79, 1.75) | none | triangle with "!", "VEHICLE RAMP - KEEP CLEAR WHILE AMBER" |
| S3 | `dc_hazard_sign` | same | partition, bay face, above the charger, (2.04, 3.10, 2.05) | none | triangle with a lightning bolt, "CHARGER 400 V DC - PROBE MOVES WITHOUT WARNING" |
| S4 | `dc_hazard_sign` | same | outside, on the facade west of the door, (-3.70, 4.01, 1.60) | none | "!", "VEHICLE RAMP - STAND CLEAR" (seen by the rover's cameras) |

The symbols are simple original glyphs in the spirit of standard safety signs, not copies of any
published sign artwork.

### 3.3 Signs of the crew

| ID | Piece | Size (m) | Where | Collision | Notes |
|---|---|---|---|---|---|
| MUG | `dc_mug` | 0.08 diameter x 0.10 | console desk, left of the screen as the operator sees it, (2.20, 0.20, 0.90) | none | off-white with an amber band and a handle |
| TAB | `dc_tablet` | 0.25 x 0.18 x 0.01 | console desk, right of the screen, (2.30, -0.78, 0.90), turned 12 degrees | none | dark case with its screen **off** (`ws_screen`), so it isn't another decorative screen |
| PLANT | `dc_plant_lab` | shelf 0.25 x 0.90; chamber 0.80 x 0.22 x 0.30 | under the east window (operator area): shelf x 4.55 to 4.80, y 0.55 to 1.45, top at z 0.88; chamber z 0.88 to 1.18, just under the 1.2 m sill | one box (the shelf and chamber) | A clear lid (`ws_glass`), a tray of six low-poly seedlings (`dc_green`), and an emissive grow strip under the lid (`dc_grow`, pink-violet, no light). Sunlight comes through the east window onto it. It clears the reserved `anchor_bench` (4.2, 2.6) and spawn (3.8, 2.0). |

### 3.4 Service notes (A12)

`dc_service_note`: a 0.21 x 0.30 card in a clip, 1 cm off its surface, with no collision. Text is
a `Label3D` (18 mm caps, four lines at most), so the story owner can change the words without
remodelling. At 0.4 m from the eye that's about 24 px tall on a 1080p screen. Each note sits next
to the equipment it describes and outside that equipment's trigger.

| ID | Where (centre) | About | Draft text (for the story owner to replace) |
|---|---|---|---|
| N1 | north wall, (-4.00, 3.79, 1.40), beside the bay door panel | bay door | "BAY DOOR / Opens only for a driven rover / Never cycle with the ramp occupied / Seal check every 10 cycles - last: 7" |
| N2 | north wall, (1.40, 3.79, 1.25), 0.25 m from the charger (its trigger starts at x 1.55) | charger | "CHARGER C-2 / Keep feet off the contact plate / Amber: not in the zone, creep forwards / Red: no battery, or the rover moved" |
| N3 | partition bay face, (2.04, -3.30, 1.45), beside the rack's east end and the restock button | rack | "RACK - AFTER EVERY SORTIE / Count wheels: 6 standard, 4 high-grip / Battery back on its slot / Log cartridge serials" |
| N4 | east wall, (4.79, -2.75, 1.45), beside the suit stand | suit | "SUIT 2 / Left glove seal replaced / Check O2 before donning / Visor scratched: use the spare" |
| N5 | east wall, (4.79, 1.75, 1.30), beside the plant lab | plant | "GROWTH TEST 4 - MIZUNA / Day 23: 4 cm, three true leaves / 20 ml water a day / Lamp 16 h on, 8 h off" |

N2's states match `charging_pad.gd`'s lights, so the note also helps the player.

---

## 4. Exterior dressing (visible from the rover's cameras)

### 4.1 Exterior keep-clear lane

Nothing stands in **x -4.0 to +2.0 (the door plus 1 m each side), from the facade (y 4.0) to the
apron's end (y 16.5)**: the door's swing, the ramp, the way out and the way back in. The rover
returns from IRIS slightly from +X (IRIS is 10 degrees right of straight out), so the larger
pieces go on the west flank. `trigger_door_auto` (x -4 to +2, y 1 to 9) holds only the cable
reel's footprint edge, and the reel isn't on the rover layer, so the door doesn't react to it.

### 4.2 Pieces

| ID | Piece | Where | Collision | Notes |
|---|---|---|---|---|
| XC1, XC2 | `dc_crate` x 2 | west flank: XC1 at x -4.95 to -4.35, y 4.10 to 4.50; XC2 at about (-4.75, 4.95), turned 20 degrees | one box each (the rover can bump them; they don't move) | labels "EMPTY - RETURN TO LANDER", "SAMPLE BAGS" |
| XR | `dc_cable_reel` | east flank, (3.60, 4.60), axle along X | one box | the same mesh as REEL1 |
| XJ | `dc_junction_box` | facade, east of the door, x 2.60, z 0.60 to 1.10 (0.40 x 0.20 x 0.50) | none | a pale box, a dark gland and an amber "POWER OUT" plate |
| XW | `dc_cable_run` | from XJ down the wall, then along the ground to XR with one slack loop | none | 0.03 m flat-sided cable, about 12 segments, each snapped to the ground (4.3) |
| TR1 | tyre tracks, the way out | from the ramp's end (y 6.4) along x -1.0 to y 9, curving towards IRIS's bearing to the apron's end | none | Godot `Decal`s (4.4) |
| TR2 | tyre tracks, the way in (older) | along x -2.2, the entry lane, from the apron into the door | none | fainter |
| TR3 | tyre tracks, an old loop | across the apron at an angle, about 8 m long | none | faintest; dropped first (section 9) |

There are no bootprints: the crew stays inside on the Moon (`WORKSHOP_KIT.md` 1).

### 4.3 Sitting on the ground

The ground round the workshop isn't flat. On the Moon it's 1-12 cm under the floor's z 0
(`WORKSHOP_KIT.md` 4), and in the test level the workshop stands on a flat floor. Exterior pieces
are therefore separate instances, not merged. `Workshop` casts a ray down from 1 m above each one
(layer 1) and sets its origin 1 cm into the hit point, so it rests on the ground in both levels.
The cable run's segment ends snap the same way. The exterior keeps its own `dc_exterior` node so
the frame-rate check can switch it off (section 8).

### 4.4 Tyre tracks

- One original tread texture: a 256 x 1024 alpha-masked albedo and normal map of the rover's
  tread, the pair 1.0 m apart (the wheels' centre spacing). It's generated by
  `tools/blender/scripts/decor/make_track_texture.py` in plain Python, with nothing borrowed.
- Godot `Decal` nodes, each at most 8 m long and 0.4 m tall, projecting straight down, so they
  follow the ground. Decals cost nothing in triangles and use Forward+'s clustered path.
- **Cull mask: render layer 10 only.** That's the Moon terrain's layer (`MoonTerrain.RENDER_LAYER`),
  so a rover or crate driving through a track never gets it painted on. As a result, the test
  level's CSG floor shows no tracks, which is acceptable for the sandbox.
- Darkening is mild (albedo multiplied by 0.85, plus the normal map). Compressed regolith reads
  darker, but the tracks mustn't look like a painted route marker.

---

## 5. Look

- Low-poly, flat-shaded, with no textures except the two photos and the track decal, as
  `WORKSHOP_KIT.md` 7.1 sets out.
- Wear comes from geometry and colour: dented panel edges, a chipped crate corner, a worn tread.
  There's no grime texture.

| Material | Colour | Used for |
|---|---|---|
| the ten `ws_*` materials | as in `WORKSHOP_KIT.md` 7.2 | almost everything |
| `dc_red` | `#B8322A` | extinguishers, the fire plate |
| `dc_green` | `#4E8A3A` | seedlings, the O2 cylinders' shoulder band |
| `dc_grow` | emissive `#D070E0`, energy 1.5 | the plant chamber's grow strip only |
| `dc_card_a12`, `dc_card_s3` | the photo textures (6) | the history cards' photo quads only |

Every `Label3D` in the decor uses the rack labels' font, `alpha_cut` = opaque prepass (no
transparent sorting) and no shadows.

---

## 6. History cards

`dc_history_card`: a 0.50 x 0.66 dark frame with fastener heads and a 0.42 x 0.42 photo quad
(the photos are square 70 mm Hasselblad frames). Below the photo is a 0.42 x 0.16 caption plate
with two `Label3D`s: the title and caption in 22 mm caps, the credit in 14 mm caps. No collision
and no shadows.

**Where:** the east wall of the operator area, facing west, centres (4.79, -0.95, 1.50) (HC1) and
(4.79, -1.65, 1.50) (HC2). That puts them in view straight ahead as the player comes through the
personnel door, lit by the operator lamp. They clear the window (y 0.4 to 1.6) and N4 (y -2.75).

| | HC1: Apollo 12 | HC2: Surveyor 3 |
|---|---|---|
| Photo | **AS12-49-7278**: Alan Bean holds a Special Environmental Sample Container; Pete Conrad, who took the picture, is reflected in his visor. 20 November 1969, near Sharp crater. | **AS12-48-7136**: Pete Conrad examines Surveyor 3 during the second moonwalk; the lunar module Intrepid stands in the background. 20 November 1969. Taken by Alan Bean. |
| Source | NASA, <https://www.nasa.gov/image-detail/amf-as12-49-7278/> | NASA Image and Video Library, nasa_id `as12-48-7136` (NASA JSC), <https://images.nasa.gov/details/as12-48-7136> |
| Caption (draft) | "APOLLO 12 - 20 NOV 1969 / Alan Bean holds a sealed soil sample. Pete Conrad, who took the photo, is in his visor." | "SURVEYOR 3 - LANDED 20 APR 1967 (UTC) / Pete Conrad at Surveyor 3, 31 months later. Intrepid behind. About 560 m from this bay." |
| Credit on the card | "Photo: NASA / Charles Conrad Jr. - AS12-49-7278" | "Photo: NASA / Alan L. Bean - AS12-48-7136" |

- **Before the build:** download each original from NASA (the full-resolution JPEG), crop it to
  square and resize to 1024 x 1024, with no other changes. Store the results as
  `game/res/textures/decor/as12-49-7278.jpg` and `as12-48-7136.jpg`.
- Record in `game/res/textures/decor/PROVENANCE.md`: the download URL, the date, the original
  file's name, size and SHA-256, and the crop. Add one line per photo to `CREDITS.md` under a new
  "History cards" heading. `CREDITS.md` already says no endorsement by NASA is implied, which
  NASA's media guidelines ask for with identifiable astronauts.
- **The "about 560 m" is checked at the build** from `terrain.json`'s Surveyor 3 position and
  the workshop's transform. `WORKSHOP_KIT.md` 4 gives 556 m to the nearest point of the building
  or apron. If the number turns out wrong, the phrase is dropped rather than fudged.
- **Optional HC3:** a picture taken by Surveyor 3's own camera in 1967. Its NASA/JPL ID isn't
  confirmed yet, so it's only proposed: it gets modelled only once a public-domain NASA source
  with an exact ID is found, and it goes at (4.79, -2.30, 1.50) if N4 moves 0.15 m south.

---

## 7. Budget

### 7.1 Triangles (targets; each generator reports its exact count)

| Piece | Each | Count | Total |
|---|---|---|---|
| `dc_tool_chest` | 300 | 1 | 300 |
| `dc_crate` | 80 | 4 + 2 outside | 480 |
| `dc_cable_reel` | 150 | 1 + 1 outside | 300 |
| `dc_spare_panels` | 120 | 1 | 120 |
| `dc_wheel_spare` (with hook and tag) | 260 | 1 | 260 |
| `dc_ladder` | 120 | 1 | 120 |
| `dc_o2_rack` | 330 | 1 | 330 |
| `dc_extinguisher` (with bracket) | 120 | 2 | 240 |
| `dc_threshold_band` | 40 | 1 | 40 |
| `dc_hazard_sign` | 30 | 4 | 120 |
| `dc_service_note` | 14 | 5 | 70 |
| `dc_mug`, `dc_tablet` | 60, 24 | 1 each | 84 |
| `dc_plant_lab` | 400 | 1 | 400 |
| `dc_history_card` | 40 | 2 | 80 |
| `dc_junction_box`, `dc_cable_run` | 80, 100 | 1 each | 180 |
| **Total** | | | **about 3,140** (cap **3,500**) |

For comparison, the workshop is 6,914 triangles, the rover 6,308 and the Moon level about 5.3 M a
frame. On this machine triangles aren't the cost; draw calls, shadow passes and lights are.

### 7.2 Draw calls

- **Interior:** `make_decor_layout.py` also exports `dc_interior.glb`, every interior piece joined
  into one mesh with one surface per material: about 10 surfaces, so about 10 draw calls (plus
  their shadow pass). The collision boxes come along as `-convcolonly` children. The per-piece
  GLBs stay for previews and checks.
- **Exterior:** 7 small instances (they have to snap to the ground), about 15 draw calls.
- **Labels:** about 24 `Label3D`s, one draw call each.
- **Tracks:** 3-5 `Decal`s, clustered, with no draw calls of their own.
- **In all: about 50 extra draw calls,** against the workshop's 103 instances.

### 7.3 Shadows

- Floor-standing interior pieces and all exterior pieces cast shadows; that's what grounds them.
- Notes, signs, cards, labels, the band, the mug and the tablet don't (`cast_shadow` off).

---

## 8. Frame-rate check

The baseline is `WORKSHOP_KIT.md`'s measurement: in the bay facing the docked rover, 148.6 fps
(6.73 ms), +0.65 ms over facing the rover outside in the same run.

- `Workshop` gets `decor_enabled` (default true), which switches off `dc_interior`, the exterior
  instances, the decor labels and the decals. With it, `tools/measure_moon_fps.gd` can measure
  with decor and without in **the same build, alternating, three runs each**, counting only
  phases where the window kept focus. That avoids the machine spread `WORKSHOP_KIT.md` describes.
- A new phase, "**rover outside facing the facade**" (chase camera, 8 m out on the apron), covers
  the exterior dressing.
- **Pass:** in both the bay phase and the facade phase, decor on is at most **0.15 ms** slower
  than decor off on the mean frame, and its p99 is inside the decor-off runs' spread. The tool
  also prints `RENDER_TOTAL_DRAW_CALLS_IN_FRAME` and `RENDER_TOTAL_PRIMITIVES_IN_FRAME` for both,
  to confirm 7.2's estimates.
- If it fails, drop pieces in section 9's order and measure again.

---

## 9. What I'd drop if the budget is tight (first dropped first)

1. **HC3**, the optional third history card.
2. **TR3**, the old looping track (TR1 and TR2 stay).
3. **CR4 and EX2** (the ration crate and the second extinguisher).
4. **XJ, XW and XR**: the exterior junction box, cable and reel (the crates and tracks then carry
   the exterior).
5. **LAD**, the ladder.
6. **PNL**, the spare panels.
7. **N4 and N5** (the suit and plant notes). N1-N3 stay, since they describe gameplay equipment.

**Always kept:** the safety set (EX1, O2, ST, S1-S4), N1-N3, the mug, tablet and plant lab, the
two history cards, the tool chest, the bay crates, REEL1, the spare wheel, XC1, XC2 and TR1/TR2.
Those cover every item in the request.

---

## 10. Files

| | Path |
|---|---|
| Generators | `tools/blender/scripts/decor/`: `make_decor_bay.py` (CHEST, crates, reel, panels, spare wheel, ladder, O2, extinguisher, band, signs), `make_decor_crew.py` (mug, tablet, plant lab, notes, history cards), `make_decor_exterior.py` (junction box, cable run), `make_track_texture.py`, `make_decor_layout.py`; shared `decor_kit_common.py`, built on `workshop_kit_common.py` |
| Sources | `tools/blender/parts/decor/<script>.blend` |
| Exports | `game/res/models/decor_kit/<piece>.glb`, `dc_interior.glb` (merged), `dc_layout.glb` (empties: `place_<piece>_NN`, `label_*` for each `Label3D`, `decal_*` for each track) |
| Textures | `game/res/textures/decor/` (two photos, the track texture) and its `PROVENANCE.md` |
| Previews | `tools/blender/previews/decor/<piece>/` (git-ignored): front, side, top and inner face; the layout adds a plan with every decor footprint over `make_layout.py`'s plan |
| Provenance | `game/res/models/decor_kit/PROVENANCE.md` (original, by script); `CREDITS.md`: one line for the kit, one per photo |

- `ws_layout.glb` and the workshop's part GLBs aren't changed. Decor is added by `Workshop`
  under a `Decor` node built from `dc_layout.glb`.
- The workshop's assembled checks run once more: `make_decor_layout.py` imports
  `make_layout.py`'s checks and runs them with the decor footprints added.

---

## 11. Checks before it's done

**Blender (each generator, then the layout):**
- dimensions to 1 mm against section 3;
- names pass the suffix check (no `_wheel` and the rest);
- only section 5's materials;
- triangle counts against 7.1;
- previews from the side, front and inner face;
- in the layout, every `make_layout.py` check still passes with the decor added: rover lanes,
  U-turn (at least 0.48 m), dock zone, walkways and reach;
- every decor box is at least 5 cm outside every trigger (except the desk items);
- no decor collider crosses a sight line from a walkway point to a reach target;
- nothing exterior is in the exterior lane (4.1).

**Godot (`tests/test_workshop.gd`, extended; Moon level and test level):**
- No node under `Decor` is a `RigidBody3D`, `InteractTrigger`, `HotswapPart` or `CargoPort`, or
  in any gameplay group. Every decor collider is on layer 1 with mask 0.
- The player looks at each decor piece from the nearest walkway point: the crosshair stays the
  plain one and `PartTooltip` stays hidden. For the mug and tablet it shows the console's prompt.
- Every existing reach check still passes with the decor colliders in place.
- The existing scripted drive (out through the door, back in, U-turn, dock) still touches
  nothing, and the existing walkway and suit-stand walks still pass.
- Exterior pieces rest within 2 cm of the ground in both levels, and nothing exterior is inside
  `trigger_door_auto`'s rover detection.
- The labels on the decor fit their plates.
- `tests/test_iris.gd` still passes (the drive out to IRIS crosses the apron).

**Frame rate:** section 8.

---

## 12. Questions for approval

1. **Budget:** is about 3,100 triangles (3,500 cap) and about 50 draw calls acceptable, or should
   I start from a smaller set in section 9's order?
2. **Notes' text:** are the draft texts in 3.4 and 6 fine as placeholders, or should notes wait
   for the story script?
3. **HC3:** should I look for a confirmed Surveyor 3 camera image now, or keep two cards?
4. **Test level tracks:** is it acceptable that the tracks show only on the Moon (4.4)?
