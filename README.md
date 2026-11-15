# LAST LIGHT (Tandborste)

A mission design game on real lunar terrain, made for the NASA Space Apps Challenge 2026, challenge
**Space Mission Design Game**.

You are an engineer at a small outpost at the Apollo 12 landing site in 2058, with one modular rover,
Kite. In three missions you plan, configure Kite's parts, check the console's forecast, drive on
terrain built from NASA elevation data, and read a report on why the run worked or failed. A bad plan
strands the rover; failure is information, not a restart.

## Play it

- **Build:** download the Windows or macOS build from the project's Space Apps page.
- **From source:** open `game/project.godot` in Godot 4.7 and press Play.
  Architecture and details: [game/README.md](game/README.md).

| On foot | Kite (the rover) |
|---|---|
| Move: WASD · Look: mouse · Interact: E | Drive: WASD · Camera: C · Reset upright: F · Lights: L |
| | Arm: R, then click to grab and release |

Every key can be rebound in Settings > Controls.

## What makes it mission design

- **Trade-offs:** every part changes mass, energy, grip or heat. Two batteries (40 or 100 Wh), standard or
  grip wheels, a thermal kit, a sampler; two cargo landers (Courier: 30 kg in daylight, Freighter: 40 kg
  near dusk).
- **Forecast, then consequence:** the console forecasts each route's energy against Kite's range before
  you drive. In Mission 3 the default build fails both routes, and different builds succeed for
  different reasons.
- **Verified:** 12 automated drive tests run every loadout down both routes with both cargo options
  (`game/tests/test_m3_routes.gd`).

## Built on NASA data

Terrain from the LROC NAC elevation model of the Apollo 12 site (2 m sampling), lunar gravity
1.624 m/s² from NASA's Moon by the Numbers, and the challenge's resources (the Design and Develop Science
Missions webinar, the Mission Design Lab, JPL's Concept Maturity Levels). Anything simulated is labelled
in the game. Sources and limits: [game/docs/SCIENCE_AND_DATA.md](game/docs/SCIENCE_AND_DATA.md) and the
in-game Data Sources screen.

## Team

Three Indonesian students in three countries:

- **Fahd Muhammad Zahid** (Institut Teknologi Bandung): lead developer. Built the Apollo 12 terrain
  from NASA data, the levels and missions, the console and its forecast, the UI, and integrated and
  merged everyone's work.
- **Muhammad Rafi Widyatama** (Universiti Malaya, mechanical engineering): Kite's engineering and the
  Mission 3 balance (part masses, energy and grip trade-offs, the route tests), the hand-controlled
  claw and storage tray, story and voice lines, and the playtest-driven fixes.
- **Faiq Haidar Dzikrullah Satriawan** (Monash University): the story, the characters' dialogue and
  the voice lines, and the cutscene and dialogue triggers.

All three of us brainstormed the game and the missions, researched the NASA sources, playtested,
found bugs and decided what changed after each playtest.

The early base code was written by a former teammate who withdrew before judging; it is used with
his permission ([CREDITS.md](CREDITS.md)).

## How it was made

- **Timeline:** we formed the team in late September 2026 to prepare for Space Apps and started early.
  The first week went into a general first-person base (player, dialogue, console, a first rover).
  From 8 October we built the game itself around NASA's data and the mission design challenge: the
  Apollo 12 terrain, lunar gravity, Kite's parts and the three missions. On the event weekend
  (14 to 15 November) we added the hand-controlled claw and storage tray, the astronaut rescue with
  suit oxygen, saving, the voiced dialogue, the required sample, playtest fixes and the trailer.
  The full history is in this repository.
- **AI tools:** Claude (Anthropic), through Claude Code, for code, the Blender scripts that build the
  models, and music and sound scripts; ElevenLabs for the voices. The mission design, balance, story
  and data research are the team's. Details: [CREDITS.md](CREDITS.md).
- **Licence:** the team's code and content are under the [MIT License](LICENSE); third-party material
  keeps its own licence, listed in [CREDITS.md](CREDITS.md).

## Docs

- [START_HERE.md](START_HERE.md): final story and gameplay handoff (11 October 2026), and which file each person needs
- [Game and story plan](Tandborste-Game-and-Story-Plan.md)
- [Gameplay contract and acceptance checks](game/README_GAMEPLAY.md)
- [Story script](game/docs/STORY_SCRIPT.md), [asset brief](game/docs/ASSET_BRIEF.md), [science and data](game/docs/SCIENCE_AND_DATA.md), [voice and audio](game/docs/VOICE_AND_AUDIO.md), [example mission definitions](game/docs/examples/MISSIONS.json)
- [UI design](docs/ui/README.md): spec, boards, screenshots, fonts and implementation prompts
- [Instructions for AI assistants](README_AI.md), [team message](TEAM_MESSAGE.md)
- [Credits](CREDITS.md)
