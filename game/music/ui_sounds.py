"""UI sound effects in the Deep Space style: tuned to the music's key, soft, a little clearer than
the music, same reverb character with short tails, no loops, nothing that rings or sounds metallic.

Two alternative sets share the swells (menus, game start) and the error thud:
  soft: pure sine droplets and pad_sine blooms, warm and round.
  felt: muted felt piano taps and notes (the memory track's felt piano, with short tails).

    .venv/bin/python ui_sounds.py                  # both sets -> output/ui_soft/, output/ui_felt/
    .venv/bin/python ui_sounds.py felt             # one set
    .venv/bin/python ui_sounds.py soft confirm     # only some sounds of a set

Pitches are scale degrees of KEY_ROOT in SCALE (degree 0 = KEY_ROOT, 7 = an octave up), so
retuning everything is one line. Each sound is peak-normalised to its own level in LEVELS.
"""
import sys
import tempfile
from pathlib import Path

import numpy as np
import pedalboard
import pretty_midi
import soundfile as sf

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE / "tracks"))
import kit  # noqa: E402
import render  # noqa: E402
import synth  # noqa: E402

SR = 48000
KEY_ROOT = "C5"          # the music's key; all pitched sounds are degrees of this scale
SCALE = kit.LYDIAN
OUTPUT = HERE / "output"

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


def blip(f0, f1=None, seconds=0.12, decay=0.04, glide=0.04, attack=0.002, body=0.0):
    """Sine blip, optionally gliding from f0 to f1 (exponential). `body` adds a 2nd partial."""
    t = t_axis(seconds)
    f1 = f0 if f1 is None else f1
    freq = f0 * (f1 / f0) ** np.clip(t / glide, 0, 1)
    ph = 2 * np.pi * np.cumsum(freq) / SR
    env = (0.5 - 0.5 * np.cos(np.pi * np.clip(t / attack, 0, 1))) * np.exp(-t / decay)
    return synth.pan((np.sin(ph) + body * np.sin(2 * ph)) * env, 0.0)


def soft_tick(seconds=0.02, cutoff=1800, seed=0):
    """A very short, low-passed noise touch, never sharp."""
    t = t_axis(seconds)
    noise = np.random.default_rng(seed).standard_normal(len(t)) * np.exp(-t / 0.004)
    return synth.pan(synth.tv_filter(noise, np.full(len(t), float(cutoff)), SR), 0.0)


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


def bloom(notes, attack=0.04, hold=0.1, release=0.35):
    """Soft pad_sine blooms: [(degree, start, velocity), ...], each a short swell in and out."""
    inst = pretty_midi.Instrument(0)
    p = dict(synth.VOICES["pad_sine"], attack=attack, release=release, sweep_oct=0.0)
    parts = []
    for d, start, vel in notes:
        note = pretty_midi.Note(vel, kit.scale(KEY_ROOT, d, SCALE), 0.0, hold)
        parts.append(place(synth.pad(note, inst, SR, 10.0, p), start))
    return mix(*parts)


def felt(notes, dim=1400, damp=None, blur=0.4):
    """Muted felt piano: [(degree, start, seconds, velocity), ...] rendered dry by FluidSynth,
    then attacks softened, dimmed with a steep lowpass and lightly blurred (as in the memory
    track's felt_piano, without its long reverb). `damp` (seconds) is a firmer damper: each note
    dies away with that time constant right after its note-off, for short muted taps."""
    pm = pretty_midi.PrettyMIDI(initial_tempo=60)
    piano = pretty_midi.Instrument(0, name="felt")
    piano.notes = [pretty_midi.Note(v, kit.scale(KEY_ROOT, d, SCALE), s, s + n) for d, s, n, v in notes]
    with tempfile.TemporaryDirectory() as tmp:
        dry = render.render_dry(pm, [piano], Path(tmp), "felt").astype(np.float64)
    if damp:
        t = np.arange(len(dry)) / SR
        end = max(n.end for n in piano.notes) + 0.01
        dry *= np.exp(-np.clip(t - end, 0, None) / damp)[:, None]
    x = synth.soften_attacks(dry, SR, amount=0.7)
    x = synth.steep_lowpass(x, SR, dim)
    return 0.7 * x + blur * synth.reverb(x, SR, (0.5, 0.4, 0.2), predelay=0.0)


def place(audio, start):
    return np.concatenate([np.zeros((int(start * SR), 2)), audio])


def mix(*parts):
    out = np.zeros((max(len(p) for p in parts), 2))
    for p in parts:
        out[:len(p)] += p
    return out


