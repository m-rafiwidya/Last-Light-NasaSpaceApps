# CLAUDE.md

- Game architecture and gotchas: `game/README.md`.
- Rover 3D kit (Blender parts for the drivable rover): follow `tools/blender/ROVER_KIT.md` for every
  part: layout, naming, origins, connectors, clearances, triangle budget, materials and export.
- Part generators live in `tools/blender/scripts/` (shared helpers in `rover_kit_common.py`). Run
  them headless from the repo root, e.g.
  `blender -b --factory-startup -P tools/blender/scripts/make_wheel.py`
  (`blender` is a wrapper script in `/usr/local/bin`; a plain symlink to the app binary crashes
  because Blender can't find its bundled Python). Each run writes `tools/blender/parts/<part>.blend`,
  `game/res/models/rover_kit/<part>.glb` and previews in `tools/blender/previews/<part>/`
  (git-ignored). Check the previews from the side, front and inner face for every part.
