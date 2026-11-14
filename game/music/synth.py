"""Synthesis engine for Deep Space stems: pads, drones, FM bells/chimes, wind texture and their effects.

render.py sends every stem whose name is a voice name, or starts with one plus "_" ("pad_high" ->
pad, "bell_far" -> bell), to render_stem(); other stems go through FluidSynth. The MIDI gives
pitch, velocity, start and end; CC11 is volume and CC74 brightness (filter cutoff, 64 = neutral).

All LFO rates are snapped to whole cycles per loop, so modulation is periodic in the loop and
folding the tail back onto the start (render.py) continues it exactly.
"""
from functools import lru_cache

import numpy as np
import pedalboard
import scipy.signal as sig

# ---------------------------------------------------------------- helpers


def snap(hz, loop_s):
    """Nearest rate with a whole number of cycles per loop (at least one)."""
    return max(1, round(hz * loop_s)) / loop_s


def midi_hz(p):
    return 440.0 * 2 ** ((p - 69) / 12)


def rng_for(note, salt=0):
    """Deterministic randomness per note, so renders are repeatable."""
    return np.random.default_rng([note.pitch, int(note.start * 1000), salt])


def velocity_gain(note):
    return (note.velocity / 127) ** 1.6


def envelope(n_hold, n_total, attack_n, release_n):
    """Raised-cosine attack, hold until note end, raised-cosine release from wherever it got to."""
    t = np.arange(n_total)
    env = 0.5 - 0.5 * np.cos(np.pi * np.clip(t / max(attack_n, 1), 0, 1))
    end_level = env[min(n_hold, n_total) - 1] if n_hold > 0 else 0.0
    rel = t >= n_hold
    env[rel] = end_level * (0.5 + 0.5 * np.cos(np.pi * np.clip((t[rel] - n_hold) / max(release_n, 1), 0, 1)))
    return env


def cc_curve(inst, number, times, default):
    """Controller value over `times` (linear between events, first value before the first event)."""
    events = sorted((c.time, c.value) for c in inst.control_changes if c.number == number)
    if not events:
        return np.full(len(times), float(default))
    ts, vs = zip(*events)
    return np.interp(times, ts, vs)


def pan(mono, position):
    """Equal-power pan, position -1 (left) .. 1 (right) -> (n, 2)."""
    angle = (position + 1) * np.pi / 4
    return np.stack([mono * np.cos(angle), mono * np.sin(angle)], axis=1)


