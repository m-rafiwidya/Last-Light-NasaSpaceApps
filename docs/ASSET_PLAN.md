# Asset plan — LAST LIGHT

Audit of `game/docs/ASSET_BRIEF.md` (11 Oct 2026) against the repo, 14 Oct 2026. Nothing was generated or changed.
Missions: M1 Wake Kite, M2 First Signal, M3 Beyond the Rim (`Tandborste-Game-and-Story-Plan.md`, `game/docs/STORY_SCRIPT.md`).
All pipeline work uses Blender scripts in `tools/blender/scripts/` (headless, in metres, `.blend` + `.glb`, PROVENANCE.md per kit).

## 1. Status table

Status: **ready** = built, checked by its generator, in the Moon level. **needs work** = exists but differs from the brief or lacks a piece. **missing** = nothing in the repo.

| ID | Asset | First need | Status | Existing files |
|---|---|---|---|---|
| A01 | Workshop kit (one room) | M1 | ready | `game/res/models/workshop_kit/ws_*.glb` (shell, floor, roof, partition, doors, lamps), `ws_layout.glb`; `tools/blender/scripts/workshop/make_shell.py`, `make_layout.py`; `game/src/workshop/workshop.tscn`; `tools/blender/WORKSHOP_KIT.md`; `game/tests/test_workshop.gd` |
| A02 | Dock/charging pad | M1 | ready | `ws_pad.glb`, `ws_charger.glb`, `ws_cable_cover.glb`; `make_pad.py`; `game/src/workshop/charging_pad.gd`; dock hint UI `game/src/ui/dock_hint/` |
| A03 | Mission console | M1 | ready (screen content is Godot UI) | `ws_console.glb` (with `console_screen`); `make_console.py`; `game/src/ui/console/`, `game/src/ui/mission_console/` |
| A04 | Parts rack | M1 | ready | `ws_rack.glb`; `make_rack.py`; `game/src/levels/parts_stock.gd` |
| A05 | Kite (stored / operational) | M1 | **needs work** | Playable rover: `game/res/models/rover_kit/*.glb`, `game/src/robot/`. Old `kite.glb` is a wrecked static rover, a different thing (see section 4) |
| A06 | Part variants (2 batteries, 2 wheel sets, existing motor) | M1 | needs work | `wheel_L/R.glb`, `power_unit.glb`, `motor.glb`; catalog has `wheel` and `wheel_high_grip` (`game/src/robot/socket/part_catalog.gd`). Second battery: check catalog, likely missing a distinct mesh/entry |
| A07 | IRIS | M1 | **missing** | Only names in docs, `MISSIONS.json`, save-slot text. No model, scene, or position. README_GAMEPLAY puts it 100–160 m along the first safe approach |
| A08 | Navigation markers | M1 | ready (reposition for IRIS) | `ws_marker_post.glb`, `ws_sign_route.glb`, `ws_sign_base.glb`, `ws_floor_chevron.glb`, `ws_floor_stripe.glb`, `ws_door_sign.glb`; `make_markers.py`; Kite gate in `game/src/kite/` |
| A09 | Terrain and collision | M1 | ready | `game/res/terrain/moon_apollo12/` (`terrain.json`, `play.f32`, chunks, rocks); `game/src/levels/terrain/moon_terrain.gd`; `tools/terrain/MOON_TERRAIN.md`; `test_terrain.gd` |
| A10 | Replacement radio-power module | M2 | missing | Closest: `cartridge.glb` + `cargo_mount.glb` (`make_cartridge.py`, `make_cargo_mount.py`) |
| A11 | Module cradle/adapter | M2 | missing | Reuse cargo mount pattern |
| A12 | Sampling kit (scoop, sealed container, lab tray) | M2 (optional), M3 | missing | `arm_tool.glb` is the gripper to hold a scoop; `make_arm.py` |
| A13 | Sample containers (x2) | M2/M3 | missing | none |
| A14 | Surface-temperature sensor | M3 | missing | Mast head/camera housing: `mast_head.glb`, `make_mast.py`, `game/src/robot/kit/rover_camera.gd` |
| A15 | Reference sample targets (x2) | M2 near IRIS, M3 far rim | missing | none; terrain texture only |
| A16 | Field logger | M3 | missing | none |
| A17 | Thermal kit (cover + heater) | M3 | missing | none |
| A18 | Logs/labels (3 entries) | M1–M3 | partial | Decor text pipeline exists: `game/res/decor/decor_texts.json`, `dc_service_note.glb`, `dc_history_card.glb`, `dc_tablet.glb`. Entries themselves not written |
| P2 | Rocks, ambience, audio, gloves, source cards | late | partial | `rock_field.gd` (rocks), `game/src/audio/`, `starmap_2020_4k.exr` sky, `credits.md`. Decor kit (`dc_*.glb`) already covers bay props |

