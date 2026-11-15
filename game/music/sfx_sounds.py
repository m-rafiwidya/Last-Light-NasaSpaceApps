"""Gameplay sound effects in the Deep Space style (CLAUDE.md, "Gameplay sound effects").

Soft, muffled, distant and calm. On the Moon everything outside is heard through the suit or the
rover's structure (steep lowpass, no air whooshes); the workshop is a small, dead room. Nothing
rings: no bells, chimes or FM. Tonal sounds are scale degrees of the music's key (ui_sounds.hz)
and the game plays them at their exact pitch; non-tonal ones (steps, impacts, bumps, rolling)
get a small random pitch in the game instead.

Some sounds are built from CC0 samples in samples/ (samples/SOURCES.md says where each came from).

    .venv/bin/python sfx_sounds.py                     # every sound -> output/sfx/ + _preview.wav
    .venv/bin/python sfx_sounds.py grab step_regolith  # only some (a base name renders all its variations)

One-shots are WAV, loops OGG (<name>_loop and amb_*). 3D sounds are mono; link_*, battery_low and
the ambience beds are stereo. Loops are built periodic, so they loop sample-exactly: noise from
random phases over exactly the loop length, grains wrapped round the end, every rate a whole
number of cycles per loop, and filters run circularly.
"""
import sys
from fractions import Fraction
from pathlib import Path

import numpy as np
import pedalboard
import soundfile as sf
from scipy.signal import resample_poly

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE / "tracks"))
import render  # noqa: E402
import synth  # noqa: E402
import ui_sounds as ui  # noqa: E402

SR = ui.SR
SAMPLES = HERE / "samples"
OUTPUT = HERE / "output" / "sfx"
hz = ui.hz
LP = pedalboard.LowpassFilter
HP = pedalboard.HighpassFilter

# Peak level (dBFS) per sound (base name), before the game's own volume per play. Frequent sounds
# quietest; alerts and big events loudest; the ambience beds far under everything.
LEVELS = {
    "step_regolith": -30, "step_floor": -30, "land_regolith": -24, "land_floor": -24,
    "grab": -26, "drop": -28, "throw": -28,
    "impact_regolith_light": -30, "impact_regolith_medium": -26, "impact_regolith_heavy": -22,
    "impact_hard_light": -30, "impact_hard_medium": -26, "impact_hard_heavy": -22,
    "part_seat": -22, "part_release": -24, "part_refused": -22,
    "power_up": -20, "power_down": -21, "link_open": -20, "link_close": -22, "battery_low": -21,
    "bump": -22, "rolling_loop": -22,
    "door_start": -22, "door_loop": -26, "door_stop": -21,
    "charger_connect": -22, "charger_full": -20, "charger_fault": -23,
    "amb_workshop": -30, "amb_moon": -36,
    "engine_rumble_loop": -22, "radio_static_loop": -46, "radio_click_on": -30, "radio_click_off": -31,
}
STEREO = {"link_open", "link_close", "battery_low", "amb_workshop", "amb_moon",
          "radio_static_loop", "radio_click_on", "radio_click_off"}

# ---------------------------------------------------------------- building blocks


def t_axis(seconds):
    return np.arange(int(seconds * SR)) / SR


def stereo(m):
    return np.stack([m, m], axis=1)


def mono(x):
    return x.mean(axis=1) if x.ndim == 2 else x


def filt(m, *plugins):
    """Run mono `m` through pedalboard plugins."""
    return mono(synth._pb(pedalboard.Pedalboard(list(plugins)), stereo(m), SR))


def at(m, start):
    return np.concatenate([np.zeros(int(start * SR)), m])


def mixm(*parts):
    out = np.zeros(max(len(p) for p in parts))
    for p in parts:
        out[:len(p)] += p
    return out


