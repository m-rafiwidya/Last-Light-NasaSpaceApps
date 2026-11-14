# Last Light: team workflow

This is how the four of us build the rest of Last Light in parallel before NASA Space Apps (14 to 15 November). The engine, assets and menus are mostly done. What's missing is the mission loop: nothing yet turns M1 to M3 into something you can play and finish. Each of us gets one area, works on our own branch, and merges into `main` every day.

## Who owns what

| Person | Area | Main work |
|---|---|---|
| Fahd | Core mission flow | `CampaignState`, mission data, the full M1 loop, docking, downlink, mission console, saves, final integration |
| Rafi | Field interactions | IRIS repair and activation, radio-power module cargo, sampling, temperature readings, field logger |
| Goriorio | Rover and dialogue system | Rover fixes and tuning, part effects in physics, `DialogServer` queue, voice playback |
| Faiq | Voices, story content, playtesting | Recording Mira, Hana and Evan, the dialogue data files, testing every build |

Fahd and Rafi use Claude Code. Goriorio codes by hand, and his tasks are sized for that. Faiq's work needs no code except editing JSON files.

## Scene ownership

Godot `.tscn` files merge very badly. If two people edit the same scene on different branches, one person's work usually gets lost. So every scene has exactly one owner, and only the owner edits it.

| Scenes | Owner |
|---|---|
| Moon level, workshop, mission console | Fahd |
| IRIS station, module cradle, sample sites, logger, thermal sensor (each as its own self-contained scene) | Rafi |
| Rover (Kite) and its parts | Goriorio |
| Dialogue / radio UI | Goriorio |

Rafi builds each interaction as a separate scene that works on its own. Fahd places those scenes into the Moon level. If Rafi needs something moved or added in the level, he tells Fahd instead of editing it. If you need a change in a scene you don't own, ask the owner in the group chat.

## Branches

Everyone branches off `main` and keeps one branch per area:

| Branch | Owner |
|---|---|
| `feat/campaign-state` (first), then `feat/m1-loop` | Fahd |
| `feat/field-interactions` | Rafi |
| `feat/rover-fixes`, then `feat/dialogue` | Goriorio |
| `content/voices` | Faiq |

Merge your branch into `main` at least once a day, even if your feature isn't finished, as long as the game still launches. Before merging, pull the latest `main` into your branch and check the game still runs. Small daily merges are easy. One giant merge on Friday is not.

Before you merge, check that:

1. The game launches and reaches the Moon level.
2. The headless tests pass.
3. You didn't edit a scene you don't own.
4. Unfinished features are hidden or harmless, not crashing.
5. New scripts have their `.uid` files committed. Open the project in the Godot editor once so it creates them. If they're missing, each person's editor makes its own and they clash.

