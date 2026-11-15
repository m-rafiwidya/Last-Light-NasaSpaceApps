# LAST LIGHT — complete playtest handoff for Rafi and Fahd

**Tandborste · revised to preserve Rafi's intent and light player guidance**

This document keeps Rafi's original notes verbatim, translates them into clear implementation requests, retains useful research/suggestions, and assigns the work to **two people: Rafi and Fahd**. It is a developer handoff, not a list of instructions to show players.

The Godot repository has not been supplied to the writer. Reported existing behaviour comes from Rafi's playtesting; Claude must inspect the actual project and verify it. Existing planning text is not proof of implementation.

## 1. Player experience and requirement priority

**Preserve the experimentation Rafi enjoyed.** The player should understand the basic controls and their overall task, then discover useful configurations and routes by trying things. Do not convert the workshop into a compulsory step-by-step lesson.

Priority when interpreting this brief:

1. Rafi's latest explicit decisions: astronaut rescue now, existing rover pickup reused, oxygen resource, one save/load system, and minimal hand-holding.
2. Clear outcomes from playtesting: readable sample site, recoverable failures, persistent progress and an understandable assembly interaction.
3. Suggested implementations and researched design lessons. Adapt these to the current project; they are not all mandatory new features.

Required: sample visibility fix; human rescue using existing pickup; oxygen HUD/consumption/refill/failure; manual and auto saving/loading; light control guidance; story continuity; verification.

Suggested/tunable: oxygen duration and margin, warning thresholds, save interval, part-comparison presentation, carry speed and chapter timing. Measure these in the actual build.

Optional: a small practice ramp/loop if useful and easy to reuse. Do not require completing it. No automatic timed hints, prescribed winning loadout, forced assembly order, compulsory test drive or new multi-stage tutorial.

Technical consistency checks below—such as saving cargo once—belong in implementation/testing. They do not imply additional player-facing popups, checklists or dialogue.

## 2. Two-person work split

| Ticket | Owner | Task | Done when |
|---|---|---|---|
| F1 | Fahd | Move/readably mark the M2 ordinary sample target and update its linked interaction/coordinates | Target is visible and usable from the normal rover approach |
| F2 | Fahd | Allow human exit and rover rescue through existing pickup/carry/drop | Stranded Kite can be returned through the service route with cargo intact |
| F3 | Fahd | Implement suit oxygen, HUD/warnings, habitat refill and exhaustion state | Oxygen behaves correctly outside/inside, during pause and across control changes |
| F4 | Fahd | Enforce actor/tool permissions and physical rescue reliability | Walking humans/carried rovers cannot complete rover missions; pickup/drop does not duplicate or lose anything |
| R1 | Rafi | Audit/reuse save code; implement consistent campaign/world persistence | Stock, parts, charge, mission records, human/rover pose and oxygen round-trip correctly |
| R2 | Rafi | Manual/auto saving, Continue/Load menus, safe base save and save feedback | Quit/reopen and failure recovery work, with accurate visible save status |
| R3 | Rafi | Minimal onboarding copy/help and the stored-rover story explanation | Basic controls are discoverable without prescribed assembly/loadout/route steps |
| R4 | Rafi | Run pacing/new-player tests and prepare the presentation path | Real timings, confusing moments and remaining issues are recorded |
| J1 | Both; Rafi coordinates | Merge, export and verify complete play/rescue/save interactions | A complete exported run and quit/relaunch/rescue checks pass on a second machine |

This split is a recommendation based on the team's current work: Fahd handles the physical world/rescue; Rafi handles persistence, UI flow and player experience. Each can use Claude on their own assigned tickets.

### Avoid conflicting edits

- Start from the same working commit and keep a working export before editing.
- Each person/Claude session owns their assigned changes. Use separate branches or isolated working copies; do not run two agents editing the same checkout.
- **Fahd owns the level scene, human movement/EVA, oxygen state/HUD, carry handling and rover-only interaction guards.**
- **Rafi owns the save/load service, pause/main-menu save UI, onboarding/story text and playtest record.**
- Identify actual shared scene/input/HUD files before edits. If both need a shared file, one owner applies the small integration change sequentially. Avoid independently re-saving the same root scene.
- Preserve the current rover driving controller. Change it only for a reproduced rescue/control bug, and coordinate with its existing author rather than rewriting it.

