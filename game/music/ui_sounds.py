"""UI sound effects in the Deep Space style, from the synth engine: tuned to the music's key,
soft, a little clearer than the music, same reverb character with short tails, no loops.

    .venv/bin/python ui_sounds.py            # all sounds + preview into output/ui/
    .venv/bin/python ui_sounds.py confirm    # only some (preview still covers all rendered)

Pitches are scale degrees of KEY_ROOT in SCALE (degree 0 = KEY_ROOT, 7 = an octave up), so
retuning the whole set is one line. Each sound is peak-normalised to its own level in LEVELS.
"""
import sys
from pathlib import Path

import numpy as np
import pedalboard
import pretty_midi
import soundfile as sf

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE / "tracks"))
import kit  # noqa: E402
import synth  # noqa: E402

SR = 48000
KEY_ROOT = "C5"          # the music's key; all pitched sounds are degrees of this scale
SCALE = kit.LYDIAN
OUT = HERE / "output" / "ui"

# Peak level (dBFS) per sound: hovers and ticks far below confirms and the start swell.
LEVELS = {
    "hover": -32, "click": -24, "confirm": -18, "back": -20, "error": -18,
    "menu_open": -24, "menu_close": -24, "toggle_on": -27, "toggle_off": -27,
    "slider_tick": -36, "notification": -18, "game_start": -15,
}


def hz(degree):
    return synth.midi_hz(kit.scale(KEY_ROOT, degree, SCALE))


def t_axis(seconds):
    return np.arange(int(seconds * SR)) / SR


# ---------------------------------------------------------------- building blocks


def blip(f0, f1=None, seconds=0.12, decay=0.04, glide=0.04, attack=0.002, body=0.15):
    """Soft sine blip, optionally gliding from f0 to f1 (exponential), with a gentle 2nd partial."""
    t = t_axis(seconds)
    f1 = f0 if f1 is None else f1
    freq = f0 * (f1 / f0) ** np.clip(t / glide, 0, 1)
    ph = 2 * np.pi * np.cumsum(freq) / SR
    env = np.clip(t / attack, 0, 1) * np.exp(-t / decay)
    return synth.pan((np.sin(ph) + body * np.sin(2 * ph)) * env, 0.0)


def soft_tick(seconds=0.02, cutoff=1800, seed=0):
    """A very short, low-passed noise tick (the 'touch' of a click), never sharp."""
    t = t_axis(seconds)
    noise = np.random.default_rng(seed).standard_normal(len(t)) * np.exp(-t / 0.004)
    noise = synth.tv_filter(noise, np.full(len(t), float(cutoff)), SR)
    return synth.pan(noise, 0.0)


def bell(degree, start=0.0, velocity=70, voice="bell", **override):
    """One synth-engine bell/chime note (soft FM), with shorter ring for UI use."""
    p = dict(synth.VOICES[voice], **override)
    note = pretty_midi.Note(velocity, kit.scale(KEY_ROOT, degree, SCALE), 0.0, 0.2)
    audio = synth.bell(note, pretty_midi.Instrument(0), SR, 10.0, p)
    return place(audio, start)


def swell(degrees, seconds, brightness, attack, release, velocity=70, voice="pad"):
    """Synth-engine pad chord whose filter follows `brightness` [(time, cc74), ...]."""
    inst = pretty_midi.Instrument(0)
    inst.control_changes = [pretty_midi.ControlChange(74, v, t) for t, v in brightness]
    p = dict(synth.VOICES[voice], attack=attack, release=release, sweep_oct=0.0)
    out = np.zeros((0, 2))
    for d in degrees:
        note = pretty_midi.Note(velocity, kit.scale(KEY_ROOT, d, SCALE), 0.0, seconds)
        out = mix(out, synth.pad(note, inst, SR, 10.0, p))
    return out


def place(audio, start):
    return np.concatenate([np.zeros((int(start * SR), 2)), audio])


