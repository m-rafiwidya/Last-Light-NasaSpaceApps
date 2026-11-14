# LAST LIGHT — gameplay implementation brief

**Final direction: 11 October 2026.** Desired behaviour, not a claim of implemented or tested code. Preserve the repository's actual run/architecture README and read its instructions before changing scenes.

Companions: [story](docs/STORY_SCRIPT.md), [assets](docs/ASSET_BRIEF.md), [science/data](docs/SCIENCE_AND_DATA.md), [example mission definitions](docs/examples/MISSIONS.json), [AI guide](../README_AI.md).

## Product and first ticket

First-person lunar workshop, one configurable rover **Kite**, one terrain patch, one primary research station **IRIS**, and a field logger/reference site farther away. Three outings form a 20–30 minute target chapter. Tune duration from playtests.

**Implement M1 end to end first.**

1. Start in the workshop with Kite's battery socket highlighted.
2. Fit a compatible charged battery and wheel set using existing part logic.
3. At the console choose Control Kite. Exactly one human/rover gameplay input owner is active.
4. Follow the safe route to IRIS and record a readable diagnostic image at its service panel.
5. Drive back; exiting control parks Kite without changing its location or cargo.
6. Dock, submit the image, receive the scripted diagnosis and see a completion report.
7. Replay or continue; early return explains the missing image and allows another trip.

Prerequisite: baseline driving and dock contact work on the test ramp and the intended route. Do not put a mission on top of a reproducible terrain-clipping problem.

## World contract

| Element | Behaviour |
|---|---|
| Home base | Pressurized operator/workshop area; part rack, pad, console and an abstracted rover service-airlock cycle |
| Kite | Existing controllable chassis; wheel, motor and battery swaps remain functional |
| IRIS | Fixed fictional research unit: service panel, module socket, antenna, indicator and archive state |
| Far site | Static logger plus a sample/temperature target; uses the same terrain rather than another level |
| Crew | Background context. Two Earth radio roles and one archive voice; no walking NPC systems |
| Dock | Forgiving parking/alignment check, charge/service action, inventory/sample transfer and data queue |
| Sensors | Defined target interactions with metadata; no live computer-vision backend |

Kite was stored at the base. There is no separate lost-rover prop or fleet selection. Existing internal script names may remain; change player-facing names without a repository-wide rename.

## Campaign state and mission gates

| Stage | Required action/result | Persistent update |
|---|---|---|
| Cargo planning | Valid service, manifest, mass/cost and declared descent margin | Delivery ledger and selected stock |
| Cargo arrival | Skippable phase sequence completes, with labelled story time | Stock enters inventory once |
| M1 | Diagnostic panel image received on Earth and Kite docked | Radio-power fault diagnosed; replacement work order available |
| M2 | Correct module installed, IRIS online, initial station archive received, Kite docked | Station active; far logger objective revealed |
| M3 | IRIS active; logger record, valid two-site sample comparison report and paired temperatures received; Kite docked | Archive complete; final comparison report and chapter ending |

M2's near-site sample is optional preparation for M3. M3's readiness/checklist accounts for it if missing. Sample comparison is completed locally; reports are transmitted while physical containers remain at the outpost.

Suggested responsibilities: one authoritative campaign state, per-sortie state, immutable mission/part definitions, UI observers and a content-driven narrative resolver. These can be existing systems; do not add competing autoloads.

Suggested events: part_changed, loadout_validated, control_taken, inspection_recorded, sample_collected, temperature_recorded, cargo_changed, rover_docked, observation_received, repair_installed, station_restored, logger_received, sortie_evaluated. Use verified existing names when available. An event may update multiple displays, but only one place owns its underlying state.

## Building and upgrades

Snap parts into compatible sockets. The wheel-set action can replace the set together; do not require six identical perfect placements. Show one benefit, one cost and a short compatibility reason. Parts should remain identifiable physically and in the UI.

Two headline choices: wheel set and battery/load allocation. Motor and thermal variants extend the same system. Essential mission tools are readiness requirements; optional survey equipment competes for spare capacity.

- Batteries: capacity_Wh, charge_Wh, mass_kg and operating-temperature assumptions.
- Wheels: mass_kg, radius_m, compatible mount, traction/rolling-resistance parameters or the controller's existing equivalents.
- Motor: torque/power/efficiency assumptions or measured existing equivalents. More torque still needs tyre contact and usable traction.
- Cargo: mass_kg, socket, required identity and consumed/installed state.
- Sampling kit: gripper-compatible scoop, containers and surface-temperature sensor. No particle physics simulation.
- Thermal kit: cover mass/insulation parameter and an optional heater power_W.

The baseline camera remains installed. A higher-quality optional camera belongs in later survey contracts. Camera versus repair payload can be a contract choice; the story's required repair always tells the player which module is needed.