def sample(name, pitch=1.0, pack="kenney_impact"):
    """A CC0 sample as mono at SR, played `pitch` times as fast (varispeed), peak 1, no lead-in."""
    x, sr = sf.read(SAMPLES / pack / f"{name}.ogg", always_2d=True)
    ratio = Fraction(SR, sr) / Fraction(pitch).limit_denominator(50)
    m = resample_poly(x.mean(axis=1), ratio.numerator, ratio.denominator)
    m /= np.abs(m).max() + 1e-12
    return m[np.nonzero(np.abs(m) > 1e-3)[0][0]:]


def damp(m, tau, hold=0.012):
    """Cut any ring short: exponential decay with time constant `tau` after `hold` seconds."""
    t = np.arange(len(m)) / SR
    return m * np.exp(-np.clip(t - hold, 0, None) / tau)


def noise(seconds, seed):
    return np.random.default_rng(seed).standard_normal(int(seconds * SR))


def env(seconds, attack, decay):
    """Raised-cosine attack, then exponential decay."""
    t = t_axis(seconds)
    return (0.5 - 0.5 * np.cos(np.pi * np.clip(t / attack, 0, 1))) * np.exp(-np.clip(t - attack, 0, None) / decay)


def tone(d0, d1=None, seconds=0.5, decay=0.12, glide=0.06, attack=0.01, body=0.0):
    """Mono sine blip on scale degrees (ui_sounds.blip), gliding from degree d0 to d1."""
    return mono(ui.blip(hz(d0), hz(d0 if d1 is None else d1), seconds=seconds, decay=decay,
                        glide=glide, attack=attack, body=body))


def done(x, lowpass=2500, wet=0.1, rt60=(0.4, 0.3, 0.15)):
    """ui_sounds.finish (short synthetic room, lowpass, trimmed tail) on mono or stereo audio;
    keeps mono mono."""
    out = ui.finish(stereo(x) if x.ndim == 1 else x, wet=wet, rt60=rt60, lowpass=lowpass)
    return mono(out) if x.ndim == 1 else out


# Loops


def circular(fn, x):
    """Apply a filter to a loop without a seam: run it over three copies, keep the middle one."""
    n = len(x)
    return fn(np.concatenate([x, x, x]))[n:2 * n]


def loop_noise(seconds, seed, tilt=0.0, low=None, high=None):
    """Seamless noise: random phases over exactly `seconds`. `tilt` 1 = pink, 2 = brown; `low` /
    `high` are steep band edges (Hz)."""
    n = int(seconds * SR)
    f = np.fft.rfftfreq(n, 1 / SR)
    f[0] = 1.0
    mag = f ** (-tilt / 2)
    if high:
        mag /= np.sqrt(1 + (f / high) ** 8)
    if low:
        mag /= np.sqrt(1 + (low / f) ** 8)
    mag[0] = 0.0
    phases = np.exp(2j * np.pi * np.random.default_rng(seed).random(len(f)))
    x = np.fft.irfft(mag * phases, n)
    return x / np.abs(x).max()


def loop_sine(freq, seconds, phase=0.0):
    return np.sin(2 * np.pi * synth.snap(freq, seconds) * t_axis(seconds) + phase)


def wrap_add(out, grain, start):
    np.add.at(out, (start + np.arange(len(grain))) % len(out), grain)


def bumps(seconds, times, width):
    """Periodic envelope of raised-cosine swells `width` seconds long, centred on `times`."""
    t = t_axis(seconds)
    e = np.zeros(len(t))
    for c in times:
        d = (t - c + seconds / 2) % seconds - seconds / 2      # wrapped distance to the centre
        e += np.where(np.abs(d) < width / 2, 0.5 + 0.5 * np.cos(2 * np.pi * d / width), 0.0)
    return e


# ---------------------------------------------------------------- player

def crunch(i, pitch=0.8, cutoff=1300):
    """Regolith crunch through the boot: the snow step, slowed and dimmed."""
    return filt(sample(f"footstep_snow_00{i % 5}", pitch), HP(80), LP(cutoff), LP(cutoff))