Four tests, `test_cursor`, `test_terrain`, `test_level_switch` and `test_player_body`, were already failing before this workflow started (the last three because the rack now holds 19 parts and there's a new `THERMAL` part type). Don't worry about those, but don't let any other test break.

## Rules for Claude Code

Claude Code fixes and writes code, and you handle git yourself. When you give it a task, tell it:

1. Work on one task at a time, using the existing architecture.
2. Don't create branches, commit, push or open pull requests.
3. Don't edit scenes or scripts outside your area. If it needs a change elsewhere, it should stop and say so.
4. Run the headless tests after changes.

`README_AI.md` in the repo has the longer version of these rules.

## Shared contracts (agreed on day 1)

These let everyone work at the same time. Rafi, Goriorio and Faiq build against them on day 1 without waiting for Fahd's full implementation. Fahd merges a working stub of `CampaignState` to `main` on day 1, and after that the names below don't change without telling the group.

### CampaignState (autoload singleton)

It remembers where the player is in the campaign: which mission is active, which objectives are done, what flags are set and what's in the inventory. Anything that finishes a task tells `CampaignState`, and anything that needs to react listens to its signals.

```gdscript
signal mission_started(id: String)
signal mission_completed(id: String)
signal objective_completed(id: String)
signal flag_changed(name: String, value: bool)

func start_mission(id: String) -> void
func current_mission() -> String
func complete_objective(id: String) -> void
func is_objective_done(id: String) -> bool
func set_flag(name: String, value: bool = true) -> void
func has_flag(name: String) -> bool
func add_item(id: String, count: int = 1) -> void
func remove_item(id: String, count: int = 1) -> void
func has_item(id: String) -> bool
```

The script lives at `game/src/autoloads/campaign_state.gd`. It also has `debug_dump()`, which is only for the debug console, so don't use it in gameplay code.

It also has read-only helpers for UI and dialogue:

```gdscript
func mission_title(id: String) -> String
func mission_objectives(id: String, include_optional := false) -> PackedStringArray
func objective_title(id: String) -> String
func current_objective() -> String
func is_mission_completed(id: String) -> bool
func next_mission(id: String) -> String
func mission_report(id: String) -> String
```

### Scan targets

Anything Kite can scan is a node in group `scan_target` with `@export var target_id: String`, `scan_name`, `scan_report`, `is_scanned`, `mark_scanned(rover)` and `signal scanned(rover: Robot)`. The easiest way is to extend `ScanTarget` (`src/levels/scan_target.gd`). The mission director turns scans into objectives by `target_id`, so `"iris_panel"` completes `m1.iris_scanned`. IRIS's `ServicePanel` (`src/iris/iris_service_panel.gd`) is the `iris_panel` target; Guidance glows its `highlight_node` when set, else a GuidanceBox.

### Other hooks

`ChargingPad` has `signal docked(rover: Robot)` and `is_docked()`. The `MissionDirector` node in the Moon level (group `mission_director`) emits `recovery_started` and `recovery_finished` when Kite's battery goes flat and it gets recovered, which is useful for radio lines.

For example, when the player finishes repairing IRIS, Rafi's code calls `CampaignState.complete_objective("m2.iris_activated")` and `CampaignState.set_flag("iris_online")`. It doesn't need to know what happens next.

### Testing without playing through

The debug console has four commands, so you can jump straight to the state you need:

| Command | What it does |
|---|---|
| `startmission <id>` | Starts a mission, e.g. `startmission m2` |
| `objective <id>` | Completes an objective, e.g. `objective m1.iris_scanned` |
| `flag <name> [true\|false]` | Sets a flag |
| `campaign` | Prints the whole campaign state |

### Objective IDs (final)

All IDs are lowercase with dots. Use these exact names in your code and data files.

| Mission | Objectives, in order |
|---|---|
| m1 (Wake Kite) | `m1.kite_prepared`, `m1.iris_scanned`, `m1.kite_docked`, `m1.inspection_sent` |
| m2 (First Signal) | `m2.cargo_ordered`, `m2.module_loaded`, `m2.module_installed`, `m2.iris_activated`, `m2.telemetry_received`, `m2.kite_docked`, optional `m2.near_sample_collected` |
| m3 (Beyond the Rim) | `m3.logger_recovered`, `m3.kite_docked`, `m3.archive_sent` |

A mission completes when all its required objectives are done. Optional objectives never block completion. Flags describe world state, like `iris_online`. If you need a new ID, ask Fahd in the chat so it gets added to the mission data.

### Cargo order (M2)

`m2.cargo_ordered` (console Planning tab, `CargoPlan` in `src/levels/cargo_plan.gd`, data in `res/story/cargo.json`) records the delivery in `CampaignState`: items `cargo.<item_id>` (`radio_module`, `grip_wheels`, `thermal_kit`, `sampling_kit`, `thermal_turret`), `cargo.service.<courier|freighter>` and the flag `cargo_delivered`. Workshop slots for undelivered items stay empty.

**Crate contract (Rafi):** the crate scene joins group `cargo_crate`. It fills itself from `CargoPlan.crate_parts()` (one part scene path per part, currently the radio-power module only) in `_ready` when `CargoPlan.is_delivered()`, otherwise when `CampaignState.flag_changed` reports `cargo_delivered` = true. While no `cargo_crate` node exists, the module sits on rack slot 18 (TEMPORARY `fallback_stock` in `cargo.json`). Once a crate is in the level, slot 18 stays empty, so the module appears only once.

### Mission data

Missions, their objectives and their order live in `game/res/story/missions.json`, along with each mission's `objective_titles` and end-of-mission `report`. Fahd owns this file.

### Dialogue data

The radio and log lines live in two JSON files that Faiq owns:

`game/res/story/lines.json` holds every line once:

```json
{
  "mira_m1_01": { "speaker": "Mira", "text": "Kite's battery reads green. Take her out.", "audio": "res://res/audio/voice/mira_m1_01.ogg" }
}
```

`game/res/story/dialogue_triggers.json` says when each line plays:

```json
[
  { "on": "objective:m1.iris_scanned", "line": "mira_m1_03" },
  { "on": "mission_started:m2", "line": "hana_m2_01" }
]
```

Audio files go in `game/res/audio/voice/` and are named exactly like the line ID. Goriorio's dialogue system reads both files and listens to `CampaignState` signals, so Faiq can add or change lines without touching code. A line with no audio yet shows its subtitle only.

## Schedule

| Day | Fahd | Rafi | Goriorio | Faiq |
|---|---|---|---|---|
| Mon 9 | `CampaignState` stub and mission data merged to `main` | Read the contracts, start the IRIS station scene | Esc pauses instead of exiting, motor sizing | Draft `lines.json` from the story script |
| Tue 10 | M1 loop: fit parts, drive, scan IRIS | IRIS repair and module cargo | Gravity tuning, part masses and heater in physics | Record M1 lines |
| Wed 11 | M1 loop: dock, downlink, report, retry. **M1 playable** | Sampling and temperature readings | `DialogServer` queue and voice playback | Record M2 and M3 lines, playtest M1 |
| Thu 12 | Place Rafi's scenes, wire M2, M3 cut to logger recovery | Field logger, fixes from playtest | Hook dialogue triggers to `CampaignState` | Playtest M2, write the source attribution screen text |
| Fri 13 | Saves, exported build | Bug fixes | Bug fixes | Outside playtest with at least 3 people, report where they get stuck |

Each person has about 4 hours a day. If a day's task finishes early, help the person who's behind instead of starting something new.

## What we cut if we run late

We protect M1 and M2 fully playable, M3 as logger recovery, the ending, an exported build and the attribution screen. We cut, in this order:

1. Cargo flight / delivery sequence
2. Optional samples and temperature readings
3. Thermal damage and heater effects
4. Visual polish and extra effects

## Daily check-in

Every evening, post three lines in the group chat: what you merged today, what you're doing tomorrow, and anything blocking you. If you're blocked on someone else's part, say so the same day.
