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
    attack = 0.5 - 0.5 * np.cos(np.pi * np.clip(t / p["attack"], 0, 1))  # soft mallet
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
    # Nearly silent, with a rare soft gust where two slow cycles happen to peak together.
    slow, slower = (0.5 + 0.5 * np.sin(2 * np.pi * snap(hz, loop_s) * t + rng.uniform(0, 2 * np.pi))
                    for hz in (1 / 25, 1 / 60))
    gust = 0.04 + 0.6 * slow ** 6 * slower
    volume = (cc_curve(inst, 11, t, 127) / 127) ** 1.5
    return out * (env * gust * volume * velocity_gain(note) * p["gain"])[:, None]


# ---------------------------------------------------------------- effects
# All take and return float arrays shaped (n, 2).


def _pb(board, x, sr):
    return board(np.ascontiguousarray(x.T, dtype=np.float32), sr).T.astype(np.float64)


@lru_cache(maxsize=8)
def space_ir(sr, rt60=(10.0, 7.5, 3.5), predelay=0.06):
    """Smooth synthetic hall: stereo decaying noise in three bands, lows decaying slowest."""
    n = int(max(rt60) * 1.3 * sr)
    t = np.arange(n) / sr
    rng = np.random.default_rng(7)
    bands = [sig.butter(2, 300, "lowpass", fs=sr, output="sos"),
             sig.butter(2, [300, 3000], "bandpass", fs=sr, output="sos"),
             sig.butter(2, 3000, "highpass", fs=sr, output="sos")]
    ir = np.zeros((2, n))
    for c in range(2):
        for sos, rt in zip(bands, rt60):
            ir[c] += sig.sosfilt(sos, rng.standard_normal(n)) * np.exp(-6.91 * t / rt)
    ir *= 0.5 - 0.5 * np.cos(np.pi * np.clip(t / 0.25, 0, 1))  # slow, diffuse build-up: no early reflection
    ir = np.concatenate([np.zeros((2, int(predelay * sr))), ir], axis=1)
    ir /= np.sqrt((ir ** 2).sum(axis=1, keepdims=True))
    return ir.astype(np.float32)


def reverb(x, sr, rt60, predelay=0.06):
    """Wet-only reverb."""
    return _pb(pedalboard.Pedalboard([pedalboard.Convolution(space_ir(sr, rt60, predelay), 1.0, sr)]), x, sr)


def soften_attacks(x, sr, amount=0.9):
    """Transient softener: where a fast envelope jumps ahead of a slow one (a hammer strike),
    turn the gain down, so notes swell in like felt instead of striking."""
    level = np.abs(x).max(axis=1) + 1e-9
    follow = lambda tau: sig.lfilter([1 - np.exp(-1 / (tau * sr))], [1, -np.exp(-1 / (tau * sr))], level)
    gain = np.clip(follow(0.06) / follow(0.002), 0, 1) ** amount
    gain = sig.lfilter([1 - np.exp(-1 / (0.004 * sr))], [1, -np.exp(-1 / (0.004 * sr))], gain)
    return x * gain[:, None]


def steep_lowpass(x, sr, hz):
    return _pb(pedalboard.Pedalboard([pedalboard.LowpassFilter(hz), pedalboard.LowpassFilter(hz)]), x, sr)


def shimmer(x, sr, rt60):
    """Wet-only octave-up shimmer, kept dark: pitch up, band-limit, then into the reverb."""
    up = _pb(pedalboard.Pedalboard([pedalboard.PitchShift(12), pedalboard.HighpassFilter(600),
                                    pedalboard.LowpassFilter(2500)]), x, sr)
    return reverb(up, sr, rt60)


def chorus(x, sr, loop_s, depth):
    return _pb(pedalboard.Pedalboard([pedalboard.Chorus(rate_hz=snap(0.12, loop_s), depth=depth,
                                                        centre_delay_ms=12, feedback=0.0, mix=0.5)]), x, sr)


def echo(x, sr):
    """Wet-only soft, dark echo, slightly different times left and right."""
    out = np.zeros_like(x)
    for c, seconds in enumerate((0.47, 0.62)):
        board = pedalboard.Pedalboard([pedalboard.Delay(seconds, feedback=0.4, mix=1.0),
                                       pedalboard.HighpassFilter(300), pedalboard.LowpassFilter(1500)])
        out[:, c] = board(np.ascontiguousarray(x[:, c], dtype=np.float32), sr)
    return out


