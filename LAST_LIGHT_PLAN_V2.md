# Last Light: Plan v2 (make the build matter)

From Rafi's full playthrough · for the whole team and each person's AI
Updated with the team's decisions (section 9). Where this file and older messages disagree, this file wins.

**Goal in one line:** the loadout you plan decides whether Kite comes home.

Right now the game works end to end but plays like a list of instructions (14:06 total; M1 ~4 min, M2 ~7 min, M3 only ~3 min). The rack parts never matter, because the default loadout always succeeds. The design docs (`game/README_GAMEPLAY.md`) already describe the game we want. The build drifted from them under deadline. This plan brings it back, and adds two things Rafi asked for: a **claw** and **parts you go out and fetch**.

---

## 1. Rules for every person and every AI

Paste this section into each AI session before its task.

1. **One branch per task**, from the latest `origin/main`, named `feat/<task-id>-<short-name>` (for example `feat/G1-claw`). Small PRs, merged often.
2. **Edit only your own files** (see the ownership table). If you need a change in someone else's file, write exactly what and for whom in your PR description. Do not edit it yourself.
3. **Shared IDs are fixed** (section 4). Use them exactly, so parallel work fits together without renaming.
4. **Every new interaction is its own scene** with a `highlight_node`, works on its own, and has a headless test in `game/tests/`.
5. Headless tests must not use `class_name` types as static types. After adding a `class_name` script, run `--headless --path game --import` once before the tests.
6. On Windows, ~200 `.import` files show as modified (line endings only). Do not commit or revert them. Do commit new `.uid` files.
7. Reuse what exists (section 3). No new frameworks, no refactors. Data before code.
8. Run only the tests related to your change. Each PR description lists them with their result.
9. Do not invent NASA facts. Simulated values are named constants and labelled "simulated".
10. Every phase must leave the game completable from the main menu with no console commands.
11. **A player can predict a failure before leaving.** Range, route risks and required equipment are shown before departure. Players fail from a poor decision, never from a hidden rule.
12. **Anything a required objective needs is on the rack from the start.** Cargo orders add options, never the only way to finish.

### Who owns what

| Person | Owns |
|---|---|
| **Fahd** | `moon_level.tscn`, `missions.json`, `cargo.json`, workshop, console, reports, cutscenes, saves, the lander |
| **Rafi** | `src/field/`, `src/iris/`, field and IRIS tests |
| **Former teammate** | the rover, its parts and sockets (`src/robot/`), `lines.json`, `dialogue_triggers.json` |
| **Rafi, for G1 only** | battery and wheel values, `Robot.ground_traction` and `range_estimate()` in `src/robot/` (taken over from the former teammate, who is less available) |
| **Faiq** | story text, voices, narrator, report wording |

---

## 2. Where we are and why it drifted

- "Every cargo order must be finishable" got built as "every loadout succeeds on every route". The right reading: every order has **some** plan that works.
- The cut order removed the far sample and the comparison report, so M3 is drive, grab, drive back.
- Emergency recovery (battery flat, or cold shutdown) returns Kite to the pad at no cost.
- Guidance spells out every click.

---

## 3. What already exists (reuse it)