### Small integration contract

Before changing shared state, inspect the actual APIs and agree on the field names and restore order. No new parallel game-state manager is required.

Fahd supplies the save system with: human pose, remaining/max oxygen, EVA/zone state, rover pose, carry relationship if supported, and stable IDs for carried cargo/parts. Fahd owns restoring these into the live human/rover systems.

Rafi supplies: a save-request/load interface, save availability/status, valid slot information and consistent persistence of the rest of the campaign. Rafi routes oxygen exhaustion through the same Load Game UI. Use existing signals/methods where possible; this paragraph describes responsibilities, not prescribed API names.

Both check that loading cannot refill oxygen outside, duplicate a held rover, lose logger cargo, or turn locally collected data into Earth-received data.

### Start in parallel

**Fahd starts F1:** fix the sampling target, then proceed to F2/F3 using the existing pickup system.

**Rafi starts R1:** audit and exercise current saving in an exported build, then add the missing persistence/menu behaviour. Coordinate with Fahd early for oxygen/carry state. Continue R3 copy work without changing Fahd's player/HUD files concurrently.

After those changes integrate, both run the same battery-depletion/rescue/quit/reload scenario. A local ticket passing alone does not verify the integration.

### Prompt for Rafi's Claude session

> You are implementing Rafi's tickets R1–R4 from this handoff. Inspect existing project instructions, state, saves and menus. Start with R1 and complete a bounded, verified improvement. Own save/load, menu flow, light onboarding/story copy and playtest reporting. Reuse the current architecture. Coordinate with Fahd's oxygen/carry fields before integrating them; do not independently edit his movement, rescue, level or oxygen-HUD files. Keep player guidance minimal and optional. Report actual changes/checks and concrete blockers. Do not stop at a general plan.

### Prompt for Fahd's Claude session

> You are implementing Fahd's tickets F1–F4 from this handoff. Inspect existing project instructions, target placement, human movement, rover pickup/carry and mission interactions. Start with F1, then extend the existing pickup for astronaut rescue with a configurable oxygen resource. Own world placement, rescue/oxygen/HUD, carry reliability and actor/tool guards. Expose coherent save/restore state to Rafi's save system; do not create a separate save manager or rewrite rover driving. Keep player guidance minimal. Report actual changes/checks and concrete blockers. Do not stop at a general plan.

## 3. Decisions to work toward

| Area | Decision |
|---|---|
| M2 sample target | Move the ordinary reference sample to a readable nearby location; retain any deliberately shaded temperature target |
| Stranded rover | Human EVA rescue using the existing rover pickup/carry system |
| Human exploration | Allow oxygen-limited outdoor rescue; keep mission tool actions rover-only |
| Persistence | One save/load system for autosave, manual save, Continue and failure recovery |
| Assembly | Keep grab/fit/remove controls legible; optional help, free loadout choice and no compulsory tutorial sequence |
| Story | Kite is a tested modular rover stored at the outpost. The engineer commissions and configures it for field use |
| Duration | Target 20–30 minutes for a first successful Moon chapter, with a much shorter presentation route |
| Delivery | Audit first, then implement one bounded change at a time; preserve the current rover controller |

Revision: Rafi confirms that rover pickup is already implemented and requests astronaut rescue now. This brief supersedes earlier workshop-only/retry-framework recommendations for recovery. Preserve the three-mission story and reuse the existing save/load and carry systems.

## 4. M2 sample visibility — observed issue

**Observation:** The M2 surface-sample patch is covered by shadow and is difficult to recognise.

**Requested outcome:** A first-time player can identify the intended sample site from the ordinary rover approach and understand when they are close enough to sample.

Recommended implementation:

- Reposition this authored reference target to nearby readable ground. Preserve its relationship to IRIS and its near-site identity.
- Move the visible prop/decal, interaction area, waypoint, objective reference and recorded coordinates together. Keep its stable target ID consistent.
- Check it through the actual rover camera and exposure, not only the editor view. Use a restrained marker or on-aim outline where useful; do not depend on colour alone.
- Keep genuine shadowed temperature targets: darkness can be meaningful science context. If such a target is intentionally shaded, use the current rover light or a readable instrument marker rather than relocating it into sunlight.
- Preserve NASA-derived elevation scale and source imagery. Relocating fictional equipment is different from changing measured terrain or relighting an orthophoto's baked shadow.