def mix(*parts):
    out = np.zeros((max(len(p) for p in parts), 2))
    for p in parts:
        out[:len(p)] += p
    return out


def finish(x, wet=0.3, rt60=(1.2, 0.9, 0.4), lowpass=5500, shimmer=0.0, floor_db=-50):
    """Short version of the music's space: the same smooth synthetic hall with short decay, a
    gentle lowpass (clearer than the music), then trim the tail and fade it out."""
    x = np.concatenate([x, np.zeros((int(max(rt60) * 1.3 * SR), 2))])
    out = x + wet * synth.reverb(x, SR, rt60, predelay=0.01)
    if shimmer:
        out += shimmer * synth.shimmer(x, SR, rt60)
    out = synth._pb(pedalboard.Pedalboard([pedalboard.HighpassFilter(40), pedalboard.LowpassFilter(lowpass),
                                           pedalboard.LowpassFilter(lowpass)]), out, SR)
    level = np.abs(out).max(axis=1)
    end = np.nonzero(level > level.max() * 10 ** (floor_db / 20))[0][-1] + 1
    out = out[:end]
    fade = min(int(0.03 * SR), end)
    out[-fade:] *= np.linspace(1, 0, fade)[:, None]
    return out


# ---------------------------------------------------------------- sounds


def hover(v):
    degree = (11, 9, 12)[v]            # G6, E6, A6
    return finish(blip(hz(degree), seconds=0.08, decay=(0.018, 0.022, 0.016)[v]), wet=0.18, rt60=(0.5, 0.4, 0.2))


def click(v):
    degree = (7, 8, 9)[v]              # C6, D6, E6, with a tiny downward settle
    f = hz(degree)
    body = blip(f * 1.04, f, seconds=0.15, decay=(0.045, 0.05, 0.04)[v], glide=0.012)
    return finish(mix(body, 0.08 * soft_tick(seed=v)), wet=0.22, rt60=(0.7, 0.5, 0.25))


def confirm():
    return finish(mix(bell(7, 0.0, 72, decay=0.3, ring=1.0, attack=0.006),        # C6
                      bell(11, 0.09, 78, decay=0.4, ring=1.1, attack=0.006)), wet=0.25, rt60=(0.9, 0.7, 0.3),
                  lowpass=4500)  # G6


def back():
    return finish(mix(bell(4, 0.0, 70, decay=0.3, ring=1.0, attack=0.006),        # G5
                      bell(0, 0.09, 66, decay=0.35, ring=1.0, attack=0.006)), wet=0.25, rt60=(0.9, 0.7, 0.3))   # C5


def error():
    """Low, muffled, soft thud: a sine falling from G2 to C2, with a felt-soft noise touch."""
    thud = blip(hz(-17), hz(-21), seconds=0.45, decay=0.14, glide=0.08, attack=0.004, body=0.25)
    out = finish(mix(thud, 0.15 * soft_tick(0.04, cutoff=300, seed=9)), wet=0.25, rt60=(0.9, 0.6, 0.3), lowpass=500)
    return out


MENU_CHORD = (-7, -3, 1, 2)             # C4 G4 D5 E5: open Cadd9


def menu_open():
    s = swell(MENU_CHORD, 0.35, [(0.0, 30), (0.45, 96)], attack=0.3, release=0.35)
    return finish(s, wet=0.3, rt60=(0.9, 0.7, 0.3))[:int(0.95 * SR)]


def menu_close():
    s = swell(MENU_CHORD, 0.2, [(0.0, 96), (0.4, 30)], attack=0.12, release=0.45)
    return finish(s, wet=0.3, rt60=(0.9, 0.7, 0.3))[:int(0.95 * SR)]


def toggle_on():
    return finish(blip(hz(4), hz(7), seconds=0.14, decay=0.045, glide=0.035), wet=0.2, rt60=(0.6, 0.45, 0.2))  # G5 -> C6


