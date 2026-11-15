# Last Light: plan to the build (Wed 11 Nov to Fri 13 Nov 2026)

Read this first, then `CLAUDE.md`, `workflow.md`, `planning_handoff.md` and `game/README.md`. This file is the team's agreed plan after the playtest. If it conflicts with older planning docs, this file wins until the build is exported.

## 1. Goal

Make the existing game feel like a real mission: choices have physical consequences, the route is visibly risky, repairs pay off, and the report explains why a run went the way it did. **We add tension and replay reasons, not new content.**

Hard dates: exported build due **Fri 13 Nov**. Hackathon 14 to 15 Nov. Judging starts 16 Nov. The 2026 Project Submission Guide and Judging and Awards Guide are reported to be released on 13 Nov: read both Friday morning. Criteria from 2025 (2026 unconfirmed): Impact, Creativity, Validity, Relevance, Presentation.

## 2. Scope freeze (do not build these)

Station 2, Mars, multiplayer, playable crew roles, plants, a second rover, random events, difficulty modes. They go on the "what's next" slide only.

## 3. The loop we are making work

Plan (lander, manifest, route) -> Load Kite (mass matters) -> Drive (landmarks, cold zone, reserve) -> Do science (sample, temperature) -> Return with reserve -> Report (with why) -> Replay with a better plan.

Why these changes (research, general design lessons, not hard rules):
- Kerbal Space Program: failure is informative, so the report must say why.
- Subnautica: nested loops, so each mission shows the next goal.
- FTL: a few meaningful choices per run, so lander and route choices, plus a comparison to the last run.
- Mars First Logistics: the weight you load changes how the vehicle drives.
- A failed FTL/Subnautica hybrid died of a broken core loop, so finish M2 and M3 before anything else.

## 4. Work items, owners, acceptance

Owners edit only their own files (see `workflow.md`). If you need a change in someone else's file, ask them in the group chat and give the exact change.

