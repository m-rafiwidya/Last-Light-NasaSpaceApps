# Astronaut Kit Spec

One low-poly, flat-shaded astronaut in a modern hard-armour EVA suit, built by script, with a
simple skeleton made by the same script. It is **posed, never animated**, and ships in the two
static uses below. (Exception, on the `exp/fp-body` branch: the player's own first-person body,
section 13, is animated.) It is also **ready for Mixamo later**: T-pose, one combined mesh, real scale,
FBX export. Same conventions as `ROVER_KIT.md` and `WORKSHOP_KIT.md` unless this file says
otherwise.

Status: **approved 2026-10-10**, with these answers (section 12):
- the seated suit shows only while the console drives the rover, as the operator the rover's
  camera sees through the window;
- the empty suit on its stand stays;
- its helmet is off, on a shelf;
- the stand is in the operator area's south-east corner, keeping WORKSHOP_KIT.md's walkways and
  clearances.

The style was checked against the private reference before modelling (general style only: the
tall backpack and broad chest box led to the larger backpack in the as-built list).

**Built 2026-10-10.** Models: `tools/blender/scripts/astronaut/make_astronaut.py` and
`tools/blender/scripts/workshop/make_suit_props.py` (every check passes); game:
`game/src/workshop/workshop.gd`; test: `game/tests/test_workshop.gd`. Where the build differs
from the text below, this list wins:

- **Proportions.**
  - Shoulder joints at x +-0.225 (were +-0.23); the chest is at most +-0.215 wide. With the
    joints inside a wider chest, hanging arms went through it.
  - Hip joints at x +-0.115, ankles at +-0.125.
  - Backpack 0.46 x 0.25 x 0.71 m, y 0.15 to 0.40, z 0.95 to 1.66. It is taller than planned:
    the reference's backpack rises well above the shoulders.
  - Helmet: an ellipsoid 0.34 x 0.34 x 0.33 m centred at (0, -0.045, 1.623), under a 12 mm
    ridge whose top is 1.80. The visor runs from z 1.535 to 1.715 and stands 8 mm proud.
- **Triangles: 4,886** (cap 5,000; 3,958 before the glove pass and the ankle bellows for the first-person body, section 13):

  | Region | Triangles |
  |---|---|
  | helmet | 436 |
  | visor | 88 |
  | neck ring | 82 |
  | torso | 380 |
  | shoulder cups | 192 |
  | waist | 96 |
  | chest box | 140 |
  | backpack | 168 |
  | arms | 640 |
  | gloves | 1,200 |
  | legs | 784 |
  | boots | 680 |

  The generator checks per-region budgets of 520 / 100 / 90 / 420 / 200 / 100 / 160 / 240 /
  680 / 1240 / 810 / 700. Props: `ws_suit_stand` 122, `ws_stool` 172 (budget 200, was 150).
- **Weights:**
  - 27 of the 42 parts are rigid.
  - Blended by design: the torso (Hips to UpperChest), elbows and knees.
  - Two-bone parts: each finger (Proximal, Intermediate) and thumb (Proximal, Distal).
  - The wrist bearing rides `LowerArm` and the glove cuff `Hand`.
- **Bone rolls.** Lying bones have Z up, upright bones Z forward. They aren't matched to Godot's
  profile axes; Godot's retargeting (BoneMap, "Overwrite Axis") normalises them when Mixamo
  clips are added.
- **Poses** are stored in the `.blend` as two one-key actions, `pose_seated` and `pose_rack`,
  instead of pose-library assets.
- **Seated (7.1).**
  - The stool is at **(3.22, -0.30)**, not 3.30, so the knee caps go 9 cm under the desk. Its
    seat top is 0.62 m and its foot ring top 0.21 m.
  - The **boots rest on the foot ring**, not the floor: from a 0.62 m seat the legs don't reach
    it. The thighs are level, and the hip bearings are round so they stay out of the seat.
  - Gloves hover over the deck's front edge, 21 mm above the switches.
  - Measured: helmet top 1.61 m, visor centre 1.41 m. The visor is seen through the partition
    window from 13 of 20 bay points at the mast camera's height. From straight behind the
    console (its own line, y -0.3), the screen housing hides it.
  - **No collision** (9.1 changed): the operator only shows while the player stands at the
    console, and a box there would fight the player's capsule. Shadows are off too, because the
    player's camera and helmet light are inside the seated helmet.