def tv_filter(x, cutoff, sr, kind="low", q=0.707, block=256):
    """Biquad (RBJ) low- or band-pass of mono x with a per-sample cutoff, updated every block."""
    y = np.empty_like(x)
    zi = np.zeros(2)
    for k in range(0, len(x), block):
        fc = np.clip(cutoff[min(k + block // 2, len(x) - 1)], 20.0, 0.45 * sr)
        w0 = 2 * np.pi * fc / sr
        cos, alpha = np.cos(w0), np.sin(w0) / (2 * q)
        if kind == "low":
            b = [(1 - cos) / 2, 1 - cos, (1 - cos) / 2]
        else:
            b = [alpha, 0.0, -alpha]
        a = [1 + alpha, -2 * cos, 1 - alpha]
        y[k:k + block], zi = sig.lfilter(b, a, x[k:k + block], zi=zi)
    return y


def phase(freq, sr, start):
    return (start + np.cumsum(freq) / sr) % 1.0


def saw(ph, dt):
    """PolyBLEP band-limited saw from phase (0..1) and per-sample phase increment."""
    y = 2 * ph - 1
    lo = ph < dt
    x = ph[lo] / dt[lo]
    y[lo] -= x + x - x * x - 1
    hi = ph > 1 - dt
    x = (ph[hi] - 1) / dt[hi]
    y[hi] -= x * x + x + x + 1
    return y


# ---------------------------------------------------------------- voices
# Each voice returns stereo audio (n, 2) starting at the note's start.


def pad(note, inst, sr, loop_s, p):
    f = midi_hz(note.pitch)
    n_hold = int((note.end - note.start) * sr)
    n = n_hold + int(p["release"] * sr)
    t = note.start + np.arange(n) / sr
    rng = rng_for(note)
    env = envelope(n_hold, n, int(p["attack"] * sr), int(p["release"] * sr))
    detunes = p["detune"]
    out = np.zeros((n, 2))
    for i, cents in enumerate(detunes):
        drift = 1.5 * np.sin(2 * np.pi * snap(rng.uniform(0.03, 0.08), loop_s) * t + rng.uniform(0, 2 * np.pi))
        freq = f * 2 ** ((cents + drift) / 1200)
        ph = phase(freq, sr, rng.uniform())
        wave = saw(ph, freq / sr) if p["wave"] == "saw" else np.sin(2 * np.pi * ph)
        position = -0.7 + 1.4 * i / max(len(detunes) - 1, 1)
        out += pan(wave, position)
    out /= np.sqrt(len(detunes))
    if p["octave_sine"]:
        out += pan(p["octave_sine"] * np.sin(2 * np.pi * phase(np.full(n, 2 * f), sr, rng.uniform())), 0.0)

    sweep = 2 ** (p["sweep_oct"] * np.sin(2 * np.pi * snap(p["sweep_hz"], loop_s) * t + rng.uniform(0, 2 * np.pi)))
    bright = 2 ** ((cc_curve(inst, 74, t, 64) - 64) / 32)
    cutoff = np.clip(f * p["key"], p["cutoff_min"], p["cutoff_max"]) * sweep * bright * (0.4 + 0.6 * env)
    for c in range(2):
        out[:, c] = tv_filter(out[:, c], cutoff, sr)
    volume = (cc_curve(inst, 11, t, 127) / 127) ** 1.5
    return out * (env * volume * velocity_gain(note) * p["gain"])[:, None]


def drone(note, inst, sr, loop_s, p):
    f = midi_hz(note.pitch)
    n_hold = int((note.end - note.start) * sr)
    n = n_hold + int(p["release"] * sr)
    t = note.start + np.arange(n) / sr
    rng = rng_for(note)
    env = envelope(n_hold, n, int(p["attack"] * sr), int(p["release"] * sr))
    drift = p["drift_cents"] * np.sin(2 * np.pi * snap(0.03, loop_s) * t + rng.uniform(0, 2 * np.pi))
    out = np.zeros((n, 2))
    for ratio, level in p["partials"]:
        for side, beat in ((-0.5, -p["beat_cents"]), (0.5, p["beat_cents"])):
            freq = f * ratio * 2 ** ((drift + beat) / 1200)
            out += pan(level * np.sin(2 * np.pi * phase(freq, sr, rng.uniform())), side)
    swell = 1 + 0.25 * np.sin(2 * np.pi * snap(0.05, loop_s) * t + rng.uniform(0, 2 * np.pi))
    cutoff = f * p["key"] * 2 ** (0.5 * np.sin(2 * np.pi * snap(0.02, loop_s) * t))
    for c in range(2):
        out[:, c] = tv_filter(out[:, c], cutoff, sr)
    volume = (cc_curve(inst, 11, t, 127) / 127) ** 1.5
    return out * (env * swell * volume * velocity_gain(note) * p["gain"])[:, None]


def bell(note, inst, sr, loop_s, p):
    """Two-operator FM bell plus an inharmonic partial; rings out regardless of note length."""
    f = midi_hz(note.pitch)
    n = int(p["ring"] * sr)
    t = np.arange(n) / sr
    rng = rng_for(note)
    attack = np.clip(t / 0.004, 0, 1)
    amp = attack * np.exp(-t / p["decay"])
    index = p["index"] * (0.5 + note.velocity / 127) * np.exp(-t / p["index_decay"])
    tone = np.sin(2 * np.pi * f * t + index * np.sin(2 * np.pi * f * p["ratio"] * t))
    tone = tone * amp + p["partial2"] * np.sin(2 * np.pi * f * p["ratio2"] * t) * attack * np.exp(-t / (p["decay"] * 0.35))
    volume = cc_curve(inst, 11, note.start + t, 127) / 127
    return pan(tone * volume * velocity_gain(note) * p["gain"], rng.uniform(-0.5, 0.5))


def texture(note, inst, sr, loop_s, p):
    """Band-passed stereo noise, centred on the note's pitch, slowly sweeping and gusting."""
    f = midi_hz(note.pitch)
    n_hold = int((note.end - note.start) * sr)
    n = n_hold + int(p["release"] * sr)
    t = note.start + np.arange(n) / sr
    rng = rng_for(note)
    env = envelope(n_hold, n, int(p["attack"] * sr), int(p["release"] * sr))
    out = np.zeros((n, 2))
    for c in range(2):
        noise = rng.standard_normal(n)
        sweep = p["sweep_oct"] * np.sin(2 * np.pi * snap(p["sweep_hz"], loop_s) * t + rng.uniform(0, 2 * np.pi))
        out[:, c] = tv_filter(noise, f * 2 ** sweep, sr, kind="band", q=p["q"])
    gust = sum(np.sin(2 * np.pi * snap(hz, loop_s) * t + rng.uniform(0, 2 * np.pi)) for hz in (0.04, 0.09, 0.17))
    gust = 0.6 + 0.4 * gust / 3
    volume = (cc_curve(inst, 11, t, 127) / 127) ** 1.5
    return out * (env * gust * volume * velocity_gain(note) * p["gain"])[:, None]


# ---------------------------------------------------------------- effects
# All take and return float arrays shaped (n, 2).


def _pb(board, x, sr):
    return board(np.ascontiguousarray(x.T, dtype=np.float32), sr).T.astype(np.float64)


@lru_cache(maxsize=4)
def space_ir(sr, seconds=14.0, rt60=(10.0, 7.5, 3.5), predelay=0.04):
    """Huge, smooth synthetic hall: stereo decaying noise, with lows decaying slowest."""
    n = int(seconds * sr)
    t = np.arange(n) / sr
    rng = np.random.default_rng(7)
    bands = [sig.butter(2, 300, "lowpass", fs=sr, output="sos"),
             sig.butter(2, [300, 3000], "bandpass", fs=sr, output="sos"),
             sig.butter(2, 3000, "highpass", fs=sr, output="sos")]
    ir = np.zeros((2, n))
    for c in range(2):
        for sos, rt in zip(bands, rt60):
            ir[c] += sig.sosfilt(sos, rng.standard_normal(n)) * np.exp(-6.91 * t / rt)
    ir *= np.clip(t / 0.12, 0, 1)  # diffuse build-up instead of a hard first reflection
    ir = np.concatenate([np.zeros((2, int(predelay * sr))), ir], axis=1)
    ir /= np.sqrt((ir ** 2).sum(axis=1, keepdims=True))
    return ir.astype(np.float32)


def reverb(x, sr):
    """Wet-only huge reverb."""
    return _pb(pedalboard.Pedalboard([pedalboard.Convolution(space_ir(sr), 1.0, sr)]), x, sr)


def shimmer(x, sr):
    """Wet-only octave-up shimmer: pitch up an octave, soften, then into the huge reverb."""
    up = _pb(pedalboard.Pedalboard([pedalboard.PitchShift(12), pedalboard.HighpassFilter(600),
                                    pedalboard.LowpassFilter(7000)]), x, sr)
    return reverb(up, sr)


def chorus(x, sr, loop_s):
    return _pb(pedalboard.Pedalboard([pedalboard.Chorus(rate_hz=snap(0.12, loop_s), depth=0.3,
                                                        centre_delay_ms=12, feedback=0.0, mix=0.45)]), x, sr)


def echo(x, sr):
    """Wet-only soft echo, slightly different times left and right."""
    out = np.zeros_like(x)
    for c, seconds in enumerate((0.47, 0.62)):
        board = pedalboard.Pedalboard([pedalboard.Delay(seconds, feedback=0.45, mix=1.0),
                                       pedalboard.HighpassFilter(400), pedalboard.LowpassFilter(3500)])
        out[:, c] = board(np.ascontiguousarray(x[:, c], dtype=np.float32), sr)
    return out


def wow(x, sr, loop_s, cents):
    """Very slight tape-like pitch wobble: a slowly modulated delay read (no added latency)."""
    if not cents:
        return x
    t = np.arange(len(x)) / sr
    rates = (snap(0.21, loop_s), snap(0.067, loop_s))
    # A delay swinging by amplitude A at rate r detunes by up to 2*pi*r*A (as a ratio).
    depth = (2 ** (cents / 1200) - 1) / (2 * np.pi * rates[0])
    mod = depth * (0.7 * np.sin(2 * np.pi * rates[0] * t) + 0.3 * rates[0] / rates[1] * np.sin(2 * np.pi * rates[1] * t + 1.0))
    read = np.arange(len(x)) - mod * sr
    return np.stack([np.interp(read, np.arange(len(x)), x[:, c]) for c in range(2)], axis=1)


def soften(x, sr):
    return _pb(pedalboard.Pedalboard([pedalboard.HighpassFilter(25),
                                      pedalboard.HighShelfFilter(cutoff_frequency_hz=7000, gain_db=-4.0)]), x, sr)


def fx_chain(kind, x, sr, loop_s):
    if kind == "pad":
        x = chorus(x, sr, loop_s)
        x = 0.6 * x + 0.55 * reverb(x, sr) + 0.2 * shimmer(x, sr)
        return soften(wow(x, sr, loop_s, cents=5), sr)
    if kind == "drone":
        return soften(wow(0.8 * x + 0.35 * reverb(x, sr), sr, loop_s, cents=3), sr)
    if kind == "bell":
        e = 0.35 * echo(x, sr)
        x = 0.7 * x + e + 0.65 * reverb(x + e, sr) + 0.25 * shimmer(x, sr)
        return soften(wow(x, sr, loop_s, cents=6), sr)
    if kind == "texture":
        return soften(0.6 * x + 0.6 * reverb(x, sr), sr)
    raise ValueError(kind)


# ---------------------------------------------------------------- presets

VOICES = {
    # Warm detuned-saw pad, filter breathing slowly.
    "pad": dict(fn=pad, fx="pad", wave="saw", detune=(-11, -4, 4, 11), octave_sine=0.2,
                attack=4.0, release=7.0, key=4.0, cutoff_min=450, cutoff_max=3500,
                sweep_oct=0.8, sweep_hz=1 / 20, gain=0.5, preview=89),
    # Glassier pad from detuned sines.
    "pad_sine": dict(fn=pad, fx="pad", wave="sine", detune=(-7, 0, 7), octave_sine=0.3,
                     attack=5.0, release=8.0, key=8.0, cutoff_min=600, cutoff_max=6000,
                     sweep_oct=0.6, sweep_hz=1 / 25, gain=0.5, preview=88),
    # Very low sustained tone with slow beating, drift and swell.
    "drone": dict(fn=drone, fx="drone", partials=((1, 1.0), (2, 0.5), (3, 0.2), (4, 0.08)),
                  beat_cents=4, drift_cents=3, key=6.0, attack=6.0, release=9.0, gain=0.16, preview=95),
    # Soft FM bell, long decay.
    "bell": dict(fn=bell, fx="bell", ratio=3.5, index=1.4, index_decay=0.5, ratio2=2.76, partial2=0.12,
                 decay=2.8, ring=16.0, gain=1.0, preview=14),
    # Higher, glassier, shorter chime.
    "chime": dict(fn=bell, fx="bell", ratio=1.41, index=1.0, index_decay=0.3, ratio2=5.4, partial2=0.08,
                  decay=1.6, ring=10.0, gain=1.0, preview=112),
    # Distant wind: the note's pitch sets the band centre (around C5-C6 sounds airy).
    "texture": dict(fn=texture, fx="texture", q=0.8, sweep_oct=1.0, sweep_hz=1 / 23,
                    attack=6.0, release=8.0, gain=0.35, preview=122),
}

REVERB_TAIL_SECONDS = 18.0  # IR length plus shimmer and echo build-up


def voice_for(name):
    """Voice preset name for a stem/instrument name, or None for a soundfont instrument."""
    matches = [v for v in VOICES if name == v or name.startswith(v + "_")]
    return max(matches, key=len) if matches else None


def render_stem(instruments, voice, sr, loop_s):
    """Render all notes of `instruments` with `voice` and run the voice's effects; (n, 2)."""
    p = VOICES[voice]
    notes = [(inst, n) for inst in instruments for n in inst.notes]
    voices = [(int(round(n.start * sr)), p["fn"](n, inst, sr, loop_s, p)) for inst, n in notes]
    length = max(s + len(v) for s, v in voices) + int(REVERB_TAIL_SECONDS * sr)
    buf = np.zeros((length, 2))
    for s, v in voices:
        buf[s:s + len(v)] += v
    return fx_chain(p["fx"], buf, sr, loop_s).astype(np.float32)
