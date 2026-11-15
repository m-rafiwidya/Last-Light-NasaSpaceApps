# Tandborste — final game and story plan

**LAST LIGHT · Moon chapter · 11 October 2026**

This is the team's final production direction for this chapter. It replaces the earlier two-rover opening. The player uses **Kite**, already stored at the lunar outpost. The home base and the research station **IRIS** are separate places. This handoff describes intended behaviour; the Godot repository was not supplied for code review or runtime verification.

## What we are making

A single-player game about preparing a small rover, driving across difficult lunar terrain, investigating old equipment, and returning useful work to Earth. You move in first person inside a workshop. A console switches control to Kite outside. You can see and feel what your equipment choices change.

The completed Moon chapter targets **20–30 minutes for a first run**, with three outings on one terrain patch. Duration is a playtest target, not a countdown. Mission replay and a few authored contracts reuse the same world.

## Story in plain language

In a fictional 2058 expedition, you are an astronaut and robotics engineer with the international **Surface Research Programme**. Its design is inspired by NASA and partner research; the organisation and its operations are fictional. You arrive with a small crew by spacecraft and lunar lander. Cargo and habitat checks have prepared an existing field outpost for your rotation.

Your workshop contains Kite, a reusable rover left in storage by the earlier crew. Its frame is serviceable; the battery and equipment need attention. You repair it using stocked or delivered parts rather than shipping another whole vehicle.

Nearby, the unattended research station IRIS has stopped transmitting. The previous crew ran out of replacement stock before their departure. Its science archive is incomplete on Earth. Your assignment is to inspect the fault, restore the station, and retrieve its last missing field record before the current field rotation ends.

**Mira**, the Earth systems lead, handles mission planning and diagnosis. **Hana**, the Earth science lead, helped run the earlier IRIS campaign. **Evan**, its previous field technician, appears through short recorded notes. Other expedition members handle the habitat and wider research rotation; they do not require animated NPCs.

The human stays in the outpost while controlling Kite through a local link. Earth provides analysis and instructions. Hardware comes from actual workshop inventory or cargo deliveries. Samples remain on the Moon; their recorded measurements and lab reports are downlinked.

## Three outings, with a reason to reconfigure

| Mission | Main activity | New challenge | Useful result |
|---|---|---|---|
| **M1 — Wake Kite** | Repair Kite, visit IRIS, photograph its service panel, return and downlink | Learn building, control, driving and return reserve | Diagnosis identifies the failed radio-power module |
| **M2 — First Signal** | Carry a replacement, restore IRIS, take a reference sample if equipped, return | Heavy cargo changes handling; short difficult and long gentle routes | IRIS resumes live readings and reveals a missing remote logger |
| **M3 — Beyond the Rim** | Recover the logger, collect two reference-site samples and paired ground-temperature readings, return | Farther travel, a loaded return, slopes and temporary shadow | Earth receives the complete archive and a new comparison survey |

M3 can collect the near-site reference sample if the player skipped it during M2. Its checklist must say so before departure. The player does not lose the campaign for missing an optional earlier task.

The final scene happens at home: Kite docks, IRIS remains active, the archive is received, and Hana recognises the earlier crew's last record. Mira closes the field report. The result screen credits the actual tasks achieved and offers replay or free workshop access. Mars appears as a later assignment, not a level the team must build now.

## Progression: equipment solves problems

The next mission changes the job. It does not automatically grant a stronger version of everything.

- M1 starts with a safe baseline configuration and a basic camera.
- Its report makes the replacement-module work order available and explains loaded climbing. Existing stock or the selected cargo kit supplies compatible wheels, motors and spares.
- M2 reveals the remote logger and a colder route forecast. The player can assemble an insulating cover/heater from stock and fit the sampling kit.
- M3 offers a shorter, more demanding approach and a longer, gentler alternative. Choose equipment and power use around the route.

“Unlocked” means a diagnosis, approved work order or delivered physical item. A photograph never creates a battery from nothing. Soil samples do not turn directly into motors or fuel.