def step_regolith(i):
    body = filt(sample(f"impactSoft_medium_00{i % 5}"), LP(400))
    return done(mixm(0.8 * crunch(i), 0.5 * body), lowpass=1500, wet=0.04)


def step_floor(i):
    tap = filt(sample(f"footstep_concrete_00{i % 5}", 0.85), HP(90), LP(1600), LP(1600))
    body = filt(sample(f"impactSoft_medium_00{(i + 2) % 5}"), LP(350))
    return done(mixm(0.7 * damp(tap, 0.05), 0.6 * body), lowpass=1800, wet=0.18, rt60=(0.5, 0.35, 0.15))


def land(surface, i):
    thud = filt(sample(f"impactSoft_heavy_00{i % 5}", 0.9), LP(500))
    if surface == "regolith":
        top = mixm(crunch(i, 0.75), at(0.6 * crunch(i + 2, 0.7), 0.035))
        return done(mixm(thud, 0.55 * top), lowpass=1300, wet=0.04)
    tap = filt(sample(f"footstep_concrete_00{i % 5}", 0.75), LP(1400), LP(1400))
    return done(mixm(thud, 0.5 * damp(tap, 0.05)), lowpass=1600, wet=0.18, rt60=(0.5, 0.35, 0.15))


# ---------------------------------------------------------------- holding

def breath(seconds, seed, lo, hi, attack, decay):
    n = filt(noise(seconds, seed), HP(lo), LP(hi), LP(hi))
    return n / np.abs(n).max() * env(seconds, attack, decay)


def grab():
    """A soft low swell up G3 -> C4 with a breath of filtered noise."""
    return done(mixm(tone(-10, -7, 0.5, decay=0.14, glide=0.09, attack=0.025, body=0.15),
                     0.25 * breath(0.4, 1, 200, 700, 0.02, 0.08)), lowpass=1800, wet=0.12)


def drop():
    return done(mixm(tone(-7, -10, 0.45, decay=0.1, glide=0.08, attack=0.02, body=0.1),
                     0.18 * breath(0.35, 2, 200, 600, 0.015, 0.07)), lowpass=1600, wet=0.12)


def throw():
    """A soft low push of noise (no air whoosh, no pitch)."""
    n = noise(0.5, 3)
    cutoff = np.interp(t_axis(0.5), [0.0, 0.06, 0.4], [250.0, 900.0, 300.0])
    swept = synth.tv_filter(n, cutoff, SR, kind="band", q=0.9)
    thump = filt(noise(0.3, 4), LP(120), LP(120))
    x = mixm(swept / np.abs(swept).max() * env(0.5, 0.03, 0.12),
             0.6 * thump / np.abs(thump).max() * env(0.3, 0.01, 0.06))
    return done(x, lowpass=1200, wet=0.08)


# ---------------------------------------------------------------- props and parts

IMPACTS = {
    # (surface, weight): build(variation)
    ("regolith", "light"): lambda i: mixm(filt(sample(f"impactSoft_medium_00{i}", 1.25), LP(700)),
                                         0.35 * crunch(i, 1.0, 1100)),
    ("regolith", "medium"): lambda i: mixm(filt(sample(f"impactSoft_medium_00{i + 1}", 0.9), LP(600)),
                                          0.45 * crunch(i + 1, 0.8, 1100)),
    ("regolith", "heavy"): lambda i: mixm(filt(sample(f"impactSoft_heavy_00{i}", 1.0), LP(500)),
                                         0.5 * crunch(i + 2, 0.7, 1000)),
    ("hard", "light"): lambda i: damp(filt(sample(f"impactGeneric_light_00{i}", 0.9), LP(1500), LP(1500)), 0.04),
    ("hard", "medium"): lambda i: mixm(damp(filt(sample(f"impactWood_heavy_00{i}", 1.0), LP(1200)), 0.07),
                                      0.4 * damp(filt(sample(f"impactGeneric_light_00{i + 1}", 0.8), LP(1200)), 0.04)),
    ("hard", "heavy"): lambda i: mixm(damp(filt(sample(f"impactWood_heavy_00{i + 1}", 0.8), LP(1000)), 0.09),
                                     0.7 * filt(sample(f"impactSoft_heavy_00{i}", 1.0), LP(500))),
}