**Acceptance:** A new player finds the M2 sample without verbal directions; the interaction succeeds at its displayed location; the recorded metadata follows the new position; the paired temperature task still has its intended contexts. Check save compatibility if old saves refer to the moved location.

## 5. Astronaut rescue and oxygen — implement in this build

**Updated team decision:** Astronaut rescue is part of this release. Rafi confirms that picking up the rover already works. Extend that interaction; do not build another carry controller or defer the feature simply because the earlier plan restricted human exploration.

### Main recovery loop

1. Kite runs out of usable battery away from home. Powered tools/drive stop; the rover remains where it is, with cargo, samples and observations intact.
2. Show: **“Kite is out of power. Return to the workshop console, then go outside to recover it.”** Switching from rover control returns to the operator's actual location, normally the workshop; it does not teleport Kite.
3. The human exits through the existing service/airlock route with a full suit oxygen supply. The HUD shows oxygen percentage and approximate remaining time.
4. Walk to Kite, use the existing pickup interaction, and carry it back to the marked service bay. Carrying is slower than ordinary walking; use the existing carry parameters where possible.
5. Put Kite down on the pad. Service/charging uses the current system. Preserve completed world interactions and collected records. Resume the expedition after reconfiguration/recharge.

Physical rescue is a recovery task. It does not automatically complete the expedition, downlink onboard records or award new science. A dropped rover remains the same unique object; no fresh duplicate is spawned.

### Oxygen model and tuning

Use a configurable gameplay-duration model, explicitly a simplified suit resource rather than a physiological simulation. Oxygen drains while the human is outside a registered pressurised zone; it replenishes only at the home habitat's service point/inside its pressurised area. IRIS is uncrewed equipment and does not refill suit oxygen.

Display **O2 100%** and an approximate remaining-time indicator in human EVA view. Add clear, rate-limited low/critical warnings using text plus sound/visuals, not colour alone. A warning should tell the player to head home and show the base direction.

Tune duration from measured travel, not an arbitrary short countdown:

**Oxygen duration >= outbound walk + pickup/alignment time + loaded return + airlock entry + safety margin.**

Measure intended rescue routes, including the farthest mission area. Use the actual slower carry speed, slopes and detours. Start with a roughly 25–30% margin over the measured rescue time, then tune in playtests. This is a design starting point, not an empirical safety standard. If existing distances make rescue take too long, tune oxygen/carry movement coherently rather than making far-site failures impossible to recover.

Use the same paused simulation clock as other gameplay resources. Pause/menu/loading must not silently consume oxygen. Saving and loading must preserve remaining oxygen; switching cameras or control mode must not refill it. If control can be taken remotely while the human remains outside, oxygen continues draining in active gameplay; preferably use the existing workshop console as the normal control entry point.

### Oxygen exhaustion

At zero oxygen, stop normal movement/interactions, pause the failure state, and offer **Load Game**, including the latest safe base save, or the main menu. Use the ordinary save/load system. Do not add a separate expedition-retry snapshot manager.

If the latest field save is already a doomed EVA state, the earlier safe base autosave must remain selectable. Never replace the sole recoverable save with the oxygen-exhaustion screen. Loading restores the whole selected snapshot consistently; it may roll back work done since that save. State that consequence clearly.

Do not automatically teleport the rover home on oxygen failure. A future assisted-recovery mode can be designed separately; it is not needed to implement this request.

### Prevent on-foot mission bypasses

A timer alone does not prevent the human from completing nearby rover objectives. Enforce actor/tool requirements in mission interaction code:

- Humans may pick up/recover Kite and use habitat/service interactions.
- Inspection, station repair, mission sampling, sensor measurements and logger collection require the appropriate installed rover tool and a valid rover interaction state.
- A carried rover cannot execute mission tools or count as a controlled, stable deployed rover.
- Outside the workshop, recovery pickup should apply to a parked, disabled or genuinely stuck rover. Preserve normal workshop pickup for assembly/service.
- Carrying a rover must suspend its drive input and use the existing collision/carry handling. Check self-collision, doorway clearance and safe placement.
- A failed pickup/drop must not remove the vehicle, duplicate it, eject its mounted parts or detach its cargo incorrectly.
- Human EVA uses a clear map boundary and visible base marker. Opening the former workshop boundary must not expose unfinished terrain or allow falls off the map.