The two headline engineering choices are **wheel set** and **battery/load allocation**. The mission specifies necessary tools. Optional camera quality or additional samples compete for remaining mass, power and storage. The earlier camera-versus-repair example becomes a replay contract, rather than a confusing mandatory story fork.

| Choice | Benefit | Cost or limitation |
|---|---|---|
| Efficient wheels | Lower mass; suitable for gentle routes | Less margin on rough or steep approaches |
| Grip wheels | Better usable traction | More mass; can spend more energy, depending on slip and route |
| Compact battery | Frees mass for tools and cargo | Less energy reserve |
| Extended battery | More range/heater reserve | More mass and freight cost |
| Higher-torque motor | Better loaded climbing capability | Cost, mass and electrical demand; traction still limits climbing |
| Thermal cover/heater | Reduces cold exposure risk | Cover mass and heater power |

Higher grip is not automatically worse for energy: avoiding wheel slip can save energy. Balance using measured playtest runs. If the largest battery wins every situation without a cost, the constraints are not doing their job.

## What makes traversal enjoyable

Use a visible short difficult route and a longer forgiving route. Put difficulty in slopes, cross-slopes, boulders, payload stability and a few authored loose-regolith patches. A stronger motor does not solve insufficient traction, poor clearance or a tipping risk.

The first route works with the supplied baseline rover. Later preparation changes what is comfortable or feasible. Make each new capability visible: a loaded climb becomes controllable; a cold approach uses the heater; the sampling kit adds a clear interaction.

Keep the rover responsive and the camera readable. Use existing chase/mast cameras; permit camera switching. Required arm work uses a forgiving context interaction with an assisted animation. Manual joint control can remain an optional mode. A first-time player should not spend five minutes fighting a socket or arm joint.

Revisit familiar ground with a changed task and cargo. Restoring IRIS changes lights, antenna state and telemetry. An optional station charging point can extend exploration later; it is not required for the first complete chapter.

## Science activities

**Ship:** inspection photographs, physical sample collection, ground-temperature measurements and logger recovery. Each has an identifiable target, metadata and a reason to influence the mission.

- A panel photograph identifies the fault and the correct replacement.
- Samples from the near and far sites produce a comparison report. Scoop animation and sealed containers are enough; no granular-soil simulation is required.
- A radiometer reads surface temperature, not Earth-style outdoor air temperature. Compare two locations under stated conditions; a short reading is not a measurement of lunar heat flow.
- The logger preserves the older observation series. Receiving its record closes the story.

**Later:** a trace-gas instrument for a lunar exosphere contract. The Moon has a sparse exosphere, not breathable air or ordinary weather. Keep air-pressure/atmospheric sampling as a stronger Mars feature. NASA-derived geometry, sourced facts, authored sensor readings and fictional logs must be identified separately. See [science and data](game/docs/SCIENCE_AND_DATA.md).

## Space-mission lifecycle

Include a small parts manifest, two delivery-service cards, mass/cost checks and a short educational flight-feasibility sequence before the field operations. The selected crate changes workshop stock. Show launch, transfer, lunar arrival and delivery, with story days compressed and labelled. A declared descent delta-v model is enough for this build; manual spaceship flight and complete orbit integration are not required.

Then plan the surface objective, configure Kite, execute the trip, return/transmit data, evaluate consequences and prepare the next mission. The choice must affect the playable mission, not just a decorative launch animation.

## Interface and tone

One console: **Mission / Kite / Downlink**. One large Control Kite button. Default rover HUD: current objective, destination, battery/return warning, cargo and relevant temperature warning. Put the long wheel-force panel and debug keys behind a developer view.

Use one objective at a time. Keep source equations in a details panel. Avoid making the player read a textbook before driving. English is the proposed game language; subtitles are always available.

The tone is a quiet, practical field expedition. A little dry humour, used equipment, handwritten service notes and a station that visibly wakes up create atmosphere. No apocalypse or missing-astronaut plot is needed.

## Voices and audio

**Record the team yourselves.** Two live radio roles and one short archive role are enough. Use short natural deliveries, consistent recording distance and light cleanup. Accents fit an international expedition. Performance and intelligibility matter more than sounding like a film trailer.