Also present and not in the brief: astronaut kit (`astronaut.glb`, `astronaut_fp.glb`, `ASTRONAUT_KIT.md`), decor kit (21 `dc_*.glb`), Kite diagnostic cartridge and delivery code, tyre tracks, wheel dust.

## 2. How to make each missing or needs-work asset

Default method for everything: our Blender script pipeline (flat-shaded, shared materials, original design, consistent with `rover_kit_common.py` / `workshop_kit_common.py`). No NASA mesh fits any of these; they are fictional equipment. NASA models are reference only (see last row).

| ID | Method | Size / detail | Collision and anchors |
|---|---|---|---|
| A05 Kite | No new mesh. Make the existing playable rover the "Kite": rename in docs/UI, state = docked/idle vs active. Retire or repurpose the wrecked static Kite (section 4) | Existing rover | Existing |
| A06 variants | Reuse. Wheels: `wheel` vs `wheel_high_grip` already in catalog. Battery: add a second `power_unit` variant by a small param change in `make_power_antenna_motor.py` (different size/label colour) and a catalog entry | ~400 tris each (current power_unit budget) | Same socket and convex collider as existing |
| A07 IRIS | **Blender script** `scripts/iris/make_iris.py`, new kit doc `IRIS_KIT.md`. Pieces: body box, service panel (hinged `service_door`), module socket, `antenna` on a pivot, status `indicator` (off/on via emission), solar/radiator plate | Body ~2 x 1.5 x 1.3 m, mast ~3 m; 3–6k tris | Convex boxes for body and mast; anchors: scan point at the panel, `socket_module`, rover parking marker. Put on the terrain 100–160 m from the base on a gentle slope, as Kite was placed |
| A10 module | Script variant of `make_cartridge.py` (larger, radio-module look, handle for gripper) | ~0.3 x 0.2 x 0.2 m, <1k tris | Pickup anchor, mount anchor on cargo mount, matching pose at IRIS socket |
| A11 cradle | Small script piece. Could be a second cargo-mount variant | <1k tris | Fixed to cargo mount |
| A12 sampling kit | Script: scoop (arm_tool-sized handle), sealed container with lid pivot, tray prop for the workshop | 1–2k tris total | Convex proxies; `container_lid` pivot; tool held by gripper, assisted pose only |
| A13 containers | Same container mesh x2, two materials/labels (empty / full via a visible fill mesh) | <1k tris | Cargo/storage anchors |
| A14 sensor | Small radiometer housing, reuse mast head style, placed on `mast_head` or the arm tool | <500 tris | Scan point only |
| A15 targets | Simple authored patches (flat decals/darker regolith discs) plus a small marker post; near-IRIS and far-rim, plus a fallback near each | 2 decals, 1 post reuse | None (walkable ground) |
| A16 logger | Script: small box with antenna stub, two labels (Godot text), stowable on cargo mount | <1.5k tris | Pickup anchor, cargo attachment anchor |
| A17 thermal kit | Script: foil cover (quad hull) and heater box; visible when installed | <1k tris | Fixed attachment |
| A18 logs | Write 3 entries in `decor_texts.json`; show on `dc_service_note` / tablet UI, rendered in Godot | text only | None |
| Reference only | NASA 3D Resources (`science.nasa.gov/3d-resources`): ALSEP / Surveyor 3 / Curiosity as silhouette reference. Public domain in most cases but each must be checked and credited; brief says keep IRIS fictional | n/a | n/a |