The carrying interaction is an authored gameplay abstraction; do not present it as validated astronaut lifting performance. Reuse the project's actual rover scale and handling rather than inventing a new vehicle.

### Power warnings still matter

Keep charge warnings and a feasible baseline M1 round trip. Explain measured causes of power use where available. If a return estimator is absent, display a simple reserve warning rather than a false precise guarantee. Existing solar charging can remain a situational option, but a long wait must not be the only recovery route.

**Acceptance:** Deplete power near IRIS and at the far mission site; walk out, pick up Kite, carry it through the service route, drop it on the pad, recharge and continue. Repeat with samples/logger onboard and after IRIS restoration. Verify cargo/mission state, carry collision, no on-foot mission completion, pause behaviour, low-oxygen warnings and a recoverable oxygen-exhaustion outcome.

## 6. One save/load system for persistence and failure recovery

**Current implementation status is unknown.** Inspect existing save/load code and reuse it. Rafi's decision is to avoid a separate pre-departure retry framework. Use the same serialisation and load APIs for Continue, manual loading and failure recovery.

The target includes **manual saves, autosaves and stable mid-expedition resume**, including astronaut rescue state. Implement and verify these incrementally in this build rather than treating them as a later-release feature.

### Save slots and menu behaviour

| Save type | Purpose |
|---|---|
| Resume autosave | Latest coherent current-run state, including field/EVA progress |
| Safe base autosave | Most recent coherent human-in-habitat, rover-in-service-bay state; remains available during a stranded-rover/EVA attempt |
| Manual save | Explicit player-selected snapshot; autosave does not overwrite it |

These are ordinary slots handled by one existing save service, not parallel state managers. Retain a valid previous-file backup during disk writes for corruption recovery. One campaign and one manual slot are enough for now.

Autosave after committed mission results, successful service/recharge, valid preparation in the bay, and coherent important field actions such as repair/sample/logger collection. Capture a safe base save before a rescue leaves the habitat when the whole world is actually in a suitable base state. If the rover is already stranded outside, keep the earlier valid base save; do not relabel the stranded world as safe simply because the human is indoors.

Coalesce related events and save after the operation has settled. A configurable periodic autosave, initially around 60 seconds, can wait for a stable save window. Do not write every frame or partway through a pickup/drop transaction.

**Pause menu:** Resume, Save Game, Load Game, Settings, Quit to Main Menu. Main menu: Continue, New Game, Load Game, Settings, Quit. No separate Retry Expedition button is required; use Load Game to choose the relevant saved state. Reuse the actual menu structure.

- Show whether saving is available. During a part installation, rover pickup/drop or unsafe airborne pose, explain: **“Finish this interaction and stand/park safely before saving.”**
- Save a carried rover only if the current system reliably serialises the attachment relationship. Otherwise require placing it safely first; clearly disable Save during carrying rather than pretending the load will restore it correctly.
- Display **“Saving…”**, then **“Saved”** briefly only after a successful write. On failure show a readable message and keep the last valid save.
- Loading asks before discarding unsaved progress. Continue selects the newest valid normal resume/manual save. Load Game also exposes the labelled safe base save for failures.
- On quit, offer Save & Quit when available, Quit Without Saving, and Cancel. If saving is unavailable, show the last save point and let the player return to the game.
- Confirm before New Game overwrites existing campaign progress.
- A field autosave with an empty battery or low oxygen must not overwrite the safe base slot.

### State to persist and restore

Include campaign/mission stage; stable IDs for installed parts and unique stock; charge/capacity; cargo/containers; sample and report records; collected/queued/received data; IRIS/logger state; work orders; credits/delivery ledger if used; objectives; story/tutorial flags; relevant route/thermal state; human and rover transforms; suit oxygen and EVA/pressurised-zone state; and carry attachment state if supported.

Restore a coherent world using current mission/part APIs. Grounded rover loads should initialise suspension safely, with zero transient velocity/brakes as appropriate. Restore the human's saved safe location; do not move an outside human indoors or refill oxygen merely because loading occurred. Normal loading must not teleport Kite to the base.