def finish(x, wet=0.3, rt60=(1.2, 0.9, 0.4), lowpass=5000, floor_db=-50):
    """Short version of the music's space: the same smooth synthetic hall with short decay, a
    gentle lowpass (clearer than the music), then trim the tail and fade it out."""
    x = np.concatenate([x, np.zeros((int(max(rt60) * 1.3 * SR), 2))])
    out = x + wet * synth.reverb(x, SR, rt60, predelay=0.01)
    out = synth._pb(pedalboard.Pedalboard([pedalboard.HighpassFilter(40), pedalboard.LowpassFilter(lowpass),
                                           pedalboard.LowpassFilter(lowpass)]), out, SR)
    level = np.abs(out).max(axis=1)
    start = np.nonzero(level > level.max() * 1e-4)[0][0]   # drop any leading silence (fast response)
    end = np.nonzero(level > level.max() * 10 ** (floor_db / 20))[0][-1] + 1
    out = out[start:end]
    fade = min(int(0.03 * SR), len(out))
    out[-fade:] *= np.linspace(1, 0, fade)[:, None]
    return out


SHORT = dict(wet=0.15, rt60=(0.5, 0.4, 0.2))     # taps and droplets: barely any tail
MEDIUM = dict(wet=0.25, rt60=(0.9, 0.7, 0.3))    # confirm, back, error, menus

# ---------------------------------------------------------------- shared sounds


def error():
    """Low, muffled, soft thud: a sine falling from G2 to C2, with a felt-soft noise touch."""
    thud = blip(hz(-17), hz(-21), seconds=0.45, decay=0.14, glide=0.08, attack=0.004, body=0.25)
    return finish(mix(thud, 0.15 * soft_tick(0.04, cutoff=300, seed=9)), lowpass=500, **MEDIUM)


MENU_CHORD = (-7, -3, 1, 2)             # C4 G4 D5 E5: open Cadd9


def menu_open():
    s = swell(MENU_CHORD, 0.35, [(0.0, 30), (0.45, 96)], attack=0.3, release=0.35)
    return finish(s, **MEDIUM)[:int(0.95 * SR)]


def menu_close():
    s = swell(MENU_CHORD, 0.2, [(0.0, 96), (0.4, 30)], attack=0.12, release=0.45)
    return finish(s, **MEDIUM)[:int(0.95 * SR)]


def game_start():
    """About 2.5 s: a Cmaj7#11 pad swells open with a soft high pad_sine layer inside it."""
    pad = swell((-14, -10, -8, -6, -4), 1.4, [(0.0, 28), (1.6, 100)], attack=1.2, release=1.0)
    glass = place(swell((7, 11, 13), 0.9, [(0.0, 50), (1.0, 90)], attack=0.7, release=0.9,
                        velocity=50, voice="pad_sine"), 0.6)
    out = finish(mix(pad, glass), wet=0.4, rt60=(2.0, 1.5, 0.6))[:int(3.0 * SR)]
    fade = int(0.5 * SR)
    out[-fade:] *= np.linspace(1, 0, fade)[:, None] ** 2
    return out


SHARED = {"error": error, "menu_open": menu_open, "menu_close": menu_close, "game_start": game_start}

# ---------------------------------------------------------------- set A: soft
# Pure sines (no overtones) an octave below the first set, tiny upward "bubble" glide, very short.


def droplet(degree, decay, seconds=0.1):
    f = hz(degree)
    return finish(blip(f * 0.97, f, seconds=seconds, decay=decay, glide=0.015, attack=0.003), **SHORT)


SOFT = {
    "hover_1": lambda: droplet(4, 0.012),     # G5
    "hover_2": lambda: droplet(2, 0.014),     # E5
    "hover_3": lambda: droplet(5, 0.011),     # A5
    "click_1": lambda: droplet(0, 0.025),     # C5
    "click_2": lambda: droplet(1, 0.027),     # D5
    "click_3": lambda: droplet(2, 0.023),     # E5
    "toggle_on": lambda: finish(blip(hz(-3), hz(0), seconds=0.12, decay=0.035, glide=0.035, attack=0.003), **SHORT),
    "toggle_off": lambda: finish(blip(hz(0), hz(-3), seconds=0.12, decay=0.035, glide=0.035, attack=0.003), **SHORT),
    "slider_tick": lambda: droplet(7, 0.008, seconds=0.05),   # C6
    # Two-note soft blooms, rising for confirm, falling for back.
    "confirm": lambda: finish(bloom([(0, 0.0, 70), (4, 0.1, 76)]), **MEDIUM),          # C5 -> G5
    "back": lambda: finish(bloom([(-3, 0.0, 70), (-7, 0.1, 64)]), **MEDIUM),           # G4 -> C4
    # Rising bloom through the Lydian #4: G4, D5, F#5.
    "notification": lambda: finish(bloom([(-3, 0.0, 62), (1, 0.12, 68), (3, 0.24, 72)],
                                         hold=0.25, release=0.6), wet=0.3, rt60=(1.2, 0.9, 0.4)),
    **SHARED,
}

