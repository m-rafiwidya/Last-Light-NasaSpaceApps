"""Placeholder 16:9 mission images for the PLAY popup's save cards.

Writes game/res/ui/missions/<mission_id>.png (640 x 360): dark, a few grey shapes, no text,
loosely after the thumbnails in docs/ui/boards/Main.dc.html. Replace them with real images of
the same names. Run from the repo root:

    python3 tools/ui/make_mission_placeholders.py
"""

from pathlib import Path

from PIL import Image, ImageDraw

W, H = 640, 360
SS = 3  # supersampling for smooth edges
OUT = Path(__file__).resolve().parents[2] / "game" / "res" / "ui" / "missions"


def s(*values):
    return [v * SS for v in values]


def wake_kite(d):
    # Inside the workshop: floor, back wall, a light panel, Kite's body
    d.rectangle(s(0, 0, W, H), fill="#16161A")
    d.rectangle(s(0, 230, W, H), fill="#232327")
    d.line(s(0, 230, 110, 140, 530, 140, 640, 230), fill="#3A3A40", width=4 * SS)
    d.rectangle(s(70, 80, 190, 230), fill="#1F1F24", outline="#3A3A40", width=2 * SS)
    d.ellipse(s(250, 60, 470, 82), fill="#2C2C32")
    d.rectangle(s(225, 182, 445, 242), fill="#8A8783")
    d.rectangle(s(195, 168, 240, 200), fill="#8A8783")
    d.rectangle(s(395, 120, 401, 182), fill="#6B6863")
    for x in (255, 415):
        d.ellipse(s(x - 14, 232, x + 14, 260), fill="#3A3A40")


def first_signal(d):
    # Night surface: rolling ground, IRIS's mast with its dish, the rover
    d.rectangle(s(0, 0, W, H), fill="#050507")
    for x, y in ((110, 56), (465, 40), (560, 95), (300, 70), (40, 120)):
        d.ellipse(s(x - 2, y - 2, x + 2, y + 2), fill="#6B6863")
    d.polygon(s(0, 205, 160, 185, 330, 200, 480, 188, 640, 192, 640, 360, 0, 360), fill="#4A4944")
    d.polygon(s(0, 272, 220, 245, 640, 262, 640, 360, 0, 360), fill="#5C5A54")
    d.rectangle(s(372, 130, 436, 202), fill="#8A8783")
    d.line(s(404, 130, 404, 86), fill="#8A8783", width=3 * SS)
    d.arc(s(386, 72, 422, 100), 200, 340, fill="#8A8783", width=3 * SS)
    d.rectangle(s(70, 228, 150, 250), fill="#8A8783")
    for x in (84, 136):
        d.ellipse(s(x - 9, 245, x + 9, 263), fill="#2A2A2E")


def beyond_the_rim(d):
    # A crater rim against the sky, a low Earth, the rover on the slope
    d.rectangle(s(0, 0, W, H), fill="#050507")
    d.ellipse(s(510, 34, 570, 94), fill="#3A3A40")
    d.polygon(s(0, 180, 170, 112, 335, 172, 640, 150, 640, 360, 0, 360), fill="#3E3D39")
    d.polygon(s(0, 245, 320, 205, 640, 232, 640, 360, 0, 360), fill="#57554F")
    d.polygon(s(280, 232, 470, 210, 640, 232, 640, 360, 280, 360), fill="#26262A")
    d.rectangle(s(465, 200, 485, 228), fill="#8A8783")
    d.line(s(475, 200, 475, 178), fill="#8A8783", width=3 * SS)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, draw in (("wake_kite", wake_kite), ("first_signal", first_signal),
                       ("beyond_the_rim", beyond_the_rim)):
        image = Image.new("RGB", (W * SS, H * SS))
        draw(ImageDraw.Draw(image))
        image = image.resize((W, H), Image.LANCZOS)
        image.save(OUT / f"{name}.png", optimize=True)
        print(OUT / f"{name}.png")


if __name__ == "__main__":
    main()