If a held-object snapshot cannot be supported safely, use the explicit save restriction above. Do not silently drop/delete a carried rover on load or spawn it both on the pad and in the player's hands. Recompute zone/carry validity after loading before unpausing resource drain.

Loose uninstalled stock can return to labelled shelves if that is the project's documented inventory convention, preserving quantity and per-item charge. Mission cargo must not duplicate onto the rack. Use stable item IDs rather than arbitrary node paths.

Keep one authoritative state implementation and the actual Godot version. Use GDScript, a small explicit schema under user://, schema/content versions, validated IDs/types, temporary writes and safe replacement/backup handling. Avoid partially applying corrupt or incompatible files. Keep runtime values separate from shared part definitions.

Godot's saving example is a starting reference; mounted parts, oxygen, carrying and mission relationships require adaptation to the current project.

**Acceptance:** Save, close and reopen the export at M1 completion, after IRIS restoration, with logger cargo, and during an EVA while standing safely with reduced oxygen. Verify location, oxygen, stock, parts and records. Load twice to check duplicates. Verify unsupported carrying saves are clearly blocked, or supported carrying saves restore exactly once. Test corrupt-save fallback and oxygen exhaustion with a usable earlier base save.

## 7. Assembly introduction and story integration

### Canonical explanation

The player arrives at a prepared lunar outpost. **Kite is a modular, tested rover stored in its service bay.** Its battery is isolated and replaceable modules are stowed for storage/maintenance. The engineer installs a serviced battery and chooses equipment for the current job. A local test drive is available without being a compulsory tutorial step.

The chassis, control electronics and basic engineering were already designed and tested by the programme. The first-person interaction is field commissioning and configuration. This fits the existing 2058 fiction without requiring NASA to have sent an untested pile of parts or explaining that future technology is somehow worse.

Suggested short Mira line:

> “Kite was stored with its battery isolated. The frame is checked; choose the field kit for this inspection.”

Do not replace the current opening with a long arrival cinematic, new lander scene, another rover or a fabrication tree. Inspect current narrative names before changing dialogue IDs.

### Minimal onboarding — preserve discovery

**Opening goal:** “Prepare Kite for the IRIS inspection.”

Keep the current workshop, rover and available parts. Put short control labels where the player actually interacts: grab, rotate if needed, attach, detach and take control. Reuse existing prompts rather than building a new tutorial system.

Give brief part information and clear feedback when an action fails. The player chooses parts, assembly order and route. Accept all functional configurations; do not require the designer's preferred battery/wheels or a scripted sequence.

**No mandatory tutorial steps, compulsory checkout loop, automatic hints after a timer, or prompts recommending the correct solution.** Help is available when the player requests it. A practice ramp can be used freely if it already exists or is a small useful addition; it is not a departure gate.

A missing essential component can be explained when the player tries to operate it, using the existing interaction/readiness behaviour. Avoid a new persistent tutorial checklist or a sequence of approval screens. Battery, oxygen and save feedback remain readable; they describe state/consequences rather than solving the mission.

For later sampling/thermal equipment, show the item's basic purpose, controls and compatibility at the relevant interaction or in optional help. Let the player discover how it affects a mission. Do not hide the sampling key or required tool identity as a puzzle. Retain existing manual arm control; any required precision assistance should be simple and forgiving.

**Acceptance:** A new player understands how to attach/remove a part without verbal coaching, can experiment in another order, and can explain one observed equipment trade-off. No tutorial sequence blocks a valid build, test drive or mission start. Optional help can be opened/reviewed. Save/reload preserves relevant introduction flags without replaying unwanted guidance.

## 8. Duration and player enjoyment

Target a **20–30 minute first successful Moon chapter**, around 30–40 with experiments and a rescue. Measure it on the export. Do not stretch the game to meet a number.

| Segment | Initial target, including that segment's preparation |
|---|---|
| Workshop arrival, free assembly and optional practice | 3–4 minutes |
| M1 inspection and report | 4–6 minutes |
| M2 loaded repair and report | 5–7 minutes |
| M3 logger/science and return | 6–9 minutes |
| Final report/ending | 2–3 minutes |