def wow(x, sr, loop_s, cents, flutter_cents=0.0):
    """Tape-like pitch wobble: slow wow plus optional fast flutter, as a modulated delay read
    (no added latency). A delay swinging by amplitude A at rate r detunes by up to 2*pi*r*A."""
    if not cents and not flutter_cents:
        return x
    t = np.arange(len(x)) / sr
    mod = np.zeros(len(x))
    for hz, c, phase0 in ((0.21, 0.7 * cents, 0.0), (0.067, 0.3 * cents, 1.0),
                          (5.3, 0.6 * flutter_cents, 2.0), (7.9, 0.4 * flutter_cents, 0.5)):
        if c:
            r = snap(hz, loop_s)
            mod += (2 ** (c / 1200) - 1) / (2 * np.pi * r) * np.sin(2 * np.pi * r * t + phase0)
    read = np.arange(len(x)) - mod * sr
    return np.stack([np.interp(read, np.arange(len(x)), x[:, c]) for c in range(2)], axis=1)


def saturate(x, drive):
    """Soft tape-style saturation; level-matched for quiet signals."""
    return np.tanh(drive * x) / drive


def distance(x, sr, lowpass, room_boom_db=0.0):
    """Push the sound far away: steep (24 dB/oct) lowpass, optional low-mid "through the wall"
    bump, and no rumble below 25 Hz."""
    chain = [pedalboard.HighpassFilter(25), pedalboard.LowpassFilter(lowpass), pedalboard.LowpassFilter(lowpass)]
    if room_boom_db:
        chain.append(pedalboard.PeakFilter(cutoff_frequency_hz=220, gain_db=room_boom_db, q=0.8))
    return _pb(pedalboard.Pedalboard(chain), x, sr)


# Spaces: how far away and through what the music is heard. A track picks one with
# song.space("dark") (stored in the MIDI); "distant" is the default.
SPACES = {
    "distant": dict(rt60=(11.0, 8.0, 3.0), dry=0.25, wet=1.0, shimmer=0.04, lowpass=2200,
                    chorus=0.3, wow=4, flutter=0, drive=0, boom=0),
    # Heaviest muffling, biggest and darkest space.
    "dark": dict(rt60=(14.0, 9.0, 2.5), dry=0.12, wet=1.1, shimmer=0.0, lowpass=900,
                 chorus=0.25, wow=3, flutter=0, drive=0, boom=0),
    # Warm and blurry: deeper chorus and slow wow smear everything.
    "dream": dict(rt60=(10.0, 8.0, 3.5), dry=0.22, wet=1.0, shimmer=0.05, lowpass=1800,
                  chorus=0.55, wow=9, flutter=0, drive=0, boom=0),
    # Heard from another room: a smaller room, then muffled through the wall, on worn tape.
    "liminal": dict(rt60=(4.5, 3.0, 1.2), dry=0.35, wet=0.75, shimmer=0.0, lowpass=1000,
                    chorus=0.3, wow=14, flutter=4, drive=6.0, boom=3.0),
    # Dream's warm blur with a little of liminal's worn tape: sweet and sorrowful.
    "memory": dict(rt60=(10.0, 8.0, 3.5), dry=0.22, wet=1.0, shimmer=0.03, lowpass=1700,
                   chorus=0.5, wow=11, flutter=2, drive=0, boom=0),
}

# How much darker than the space each kind sits (bells and felt piano are more muffled).
LOWPASS_FACTOR = {"bell": 0.8, "felt": 0.6}


def fx_chain(kind, x, sr, loop_s, space):
    s = SPACES[space]
    if kind == "pad":
        x = chorus(x, sr, loop_s, s["chorus"])
    if kind == "bell":
        x = x + 0.35 * echo(x, sr)
    if kind == "felt":
        x = soften_attacks(x, sr)
        x = steep_lowpass(x, sr, s["lowpass"] * LOWPASS_FACTOR["felt"])
        x = 0.5 * x + 0.9 * reverb(x, sr, (1.4, 1.1, 0.5), predelay=0.0)  # sustain blur
    out = s["dry"] * x + s["wet"] * reverb(x, sr, s["rt60"])
    if kind in ("pad", "bell") and s["shimmer"]:
        out += s["shimmer"] * shimmer(x, sr, s["rt60"])
    out = wow(out, sr, loop_s, s["wow"], s["flutter"])
    if s["drive"]:
        out = saturate(out, s["drive"])
    lowpass = s["lowpass"] * LOWPASS_FACTOR.get(kind, 1.0)
    return distance(out, sr, lowpass, s["boom"])