All usable hardware has a stock/delivery origin. Diagnosis can reveal a recipe or approve a part; it cannot spawn arbitrary materials. Keep mandatory completion possible for every offered manifest. If a chosen optional kit would block a required later mission, mark the problem before purchase or retain a feasible baseline kit.

## Traversal and route layout

Placement starting targets, to be adjusted on the actual measured patch:

- IRIS: around 100–160 m along the first safe approach.
- M2: same station, a short loaded climb and a longer gentle approach.
- Far logger: around 250–350 m from home along viable terrain; complete route lengths may be longer.

These are level-design estimates, not NASA station coordinates. Inspect the imported patch before placing points. Preserve its physical scale; do not invent a cliff by multiplying heights and still call the resulting slope measured.

Introduce one new problem per outing: basic driving, loaded stability/climbing, then longer travel and temporary shadow. Loose material zones and added physical boulders are authored assumptions. Forecast them and offer a route alternative. Avoid compulsory jumps, invisible upgrade barriers and unlimited grip.

M3 offers a shorter rougher/shadowed approach and a longer gentler approach. Keep the logger reachable near the shade boundary; do not require an unforecast unavoidable extreme-cold exposure. Thermal response has inertia. Balance the available strategies by running the actual routes with the installed parts.

Do not add a winch, bridge-building, procedural mining or a second terrain biome before the chapter works. Save them for a tested expansion.

## Energy and temperature

Use explicit units and one simulation clock for resource integration. Energy in Wh updates by `(generation_W - load_W) * dt_s / 3600`. Charge cannot exceed capacity or fall below zero. Powered actions stop at depletion; the UI reports a usable retry action.

Loads include avionics, drive, sensors, heater and downlink. If actual torque/current telemetry exists, use it with declared losses. Mechanical shaft power alone does not account for motor losses or stalled-current draw. A calibrated gameplay proxy is acceptable when labelled, but do not call it a validated lunar motor model.

Recompute mass when a component/cargo changes. Set lunar gravity consistently (about 1.62 m/s²). Mass remains in kg. Added mass may change inertia, normal force, slopes and centre of mass through the existing controller. Check the loaded rover, rather than adding cosmetic numbers.

Temperature is a simplified optional resource model. Surface temperature and internal battery temperature are separate. A first-order body-temperature response with configurable time constant and heater term can be used as a game approximation; it is not a complete radiative thermal solver. Give warnings before derating or shutdown. Do not instantly assign a cold surface reading to the battery.

Keep the sunlight direction stable for a field shift. M3 uses ordinary temporary shade in an equatorial Apollo 12-region map, not a permanently shadowed polar ice crater. Any accelerated service or mission time is labelled and applied consistently to its declared model. If thermal physics is not ready, use the stated cold-route forecast and planned heater energy cost without a second damage system.

## Science interaction details

**Inspection:** valid target, suitable range and line of sight; record ID, camera pose, position, time, quality and the fictional fault record. An optional saved screenshot illustrates the scan. Query a predefined target condition rather than image recognition. Duplicate scans do not create duplicate required science.

**Sampling:** required kit, available container and rover stable near the target. One assisted scoop animation fills one container. Store site ID, mass, local/world position, source-coordinate metadata when available, context image and disturbance state. Both reference sites should remain obtainable; if the rover disturbs the initial spot, show another nearby clean target rather than soft-locking the chapter.

**Temperature:** require the sensor and a valid surface target. Record sun/shade context, units and location. A paired reading creates a comparison record. Kelvin-to-Celsius conversion is explicit if imported data uses K. A short surface scan does not establish subsurface composition or heat flow.

**Logger:** visible single cargo object, pickup once, attached mass and storage record. Its data becomes received only after successful transfer/downlink. A basic reader/interface is part of the outpost, not magic Earth access.

**Lab/downlink:** dock transfers sample containers into outpost storage; local analysis produces authored/simulated reports; Earth receives the packet. A few seconds of UI progress can overlap service or log reading. Use compression for gameplay and state the convention. Avoid an empty long wait.

The sample report compares the two stored sites using a simplified imaging/context review, not exact chemistry from a photograph. Reuse the console and a small inspection tray. A valid `sample_comparison_report` requires both site records; it is one report, not two separate mandatory lab minigames. A sample action can capture context photo/temperature automatically when the sensors are fitted.

## Compact cargo flight

The player already arrived with the crew. A parts-resupply flight is the playable delivery-planning task. Provide two fictional educational service profiles with delivered payload capacity, credit cost and stated assumptions. Selected optional parts plus packaging count toward mass. Essential baseline completion equipment is available at the outpost or included automatically.