These ranges sum to about 20–29 minutes before optional exploration or rescue attempts. They are proposed pacing budgets, not measured playtest results. Keep the separate judge demonstration around the team's planned 5–7 minutes, using an honest prepared save/recording clearly identified as such.

If returns feel repetitive, reduce empty travel, place readable landmarks, show load/handling changes and give arrival/docking/report feedback. Reconfigure around a changed job on familiar terrain. Avoid a long forced charging wait, slow scoop grind, an oxygen budget too short for the intended rescue, full-campaign failure or repeated unskippable radio text.

Replay should test a hypothesis: can I take the gentler route with a smaller battery, or carry the repair cargo through the short approach? Compare time, energy and delivered work under the same contract. A larger part should have a real cost. Ensure more than one advertised strategy can succeed.

## 9. Researched examples and what we borrow

These are design lessons drawn from developer accounts, not claims that our game already implements their systems.

- **Outer Wilds — Mobius Digital, “Filling Out the Toolbox!” (2016).** The team described moving away from a forced action sequence toward optional practice and clearer tool controls. Borrow a safe workshop practice space and control prompts while leaving the player to choose their approach. Our explicit engineering missions still need clear objectives. [Developer source](https://www.mobiusdigitalgames.com/news/filling-out-the-toolbox).
- **Factorio — Friday Facts #361 (2020).** The developers described searchable/reviewable tips, context-dependent recommendations and using item tooltips for item-specific information. Borrow a small help panel and show sampler guidance when relevant. Do not build their entire tutorial framework. [Developer source](https://www.factorio.com/blog/post/fff-361).
- **Astroneer — Mid-Year Dev Update (2026).** The studio reported requests for more flexible, regular saving and described planned periodic/event-triggered autosaves and history. Borrow the lesson that players need understandable persistence beyond entering a base. The article describes planned work, not proof that every listed feature is currently shipped. [Developer source](https://blog.astroneer.space/system-era/mid-year-2026/).
- **Godot — Saving Games.** Official guidance identifies persistent state and demonstrates serialisation while warning that loading relationships is project-specific. Use it as technical reference alongside the existing repository architecture. [Official documentation](https://docs.godotengine.org/en/stable/tutorials/io/saving_games.html).

## 10. Extra issues worth checking during this pass

- **Departure clarity:** keep the overall task and relevant tool/charge information easy to find; use the existing console or optional details instead of adding a compulsory checklist.
- **Sampling reason:** when sampling fails, explain missing tool/container, excessive motion or invalid target rather than doing nothing.
- **Ground/camera readability:** test slopes and targets at actual camera height; keep directional light/shadow but make interaction legible.
- **Charge meaning:** show current charge and capacity consistently; a bigger depleted pack is not automatically ready.
- **Control ownership:** UI, pause, loading and operator/rover switching must always leave one gameplay input owner.
- **Observed outcomes:** expose a short report explaining actual energy use and received data; keep planned or unmeasured physics claims out of it.

## 11. Claude work order

### First response and first implementation

Read repository instructions and the actual project. Report a concise status table for recovery, saves, assembly hints and sample targets: implemented and verified, implemented but unverified, partial, missing, or blocked. Include exact relevant script/scene paths and existing API names. Do not invent files or infer runtime behaviour from README prose.

Then implement your assigned first ticket: Fahd starts F1 (sample visibility), while Rafi starts R1 (save audit and a bounded persistence improvement). Move all target dependencies together during F1; exercise real disk persistence during R1. Reuse current systems and preserve the working controller. Do not edit the other owner's shared files concurrently.

### Integration order across the two owners

1. **Fahd — astronaut rescue:** inspect/reuse rover pickup; open the service route; implement suit oxygen, HUD/warnings, carry return and mission actor restrictions.
2. **Rafi — unified persistence:** inspect/reuse the existing save service; add manual/autosave/Continue and a safe base slot with correct feedback.
3. **Both; Rafi owns saves — field/EVA saving:** persist world state, reduced suit oxygen and valid human/rover positions; support or clearly block carried snapshots; test failure recovery through Load Game.
4. **Rafi — assembly commissioning:** minimal control labels and optional help/practice, using current parts/props and story; no forced sequence or automatic timed hints.
5. **Both; Rafi coordinates — pacing/accessibility:** address observed issues, then export and run the complete chapter.

Implement all requested features in bounded, verified increments. Preserve a stable branch/export, coordinate shared-system edits with their owner, and report concrete blockers instead of silently dropping astronaut rescue or field saving. Reuse working code and verify each merge before the presentation.

For every ticket, report changed paths, what was observed in the build, checks actually run, remaining limitations and the next dependency. Implement and verify accepted scoped work rather than stopping at a general plan. Do not apply all tickets in one unreviewable pass.

### Focused test session

Use at least three new players where possible. Watch without coaching. Record time to first installed part, avoidable failed interactions, objective confusion, complete round-trip time, reserve warnings, rescue/oxygen behaviour, quit/relaunch success and whether players voluntarily try another setup. Ask what changed when they swapped a part. Prioritise confusion and broken state before additional art or mechanics.

**Release check:** complete one exported chapter on another machine, quit/relaunch through supported save points, deplete/rescue at least once and verify an oxygen-failure load, and confirm that completing IRIS alone does not skip the required final logger/science receipt and docked-rover ending.

## 12. Rafi's original notes — preserved verbatim

These are source notes, including questions and alternatives. They preserve Rafi's words and intent. **The later explicit decisions and task split above govern implementation**: the two original rescue options are not two separate features Claude must build.

### Original playtest message

> the sampling patch surface sample in M2 is covered by the shadow. move somewhere else so its more clear
>
> if battery goes out, and the rover is still away from our station, how do we do or save it. im thinking two possibilites.
>
> 1. the player can actually go out the border of the station and walk themselves outside. but im not sure if theres any thing like gamebreaking, if the player themselves can clear any mission without using rover or anything. or if they go past beyond border, but we can put a timer on the player. we will prolly playtest again for how long the timer will go
>
> 2. there is a failsafe and the rover maybe just restart from the start again. but is there already a feature like that? and yea we gotta think about the overall playtime right. how long would be best to play? 30 mins? or anything
>
> and how about saving system. does it save anything while we playing. for example if the player wanna quit the game halfway, when does it save. i think we should notify on the corner text or something like other game, that the game is saved. on the ingame pause menu while were playing, i think we should add save and load button. so we can save manual and auto, and yeah.
>
> tutorial on doing the parts. i think ive told you before i wanted to like when we just arrived to moon, were gonna build the rover from us. it can serve as a tutorial on the engineering part, where the player will know where to put and how to build it. and they can experiment with the items. what item will actually reach to the first M1 mission/to their destination, and it can be fun too right. but my lil bit concern is how does it integrate to the story. like logically its the year 2058. and when we got sent to moon, how come the space company that sent us, maybe NASA, dont give like a fully built rover. rather we built there ourselves? and hmm what is the best decision. and yea i like that theres no much guidelines and when were playtesting it we actually gotta think and find out ourselves where we put or something. so its just not like a instruction game the player actually has to figure out themselves. but thats also another concern will adding tutorial in the start make the player more used to it? well tbf theres other part thats needed for future mission like thermal or sample and they will have to figure out themselves how to take it right. im also open to any suggestions. please research from other game too and take actual good examples and good everyhting. make the best.

### Rescue clarification

> for pre departure retry checkpoint its the same thing as a save file so theres no point. and why save for later build, we can still have time. so please still add the astronaut rescue, we already have the picking up the rover system. just add timer for how long the guy can be outside, noted with the oxygen level.

### Concern about too much guidance

> wait u kinda write alot will it like im worried like did u make it too much guidelines n stuff one of my previous concern is if theres too much guideline right like

### Request for this combined handoff and task split

> okay can u make everything of that in include veeryhting like please js preserve my words too and how i like mean by everything. but also yea i appreciate ur suggestions and research. and also please divide these task for me and Fahd. so for two people. make compelete md

### Meaning to preserve

Rafi wants the player to experiment and figure things out, with enough control information to act intentionally. He wants real recovery through an oxygen-limited astronaut outing, reliable manual/auto saving, readable science targets, a believable reason to configure Kite, and enjoyable pacing. The development brief may contain detailed correctness checks; the player should encounter a simple, responsive game rather than a long instruction checklist.
