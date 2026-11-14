# Tandborste — start here

**LAST LIGHT · final Moon chapter handoff · 11 October 2026**

The target is one complete playable chapter: prepare Kite at a lunar workshop, inspect and restore IRIS, recover a field logger, collect useful comparison records, return and transmit. Three outings reuse one NASA-derived terrain patch. The story ends at home; Mars is a future assignment.

**Team:** Fahd = Fahd Muhammad Zahid · Rafi = Muhammad Rafi Widyatama · Faiq = Faiq Haidar Dzikrullah Satriawan · Satinize = Rayhan Satrio Adi Nurdjaman

## Which file each person needs

| File | Use |
|---|---|
| [Tandborste-Game-and-Story-Plan.md](Tandborste-Game-and-Story-Plan.md) | Shared final direction, story and production scope |
| [TEAM_MESSAGE.md](TEAM_MESSAGE.md) | Plain Indo/English group explanation |
| [game/README_GAMEPLAY.md](game/README_GAMEPLAY.md) | Goriorio: mission state, interactions, choices and acceptance checks |
| [game/docs/ASSET_BRIEF.md](game/docs/ASSET_BRIEF.md) | Fahd: prioritised models, imports, collision and source references |
| [game/docs/STORY_SCRIPT.md](game/docs/STORY_SCRIPT.md) | Faiq: complete dialogue, logs, triggers and ending |
| [game/docs/VOICE_AND_AUDIO.md](game/docs/VOICE_AND_AUDIO.md) | Record the team's 28 radio lines plus one archive performance |
| [game/docs/SCIENCE_AND_DATA.md](game/docs/SCIENCE_AND_DATA.md) | Rafi/team: NASA provenance, realistic science and declared models |
| [README_AI.md](README_AI.md) | Bounded tasks for coding assistants |
| [game/docs/examples/MISSIONS.json](game/docs/examples/MISSIONS.json) | Example content definitions to adapt to the actual project |

## Put this into the repository

Keep the existing technical/run README. Copy these planning files into the matching paths, reconcile any `AGENTS.md`/project conventions, and link them from the existing README. The example JSON is not a plugin or a replacement state manager; integrate its content into the verified existing schema.

This package contains documentation and example definitions. It does not contain the team's Godot repository, a playable export, newly generated 3D models or raw NASA rasters. Implementation and runtime checks remain to be completed in that repository. Existing NASA terrain downloads/starter files should be reused with their original metadata.

## Do the first loop before expanding

M1 is the next implementation milestone: assemble, control, drive, inspect, return, dock, transmit, report and retry. Fix reproducible wheel/terrain contact problems before placing the mission on that route. M2 adds physical repair cargo; M3 adds logger/science and the ending. Then integrate consequential delivery planning, source cards, voice and exported-build polish.

Use one owner per shared controller/scene/pipeline. Finish a coherent ticket rather than having two assistants independently rewrite the same system. New-player playtests determine whether the planned 20–30 minute chapter is understandable and enjoyable.

This supersedes the old lost-Kite/two-rover opening. **Kite is already at home. IRIS is not home. The station-restoration beat is not the final chapter ending.**
