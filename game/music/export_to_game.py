"""Copy the final audio from output/ into the game and import it.

    .venv/bin/python export_to_game.py

- Music: output/deep_space_memory/deep_space_memory.ogg -> res/audio/music/ (the main mix, not
  the loop test), imported with loop=true, loop_offset=0 so it loops sample-exactly.
- UI: output/ui_<DEFAULT_SET>/<name>.wav (not _preview) -> res/audio/ui/.
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


def main():
    print("music:")
    musics = [copy(OUTPUT / name / f"{name}.ogg", MUSIC_DIR) for name in MUSIC]
    print(f"ui ({UI_SET}):")
    wavs = sorted(p for p in (OUTPUT / f"ui_{UI_SET}").glob("*.wav") if not p.name.startswith("_"))
    for wav in wavs:
        copy(wav, UI_DIR)
    stale = [p for p in UI_DIR.glob("*.wav") if p.name not in {w.name for w in wavs}]
    for p in stale:
        p.unlink()
        Path(str(p) + ".import").unlink(missing_ok=True)
        print(f"  removed stale {p.relative_to(GAME)}")

    print("importing in Godot...")
    godot_import()
    if any([set_loop(m) for m in musics]):
        godot_import()   # re-import with the loop settings
    print("done")


if __name__ == "__main__":
    main()
