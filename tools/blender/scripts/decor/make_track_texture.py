"""Generates the tyre-track decal textures for the apron outside the workshop (DECOR_KIT.md 4.4):
an albedo with alpha and a tangent-space normal map of the rover's two wheel tracks, 1.0 m apart,
for a Godot Decal 1.2 m wide and TRACK_LENGTH long. Plain Python (no Blender, no third-party
modules), original pattern:

    python3 tools/blender/scripts/decor/make_track_texture.py

Writes game/res/textures/decor/track_albedo.png and track_normal.png.

Texture u runs across the decal (x, 0 at its left edge seen from above with the rover driving
towards v 0), v along it. Each track is a 0.14 m band of chevron grouser prints every 0.10 m,
compressed regolith reading a little darker; the alpha fades at the band's edges and at the
decal's two ends, so chained decals join without a seam.
"""

import math
import os
import struct
import zlib

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", ".."))
OUT_DIR = os.path.join(REPO_ROOT, "game", "res", "textures", "decor")
WIDTH, HEIGHT = 256, 1024
DECAL_WIDTH = 1.2            # metres across (u)
TRACK_LENGTH = 2.5           # metres along (v)
TRACK_CENTRES = (-0.5, 0.5)  # the wheels' centre lines
BAND = 0.14                  # tread width
GROUSER_STEP = 0.10
EDGE_FADE = 0.012            # metres of soft edge on each side of a band
END_FADE = 0.04              # fraction of the length faded at each end
BASE_ALPHA = 0.38
PRINT_ALPHA = 0.62


def write_png(path: str, width: int, height: int, rows: list, channels: int) -> None:
    color_type = {3: 2, 4: 6}[channels]
    raw = b"".join(b"\x00" + bytes(row) for row in rows)

    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    header = struct.pack(">IIBBBBB", width, height, 8, color_type, 0, 0, 0)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def height_at(x: float, y: float) -> float:
    """Depth of the print (0 = untouched ground, 1 = a grouser's full print) at x across the decal
    (metres from its middle) and y along it (metres)."""
    for c in TRACK_CENTRES:
        d = x - c
        if abs(d) > BAND / 2.0:
            continue
        # Chevron: the grouser line bends back from the band's middle
        phase = (y + abs(d) * 0.6) / GROUSER_STEP
        f = phase - math.floor(phase)
        ridge = max(0.0, 1.0 - abs(f - 0.5) / 0.18)
        return 0.35 + 0.65 * ridge
    return 0.0


def band_alpha(x: float) -> float:
    best = 0.0
    for c in TRACK_CENTRES:
        d = abs(x - c) - (BAND / 2.0 - EDGE_FADE)
        best = max(best, 1.0 if d <= 0.0 else max(0.0, 1.0 - d / EDGE_FADE))
    return best


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    albedo, normal = [], []
    px = DECAL_WIDTH / WIDTH
    py = TRACK_LENGTH / HEIGHT
    for j in range(HEIGHT):
        v = (j + 0.5) / HEIGHT
        y = v * TRACK_LENGTH
        end = min(1.0, min(v, 1.0 - v) / END_FADE)
        arow, nrow = [], []
        for i in range(WIDTH):
            x = (i + 0.5) / WIDTH * DECAL_WIDTH - DECAL_WIDTH / 2.0
            h = height_at(x, y)
            edge = band_alpha(x)
            alpha = edge * end * (BASE_ALPHA + (PRINT_ALPHA - BASE_ALPHA) * max(0.0, (h - 0.35) / 0.65))
            shade = int(round(255 * (0.20 - 0.05 * h)))
            arow += [shade, shade, shade, int(round(255 * alpha))]
            # Normal from the print's depth gradient (prints are dents: depth 1 is 6 mm down)
            depth = 0.006
            dx = (height_at(x + px, y) - height_at(x - px, y)) / (2 * px) * depth
            dy = (height_at(x, y + py) - height_at(x, y - py)) / (2 * py) * depth
            n = (dx, dy, 1.0)
            length = math.sqrt(n[0] ** 2 + n[1] ** 2 + n[2] ** 2)
            nrow += [int(round(255 * (0.5 + 0.5 * c / length))) for c in n]
        albedo.append(arow)
        normal.append(nrow)
    write_png(os.path.join(OUT_DIR, "track_albedo.png"), WIDTH, HEIGHT, albedo, 4)
    write_png(os.path.join(OUT_DIR, "track_normal.png"), WIDTH, HEIGHT, normal, 3)
    print("DECOR_KIT tracks: %dx%d px for a %.1f x %.1f m decal, bands %.2f m wide at x %s; wrote track_albedo.png, track_normal.png" % (
        WIDTH, HEIGHT, DECAL_WIDTH, TRACK_LENGTH, BAND, TRACK_CENTRES))


if __name__ == "__main__":
    main()