Use ElevenLabs for temporary placeholders or a specifically needed fallback, after checking its current publication terms. Self-recorded final lines avoid a recurring generation workflow and give the team control of delivery. See [voice and audio](game/docs/VOICE_AND_AUDIO.md).

Workshop audio can include fans and footsteps. Exterior rover feedback is an onboard vibration/contact pickup or interface sonification, not an Earth-style wind ambience. Keep music restrained and warnings understandable.

## Assets and work ownership

Reuse the existing rover, wheels, motors, batteries, arm, cameras and terrain pipeline. Build a compact workshop, pad, console, rack, IRIS, replacement module, sampling kit, two sample sites, thermal kit and field logger. Exact quantities, interactions and reference links are in the [asset brief](game/docs/ASSET_BRIEF.md).

| Owner | Main responsibility |
|---|---|
| Former teammate | Reliable rover/control handoff, part effects, dock and mission state |
| Fahd | Single terrain pipeline, workshop/station kit, tools, collision and imports |
| Faiq | Script, logs, radio triggers and voice direction |
| Rafi | Objective clarity, mission placement, external playtests and judge demo |

Assign one owner to each shared controller, terrain pipeline and scene. AI assistants implement one bounded ticket using the current architecture; [README_AI.md](README_AI.md) specifies that workflow.

## Build order and release gates

1. **M1 complete:** fit battery → control → inspect IRIS → return → dock → downlink → report → retry. Placeholder art is fine.
2. **M2 complete:** module cargo changes handling; repair consumes it once; IRIS activates; optional sample works; return/report works.
3. **M3 complete:** logger, sampling and temperature metadata; both advertised route strategies; complete ending and reset.
4. **Competition lifecycle:** consequential cargo planning/delivery, sources, assumptions, exported build and prepared demo.
5. **Polish:** voices, atmosphere, readable interactions, and then replay contracts.

If time becomes tight, cut optional contracts, extra rooms, thermal damage, a remote charging mechanic and elaborate effects. Preserve the three objectives, final ending, and an exported complete run. Simplify M3 to a logger recovery and one paired observation if needed; change its checklist and all script/data definitions together.

Do not add a second planet until the Moon chapter passes. Mars can keep the workshop/rover framework while introducing its own terrain, thin atmosphere, dust/power decisions and asynchronous Earth support. The protagonist travels on a later crew expedition; knowledge transfers, while destination-specific hardware is supplied there.

## How we know the design is working

Give the export to at least three people outside the team. Watch without explaining. Ask whether they know their objective, can assemble and drive, understand one trade-off, and want another outing. Record where they hesitate. Fix those issues before producing more assets.

A strong concept is not a measured guarantee of fun or an award. Our evidence for judges is the complete mission lifecycle, consequential NASA terrain use, defensible assumptions, explainable choices and observed player learning. Do not invent global judging weights or claim that voice acting itself earns points.

## Handoff files

- [Implementation and acceptance checks](game/README_GAMEPLAY.md)
- [Complete story script](game/docs/STORY_SCRIPT.md)
- [Asset list and references](game/docs/ASSET_BRIEF.md)
- [Science, units and source registry](game/docs/SCIENCE_AND_DATA.md)
- [Voice recording and audio](game/docs/VOICE_AND_AUDIO.md)
- [AI instructions](README_AI.md)
- [Example mission data](game/docs/examples/MISSIONS.json)
- [Ready-to-send group message](TEAM_MESSAGE.md)

Primary references: [official challenge description on a 2026 team page](https://www.spaceappschallenge.org/2026/find-a-team/missionforge/), [LROC Apollo 12 terrain](https://data.lroc.im-ldi.com/lroc/view_rdr_product/NAC_DTM_APOLLO12), [NASA lunar environment](https://science.nasa.gov/moon/weather-on-the-moon/), [NASA lunar atmosphere](https://science.nasa.gov/moon/lunar-atmosphere/). The science brief records further references and which parts remain game assumptions.