- **Stand (7.2).**
  - Plate 0.76 x 0.75 m.
  - Uprights at x 3.68 to 3.74 and 4.26 to 4.32, 2.0 m tall.
  - A backpack clamp at 1.25 m, with its pads 2 mm off the backpack.
  - Helmet shelf top at 1.83 m (45 mm over the backpack's grab bar), with an amber lip.
  - Suit origin `anchor_suit` (4.00, -3.33, 0.032): boots 2 mm over the plate.
  - Arms hang **17 degrees** out (10 went into the torso), forearms a little forward.
  - The suit spans x 3.57 to 4.43, y -3.78 to -3.05: 21 mm from the south wall.
  - Collision box x 3.55 to 4.45, y -3.80 to -3.00, up to 2.15 m.
- **Checks (10) as built.** Instead of "every part closed", which the hidden open tube ends
  inside bearings would fail, the generator checks:
  - no part inside another, in every pose (733 non-adjacent pairs; parts that share a joint are
    adjacent);
  - the stand's own contacts (plate, pads, shelf) within 0 to 5 mm, and 20 mm everywhere else.

  Normals were checked in the previews (backface culling).
- **Exports.** `astronaut.glb` (Skeleton3D with 45 bones, skinned, rest = T-pose, no
  animations); `astronaut_seated.glb` (with `pivot_helmet_light_L/R`); `astronaut_rack.glb`
  (`astronaut_rack` with child `astronaut_helmet`). The FBX is
  `tools/blender/parts/astronaut/astronaut_mixamo.fbx`; re-imported, it is one mesh, 1.800 m,
  facing -Y. **Uploading it to Mixamo hasn't been tried.**
- **Layout.** `ws_layout` gains `place_ws_suit_stand_01` and `anchor_seat`; 103 part instances.
  The player point "walking past the suit stand" (3.4, -2.6) has 0.18 m clear; the walkways and
  reach are unchanged.
- **Game.**
  - `Workshop` adds `SuitOnStand` at `anchor_suit`, and `Operator` (stool and seated suit) at
    `anchor_seat`.
  - The console shows the operator when it starts driving. Any state other than driving or
    paused hides it.
  - Preview shots in `game/tools/render_workshop_previews.gd`: `suit_on_stand`,
    `operator_from_operator_area`, `operator_from_mast_camera`.

---

## 0. The brief, and where this sits in it

`game/docs/ASSET_BRIEF.md`, finish pass: *"Full astronaut bodies, animated NPCs ... are deferred. A static
seated operator silhouette is optional if a rover camera can see through a window; it does not
require a rigged astronaut."*

- **Seated at the console.** This is the brief's optional silhouette. Its condition holds: the
  console faces the bay through the partition window (glazing z 1.0 to 2.4), and the rover's
  mast camera (about 1.19 m) sees the helmet above the screen housing (top 1.314 m).
- **Empty suit on a storage stand.** The brief doesn't mention this. It is a static prop like
  the rack parts. No body, no NPC, no motion. I think it fits the brief's intent, but it is an
  addition that you decide on (section 12).
- The skeleton goes beyond what the brief requires ("does not require a rigged astronaut"). It
  is a build tool here: the script poses the mesh with it and then bakes the pose. The game gets
  static meshes, with no skinning cost and no animation.
- **No gameplay changes.** This kit delivers models only. Placing them in `workshop.tscn` is a
  separate, later step that needs its own approval.

---

## 1. Decisions

| Topic | Decision |
|---|---|
| Height | **1.80 m** in the suit, sole to the top of the helmet, in the T-pose. |
| Style | Modern white suit with hard armour on the knees and shins, a chest control box, a large backpack, a rounded helmet with a dark visor, chunky gloves and boots. An original design (section 5). No text, logos, patches, numbers or face. |
| Look | Low-poly and **flat-shaded**, like the rover kit. Detail comes from geometry and flat colour blocks. No textures in this pass. |
| Mesh | **One combined mesh**, `astronaut`, with all parts joined. Hard parts are rigid (one bone each). Soft joints are short ring sections that blend between two bones (section 6.3). |
| Skeleton | `astronaut_rig`, 45 bones, created by script, with **Godot humanoid profile names** (section 6.1). Later Mixamo animations can then be retargeted onto it without renaming. |
| Poses | `t_pose` (the rest pose and the Mixamo pose), `seated` (at the console) and `rack` (the empty suit on its stand). Each pose is a table of bone rotations in the generator. |
| Game exports | **Static** GLBs with the pose applied: `astronaut_seated.glb` and `astronaut_rack.glb`. Plus `astronaut.glb`, the rigged T-pose with its skeleton and no animations, kept for later. |
| Mixamo | `astronaut_mixamo.fbx`: the mesh only, in the T-pose, with no armature (Mixamo's auto-rigger wants an unrigged mesh). Uploading it is a manual step for you. |
| Facing | **-Y in Blender** (unlike the rover's +Y). Mixamo needs a character facing the front view, and Godot's humanoid convention is +Z front, which is where glTF's +Y Up puts Blender -Y. |
| Budget | **4,100 triangles** target, **5,000** cap (the brief's small-prop range, 1-5k). The stand and stool are extra (section 8). |
| Props needed | `ws_suit_stand` (the storage stand) and `ws_stool` (a counter stool: the console is a standing desk, 0.9 m high). Both are workshop parts with `ws_` materials. |

---

## 2. What it's sized against

| | Value | Source |
|---|---|---|
| Player capsule | r 0.25, h 2.0, eye 1.5 m | WORKSHOP_KIT 2.2 |
| Console desk | x 2.15 to 2.80, y -0.9 to +0.3, top 0.90, underside 0.85, open at the front with side panels and a back modesty panel: **knee room under it** | `make_console.py` |
| Console screen | centre (2.30, -0.3, 1.14), bottom 0.966, top 1.314, tilted back 15 degrees | WORKSHOP_KIT, as built |
| `anchor_operator` | (3.2, -0.3, 0.0): where the player stands while driving | WORKSHOP_KIT 6.2 |
| Operator area | x 2.15 to 4.8, y -3.8 to +3.8; spawn (3.8, 2.0); `anchor_bench` (4.2, 2.6) reserved | WORKSHOP_KIT 5.5 |
| Personnel door | opening y -2.5 to -1.5; its leaf slides to y -3.5 on the operator face | WORKSHOP_KIT 5.3, 5.4 |
| Rover kit | `rover_body` `#E6E2D8`, flat-shaded, about 8k triangles | ROVER_KIT 6 |

A 1.80 m suit puts the wearer's eyes at about 1.56 m. That is 6 cm above the player's 1.5 m
camera. I'm not changing the camera.

---

## 3. Conventions (differences from ROVER_KIT 2)

### 3.1 Units, axes, origin
- 1 Blender unit = 1 m, transforms applied, never negative scale.
- **Origin: on the ground, centred between the feet**, in every pose. The character faces **-Y**.
  `_L` is the wearer's left, which is **+X** when the character faces -Y. Bones use `Left` /
  `Right` (section 6.1).
- The `.blend` keeps `ref_cube` (1 m), `ref_capsule` (the player capsule) and `ref_ground`
  (z = 0). The seated scene also holds `ref_console`, linked from `parts/workshop/console.blend`.
  All are excluded from export.

### 3.2 Naming
- Lowercase with underscores for objects and empties: `astronaut`, `astronaut_rig`,
  `ws_suit_stand`, `ws_stool`. Bones use the Godot humanoid names (`LeftUpperArm`).
- The rover kit's suffix rule applies (no name may end in `_wheel`, `_col`, `_loop` and so on).
  The exporter's `check_export_name` runs on every object and bone name.
- Empties in the static GLBs:
  - `anchor_seat` on the stool top, under the suit's seat;
  - `pivot_helmet_light_L` / `_R` on the helmet's two lamp pods (Godot may light them later; not
    now).

### 3.3 Clearance
- **20 mm** between the posed suit and any fixture: desk, deck front, side panels, stool and
  stand.
- In every pose, no rigid part may sit more than 5 mm inside another rigid part, unless the two
  are joined at a bearing (section 6.3).

---

## 4. Proportions (T-pose, metres)

Heights (z) up the centre line:

| Point | z |
|---|---|
| Sole | 0.00 (soles 35 mm thick) |
| Ankle joint | 0.11 |
| Knee joint | 0.52 |
| Hip joint | 0.90 (joints at x +-0.10) |
| Waist bearing | 1.04 |
| Chest box centre | 1.25 |
| Shoulder joint | 1.42 (joints at x +-0.23) |
| Neck ring | 1.49 |
| Visor centre | 1.62 |
| Helmet top | **1.80** |

Widths and depths:
- **Arms horizontal:** elbow joint x +-0.51, wrist +-0.77, fingertips +-0.95, so the span is
  1.90 m. The palms face down.
- **Legs straight down:** feet at x +-0.12. There is at least 60 mm between the inner thighs
  and 40 mm between the arms and the torso sides. Mixamo's auto-rigger and the weights both
  need the gaps.
- **Shoulders:** 0.62 m across the shoulder cups.
- **Torso:** 0.30 m deep, chest front y -0.17.
- **Backpack:** 0.46 W x 0.24 D x 0.62 H, behind the torso (y +0.15 to +0.39), z 0.95 to 1.57.
  Its top rises 8 cm above the shoulders. This is the "large backpack" silhouette.
- **Helmet:** a 0.34 m wide dome, 0.36 m deep. The visor covers the front 140 degrees and runs
  from z 1.53 to 1.72.

---

## 5. Design (original, in the reference's general style)

The style is taken from the reference. The shapes are our own. Every shape is built from the rover kit's
vocabulary: octagonal and 12-sided prisms, chamfered boxes, raised rims and round bearings. The
suit and the rover then read as one program's hardware.

| Part | Shape | Material |
|---|---|---|
| Helmet | A 16-sided dome, 7 rings, with a **raised centre ridge** from brow to nape. Two small square lamp pods on the temples. A neck ring of 12 sides. | `suit_shell`, ridge and pods `suit_metal` |
| Visor | One faceted dark shell (12 x 4 quads) sitting 6 mm proud of the dome, with a 15 mm `suit_metal` frame around it. No face behind it: the helmet is closed. | `suit_visor` |
| Upper torso | A hard shell with a chamfered breastplate and two shoulder cups. The cups are **bearings**: the arm rotates inside them. | `suit_shell` |
| Chest box | A low 0.26 x 0.07 x 0.14 m box on two short struts. It carries two rotary knobs, a T-lever and a small status window. All modelled, with no text. | `suit_metal`, knobs `suit_dark`, window `suit_lamp` |
| Backpack | A rounded box (30 mm chamfers) with two vertical side ribs, a top grab bar, a lower vent grille of three slots and one amber stripe across the top. | `suit_shell`, ribs `suit_metal`, grille `suit_dark`, stripe `suit_accent` |
| Waist | A dark waist bearing ring. The hip section has two hip bearings at the thighs. | `suit_fabric`, rings `suit_dark` |
| Arms | Upper arm (fabric, with a thin amber band), an elbow convolute (3 rings), forearm (fabric), wrist bearing (dark). | `suit_fabric`, `suit_dark`, `suit_accent` |
| Gloves | A chunky gauntlet cuff, a boxy back of the hand, 4 two-segment fingers and a 3-segment thumb, all square-sectioned. Dark palms and fingertips. | `suit_fabric`, `suit_dark` |
| Legs | Thigh (fabric), knee convolute (3 rings), **hard knee cap** with a raised rim, **hard shin plate** from knee to ankle, strapped at two points. | `suit_fabric`, armour `suit_shell`, straps `suit_dark` |
| Boots | Chunky, square-toed, a 35 mm dark sole with three tread bars, a hard heel cup and an amber pull tab. | `suit_shell`, `suit_dark`, `suit_accent` |

Left out on purpose: text, logos, flags, patches, numbers, name tags and a face. The amber
stripe and bands are colour blocks and carry no symbol.

### 5.1 Materials (`suit_` prefix, colours tied to the existing kits)

| Material | Colour | Metallic / roughness | Notes |
|---|---|---|---|
| `suit_shell` | `#F1EFE9` | 0.0 / 0.45 | hard armour, helmet, backpack: a shade whiter than the fabric |
| `suit_fabric` | `#E6E2D8` | 0.0 / 0.85 | the same as `rover_body`: arms, legs, waist |
| `suit_metal` | `#4A4D52` | 0.6 / 0.45 | the same as `rover_metal`: frames, chest box, ribs |
| `suit_dark` | `#1C1D20` | 0.0 / 0.8 | bearings, soles, palms, convolute rings |
| `suit_visor` | `#0B0E10` | 0.9 / 0.12 | glossy, so it picks up the reflection probe instead of reading as a hole |
| `suit_accent` | `#E0A030` | 0.0 / 0.6 | the same as `ws_accent`: the only colour accent |
| `suit_lamp` | emissive `#FFB347`, low | - | the chest status window only |

These seven only. The stand and stool use the existing `ws_` materials.

---

## 6. Skeleton, weights and poses

### 6.1 Bones (Godot `SkeletonProfileHumanoid` names, 45)

- **Core:** `Root` (at the origin) > `Hips` (0.95) > `Spine` (1.04) > `Chest` (1.18) >
  `UpperChest` (1.32) > `Neck` (1.49) > `Head` (1.56).
- **Each arm:** `LeftShoulder` > `LeftUpperArm` > `LeftLowerArm` > `LeftHand`.
- **Each hand:** `LeftThumbMetacarpal`, `Proximal`, `Distal`. Then `LeftIndex`, `Middle`, `Ring`
  and `Little`, each with `Proximal` and `Intermediate` (no `Distal`: the glove fingers have two
  segments).
- **Each leg:** `LeftUpperLeg` > `LeftLowerLeg` > `LeftFoot` > `LeftToes`.
- No eye or jaw bones. `Neck` and `Head` exist only for the profile (section 6.3).
- Bone rolls follow Godot's humanoid profile, so a retarget needs no fix-ups. Rest pose = the
  T-pose.

### 6.2 Poses (each a bone-rotation table in the generator, checked in section 10)

| Pose | Where | What it looks like |
|---|---|---|
| `t_pose` | - | Rest. Arms horizontal, palms down, legs straight. |
| `seated` | on `ws_stool` at the console (section 7.1) | Seat 0.60 m. Hips flexed about 85 degrees, knees about 95 degrees, so the knees go under the desk 50 mm below its underside. Torso leaning 10 degrees forward. Forearms forward, gloves resting on the deck's front edge, fingers curled 30 degrees. The helmet faces the screen. |
| `rack` | on `ws_suit_stand` (section 7.2) | **Empty suit.** Backpack clamped to the stand, shoulders resting on the stand's yoke, arms hanging 10 degrees out from the sides, fingers relaxed, legs straight, boots on the stand's floor plate. **The helmet is off** and sits on the stand's top shelf. The open neck ring shows a dark cap. |

The helmet off on the rack is the clearest way to say "empty". It needs the helmet as its own
object in `astronaut_rack.glb` only. The rigged mesh and the FBX keep one combined mesh.

### 6.3 Weights (assigned by the script, per part)

- **Rigid parts get 100% on one bone.** These are the helmet, visor and neck ring, the torso
  shell, cups, chest box and backpack (`UpperChest`), the hip section (`Hips`), the knee cap
  and shin plate (`LowerLeg`), boots (`Foot`/`Toes`), gauntlet cuffs (`LowerArm`), and the
  hand and finger segments (their own bones).
- **The helmet rides the torso**, as on a real hard suit, where the head turns inside a fixed
  helmet. `Neck` and `Head` have no vertices. A neck twist in a future Mixamo clip then can't
  shear the helmet off the shoulders.
- **Bearings** (shoulder, waist, hip, wrist) are rigid on the child bone. They overlap into the
  parent's ring, so rotation happens inside a visible joint, like the rover's connectors.
- **Convolutes** (elbows, knees) are three dark rings that blend from 100% parent to 100% child
  in thirds, so they bend in steps like real bellows.
- At most 4 influences per vertex, normalised. Every vertex is weighted.

---

## 7. Placement (workshop kit coordinates; integration later)

### 7.1 Seated at the console
- `ws_stool` at (3.30, -0.30, 0.0). A counter stool: 0.38 m round seat at 0.60 m, one post, a
  4-foot base and a foot ring. About 150 triangles.
- `astronaut_seated` origin at about (3.28, -0.30, 0.0), facing -X (rotated -90 degrees about Z
  from its -Y facing). Hip joint about (3.25, z 0.70), knees about (2.82, z 0.72), knee caps
  about 60 mm under the desk.
- It sits on `anchor_operator`, where the player stands while driving. **The two can't share
  that spot.** Section 12, question 1.

### 7.2 Empty suit on its stand
- `ws_suit_stand` in the operator area's south-east corner, origin (4.00, -3.80, 0.0) on the
  south wall face, facing +Y:
  - a floor plate 0.70 x 0.50 m;
  - two uprights and a backpack clamp;
  - a shoulder yoke at 1.40 m;
  - a helmet shelf at 1.75 m.
  About 250 triangles.
- The suit occupies x 3.60 to 4.40, y -3.80 to -3.23. That leaves 0.40 m to the east wall, and
  the area stays clear of the spawn (3.8, 2.0), the bench anchor, the console and the personnel
  door's leaf (x below 2.25).

---

## 8. Triangle budget

| Region | Triangles |
|---|---|
| Helmet shell, ridge, lamp pods | 520 |
| Visor and frame | 100 |
| Neck ring | 60 |
| Upper torso and shoulder cups | 400 |
| Chest box | 180 |
| Backpack | 320 |
| Waist and hip section | 260 |
| Arms (upper, elbow convolute, forearm, wrist) | 2 x 340 |
| Gloves (cuff, hand, 4 fingers, thumb) | 2 x 240 (as built after the glove pass: 2 x 600, section 13) |
| Legs (thigh, knee convolute, knee cap, shin plate) | 2 x 340 |
| Boots | 2 x 200 |
| **Astronaut** | **4,080** (cap 5,000) |
| `ws_stool` / `ws_suit_stand` | 150 / 250 |

The workshop's total goes from about 15.5k to about 20k triangles with both uses placed. That is
still tiny next to the Moon level's 5.3 M per frame. The baked statics cost one mesh each with no
skinning, and 6 to 7 material surfaces.

---

## 9. Files and export

| | Path |
|---|---|
| Generator | `tools/blender/scripts/astronaut/make_astronaut.py`: mesh, rig, weights, poses, checks, all exports. Helpers in `astronaut_kit_common.py` (reusing `rover_kit_common.py`'s geometry, name check, export and previews). |
| Props | `tools/blender/scripts/workshop/make_suit_props.py`: `ws_suit_stand` and `ws_stool` |
| Source | `tools/blender/parts/astronaut/astronaut.blend` (rig, mesh, the three poses as pose-library entries) |
| Game exports | `game/res/models/astronaut_kit/astronaut.glb` (rigged T-pose, skin, no animations), `astronaut_seated.glb`, `astronaut_rack.glb` (armature modifier applied, no skeleton); `game/res/models/workshop_kit/ws_suit_stand.glb`, `ws_stool.glb` |
| FBX | `tools/blender/parts/astronaut/astronaut_mixamo.fbx`: the T-pose mesh only, metres, unit scale. It's kept **outside `game/`**, so Godot doesn't import a second copy. |
| Previews | `tools/blender/previews/astronaut/<pose>/` (git-ignored): front, side, back, top, three-quarter, plus close-ups of the helmet, a glove and a knee. The seated pose is shown at the console. |
| Provenance | `game/res/models/astronaut_kit/PROVENANCE.md`: "original design, generated by `make_astronaut.py`; style informed by a private concept image that isn't distributed; no traced shapes, borrowed meshes or textures". One line in `CREDITS.md`. |

- **GLB:** the rover kit's exporter settings. For the static poses the script applies the
  armature modifier to a copy, so the GLB holds a plain mesh.
- **FBX:**
  - `bake_space_transform` off;
  - `apply_scale_options = FBX_SCALE_UNITS`;
  - forward -Z, up Y;
  - mesh only.

  The script re-imports it into an empty scene and checks the height (1.80 m) and the facing.

### 9.1 Collision (for the later integration)
- `astronaut_seated-convcolonly`: one box around the seated suit and stool.
- `ws_suit_stand-convcolonly`: one box around the stand with the suit on it.
- `astronaut.glb` (rigged) has none.

---

## 10. Checks before it's done

- Height 1.80 m (1 mm), span 1.90 m, origin between the feet, facing -Y.
- Triangles per region against section 8; total at most 5,000.
- Exactly one mesh object in `astronaut.glb` and the FBX. Only the section 5.1 materials. Every
  part closed (no holes), no loose vertices.
- Weights: every vertex weighted, at most 4 influences, normalised. Rigid parts on exactly one
  bone.
- **Pose interpenetration**, for each pose: on the evaluated (posed) mesh, no rigid part is more
  than 5 mm inside another, except at its own bearing.
- **Seated:**
  - 20 mm from the desk underside, deck, side panels and screen housing;
  - seat contact within 5 mm;
  - soles on the floor within 5 mm;
  - the helmet visible over the screen housing from the bay at the mast camera's height
    (a ray check through the partition glazing).
- **Rack:** 20 mm from the stand and the walls; the helmet seated on its shelf.
- **Mixamo pre-flight:** T-pose arm angle 0 +-2 degrees, the inner-thigh and arm gaps from
  section 4, a symmetric mesh (mirrored, 1 mm), unit scale.
- Previews checked from front, side, back and close-up for every pose.

---

## 11. What will look rough next to a hand-made model, and how to keep it intentional

Honest list, roughest first:

1. **Gloves.** Boxy fingers from a script read as blocks or sausages. A hand-made model sculpts
   knuckles, palm pads and a thumb web; we won't. *Mitigation:*
   - design them as armoured gauntlets: square-sectioned segments, a hard back plate and dark
     palms and tips;
   - pose them only in gentle curls;
   - render a close-up preview and accept that they're small on screen;
   - never use them as first-person hands without another pass.
2. **Shoulders and armpits** going from the T-pose to arms down. This is the classic skinning
   failure: collapsed armpits, a torn shoulder. *Mitigation:* the arms turn inside rigid
   shoulder-cup bearings (6.3), so there is nothing soft to collapse. A Mixamo auto-rig would
   reintroduce the problem (below).
3. **Hips in the seated pose.** About 85 degrees of hip flexion creases the crotch, and with
   flat shading the crease shows as a few big wrong facets. *Mitigation:*
   - a rigid hip section with hip bearings;
   - a seat height chosen to keep the hip angle under 90 degrees;
   - the interpenetration check;
   - the desk and stool hide the lap from most views anyway.
4. **Helmet dome.** It is the most looked-at part, and a low-poly sphere shows its facets.
   *Mitigation:*
   - make the facets read as construction: 16 even sides, a raised ridge, a visor frame;
   - spend the biggest share of the budget there;
   - give the visor a glossy material, so the reflection probe paints a highlight across it
     instead of leaving a flat black hole.
5. **Fabric.** There will be no folds, wrinkles or sag, so the suit reads as clean plastic, a bit
   toy-like. *Mitigation:*
   - lean into the hard-suit look (armour, bearings, convolutes);
   - break the large white areas with dark rings, straps and two whites (shell and fabric);
   - don't fake folds with a few stray polygons.
6. **Generic proportions.** A primitive-built body drifts towards a robot or mannequin.
   *Mitigation:* section 4's measurement table, tapered segments (thigh and calf, forearm
   bulge), and side-by-side previews against `ref_capsule` and a human-proportion outline.
7. **Mixamo's own rig.** If you upload the FBX and use Mixamo's auto-rigged character, its
   weights will bend the armour like rubber and turn the helmet with the head. *Mitigation:* the
   plan is to use Mixamo for **animations**, downloaded "without skin", and retarget them in
   Godot onto `astronaut_rig` (same humanoid names) with our rigid weights. Its auto-rig also
   needs the helmet's "chin" marker placed at the neck ring, which works but may take a retry.
8. **"Empty" vs "occupied".** The same mesh with the helmet on looks like someone standing
   still on a stand. Hence the helmet-off rack pose with a dark neck cap, and slightly hung
   shoulders.

---

## 12. Open questions (please answer with the approval)

1. **Seated suit vs. the player at the console.** The seated astronaut sits where the player
   stands while driving (`anchor_operator`). Options:
   - (a) **A visible "you" while driving** (recommended). The seated suit appears only while the
     console drives the rover, so the rover camera sees its operator through the window. The
     player has no body otherwise. This is a later integration change; it changes nothing in
     play.
   - (b) **A second crew member** at a second stool beside the console, always there. This needs
     a second spot that doesn't block the walkway behind the operator.
   - (c) Build the asset now and decide when integrating.
2. **The empty suit on a stand.** It isn't in the brief. Keep it, or drop it?
3. **Helmet off on the stand** (section 6.2). Or helmet on with the visor down?
4. **Stand location.** The operator area's south-east corner, or somewhere you have in mind
   (for example the bay's west wall, visible from the rover)?
5. **Reference image.** `tools/blender/reference/private/suit_reference.jpg` isn't in the repo
   yet. The folder is now in `.gitignore`. Drop it in if you want me to check proportions
   against its general style before modelling.

---

## 13. First-person body (experiment, branch `exp/fp-body`)

The same suit as the player's own body: looking down, the player sees the suit, legs and boots;
the helmet is never drawn for the player's camera but still casts its shadow. Approved
2026-10-10 with: hold parts about 0.6 m out (0.45 m from the eye in the hands), the suit scaled to
1.71 m rather than moving the camera, and the glove pass below.

- **Gloves (as built).** Armoured gauntlets: rounded octagonal finger and thumb segments with
  dark grip tips, a hard back plate and a dark knuckle guard. 600 triangles a glove (was 240).
- **Ankles (as built).** The boot shaft used to be one rigid tube on `Foot` up to 0.31 m, and the
  shin ended at 0.28 m: as soon as a clip bent the ankle (the first clips reached 41 degrees
  walking, 52 sprinting) the shin's open end and the shaft moved apart by up to 15 cm, and the
  foot looked detached. Now: a low rigid boot cuff (to 0.215 m), a dark **ankle bellows** above it
  (five rings, 10 sides, blended from `Foot` to `LowerLeg` in steps like the knee convolute, up to
  0.315 m under the shin plate) and the shin continuing down inside it as a sleeve to 0.20 m. The
  pull tab moved onto the cuff. Legs 784 and boots 680 triangles; the suit is **4,886** (cap
  5,000). Every check of section 10 and the as-built list passes again (seated, rack, T-pose),
  previews re-checked.
- **Generator.** `tools/blender/scripts/astronaut/make_astronaut_anims.py` builds the mesh and rig
  with `make_astronaut.py`, keys the clips, checks them and exports
  `game/res/models/astronaut_kit/astronaut_fp.glb`: the Skeleton3D with two skinned meshes,
  `astronaut_body` (4,202 triangles) and `astronaut_helmet` (684: helmet, visor, ridge, lamp pods,
  the neck ring and the torso's top above 1.435 m, the shoulder yoke, which right under the
  player's camera filled the view looking down), and the clips. The eyes are taken 12 cm ahead
  of the neck (`EYE`), where they are in the helmet: the camera then sits over the front of the
  chest. Source `tools/blender/parts/astronaut/astronaut_fp.blend`; previews (side and
  three-quarter strips of every clip) in `tools/blender/previews/astronaut_fp/<clip>/`.
- **Scale.** The game scales the suit to 0.95 (1.71 m), so its eyes are at the player's 1.5 m
  camera. The clips are authored full size; a clip made at speed v plays at 0.95 v.
- **Clips** (keyed at 120 fps; Godot imports them at 120 with its animation optimizer off, since
  at 30 or 60 the joints' in-between blends let planted boots wobble):

  | Clip | Length | Notes |
  |---|---|---|
  | `idle` | 4 s loop | weight shift and two breaths; arms 17 degrees out (the rack pose's clearance) |
  | `walk` | 0.67 s loop | 2.0 m/s, 0.67 m steps, 56% planted, hips up to 12 mm below standing, 3 degree lean |
  | `walk_back` | 0.67 s loop | walking backwards, 2.0 m/s, 58% planted: its own gait, not the walk reversed (below) |
  | `sprint` | 0.6 s loop | 3.0 m/s, 0.9 m steps, 40% planted (a flight phase), 6 degree lean |
  | `crouch_idle` | 2 s loop | deep squat, eye 0.77 m (the crouched camera is 0.75 m: section 13.1) |
  | `crouch_walk` | 0.9 s loop | 1.0 m/s, 0.45 m steps, 60% planted, boots flat |
  | `turn_step` | 0.8 s loop | stepping on the spot while the lower body turns |
  | `air_rise`, `air_apex`, `air_fall` | poses | blended by vertical speed over take-off speed |
  | `land` | pose | the deepest moment of a heavy landing; the game scales it by impact speed |

  Every gait starts with the left boot landing. A gait's legs come from foot paths: in stance a
  boot rolls over its heel edge, lies flat, then rolls over its toe edge while travelling back at
  exactly the clip's speed; the swing is a Hermite curve that leaves and lands at that speed.
  `walk_back` mirrors the rolls: the boot lands on its toe edge and leaves over its heel (toe up),
  so the edge it pivots on is the one on the ground (the walk played in reverse rolled the wrong
  way: its heel and toe slipped 0.22 m/s in the game, `walk_back` 0.02).
  **Ankle limits:** a boot off the ground stays within 20 degrees of its shin's pitch and is lifted
  clear of the ground; a planted boot whose shin leans more than 30 degrees over it lifts its heel,
  rolling over its toe edge, which stays put. The
  hips sit as high as the planted legs allow (98.5% of full reach), which gives the walk its bob.
  The upper body is posed from tables like sections 6.2 and 7: arms swing from the shoulder
  bearings with the elbows nearly fixed, the chest stays square (the spine takes back the
  pelvis's yaw), little spine bend.
- **Checks** (every run; all pass): a planted sole point moves at most 1.8 mm between frames in
  the world (body moving at the clip's speed), never goes into the ground; the ankle bends at
  most 35 degrees (what the bellows covers) on every frame of every clip (worst: 34.6, crouch
  walk); no part inside
  another on sampled frames of every clip (section 10's check); the crouch's eye within 5 cm of
  0.75 m. Each clip's average eye position ahead of the origin is printed for the game
  (`PlayerBody.CLIP_EYE`).

### 13.1 Rough spots, and how they are kept intentional

1. **The crouch is a deep squat.** Crouched, the player's eye is 0.75 m over the ground (the capsule
   shrinks round its centre and the player sinks 0.5 m), so a 1.71 m suit has to fold well past
   what a hard suit can: boots wide, knees turned out, the chest about 60 degrees forward between
   the knees, arms hanging inside them. The waist bearing presses into the tops of the thighs
   (the one accepted overlap, crouch clips only). From the player's camera that fold is under the
   chest and out of view. Going into the crouch, the boots slide back about 0.3 m over the 0.5 s
   the camera drops, because the head stays where the camera is.
2. **Gloves** are still blocks next to a sculpted hand. They only show open, gently curled or
   closed round a part, never finger by finger.
3. **Grips** are on the sides of the part's collision box, so on round parts the palms float a few
   millimetres off; the thick gauntlets and dark palms hide it.
4. **Strafing** turns the legs to the way the player moves and twists the suit at the waist
   bearing (a real rotating joint on a hard suit) up to 90 degrees; walking backwards plays the
   walk in reverse.
5. **Feet on slopes:** no foot IK yet; on steep Moon ground the boots sit a little into or above it.
6. **Ankle bellows** bend in steps (five rings) and can look a little faceted at the 30-35 degree
   extremes (toe-off, the deep crouch); crouch walking backwards still plays `crouch_walk` in
   reverse (flat-footed, so its rolls are small).