| # | Item | Owner | Done when |
|---|---|---|---|
| A | Merge Rafi's 3 PRs in order: `feat/field-interactions`, `feat/cargo-crate`, `feat/field-logger`. Place them in the level. | Rafi merges, Fahd places | M2 and M3 can be completed start to finish with **no debug commands** |
| B | **Mass affects driving.** Loaded part mass changes Kite's acceleration/top speed and energy use. | Former teammate (fallback Fahd) | A test shows a loaded Kite is slower and uses more Wh than an empty one on the same drive |
| C | **Two landmarks** on the short route: one big crater to route around, one boulder field with rocks up to 3 m. The long route stays gentler. | Fahd | The short route is visibly rougher; the long route avoids both |
| D | **Temperature pair in M3**: one ground reading in sun, one in shade (reuse `cold_zone.gd`). Far sample is a stretch goal. Near sample stays optional. | Rafi | M3 can require the pair, and the guidance placeholders have real targets (Rafi tells Fahd the targets; Fahd edits `missions.json`) |
| E | **Payoff moments**: IRIS lights turn on, the antenna moves modestly, the first packet arrives at the console. | Rafi | Installing the module visibly and audibly brings IRIS online |
| F | **Sectioned mission report**: objectives, science, rover, resources, assistance. A "why" line per section (for example, "short route crossed shade: heater used X Wh"). A comparison line against the last run. No single opaque score. | Fahd | The Downlink report shows all sections after each mission, with numbers read from game state |
| G | **Crew requests**: Hana and Mira each ask for one thing per mission. The report ends with "request met or missed". Text only. | Faiq writes, Fahd wires | Each mission shows one request, and the report reflects the real state |
| H | **Opening scene**: a 30 to 45 second skippable card (year, crew, Kite on the pad, Mira's first line). | Fahd | New game shows it once, with a skip |
| I | **Dialogue queue** (minimal): plays line by ID from `lines.json` and `dialogue_triggers.json`, shows the subtitle, plays an optional audio file, one voice at a time, with a skip key and a repeat cooldown. | Former teammate (fallback Fahd) | A trigger plays a subtitle, and audio when `res/audio/voice/<id>.ogg` exists |
| J | **Voice lines**: 12 to 15 key lines only (opening, IRIS restore, logger find, ending, Evan's notes). Radio filter on all. Subtitles always on. | Faiq with the team | Files named by line ID are dropped in and play with no code change |
| K | **Evan's notes** as props: workshop note, IRIS final field check (after M2), logger audio with the "second label underneath" hint. | Faiq text, Rafi props | Each is readable or audible and skippable |
| L | **Data sources screen** at the end of the game, reading a JSON file so it can be filled in on 14 Nov without code changes. | Fahd | Shows LROC Apollo 12 DTM (2 m), SLDEM and a placeholder list |
| M | **Audio pass**: engine, regolith crunch, radio static, ambient hum. | Anyone free | Each plays in the level |
| N | **Export and presenter.** | Fahd exports; the group names the presenter | The build runs from a clean export |

**Voice rules:** Mira and Hana are recorded by team members. Evan can be a lower, rougher team voice or a stock ElevenLabs voice. Do not clone a team member's voice without their agreement. Say in the submission that some voices may be AI-generated.

## 5. Schedule

- **Wed 11:** item A. The former teammate confirms today whether they can do B and I (nothing pushed since 9 Oct). If not, Fahd takes them and C moves to Thursday.
- **Thu 12:** B, C, D, E, F, G, H, I in that rough order. **Thu night: one timed full playthrough, then feature freeze.** Note the real playthrough length.
- **Fri 13:** export, bug fixes only, read the two new guides, name the presenter. Voice and audio files may still be dropped in because they need no code.
- **14 to 15 Nov:** check the challenge Resources tab for data, fill the data-sources file, record the demo video, submit.

**Cut order if late:** cargo flight sequence, far sample, ridge, polish, voice, optional challenge. **Never cut:** M2 and M3 playable with no debug commands.

## 6. Demo

- Judge run of 8 to 10 minutes, starting from a save slot just before M3. Park one save before each mission.
- Presenter named by Thursday night.
- Show: the route choice, the weight difference, IRIS coming online, the report's "why" lines, the data sources screen.
- Say plainly: single-player; the four of us map to the mission-control roles in the story; multiplayer is next.

## 7. Rules for every AI session

1. Read the relevant code first. Reuse the existing systems (`cold_zone.gd`, `cargo_plan.gd`, `mission_director.gd`, `campaign_state.gd`). Follow Godot 4.7 and GDScript conventions in `game/README.md`.
2. Touch only the files you own. Do not edit another person's files.
3. Make small changes, one work item per branch and PR. Do not refactor.
4. Run only the headless tests related to your change (see `CLAUDE.md`). Say which test you ran and its result. Do not claim something works without running it.
5. New IDs in `missions.json` or the dialogue files: tell the group.
6. Keep the final report short: what changed, test result, anything needing a decision. (`CLAUDE.md` asks for under 10 lines and no screenshots unless asked. The team may relax this if token budget is no concern, but the report should still be short.)
7. Do not invent NASA facts or numbers. Real data is the Apollo 12 LROC DTM and SLDEM; story equipment is fiction and must be labelled so.

## 8. Prompts to paste (one per person)

Start each in **plan mode** for items B and I (new systems), then switch to normal editing once the plan is agreed. Items that only place scenes or edit text can skip plan mode.

**Common opening line for every prompt:**
> Read `LAST_LIGHT_PLAN_TO_NOV14.md`, `CLAUDE.md`, `workflow.md` and `game/README.md`. You are working on item <X> only. Follow section 7.

**Former teammate, item B (mass):**
> Item B. Find where Kite's drive force and energy use are computed (`src/robot/robot.gd`, part scripts). Propose, then implement, a small change so the total mounted-part mass changes acceleration, top speed and Wh use. Keep the formula simple and put the constants in one place. Add one headless test showing a loaded Kite is slower and uses more energy than an empty one.

**Former teammate, item I (dialogue queue):**
> Item I. Inspect the existing dialogue resource schema and `lines.json` / `dialogue_triggers.json` first. Build the smallest queue that plays a line by ID: subtitle, optional audio at `res/audio/voice/<id>.ogg`, one at a time, skip key, repeat cooldown. Do not change the file formats without telling Faiq and Fahd. Add a headless test for the queue order and cooldown.

**Fahd (C, F, H, L, then N):**
> Items C, F, H, L. C: add two landmarks on the short route (a big crater to go around and a boulder field with rocks up to 3 m) in the Moon level, keeping the long route gentler. F: extend the Downlink report in `CampaignState.mission_report` into sections (objectives, science, rover, resources, assistance) with a why line each and a comparison to the last run, using real game state. H: a skippable opening card shown once. L: a data-sources screen read from a JSON file. Do them as separate PRs.

**Rafi (D, E, K props):**
> Items D, E, K. D: a paired ground-temperature reading (sun and shade) for M3 using the existing cold zone code, plus the near sample if time. E: when the module installs, turn IRIS's lights on, move the antenna modestly, and emit the first packet to the console. K: place the readable props for Evan's notes. Tell Fahd the guidance targets so he can replace the placeholders in `missions.json`.

**Faiq, items G, J, K (text and voice):**
> Items G, J, K. Using `game/docs/STORY_SCRIPT.md`, fill `lines.json` and `dialogue_triggers.json` for the 12 to 15 key lines, write one request for Hana and Mira per mission, and the text for Evan's three notes. Use the existing line IDs (LL-xxx) so audio files can be named by ID. Do not change anything outside these files.

## 9. Which Claude settings and which AI

- **Plan mode, then normal editing:** for B and I, where a wrong design costs hours. Everything else can go straight to editing.
- **Effort:** high for B and I (physics and a new system); medium for placement, JSON and text items. Raise it for a task only if the first attempt fails.
- **Model:** use the most capable available model for B and I, and a cheaper one for text, JSON and scene placement. These are my recommendations, not tested numbers.
- **The second Claude and the GPT:** use one as a **reviewer**. After a PR is written, paste the diff into a different AI and ask for bugs and missing edge cases. A second opinion catches different mistakes. Faiq's text and voice scripts are a good fit for the GPT.
- Budget: the team says it is not a concern, but the **time** budget is. Do not start a task you cannot finish by Thursday night.

## 10. Open questions (the group answers today)

1. Former teammate: can you do B and I? If not, Fahd takes them.
2. Who presents the demo?
3. Which two team members record Mira and Hana, and who does Evan?
4. Do we meet the 2026 submission requirements? Read the Submission Guide on 13 Nov.

## 11. Not verified

Rover top speed, dialogue durations, whether the sample sites and the cargo flight are wired in the running scene, the 2026 judging criteria, the 2026 submission cutoff, and what data the Mission Design Game challenge will provide.
