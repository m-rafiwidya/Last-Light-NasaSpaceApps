"""Render a multi-track MIDI into a seamlessly looping OGG mix plus per-instrument OGG stems.

    .venv/bin/python render.py output/<name>/<name>.mid [--out DIR] [--lufs -20]

Per stem (MIDI tracks grouped by track name): FluidSynth renders it dry with GeneralUser GS,
pedalboard adds the hall, and everything after the loop end (held notes, releases, reverb tail)
is folded back onto the start, so the end of the loop flows into its beginning. The mix is the sum
of the stems; one gain sets the mix to the loudness target and is applied to every stem.

Loop length: a "loop_end" MIDI text event (tracks/kit.py Song.loop), otherwise the last note end
rounded up to a whole bar.
"""
import argparse
import copy
import re
import subprocess
import tempfile
from pathlib import Path

import numpy as np
import pedalboard
import pretty_midi
import pyloudnorm
import soundfile as sf

HERE = Path(__file__).resolve().parent
SOUNDFONT = HERE / "soundfonts" / "GeneralUser-GS.sf2"
SAMPLE_RATE = 48000
TARGET_LUFS = -20.0      # calm background music
PEAK_CEILING_DB = -1.0   # gain is lowered if the loudness target would push peaks above this
TAIL_SECONDS = 15.0      # room for the reverb tail before it is folded back
SILENCE = 1e-5           # -100 dBFS: where the tail counts as finished
OGG_COMPRESSION = 0.3    # libsndfile Vorbis: 0 = best quality, 1 = smallest


def hall():
    return pedalboard.Pedalboard([
        pedalboard.HighpassFilter(cutoff_frequency_hz=35),
        pedalboard.Reverb(room_size=0.9, damping=0.5, wet_level=0.35, dry_level=0.7, width=1.0),
        pedalboard.HighShelfFilter(cutoff_frequency_hz=8000, gain_db=-3.0),  # keep bells soft
    ])


def loop_end_seconds(pm):
    for text in pm.text_events:
        if text.text.strip() == "loop_end":
            return text.time
    end = max(n.end for inst in pm.instruments for n in inst.notes)
    sig = pm.time_signature_changes[0] if pm.time_signature_changes else None
    numerator, denominator = (sig.numerator, sig.denominator) if sig else (4, 4)
    bar = 60.0 / pm.get_tempo_changes()[1][0] * numerator * 4 / denominator  # assumes one tempo
    end = np.ceil(end / bar - 1e-3) * bar
    print(f"warning: no loop_end marker, looping at {end:.3f}s (last note rounded up to a bar)")
    return end


def stem_name(inst):
    name = inst.name.strip() or pretty_midi.program_to_instrument_name(inst.program)
    return re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")


def render_dry(pm, instruments, tmp, name):
    """FluidSynth render of only `instruments`, dry, as float stereo (frames, 2)."""
    sub = copy.deepcopy(pm)
    sub.instruments = copy.deepcopy(instruments)
    mid, wav = tmp / f"{name}.mid", tmp / f"{name}.wav"
    sub.write(str(mid))
    subprocess.run(["fluidsynth", "-ni", "-q", "-R", "0", "-C", "0", "-g", "0.5",
                    "-r", str(SAMPLE_RATE), "-T", "wav", "-O", "float",
                    "-F", str(wav), str(SOUNDFONT), str(mid)], check=True)
    audio, _ = sf.read(wav, dtype="float32", always_2d=True)
    return audio


def fold(audio, loop_len):
    """Wrap everything past loop_len back onto the start (overlap-add, any number of times)."""
    out = np.zeros((loop_len, audio.shape[1]), dtype=np.float64)
    for k in range(0, len(audio), loop_len):
        seg = audio[k:k + loop_len]
        out[:len(seg)] += seg
    return out


