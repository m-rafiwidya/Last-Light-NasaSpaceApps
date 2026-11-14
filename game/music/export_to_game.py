"""Copy the final audio from output/ into the game and import it.

    .venv/bin/python export_to_game.py

- Music: output/deep_space_memory/deep_space_memory.ogg -> res/audio/music/ (the main mix, not
  the loop test), imported with loop=true, loop_offset=0 so it loops sample-exactly.
- UI: output/ui_<DEFAULT_SET>/<name>.wav (not _preview) -> res/audio/ui/.
- Gameplay sounds: output/sfx/<name>.wav and the loops' <name>.ogg (not _preview) -> res/audio/sfx/,
  the OGGs imported with loop=true, loop_offset=0 (sfx_sounds.py builds them seamless).
Re-render a sound, re-run this, and the game uses the new version. Godot (GODOT, or the
GODOT environment variable) re-imports the copied files headlessly.
"""
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
GAME = HERE.parent
OUTPUT = HERE / "output"
GODOT = os.environ.get("GODOT", "/Users/fahd/Downloads/Godot-2.app/Contents/MacOS/Godot")

MUSIC = ["deep_space_memory"]           # tracks whose main mix goes into the game
UI_SET = "soft"                         # keep in step with ui_sounds.DEFAULT_SET

MUSIC_DIR = GAME / "res" / "audio" / "music"
UI_DIR = GAME / "res" / "audio" / "ui"
SFX_DIR = GAME / "res" / "audio" / "sfx"


def copy(src, dst_dir):
    if not src.is_file():
        sys.exit(f"missing {src}: render it first")
    dst_dir.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst_dir / src.name)
    print(f"  {src.relative_to(HERE)} -> {(dst_dir / src.name).relative_to(GAME)}")
    return dst_dir / src.name


def godot_import():
    subprocess.run([GODOT, "--headless", "--path", str(GAME), "--import"], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def set_loop(ogg):
    """loop=true, loop_offset=0 in the OGG's import settings. Returns True if it changed."""
    path = Path(str(ogg) + ".import")
    text = path.read_text()
    new = re.sub(r"^loop=.*$", "loop=true", text, flags=re.M)
    new = re.sub(r"^loop_offset=.*$", "loop_offset=0", new, flags=re.M)
    if new != text:
        path.write_text(new)
    return new != text


def sync(src_dir, dst_dir, patterns):
    """Copies src_dir's files matching `patterns` (not _preview) to dst_dir and removes files
    of those kinds there that no longer exist in src_dir. Returns the copies."""
    files = sorted(p for pattern in patterns for p in src_dir.glob(pattern) if not p.name.startswith("_"))
    if not files:
        sys.exit(f"nothing in {src_dir}: render it first")
    copies = [copy(f, dst_dir) for f in files]
    names = {f.name for f in files}
    for p in [p for pattern in patterns for p in dst_dir.glob(pattern) if p.name not in names]:
        p.unlink()
        Path(str(p) + ".import").unlink(missing_ok=True)
        print(f"  removed stale {p.relative_to(GAME)}")
    return copies


def main():
    print("music:")
    musics = [copy(OUTPUT / name / f"{name}.ogg", MUSIC_DIR) for name in MUSIC]
    print(f"ui ({UI_SET}):")
    sync(OUTPUT / f"ui_{UI_SET}", UI_DIR, ["*.wav"])
    print("sfx:")
    sfx_loops = [p for p in sync(OUTPUT / "sfx", SFX_DIR, ["*.wav", "*.ogg"]) if p.suffix == ".ogg"]

    print("importing in Godot...")
    godot_import()
    if any([set_loop(m) for m in musics + sfx_loops]):
        godot_import()   # re-import with the loop settings
    print("done")


if __name__ == "__main__":
    main()
