# LAST LIGHT — instructions for AI coding assistants

**Tandborste · final Moon chapter direction · 11 October 2026**

This file is a production brief, not evidence that the features below are implemented. The actual repository was not supplied when this handoff was written. Read its `AGENTS.md`, run instructions, Godot version, scene structure and existing APIs before editing. Preserve the repository's architecture README; put the gameplay contract in `game/README_GAMEPLAY.md`.

## Read first

1. [Final product/story plan](Tandborste-Game-and-Story-Plan.md).
2. [Gameplay and acceptance checks](game/README_GAMEPLAY.md).
3. The relevant [story](game/docs/STORY_SCRIPT.md), [asset](game/docs/ASSET_BRIEF.md) or [science](game/docs/SCIENCE_AND_DATA.md) section for the assigned ticket.
4. The actual scripts/scenes affected by that ticket. [MISSIONS.json](game/docs/examples/MISSIONS.json) is an example content schema, not a drop-in implementation.

Inspect the current controller and part system before designing a replacement. Earlier handoffs mentioned `game/src/autoloads/game_state.gd`, `dialog_server.gd`, `scene_loader.gd` and a console/dialog UI. Treat these as search hints, not verified paths or signatures. Find the real equivalents and reuse them.

## Canon that code must preserve

- Fictional 2058 international Surface Research Programme; NASA/partner inspiration, not a real NASA mission or prediction.
- Player is an astronaut/robotics engineer at an existing lunar workshop, supported by a small off-screen crew.
- **Kite is the single playable rover, already stored at the workshop.** Do not implement a second rover, fleet picker or a lost-rover opening.
- **IRIS is a separate uncrewed instrument station**, not the home base. A far logger/reference site is on the same terrain patch.
- Mira and Hana are Earth radio roles. Evan appears in archived notes. These are triggered dialogue, not walking NPCs or AI chat agents.
- **M1:** repair/configure Kite, inspect IRIS's panel, return, downlink, diagnose.
- **M2:** carry/install the correct module, activate IRIS, receive initial archive, return. Near-site sample is optional preparation.
- **M3:** recover logger, complete near/far sample and paired surface-temperature records, return, transmit, finish.
- M3 must still allow the near sample when it was skipped in M2.
- Complete the chapter only with IRIS active, the final records received and Kite docked. M2 restoration is an intermediate success.
- Physical equipment comes from stock or cargo. Earth sends information; photographs and soil do not spawn hardware.

The main decisions are wheel choice and battery/load allocation. Necessary mission tools are explicit requirements. Different viable routes/configurations produce different time, energy, risk and delivered-science results within the same campaign, rather than multiplying story levels.

## Implementation boundaries

Use **GDScript** for interactions, missions, UI, resource bookkeeping and dialogue. Use **Python offline** for source-data conversion. Use **C++** only for an existing necessary integration or a measured expensive operation. Do not introduce native extensions for a short mission checklist.

Keep NASA input files and metadata bundled; the exported game must not depend on scraping, internet access or a player account. Keep real measurements, derived geometry, authored art, fictional sensor values and story logs distinguishable.

Reuse the current input actions, cameras, arm, part sockets and UI components. Preserve working handling when adding art. Do not edit the rover controller in an asset ticket. Do not guess collision-layer numbers. Audit actual names, masks, shapes, scale and contact behaviour when reproducing the ramp issue.

Use one authoritative campaign state and the current event/dialogue architecture. Part/mission definitions can be immutable Resources; each run holds mutable inventory, charge, observations and flags. Do not put per-run mutation into a shared definition or add a competing quest autoload.

Keep collected, locally analysed, queued and Earth-received records distinct. A scan's dialogue is not proof of receipt. A dock action, module installation, sample pickup or shipment can change inventory only once. An installed module cannot simultaneously remain available on the shelf.

Use explicit units: metres, kg, seconds, W and Wh. Charge integration includes `/ 3600`. Lunar gravity affects weight/contact, not the definition of mass. Ground temperature and battery temperature are different values. The ideal rocket equation uses standard gravity in the specific-impulse convention. See the science brief before implementing these calculations.

## Control, recovery and usability

- Exactly one human/rover gameplay input owner; UI focus, pause and mouse release must be predictable.
- Leaving rover control parks Kite in place. It does not teleport, charge or unload it.
- Physical return to the dock enables charging, assembly and sample transfer. Service duration may be compressed and labelled.
- Required arm work uses forgiving target-assisted animation; preserve manual control as optional if it already exists.
- A pre-sortie checkpoint includes inventory, rover configuration, station state, observations and campaign flags. Restore it consistently, including pending callbacks and dialogue state.
- No dead end from skipping an optional sample, choosing an offered manifest, disturbing one sample target or losing the rover. Offer a coherent retry or labelled assistance.
- One active objective, readable warnings, subtitles and text equivalents for essential colour/audio cues. Keep debug tyre telemetry hidden in normal play.

## Small tickets, in order

| Ticket | Deliverable | Acceptance |
|---|---|---|
| T01 | Reproduce/document ramp and control issues | Baseline and loaded Kite cross the test ramp; one input owner |
| T02 | Complete M1 | Fit parts → control → valid panel scan → return → dock → receive diagnosis → retry |
| T03 | Complete M2 | Module cargo affects load; repair consumes once; IRIS activates; archive receipt/report work |
| T04 | Sample and temperature interactions | Correct kit/targets, metadata, two containers, clean fallback and near-sample catch-up |
| T05 | Complete M3 and ending | Logger cargo/data, valid comparison, final receipt/dock gate, reliable replay/reset |
| T06 | Consequential cargo flight | Service/manifest checks; declared flight assumptions; arrival adds stock once; skip cannot bypass validation |
| T07 | Dialogue/audio and finish | Actual-state triggers, subtitles, no overlapping voices or blocked driving |

Owners: the former teammate owns rover/control/mission integration; Fahd owns terrain/assets/imports; Faiq owns story/audio content; Rafi owns objective clarity, playtests and demo. Coordinate edits to shared scenes/controllers through the owner. Adapt ticket order only for a real dependency.

## First prompt to paste into your coding assistant

> Implement T02 only: one complete M1 inspection outing using the current rover, parts, cameras, console and dialogue systems. First inspect repository instructions and locate those systems. Report the exact scripts/scenes and existing APIs you will use, then make a focused implementation. Required loop: fit compatible charged battery/wheels, take control, drive to IRIS, capture a valid service-panel inspection record, return, dock, downlink, receive the fault diagnosis, show the result and allow a consistent retry. Use placeholders for missing art. Do not add other missions, a second rover, a new controller, a parallel state framework or an AI conversation backend. Validate wrong-target scans, early return, duplicate interaction, control exit and reset. Report what changed, how it was checked, and anything that could not be run.

For later tickets, replace the requested ticket and its acceptance checks. Keep each prompt bounded. Do not ask an assistant to “finish the whole game” in one pass.

## Handoff after each ticket

Provide changed paths, intended behaviour, scene/input dependencies, meaningful checks, known failures and the next required step. Use the current branch workflow. Review scene changes and imports as well as scripts. Never describe unrun checks as passed.

The release gate is an exported complete run on another machine, followed by new-player observation. Source attribution and simulation assumptions must be visible. Preserve actual asset origins and development dates in the submission record; check the event's current published rules rather than copying older rules or inventing judging weights.
