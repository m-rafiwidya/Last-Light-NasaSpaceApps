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

For example, when the player finishes repairing IRIS, Rafi's code calls `CampaignState.complete_objective("m2.iris_repaired")` and `CampaignState.set_flag("iris_online")`. It doesn't need to know what happens next.

### Naming IDs

All IDs are lowercase with dots: `mission.thing`. For example `m1.iris_scanned`, `m1.kite_docked`, `m2.module_installed`, `m3.logger_recovered`. Flags describe world state: `iris_online`, `sample_near_taken`. Fahd keeps the full list in the mission data file. If you need a new ID, add it there and mention it in the chat.

### Mission data

Missions, their objectives and their order live in one JSON file, starting from `game/docs/examples/MISSIONS.json`. Fahd owns this file.

### Dialogue data

The radio and log lines live in two JSON files that Faiq owns:

`res/story/lines.json` holds every line once:

```json
{
  "mira_m1_01": { "speaker": "Mira", "text": "Kite's battery reads green. Take her out.", "audio": "res://audio/voice/mira_m1_01.ogg" }
}
```

`res/story/dialogue_triggers.json` says when each line plays:

```json
[
  { "on": "objective:m1.iris_scanned", "line": "mira_m1_03" },
  { "on": "mission_started:m2", "line": "hana_m2_01" }
]
```

Audio files are named exactly like the line ID. Goriorio's dialogue system reads both files and listens to `CampaignState` signals, so Faiq can add or change lines without touching code. A line with no audio yet shows its subtitle only.

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