| System | Where | Notes |
|---|---|---|
| Batteries | `src/robot/socket/battery_part.gd` | standard 100 Wh, light 60 Wh |
| Cold | `src/levels/cold_zone.gd`, `mission_director.gd` | shutdown after 20 s in shade without the thermal kit; heater 500 W |
| Nightfall | cold zones with `night_only` | active when the cargo arrived late |
| Traction | wheel `grip` in `running_gear.gd` | high-grip wheels exist |
| Mass | mass-driving (#56) | load changes handling and drain |
| Routes | `src/levels/route_markers.gd` | M3 short route through Head crater, long route around |
| Arm, manual | `src/robot/kit/rover_visuals.gd` | R deploys and stows; keys 1–5 pick a joint; joint ranges set |
| Arm, assisted | `src/robot/kit/cargo_delivery.gd` | latch, lift, carry, lower, stow; aborts if Kite moves |
| Cargo crate | `src/field/cargo_crate.gd` | opens, holds delivered parts |
| Lander | `src/field/lander.gd` | model, engine, plume, hatch |
| Sample site | `src/field/near_sample_site.gd` | S-1 on the cargo mount + E |
| Thermal sensor | `src/field/thermal_sensor.gd` | sun and shade readings with the thermal turret |
| Evan's notes | `src/field/readable_note.gd` | text, plus voice when the file exists |
| Report why lines | mission report (#59) | explains outcomes |
| Guidance | `missions.json` steps | each step already has a `stuck` text |

---

## 4. Shared IDs (use exactly)

| Kind | ID | Meaning |
|---|---|---|
| Objective | `m2.cargo_retrieved` | the delivered crate's parts are on Kite (new, M2) |
| Objective | `m3.far_sample_collected` | S-2 filled at the far site (new, M3) |
| Objective | `m3.thermal_pair_recorded` | a sun and a shade reading near the logger (new, M3) |
| Objective | `m3.cache_found` | optional: Evan's cache opened (new, M3) |
| Socket | `StorageBox` | deck box on Kite for small parts and sample containers |
| Group | `landing_zone` | where cargo landers set down |
| Group | `claw_target` | any loose part the claw can grab |
| Group | `far_sample_site`, `evan_cache` | new field scenes |
| Flag | `cargo_at_landing_zone` | the crate is waiting out at the landing zone |
| Signal | `ThermalSensor.pair_completed` | already exists; a pair at the far rim in M3 completes `m3.thermal_pair_recorded` |
| Property | `Robot.ground_traction` | float, default 1.0; a loose-ground zone sets it while Kite is inside; multiplies each wheel's grip |
| Method | `Robot.range_estimate()` | metres Kite can still drive on its battery with its current mass |

---

## 5. New mechanics

### 5.1 The claw: yes, it's possible

It isn't impossible. Most of it is already built: the arm moves joint by joint by hand, and `cargo_delivery.gd` already does a full assisted pick and place. What's missing is **grab and release**.

**Decided: build the assisted pick first, then the manual claw on top of it if there's time.** The assisted pick reuses existing code and guarantees nobody gets stuck. The manual claw is the immersive version.

- **Assisted pick (build first):** park next to a part and hold E; the arm runs the existing latch, lift, carry sequence in reverse and puts it in the box. This keeps the game accessible, as the docs require.
- **Manual claw (on top):** deploy the arm (R), move the joints, and when the latch is within ~6 cm of a `claw_target` part, E grabs it (the part rides the latch, frozen). Move over the `StorageBox` or the cargo mount and press E again: it mounts. Release anywhere else and it drops (unfrozen, real physics), so you have to be careful.
- **Driving carefully:** parts in the `StorageBox` are secured. Something carried on the latch while driving, or a loose part on the deck, drops past a tilt or bump limit after a warning. That's the tension, without risky loose-cargo physics.

### 5.2 The storage box

A small deck box with 2–3 slots for small parts and sample containers. With it, the logger, a sample and a fetched part can travel together. It's realistic and it gives the claw somewhere to put things.

### 5.3 Parts out in the world: yes, with a real reason

**Cargo lands away from the outpost.** A lander's exhaust blasts dust and rocks outward. Apollo 12 is the real example: it landed within walking distance of Surveyor 3, and parts the crew brought home showed pitting from the lunar module's descent blast. So cargo landers set down at a **landing zone a few hundred metres out**, and Kite has to drive there, open the crate, claw the parts into the box and bring them home to fit.

This fits our story and our Apollo 12 opening, and it turns the cargo order into a trip.

- The basic parts stay on the workshop rack (M1 works as now).
- **Ordered parts** (module, grip wheels, thermal kit, turret, big battery) arrive at the landing zone. A late order arrives near nightfall.
- **Evan's cache (optional, M3):** a small field box near the far rim with one useful spare (for example a thermal cover) and an Evan note. It rewards exploring and doesn't contradict "leave the mounts intact", which is about IRIS.

### 5.4 Things we are not doing

- **Skill-check minigame on part removal:** it adds friction to swapping parts, which is the thing we want players to do more.
- **Stripping IRIS for parts:** it breaks Evan's note and the story.
- **Weather:** the Moon has none. Our harsher conditions are nightfall, shade, distance and slopes.

---

## 6. Make choices matter: the M3 retune

| Route | Hazard | Needs | Without it |
|---|---|---|---|
| Short, through Head crater | rim climb on loose ground, a shade band near the logger | grip wheels + thermal kit | slips on the climb; cold shutdown |
| Long, around the crater | distance | standard battery, little extra mass | battery flat before the return |
| Either, after a late cargo | nightfall shade on both | thermal kit | cold shutdown |

- The default loadout (the light battery) fails both routes. At least two different builds succeed.
- Make it hard with cold zones and loose-ground zones, not by stretching the measured terrain.
- **Measured before the retune** (`test_m3_routes`, daytime): all six route and loadout cases get home and none spends any time in cold. The short round trip (978 m) uses about 44 Wh with the standard build and 52 Wh with grip wheels + thermal kit; the long one (1160 m) about 50 Wh and 60 Wh. So the light battery goes to **about 40 Wh** (fails both), and the short route's failure for the standard build comes from F1's loose ground and shade.
- **The cargo flight carries into M3 (kept):** Courier, 30 kg, arrives on day 4; Freighter, 40 kg, arrives on day 11, near lunar nightfall, so night-only cold zones switch on and the thermal kit matters more.
- **Range estimate** in Planning and the Kite tab: "round trip ~520 m, range ~610 m".
- **Recovery (decided):** Kite returns to base by emergency recovery, mission time advances, cargo and samples stay where it stopped (still recoverable), and the report marks "assistance used". Essential equipment always stays recoverable.
- A **why line** for every failure.

### Every rack part gets one job

| Part | Job | Trade-off |
|---|---|---|
| Wheels | climb the crater rim | grip against mass |
| Battery | reach the far rim and back | capacity against mass |
| Thermal kit | survive shade and nightfall | mass, and 500 W while heating |
| Tool turret | thermal pair for the comparison record | one turret at a time |
| Claw tool | fetch parts and samples | takes the arm slot from the thermal turret |
| Antenna | keep radio behind the crater rim (phase 3) | heavier |
| Mast camera | context photos, survey (phase 3) | more power |
| Motor | loaded climb in M2 | torque against efficiency |

---

## 7. Tasks

Each task has one owner, so up to three people (with their AIs) work in parallel without touching the same files.

### Phase 0: playthrough fixes (start now, all parallel)

| ID | Owner | Task | Done when |
|---|---|---|---|
| F0a | Fahd | Bay door: slide sideways into the wall; never close while any rover overlaps the doorway, driven or parked (`workshop.gd`, `_update_bay_door`) | Kite parked under the door is never hit; test covers it |
| F0b | Fahd | Hide skip-flight in M1 Planning | button absent in M1 |
| F0c | Fahd | Guidance shows objective + waypoint; step text only when stuck | no "open the console" text unless stuck |
| F0d | Fahd | Opening: music under title and space shots, louder descent rumble, touchdown thump, hatch sound (`cutscene_sound.gd`); add narrator lines | opening is never silent for long |
| G0 | Former teammate | Add `.mp3` audio paths to every line in `lines.json` | every line has an audio path |
| Q0 | Faiq | Record all voices and the narrator from the voice sheet | files in `game/res/audio/voice/` |

### Phase 1: the core tension (parallel)

| ID | Owner | Task | Done when |
|---|---|---|---|
| F1 | Fahd | M3 retune: cold zones and loose-ground zones on the routes (zones set `Robot.ground_traction` while Kite is inside), recovery cost, why lines, M1 fitting the light battery, one thermal turret on the rack from the start | matches the route matrix |
| G1 | **Rafi** | Light battery ~40 Wh; `Robot.ground_traction` (float, default 1.0) multiplied into each wheel's grip in `running_gear.gd`; `range_estimate()` on the rover | each part has a real benefit and cost; M1 and M2 still fit the light battery |
| R1 | Rafi | `test_m3_routes`: drive each route with each loadout headless and check the matrix | **done** (pushed); flip `ENFORCE` after F1 |
| R1b | Rafi | Show the range estimate in the field pieces' hints (uses G1) | hints mention reserve |

### Phase 2: claw, box, landing zone, science (parallel after phase 1 starts)

| ID | Owner | Task | Depends on |
|---|---|---|---|
| G2 | Former teammate | `StorageBox` socket (2–3 slots) on Kite | none |
| G3 | Former teammate | Claw: the assisted pick first (reuse `cargo_delivery.gd`), then manual grab and release on the arm latch on top | G2 for release into the box |
| R2 | Rafi | Mark loose parts as `claw_target`; make the cargo crate work at the landing zone | G3 interface |
| R3 | Rafi | Far sample scene (reuse `near_sample_site.gd` with the objective and container as settings) → `m3.far_sample_collected`, **optional**, a fuller report when done | G2 |
| R4 | Rafi | Thermal pair near the logger → `m3.thermal_pair_recorded`, **required** | **done** (pushed); Fahd adds the ID to `missions.json` |
| R5 | Rafi | Evan's cache scene → `m3.cache_found` (optional) | G3 |
| F2 | Fahd | Landing zone in the level; cargo lands there; flag `cargo_at_landing_zone`; `m2.cargo_retrieved` | R2 |
| F3 | Fahd | New M2 and M3 objectives in `missions.json`; comparison report in Downlink | R3, R4 |
| Q2 | Faiq | Lines for landing zone, far sample, comparison, cache; Evan's cache note text | none |

### Phase 3: if there's time

| ID | Owner | Task |
|---|---|---|
| G4 | Former teammate | Radio shadow behind the crater rim (one ray to the base); high-gain antenna keeps the link |
| G5 | Former teammate | Drop rule for carried or loose parts past a tilt or bump limit |
| F4 | Fahd | Optional survey photos of landmarks (existing scan targets) |

**Merge order:** phase 0 any time. In phase 2, G2 then G3 first, because the others plug into them. `missions.json` changes only through Fahd.

---

## 8. Briefs to paste into each AI

Start every AI session with: *"Read `LAST_LIGHT_PLAN_V2.md` (sections 1, 3 and 4 are rules), `CLAUDE.md` and `game/README.md`. Do only the tasks below, one at a time, and report each in under 10 lines: what changed, test results, anything another owner must do."*

- **Fahd's AI:** tasks F0a, F0b, F0c, F0d, then F1, then F2 and F3 when their dependencies land.
- **Rafi's AI:** G1, then R1b, R3, R2, R5 (R1 and R4 are done).
- **Former teammate's AI:** G0, then G2, G3, then G4 and G5. If the former teammate stays unavailable, Rafi picks up G2 and G3.
- **Faiq:** Q0 now, Q2 after the objectives are agreed.

---

## 9. Decisions

1. **Phase 1 first.** Equipment choices must really affect traction, battery life, mass and thermal survival. The default loadout fails both M3 routes; at least two different builds succeed. Players see range, route risks and required equipment before leaving.
2. **Keep the Courier/Freighter trade.** The Freighter carries more but arrives near nightfall, so M2's planning carries into M3. The landing zone stays in Phase 2, after the balancing.
3. **Recovery costs time and position, not the campaign.** Time advances, cargo and samples stay where Kite stopped and can be fetched, the report marks assistance. Essential equipment always stays recoverable.
4. **M3 science:** the thermal pair at the far rim is required (one thermal turret is on the rack from the start, so a player who skipped it in the order can still finish). The far sample and Evan's cache are optional; the far sample gives a fuller report.
5. **Claw:** the assisted pick first, the manual claw on top.

Still open: is today's export the final submission, or do we keep building? And do we keep the no-sound-in-vacuum rule in the opening, with music added on top?
