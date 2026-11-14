# CLAUDE.md

- Game architecture and gotchas: `game/README.md`.
- Planned gameplay and story (the target, not the current code): `README_AI.md`, `game/README_GAMEPLAY.md`
  and `game/docs/`. UI design: `docs/ui/README.md` (spec, boards, prompts).
- Rover 3D kit (Blender parts for the drivable rover): follow `tools/blender/ROVER_KIT.md` for every
  part: layout, naming, origins, connectors, clearances, triangle budget, materials and export.
- Part generators live in `tools/blender/scripts/` (shared helpers in `rover_kit_common.py`). Run
  them headless from the repo root, e.g.
  `blender -b --factory-startup -P tools/blender/scripts/make_wheel.py`
  (`blender` is a wrapper script in `/usr/local/bin`; a plain symlink to the app binary crashes
  because Blender can't find its bundled Python). Each run writes `tools/blender/parts/<part>.blend`,
  `game/res/models/rover_kit/<part>.glb` and previews in `tools/blender/previews/<part>/`
  (git-ignored). Check the previews from the side, front and inner face for every part.
- Game tests are headless SceneTree scripts in `game/tests/`, e.g.
  `<godot> --headless --fixed-fps 240 --path game -s res://tests/test_wheel_contact.gd`
  (use your local Godot 4.7 install; macOS: usually ~/Downloads/Godot.app or /Applications/Godot.app, binary at
  `Contents/MacOS/Godot`; each test prints `RESULT ... PASS / FAIL`).

## Working rules (token budget)
- Run only the tests related to the change. Run the full suite only when I ask (before merging).
- No screenshots, frame-time measurements or windowed runs unless I ask.
- Don't read docs/ui/boards/*.dc.html in full; grep for the values you need.
- Keep the final report under 10 lines: what changed, test result, anything I must decide.