def impact(surface, weight, i):
    if surface == "regolith":
        return done(IMPACTS[(surface, weight)](i), lowpass=1300, wet=0.04)
    return done(IMPACTS[(surface, weight)](i), lowpass=1600, wet=0.15, rt60=(0.5, 0.35, 0.15))


def clunk(i=0, pitch=1.1, cutoff=700):
    """A soft latch: a dull thud with the faintest click on top."""
    return mixm(filt(sample(f"impactSoft_medium_00{i}", pitch), LP(cutoff)),
                0.25 * damp(filt(sample(f"impactGeneric_light_00{i}", 1.0), LP(1200)), 0.03))


SEAT_TONES = {1: (-3, 0), 2: (-5, -2), 3: (-6, -3)}     # G4->C5, E4->A4, D4->G4


def part_seat(i):
    d0, d1 = SEAT_TONES[i]
    rise = tone(d0, d1, 0.4, decay=0.09, glide=0.03, attack=0.01)
    return done(mixm(clunk(i), at(0.35 * rise, 0.04)), lowpass=1800, wet=0.12)


def part_release():
    fall = tone(0, -3, 0.4, decay=0.08, glide=0.03, attack=0.01)
    lift = mixm(0.7 * damp(filt(sample("impactGeneric_light_002", 0.8), LP(1000)), 0.04),
                0.4 * filt(sample("impactSoft_medium_003", 1.2), LP(600)))
    return done(mixm(lift, at(0.3 * fall, 0.03)), lowpass=1700, wet=0.12)


def part_refused():
    """Two low, muffled thuds falling G2 -> C2 (the UI error's sound, doubled)."""
    thud = tone(-17, -21, 0.3, decay=0.09, glide=0.06, attack=0.004, body=0.25)
    return done(mixm(thud, at(0.7 * thud, 0.16)), lowpass=500, wet=0.15, rt60=(0.6, 0.4, 0.2))


# ---------------------------------------------------------------- rover

POWER_CHORD = (-14, -10, -6)      # C3 G3 D4: open fifth plus ninth


def power_up():
    """A soft rising bloom: the pad opens, then C4 and G4 bloom inside it."""
    pad = mono(ui.swell(POWER_CHORD, 0.8, [(0.0, 25), (1.0, 100)], attack=0.7, release=0.6))
    glass = mono(ui.bloom([(-7, 0.35, 55), (-3, 0.55, 60)], attack=0.08, hold=0.2, release=0.5))
    return done(mixm(pad, 0.7 * glass), lowpass=2000, wet=0.15, rt60=(0.8, 0.6, 0.3))


def power_down():
    """The pad closing over a slow sine falling G3 -> C3."""
    pad = mono(ui.swell(POWER_CHORD, 0.6, [(0.0, 100), (0.9, 20)], attack=0.08, release=0.9))
    fall = tone(-10, -14, 1.4, decay=0.35, glide=0.9, attack=0.03, body=0.1)
    return done(mixm(pad, 0.5 * fall), lowpass=1500, wet=0.15, rt60=(0.8, 0.6, 0.3))


LINK_CHORD = (-14, -10, -5, -1)   # C3 G3 E4 B4: Cmaj7 without the third below


def data(seconds, seed, level_points):
    """Faint data texture: band-passed noise gated in random 40 ms steps."""
    rng = np.random.default_rng(seed)
    t = t_axis(seconds)
    steps = rng.random(int(seconds * 25) + 1) ** 2
    gate = steps[(t * 25).astype(int)]
    gate = filt(gate, LP(60))
    n = filt(noise(seconds, seed), HP(900), LP(1600), LP(1600))
    shape = np.interp(t, *zip(*level_points))
    return n / np.abs(n).max() * gate * shape