def write_ogg(path, audio):
    path.parent.mkdir(parents=True, exist_ok=True)
    audio = np.ascontiguousarray(np.clip(audio, -1.0, 1.0), dtype=np.float32)
    with sf.SoundFile(path, "w", SAMPLE_RATE, audio.shape[1], format="OGG", subtype="VORBIS",
                      compression_level=OGG_COMPRESSION) as f:
        # libsndfile's Vorbis encoder segfaults on long single writes; feed it in blocks.
        for k in range(0, len(audio), 1 << 14):
            f.write(audio[k:k + (1 << 14)])


def seam_report(mix):
    """Sample jump across the loop point vs. typical sample steps, and level either side."""
    jump = np.abs(mix[0] - mix[-1]).max()
    typical = np.percentile(np.abs(np.diff(mix, axis=0)).max(axis=1), 99)
    half = SAMPLE_RATE // 2
    rms = lambda x: 20 * np.log10(np.sqrt(np.mean(x ** 2)) + 1e-12)
    return (f"seam: jump {jump:.4f} (99th pct step {typical:.4f}), "
            f"level last 0.5s {rms(mix[-half:]):.1f} dB / first 0.5s {rms(mix[:half]):.1f} dB")


def render(midi_path, out_dir=None, target_lufs=TARGET_LUFS):
    midi_path = Path(midi_path)
    name = midi_path.stem
    out_dir = Path(out_dir) if out_dir else HERE / "output" / name
    pm = pretty_midi.PrettyMIDI(str(midi_path))
    loop_len = round(loop_end_seconds(pm) * SAMPLE_RATE)

    groups = {}
    for inst in pm.instruments:
        if inst.notes:
            groups.setdefault(stem_name(inst), []).append(inst)

    with tempfile.TemporaryDirectory() as tmp:
        dry = {stem: render_dry(pm, insts, Path(tmp), stem) for stem, insts in groups.items()}

    length = max(loop_len, max(len(a) for a in dry.values())) + round(TAIL_SECONDS * SAMPLE_RATE)
    wet = {}
    for stem, audio in dry.items():
        padded = np.zeros((length, 2), dtype=np.float32)
        padded[:len(audio)] = audio
        wet[stem] = hall()(padded, SAMPLE_RATE)
    tail_end = max(np.nonzero(np.abs(w).max(axis=1) > SILENCE)[0][-1] for w in wet.values()) + 1
    stems = {stem: fold(w[:tail_end], loop_len) for stem, w in wet.items()}
    mix = sum(stems.values())

    lufs = pyloudnorm.Meter(SAMPLE_RATE).integrated_loudness(mix)
    gain_db = target_lufs - lufs
    peak_db = 20 * np.log10(np.abs(mix).max()) + gain_db
    if peak_db > PEAK_CEILING_DB:
        gain_db -= peak_db - PEAK_CEILING_DB
    gain = 10 ** (gain_db / 20)
    mix *= gain

    write_ogg(out_dir / f"{name}.ogg", mix)
    for stem, audio in stems.items():
        write_ogg(out_dir / "stems" / f"{stem}.ogg", audio * gain)
    write_ogg(out_dir / f"{name}_loop_test.ogg", np.tile(mix, (3, 1)))

    print(f"loop {loop_len / SAMPLE_RATE:.2f}s, tail {(tail_end - loop_len) / SAMPLE_RATE:.1f}s folded back")
    print(f"loudness {lufs + gain_db:.1f} LUFS (target {target_lufs}), "
          f"peak {20 * np.log10(np.abs(mix).max()):.1f} dBFS")
    print(seam_report(mix))
    print(f"mix:       {out_dir / f'{name}.ogg'}")
    print(f"stems:     {', '.join(stems)} in {out_dir / 'stems'}")
    print(f"loop test: {out_dir / f'{name}_loop_test.ogg'}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("midi")
    parser.add_argument("--out", help="output folder (default output/<midi name>/)")
    parser.add_argument("--lufs", type=float, default=TARGET_LUFS, help="loudness target")
    args = parser.parse_args()
    render(args.midi, args.out, args.lufs)