## 3. Build order

**M1 (inspect IRIS): do first**
1. A07 IRIS (the only blocking missing asset): placeholder first = one box + a thin cylinder mast with an emissive indicator box. **Goriorio can use this placeholder meanwhile** for mission state, position and the photo/scan trigger. Final mesh later.
2. Position IRIS on the terrain with route markers (A08, reuse `ws_marker_post`/`ws_sign_route`) and a scan anchor.
3. A06: confirm two batteries and two wheel sets exist in the catalog and the rack; add the second battery if missing. Goriorio: use the current `power_unit` and `wheel` as stand-ins.
4. A05 decision (section 4). A01–A04, A08, A09: already ready, no work.
5. A18: Kite note and IRIS note text.

**M2 (restore IRIS)**
1. A10 module + A11 cradle (A10 can be the existing cartridge scaled up until the real one lands: placeholder OK).
2. IRIS final states: antenna pivot and indicator animations (A07 finish).
3. A12 container, A13 near ID, A15 near target. Primitives (a cylinder + lid) are an acceptable stand-in.

**M3 (beyond the rim)**
1. A16 logger, far site and its reference soil patch (A15 far), A13 second container.
2. A14 sensor and A17 thermal kit (cuttable per the plan: "cut thermal damage").
3. A18 logger note. Then P2: rocks, audio, optional gloves.

Placeholders Goriorio can use now: IRIS (box + mast), module (cartridge), containers (cylinders), logger (cargo box), targets (coloured discs), sensor (none: UI reading only).

## 4. Conflicts between brief and repo

1. **Kite is two different things.** Brief (A05, plus the plan): Kite is the player's existing rover, "no separate lost-rover prop". Repo: `KITE_KIT.md`, `game/src/kite/`, `kite.glb`, `test_kite.gd`, and the README call "Kite" a disabled static rover at (-204, 136) that the player visits, and the player's rover is "ROOK" (KITE_KIT.md: "ROOK is our rover"). Decision needed: rename the player's rover to Kite and retire or repurpose the wrecked prop.
2. **M1 destination.** Brief/plan: M1 destination is IRIS (inspect the service panel, photograph). Repo M1: deliver a diagnostic cartridge to the wrecked Kite (cartridge, cargo delivery, scan, port). No IRIS exists. The cartridge delivery code could become the M2 module delivery (IRIS socket) instead.
3. **Cartridge (A06 in repo) vs A06 in brief.** Repo calls the diagnostic cartridge "A06"; the brief's A06 is battery/wheel variants. IDs are inconsistent.
4. **Approach route.** Kite's gate and route are at bearing 40 degrees, 151 m. IRIS needs its own position (100–160 m per README_GAMEPLAY) and gate; the two can share the same lane if Kite's prop is removed.
5. **Astronaut kit.** Built (astronaut, first-person, suit stand, stool) though the brief puts visible astronauts and gloves out of scope (optional P2 gloves only). Not blocking; do not extend.
6. **Mission names.** Repo docs and `game/res/ui/missions/` use `wake_kite` / `first_signal` / `beyond_the_rim`; M1 art cards exist. Titles are consistent, only the content differs.
7. **Brief says reuse "arm" and gripper for module and scoop.** The arm is scripted, not physically driven (cargo delivery is animated, no arm collision). The module and scoop must follow that same assisted-animation pattern, not free control.