def link_open():
    pad = ui.swell(LINK_CHORD, 0.7, [(0.0, 20), (0.9, 95)], attack=0.6, release=0.6)
    glass = ui.bloom([(1, 0.45, 50)], attack=0.1, hold=0.2, release=0.5)
    x = ui.mix(pad, 0.5 * glass, stereo(0.06 * data(1.4, 5, [(0, 0), (0.5, 1), (1.4, 0)])))
    return done(x, lowpass=2200, wet=0.2, rt60=(0.9, 0.7, 0.3))


def link_close():
    pad = ui.swell(LINK_CHORD, 0.35, [(0.0, 95), (0.7, 20)], attack=0.1, release=0.7)
    x = ui.mix(pad, stereo(0.05 * data(0.8, 6, [(0, 1), (0.5, 0), (0.8, 0)])))
    return done(x, lowpass=2000, wet=0.2, rt60=(0.9, 0.7, 0.3))


def battery_low():
    """A soft falling two-note pulse, E4 then B3, low and round (not the UI's back)."""
    a = tone(-5, seconds=0.45, decay=0.14, attack=0.03, body=0.1)
    b = tone(-8, seconds=0.5, decay=0.16, attack=0.03, body=0.1)
    return done(stereo(mixm(a, at(0.9 * b, 0.24))), lowpass=1800, wet=0.2, rt60=(0.9, 0.7, 0.3))


def thump(seconds=0.35, f0=55.0, f1=38.0, decay=0.12):
    """A deep, unpitched-sounding body thump (a sine sliding down below the key's range)."""
    t = t_axis(seconds)
    freq = f0 * (f1 / f0) ** np.clip(t / 0.15, 0, 1)
    return np.sin(2 * np.pi * np.cumsum(freq) / SR) * env(seconds, 0.004, decay)


def bump(i):
    x = mixm(filt(sample(f"impactSoft_heavy_00{i}", 0.8), LP(600)),
             0.5 * damp(filt(sample(f"impactWood_heavy_00{i + 1}", 0.9), LP(600)), 0.08),
             0.6 * thump(), 0.2 * crunch(i + 1, 0.7, 900))
    return done(x, lowpass=900, wet=0.05)


ROLL_SECONDS = 4.0


def rolling_loop():
    """Wheels on regolith: dense grains cut from the regolith crunch, wrapped round a 4 s loop,
    over a low tyre rumble. The game sets its level and pitch from the rover's speed."""
    rng = np.random.default_rng(11)
    n = int(ROLL_SECONDS * SR)
    sources = [sample(f"footstep_snow_00{i}", p) for i in range(5) for p in (0.6, 0.75, 0.9)]
    out = np.zeros(n)
    for _ in range(int(ROLL_SECONDS * 90)):
        src = sources[rng.integers(len(sources))]
        length = int(rng.uniform(0.025, 0.07) * SR)
        off = rng.integers(0, max(1, min(len(src), int(0.16 * SR)) - length))
        grain = src[off:off + length] * np.hanning(length) * rng.lognormal(0, 0.5)
        wrap_add(out, grain, rng.integers(n))
    out /= np.abs(out).max()
    out = circular(lambda x: filt(x, HP(60), LP(1400), LP(1400)), out)
    rumble = loop_noise(ROLL_SECONDS, 12, tilt=1.0, low=30, high=140)
    return 0.8 * out / np.abs(out).max() + 0.35 * rumble


# ---------------------------------------------------------------- workshop

DOOR_SECONDS = 3.0


def door_start():
    """Unlatch: a dull double knock as the bay door's locks let go."""
    x = mixm(damp(filt(sample("impactWood_heavy_002", 0.7), LP(700)), 0.08),
             0.6 * filt(sample("impactSoft_heavy_001", 1.0), LP(500)),
             at(0.5 * damp(filt(sample("impactWood_heavy_004", 0.75), LP(700)), 0.07), 0.11))
    return done(x, lowpass=1000, wet=0.15, rt60=(0.7, 0.5, 0.2))