# ---------------------------------------------------------------- set B: felt
# Muted felt piano: short notes so the dampers stop them, low velocities, dim.


def tap(degree, velocity=34, seconds=0.06, dim=1300, damp=0.03):
    return finish(felt([(degree, 0.0, seconds, velocity)], dim=dim, damp=damp, blur=0.08), wet=0.08, rt60=(0.4, 0.3, 0.15))


FELT = {
    "hover_1": lambda: tap(4, 26, 0.04, damp=0.02),      # G5
    "hover_2": lambda: tap(2, 26, 0.04, damp=0.02),      # E5
    "hover_3": lambda: tap(5, 26, 0.04, damp=0.02),      # A5
    "click_1": lambda: tap(0),                # C5
    "click_2": lambda: tap(1),                # D5
    "click_3": lambda: tap(2),                # E5
    "toggle_on": lambda: finish(felt([(-3, 0.0, 0.05, 30), (0, 0.06, 0.06, 34)], damp=0.04, blur=0.08), wet=0.08, rt60=(0.4, 0.3, 0.15)),   # G4 -> C5
    "toggle_off": lambda: finish(felt([(0, 0.0, 0.05, 34), (-3, 0.06, 0.06, 30)], damp=0.04, blur=0.08), wet=0.08, rt60=(0.4, 0.3, 0.15)),  # C5 -> G4
    "slider_tick": lambda: tap(7, 22, 0.03, damp=0.015),  # C6
    "confirm": lambda: finish(felt([(0, 0.0, 0.3, 40), (4, 0.12, 0.45, 44)], dim=1600), **MEDIUM),   # C5 -> G5
    "back": lambda: finish(felt([(-3, 0.0, 0.3, 40), (-7, 0.12, 0.45, 36)], dim=1500), **MEDIUM),   # G4 -> C4
    "notification": lambda: finish(felt([(1, 0.0, 0.35, 40), (3, 0.14, 0.6, 44)], dim=1600),       # D5 -> F#5
                                   wet=0.3, rt60=(1.2, 0.9, 0.4)),
    **SHARED,
}

SETS = {"soft": SOFT, "felt": FELT}
ORDER = ["hover_1", "hover_2", "hover_3", "click_1", "click_2", "click_3", "confirm", "back", "error",
         "menu_open", "menu_close", "toggle_on", "toggle_off", "slider_tick", "notification", "game_start"]


def level_for(name):
    return LEVELS[name.rsplit("_", 1)[0] if name[-1].isdigit() else name]


def render_set(set_name, names):
    out_dir = OUTPUT / f"ui_{set_name}"
    out_dir.mkdir(parents=True, exist_ok=True)
    rendered = []
    for name in names:
        audio = SETS[set_name][name]()
        audio *= 10 ** (level_for(name) / 20) / np.abs(audio).max()
        sf.write(out_dir / f"{name}.wav", audio.astype(np.float32), SR, subtype="PCM_24")
        rendered.append((name, audio))

    gap = np.zeros((int(0.7 * SR), 2))
    preview, t = [], 0.0
    print(f"set {set_name}, preview order:")
    for name, audio in rendered:
        print(f"  {t:5.1f}s  {name:13} {len(audio) / SR:4.2f}s  peak {level_for(name)} dBFS")
        preview += [audio, gap]
        t += (len(audio) + len(gap)) / SR
    sf.write(out_dir / "_preview.wav", np.concatenate(preview).astype(np.float32), SR, subtype="PCM_24")
    print(f"  sounds:  {out_dir}/<name>.wav ({len(rendered)} files)")
    print(f"  preview: {out_dir / '_preview.wav'}")


if __name__ == "__main__":
    args = sys.argv[1:]
    sets = [a for a in args if a in SETS] or list(SETS)
    names = [a for a in args if a not in SETS] or ORDER
    unknown = [n for n in names if n not in ORDER]
    if unknown:
        sys.exit(f"unknown sounds {unknown}; sets: {', '.join(SETS)}; sounds: {', '.join(ORDER)}")
    for s in sets:
        render_set(s, names)