def toggle_off():
    return finish(blip(hz(7), hz(4), seconds=0.14, decay=0.045, glide=0.035), wet=0.2, rt60=(0.6, 0.45, 0.2))  # C6 -> G5


def slider_tick():
    return finish(blip(hz(14), seconds=0.05, decay=0.01), wet=0.12, rt60=(0.35, 0.3, 0.15))  # C7


def notification():
    """Soft, slightly magical rising chime: G5, D6, F#6 (the Lydian #4), then a faint B6."""
    notes = [(4, 0.0, 66), (8, 0.11, 70), (10, 0.22, 74), (13, 0.42, 48)]
    chime = mix(*(bell(d, s, v, voice="chime", decay=0.5, ring=1.5) for d, s, v in notes))
    return finish(chime, wet=0.3, rt60=(1.2, 0.9, 0.4), shimmer=0.06)


def game_start():
    """About 2.5 s: a Cmaj7#11 pad swells open, then a soft rising sparkle settles into it."""
    pad = swell((-14, -10, -8, -6, -4), 1.4, [(0.0, 28), (1.6, 100)], attack=1.2, release=1.0, voice="pad")
    glass = place(swell((7, 11, 13), 0.9, [(0.0, 50), (1.0, 90)], attack=0.7, release=0.9,
                        velocity=50, voice="pad_sine"), 0.6)
    sparkle = mix(*(bell(d, 1.05 + 0.1 * i, 46 + 4 * i, voice="chime", decay=0.7, ring=1.6)
                    for i, d in enumerate((7, 8, 9, 11, 13))))   # C6 D6 E6 G6 B6
    out = finish(mix(pad, glass, 0.6 * sparkle), wet=0.4, rt60=(2.0, 1.5, 0.6), lowpass=5000, shimmer=0.1)
    out = out[:int(3.0 * SR)]
    fade = int(0.5 * SR)
    out[-fade:] *= np.linspace(1, 0, fade)[:, None] ** 2
    return out


SOUNDS = {
    "hover_1": lambda: hover(0), "hover_2": lambda: hover(1), "hover_3": lambda: hover(2),
    "click_1": lambda: click(0), "click_2": lambda: click(1), "click_3": lambda: click(2),
    "confirm": confirm, "back": back, "error": error,
    "menu_open": menu_open, "menu_close": menu_close,
    "toggle_on": toggle_on, "toggle_off": toggle_off,
    "slider_tick": slider_tick, "notification": notification, "game_start": game_start,
}


def level_for(name):
    return LEVELS[name.rsplit("_", 1)[0] if name[-1].isdigit() else name]


def main(names):
    OUT.mkdir(parents=True, exist_ok=True)
    rendered = []
    for name in names:
        audio = SOUNDS[name]()
        audio *= 10 ** (level_for(name) / 20) / np.abs(audio).max()
        sf.write(OUT / f"{name}.wav", audio.astype(np.float32), SR, subtype="PCM_24")
        rendered.append((name, audio))

    gap = np.zeros((int(0.7 * SR), 2))
    preview, t = [], 0.0
    print("preview order:")
    for name, audio in rendered:
        print(f"  {t:5.1f}s  {name:13} {len(audio) / SR:4.2f}s  peak {level_for(name)} dBFS")
        preview += [audio, gap]
        t += (len(audio) + len(gap)) / SR
    sf.write(OUT / "_preview.wav", np.concatenate(preview).astype(np.float32), SR, subtype="PCM_24")
    print(f"sounds:  {OUT}/<name>.wav ({len(rendered)} files)")
    print(f"preview: {OUT / '_preview.wav'}")


if __name__ == "__main__":
    wanted = sys.argv[1:] or list(SOUNDS)
    unknown = [n for n in wanted if n not in SOUNDS]
    if unknown:
        sys.exit(f"unknown sounds {unknown}; available: {', '.join(SOUNDS)}")
    main(wanted)