def door_loop():
    """The bay door's drive: low rumble, a motor hum on C2 with soft gear grind, slow wobble."""
    s = DOOR_SECONDS
    rumble = loop_noise(s, 21, tilt=2.0, low=30, high=250)
    grind = loop_noise(s, 22, tilt=1.0, low=300, high=600)
    hum = loop_sine(hz(-21), s) + 0.35 * loop_sine(2 * hz(-21), s, 1.0) + 0.12 * loop_sine(3 * hz(-21), s, 2.0)
    wobble = 1.0 + 0.15 * loop_sine(1.4, s) + 0.08 * loop_sine(3.1, s, 0.5)
    return (0.6 * rumble + 0.25 * grind + 0.3 * hum / 1.47) * wobble


def door_stop():
    """The door seals: a heavy soft thud with a short puff of air."""
    puff = breath(0.4, 23, 150, 900, 0.01, 0.15)
    x = mixm(filt(sample("impactSoft_heavy_003", 0.75), LP(450)),
             0.6 * damp(filt(sample("impactWood_heavy_001", 0.65), LP(600)), 0.1),
             0.15 * puff, 0.5 * thump(0.4, 50, 35, 0.15))
    return done(x, lowpass=900, wet=0.15, rt60=(0.7, 0.5, 0.2))


def charger_connect():
    x = mixm(clunk(2, 1.0, 800), 0.5 * damp(filt(sample("impactWood_heavy_003", 1.0), LP(800)), 0.06),
             0.5 * mono(ui.bloom([(-7, 0.08, 60), (-3, 0.2, 64)], attack=0.04, hold=0.12, release=0.4)))
    return done(x, lowpass=1800, wet=0.15)


def charger_full():
    """A soft rising bloom C4 G4 D5 E5 (pad_sine, no chime)."""
    x = mono(ui.bloom([(-7, 0.0, 56), (-3, 0.18, 60), (1, 0.36, 64), (2, 0.54, 62)],
                      attack=0.06, hold=0.3, release=0.8))
    return done(x, lowpass=2000, wet=0.25, rt60=(1.0, 0.8, 0.3))


def charger_fault():
    """Two soft, even low pulses on C3."""
    p = tone(-14, seconds=0.35, decay=0.11, attack=0.02, body=0.2)
    return done(mixm(p, at(p, 0.3)), lowpass=600, wet=0.15, rt60=(0.6, 0.4, 0.2))


# ---------------------------------------------------------------- ambience

WORKSHOP_SECONDS = 40.0
MOON_SECONDS = 60.0


def amb_workshop():
    """Inside the pressurised workshop: soft air handling and a faint hum on C2 / G2, breathing
    very slowly. Stereo from two noise seeds."""
    s = WORKSHOP_SECONDS
    sides = []
    for c in range(2):
        air = loop_noise(s, 31 + c, tilt=1.0, low=60, high=900)
        breathe = 1.0 + 0.12 * loop_sine(1 / 13.0, s, c * 1.3) + 0.06 * loop_sine(1 / 7.0, s, 2.0 + c)
        sides.append(air * breathe)
    hum = 0.06 * (loop_sine(hz(-21), s) + 0.6 * loop_sine(hz(-17), s, 1.0)) * (1.0 + 0.3 * loop_sine(1 / 20.0, s))
    return np.stack([0.7 * sides[0] + hum, 0.7 * sides[1] + hum], axis=1)


def amb_moon():
    """Outside on the Moon there is no air: near-silence, a very low rumble carried through the
    suit, a whisper of the suit's own air, and three rare soft swells of texture a minute."""
    s = MOON_SECONDS
    sides = []
    for c in range(2):
        rumble = loop_noise(s, 41 + c, tilt=2.0, low=30, high=120)
        suit = loop_noise(s, 43 + c, tilt=1.0, low=150, high=500)
        swells = loop_noise(s, 45 + c, tilt=1.0, low=250, high=700) * bumps(s, (7.0, 26.0, 45.5), 5.0 + c)
        sides.append(0.8 * rumble + 0.12 * suit + 0.35 * swells)
    return np.stack(sides, axis=1)