# ---------------------------------------------------------------- presets

VOICES = {
    # Warm detuned-saw pad, filter breathing slowly.
    "pad": dict(fn=pad, fx="pad", wave="saw", detune=(-11, -4, 4, 11), octave_sine=0.2,
                attack=7.0, release=8.0, key=4.0, cutoff_min=450, cutoff_max=3500,
                sweep_oct=0.8, sweep_hz=1 / 20, gain=0.5, preview=89),
    # Glassier pad from detuned sines.
    "pad_sine": dict(fn=pad, fx="pad", wave="sine", detune=(-7, 0, 7), octave_sine=0.3,
                     attack=8.0, release=9.0, key=8.0, cutoff_min=600, cutoff_max=6000,
                     sweep_oct=0.6, sweep_hz=1 / 25, gain=0.5, preview=88),
    # Very low sustained tone with slow beating, drift and swell.
    "drone": dict(fn=drone, fx="drone", partials=((1, 1.0), (2, 0.5), (3, 0.2), (4, 0.08)),
                  beat_cents=4, drift_cents=3, key=6.0, attack=8.0, release=10.0, gain=0.16, preview=95),
    # Soft FM bell, long decay, soft attack.
    "bell": dict(fn=bell, fx="bell", ratio=3.5, index=0.9, index_decay=0.5, ratio2=2.76, partial2=0.08,
                 attack=0.03, decay=3.0, ring=16.0, gain=1.7, preview=14),
    # Higher, glassier, shorter chime.
    "chime": dict(fn=bell, fx="bell", ratio=1.41, index=0.7, index_decay=0.3, ratio2=5.4, partial2=0.05,
                  attack=0.02, decay=1.8, ring=10.0, gain=1.7, preview=112),
    # Soundfont piano (rendered dry by FluidSynth) processed into a dim, muffled felt piano.
    "felt_piano": dict(source="soundfont", fx="felt", gain=60.0, preview=0),  # gain offsets the very low velocities
    # Distant wind, barely there with rare soft gusts; the note's pitch sets the band centre.
    "texture": dict(fn=texture, fx="texture", q=0.8, sweep_oct=0.8, sweep_hz=1 / 23,
                    attack=8.0, release=8.0, gain=0.6, preview=122),
}

REVERB_TAIL_SECONDS = 22.0  # longest reverb plus echo build-up


def voice_for(name):
    """Voice preset name for a stem/instrument name, or None for a soundfont instrument."""
    matches = [v for v in VOICES if name == v or name.startswith(v + "_")]
    return max(matches, key=len) if matches else None


def process_dry(dry, voice, sr, loop_s, space="distant"):
    """Effects for a soundfont-sourced voice (`dry` is FluidSynth's render, (n, 2))."""
    p = VOICES[voice]
    buf = np.zeros((len(dry) + int(REVERB_TAIL_SECONDS * sr), 2))
    buf[:len(dry)] = dry * p["gain"]
    return fx_chain(p["fx"], buf, sr, loop_s, space).astype(np.float32)


def render_stem(instruments, voice, sr, loop_s, space="distant"):
    """Render all notes of `instruments` with `voice` and run its effects in `space`; (n, 2)."""
    if space not in SPACES:
        raise SystemExit(f"unknown space {space!r}; choose from {', '.join(SPACES)}")
    p = VOICES[voice]
    notes = [(inst, n) for inst in instruments for n in inst.notes]
    voices = [(int(round(n.start * sr)), p["fn"](n, inst, sr, loop_s, p)) for inst, n in notes]
    length = max(s + len(v) for s, v in voices) + int(REVERB_TAIL_SECONDS * sr)
    buf = np.zeros((length, 2))
    for s, v in voices:
        buf[s:s + len(v)] += v
    return fx_chain(p["fx"], buf, sr, loop_s, space).astype(np.float32)