For a single declared lunar descent stage, use the ideal rocket equation with standard gravity 9.80665 in the Isp convention; subtract a declared required delta-v and reserve. See the science brief for the equation and its limits. Gate on mass, credits, required stock and non-negative margin. Earth ascent/transfer/orbit arrival can be prevalidated service phases whose progress and outcomes are recorded.

Show a 15–25 second skippable phase sequence: launch, transfer, lunar arrival, cargo delivery. Story time advances by days. Skipping animation cannot skip validation or duplicate delivery. Mission-service values are game assumptions until sourced; do not label them as a particular real launch vehicle's performance.

## Interface and control

Console tabs: Mission (objective/route/readiness), Kite (parts/charge/cargo/control), Downlink (records/reports/archive). Keep one prominent control action. Default rover view shows the current objective, waypoint, reserve, cargo and only relevant warnings. Detailed tyre force/contact telemetry stays in the development view.

Use existing input actions rather than overwriting them. Required interactions can use the current interact key. Mast/chase views remain switchable. Pause and mouse release must behave consistently when opening UI. Never leave both human and rover driving input active.

Leaving control safely brakes/parks Kite and returns to the human camera. It does not teleport the rover or unload cargo. Charging and assembly require physical return to the service area.

Required arm tasks use target-assisted animation and forgiving alignment. Manual joint control may remain available for experienced players. Provide a keyboard-accessible interaction alternative to precision aiming. Critical information appears in text as well as voice/colour.

## Failure, checkpoints and reports

Save a pre-sortie workshop checkpoint including inventory, loadout, campaign flags, station state and received data. A retry restores that snapshot; it does not selectively keep a consumed module while refunding its stock. M2/M3 start from the successful previous mission's checkpoint.

At depletion/flip/unreachable terrain, offer a clear retry or explicitly labelled assistance. Assistance is a game mode and appears in the report; it is not represented as a physically simulated rescue. Avoid forcing a long walk or an unimplemented NPC retrieval. Prevent negative-credit soft locks.

Report objectives, received science, station state, rover returned, resource use and assistance separately. Explain a concrete cause: loaded climbing consumed reserve, a required image was missing, the logger was still onboard, or the station is active but the final archive is pending. Avoid a single opaque score.

M2 success is not the chapter ending. Chapter completion requires IRIS active, final logger received, the required comparison records received and Kite docked. If scope is intentionally simplified, update this condition, mission definitions and story together.

## Replay and contracts

After the chapter is stable, offer a few authored contracts: limited freight, loaded repair, additional survey or cold-route recovery. Every contract has a verified feasible plan and understandable forecast. Reuse existing terrain and targets. Let players compare time, energy reserve and valid delivered science for the same contract/model version. No multiplayer, online leaderboard or random unavoidable failure is needed.

## Meaningful verification

1. Baseline/loaded rover: flat ground, test ramp, both marked routes; no clipping or persistent airborne wheels.
2. Part swap: visual/UI configuration and observed handling agree; total mass/capacity update once.
3. Control: enter/exit/pause/camera changes on flat ground and a slope; one active input owner.
4. Scan: wrong target/occlusion rejected clearly; repeats cannot multiply required data.
5. Cargo/sample: pickup once, mass correct, container consumed once, near sample can be collected later if skipped.
6. Dock: empty return remains usable; loaded return transfers once; repeated dock has no duplicate award.
7. Repair: absent/wrong module rejected; correct module consumed and station changed exactly once.
8. M3: both forecast route strategies are viable; warnings give time to respond; paired targets generate valid records.
9. Completion: no win while logger/data remain unreceived or rover remains outside.
10. Retry/new campaign: inventory, station, flags, dialogue, pending callbacks and camera all reset consistently.
11. Export: a complete run on a teammate's machine outside the editor, with data bundled and debug overlay hidden.

Then watch at least three new players without coaching. Measure objective clarity, assembly time, camera discomfort, route confusion, return-trip interest and voluntary replay. Broaden testing only when a failure or new change justifies it.

## Technical boundaries

Reuse the current Godot version and architecture. GDScript handles mission/UI/resource logic. Python prepares NASA data offline. C++ is appropriate only for an existing essential integration or measured heavy work. No runtime web requests or account system are necessary.

Audit the reported ramp issue through actual reproduction, scale, contact/collision shapes and masks. Document actual layer names instead of guessing layer numbers. If the project uses VehicleBody3D, note its documented simulation limits; that does not establish which controller the team uses or justify rewriting a working custom one.

Technical references: [Godot signals](https://docs.godotengine.org/en/stable/getting_started/step_by_step/signals.html), [Godot Resources](https://docs.godotengine.org/en/stable/tutorials/scripting/resources.html), [VehicleBody3D](https://docs.godotengine.org/en/stable/classes/class_vehiclebody3d.html), [NASA ideal rocket equation](https://www1.grc.nasa.gov/beginners-guide-to-aeronautics/ideal-rocket-equation/).