# ---------------------------------------------------------------- lander and radio

RUMBLE_SECONDS = 6.0
STATIC_SECONDS = 8.0


def engine_rumble_loop():
    """The descent engine felt through the lander's structure (no sound crosses the vacuum): a deep
    unpitched rumble with a slow, uneven flutter of combustion, no hiss."""
    s = RUMBLE_SECONDS
    deep = loop_noise(s, 61, tilt=2.0, low=22, high=110)
    body = loop_noise(s, 62, tilt=1.0, low=60, high=320)
    flutter = 1.0 + 0.18 * loop_sine(7.0, s) + 0.12 * loop_sine(11.5, s, 1.3) + 0.1 * loop_noise(s, 63, tilt=2.0, high=18)
    return circular(lambda x: filt(x, LP(400)), (0.85 * deep + 0.3 * body) * flutter)


def radio_hiss(seconds, seed):
    return loop_noise(seconds, seed, tilt=1.0, low=500, high=2200)


def radio_static_loop():
    """The suit radio's open carrier under a line: a faint, soft band-limited hiss breathing slowly,
    no crackle. Stereo from two noise seeds."""
    s = STATIC_SECONDS
    sides = []
    for c in range(2):
        hiss = circular(lambda x: filt(x, LP(1800)), radio_hiss(s, 72 + c))
        sides.append(hiss * (1.0 + 0.12 * loop_sine(1 / 4.0, s, c)))
    return np.stack(sides, axis=1)


def radio_burst(seconds, seed, attack, decay):
    n = filt(noise(seconds, seed), HP(600), LP(2200))
    return n / np.abs(n).max() * env(seconds, attack, decay)


def radio_click_on():
    """Push-to-talk keyed at the far end: a soft dull click, then the carrier opening."""
    click = filt(noise(0.03, 81), HP(300), LP(1500)) * env(0.03, 0.001, 0.004)
    x = mixm(0.9 * click / np.abs(click).max(), at(0.35 * radio_burst(0.12, 82, 0.01, 0.04), 0.008))
    return done(stereo(x), lowpass=2200, wet=0.02)


def radio_click_off():
    """Released: a short squelch tail cut by a softer click."""
    tail = radio_burst(0.09, 83, 0.004, 0.05)
    click = filt(noise(0.03, 84), HP(300), LP(1200)) * env(0.03, 0.001, 0.004)
    x = mixm(0.4 * tail, at(0.7 * click / np.abs(click).max(), 0.07))
    return done(stereo(x), lowpass=2000, wet=0.02)


# ---------------------------------------------------------------- catalogue

SOUNDS = {}
for i in range(5):
    SOUNDS[f"step_regolith_{i + 1}"] = lambda i=i: step_regolith(i)
    SOUNDS[f"step_floor_{i + 1}"] = lambda i=i: step_floor(i)
for i in range(3):
    SOUNDS[f"land_regolith_{i + 1}"] = lambda i=i: land("regolith", i)
    SOUNDS[f"land_floor_{i + 1}"] = lambda i=i: land("floor", i)
SOUNDS.update(grab=grab, drop=drop, throw=throw)
for surface in ("regolith", "hard"):
    for weight in ("light", "medium", "heavy"):
        for i in range(3):
            SOUNDS[f"impact_{surface}_{weight}_{i + 1}"] = lambda s=surface, w=weight, i=i: impact(s, w, i)
for i in range(3):
    SOUNDS[f"part_seat_{i + 1}"] = lambda i=i: part_seat(i + 1)
SOUNDS.update(part_release=part_release, part_refused=part_refused, power_up=power_up,
              power_down=power_down, link_open=link_open, link_close=link_close, battery_low=battery_low)
