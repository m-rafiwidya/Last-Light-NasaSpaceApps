"""Compose tracks/<name>.py to MIDI and render it: ./track <name> [--lufs N], ./track --list."""
import argparse
import importlib.util
import sys
from pathlib import Path

import render

TRACKS = Path(__file__).resolve().parent / "tracks"


def load(name):
    path = TRACKS / f"{name}.py"
    if not path.is_file():
        sys.exit(f"no track {path}; available: {', '.join(available())}")
    sys.path.insert(0, str(TRACKS))  # so track files can `import kit`
    spec = importlib.util.spec_from_file_location(f"track_{name}", path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def available():
    return sorted(p.stem for p in TRACKS.glob("*.py") if p.stem != "kit" and not p.stem.startswith("_"))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("name", nargs="?")
    parser.add_argument("--list", action="store_true")
    parser.add_argument("--lufs", type=float, default=render.TARGET_LUFS)
    args = parser.parse_args()
    if args.list or not args.name:
        print("\n".join(available()))
        sys.exit(0)
    module = load(args.name)
    import kit
    render.render(kit.main(module.compose), target_lufs=args.lufs)