for i in range(3):
    SOUNDS[f"bump_{i + 1}"] = lambda i=i: bump(i)
SOUNDS.update(rolling_loop=rolling_loop, door_start=door_start, door_loop=door_loop, door_stop=door_stop,
              charger_connect=charger_connect, charger_full=charger_full, charger_fault=charger_fault,
              amb_workshop=amb_workshop, amb_moon=amb_moon, engine_rumble_loop=engine_rumble_loop,
              radio_static_loop=radio_static_loop, radio_click_on=radio_click_on, radio_click_off=radio_click_off)


def base_name(name):
    return name.rsplit("_", 1)[0] if name[-1].isdigit() else name


def is_loop(name):
    return name.endswith("_loop") or name.startswith("amb_")


def render_sound(name):
    audio = SOUNDS[name]()
    if base_name(name) in STEREO and audio.ndim == 1:
        audio = stereo(audio)
    audio = audio * 10 ** (LEVELS[base_name(name)] / 20) / np.abs(audio).max()
    if is_loop(name):
        jump = np.abs(np.atleast_2d((audio[0] - audio[-1]).T)).max()
        step = np.percentile(np.abs(np.diff(audio, axis=0)), 99)
        print(f"  seam {name}: jump {jump:.5f}, 99th-percentile step {step:.5f}"
              f" {'ok' if jump <= step else 'CHECK'}")
        render.write_ogg(OUTPUT / f"{name}.ogg", audio if audio.ndim == 2 else audio[:, None])
    else:
        sf.write(OUTPUT / f"{name}.wav", audio.astype(np.float32), SR, subtype="PCM_24")
    return audio


def preview(rendered):
    """Every sound in order with gaps; loops twice round (across the seam), the ambience beds
    15 s across their seam, and the bay door as the game plays it (start, loop, stop)."""
    gap = np.zeros((int(0.6 * SR), 2))
    parts, t = [], 0.0
    print("preview order:")

    def add(label, audio):
        nonlocal t
        audio = stereo(audio) if audio.ndim == 1 else audio
        print(f"  {t:6.1f}s  {label:24} {len(audio) / SR:5.2f}s")
        parts.extend([audio, gap])
        t += (len(audio) + len(gap)) / SR

    for name, audio in rendered.items():
        if name.startswith("amb_"):
            half = int(7.5 * SR)
            add(f"{name} (seam at 7.5 s)", np.concatenate([audio[-half:], audio[:half]]))
        elif is_loop(name):
            add(f"{name} (x2)", np.concatenate([audio, audio]))
        else:
            add(name, audio)
    if {"door_start", "door_loop", "door_stop"} <= rendered.keys():
        loop = np.tile(rendered["door_loop"], 3)[:int(2.5 * SR)]          # the door takes 2.5 s
        fade = np.ones(len(loop))
        fade[:int(0.3 * SR)] = np.linspace(0, 1, int(0.3 * SR))
        fade[-int(0.3 * SR):] = np.linspace(1, 0, int(0.3 * SR))
        seq = mixm(rendered["door_start"], loop * fade, at(rendered["door_stop"], 2.3))
        add("bay door sequence", seq)
    sf.write(OUTPUT / "_preview.wav", np.concatenate(parts).astype(np.float32), SR, subtype="PCM_24")
    print(f"  preview: {OUTPUT / '_preview.wav'}")


if __name__ == "__main__":
    wanted = sys.argv[1:]
    names = [n for n in SOUNDS if not wanted or n in wanted or base_name(n) in wanted]
    unknown = [w for w in wanted if w not in SOUNDS and w not in {base_name(n) for n in SOUNDS}]
    if unknown:
        sys.exit(f"unknown sounds {unknown}; sounds: {', '.join(SOUNDS)}")
    OUTPUT.mkdir(parents=True, exist_ok=True)
    rendered = {}
    for n in names:
        rendered[n] = render_sound(n)
    print(f"  sounds: {OUTPUT}/ ({len(rendered)} files)")
    preview(rendered)
