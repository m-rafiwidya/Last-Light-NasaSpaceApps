"""Export a rendered track for a DAW (FL Studio): one MIDI file and one WAV stem per part.

    .venv/bin/python export_fl_studio.py [name]      (default deep_space_memory)

Reads output/<name>/<name>.mid (the composition the game's mix was rendered from) and writes
output/fl_studio/:
- midi/<part>.mid: type 1, 480 ticks per quarter; track 0 holds tempo, time signature, key and a
  loop_end marker, track 1 the part (name, GM preview program, notes, controllers). Every file
  starts at tick 0 and ends at the loop end, so they line up.
- wav/<part>.wav and wav/full_mix.wav: 48 kHz 24-bit stereo, exactly one loop long. They come out
  of render.py unchanged (same synthesis, effects, tail folding and gain), only written as WAV
  instead of OGG, so the stems sum to the mix and sound as in the game.
The game's music is not touched (nothing is written outside output/fl_studio/).
"""
import sys
from pathlib import Path

import mido
import numpy as np
import pretty_midi
import soundfile as sf

import render

HERE = Path(__file__).resolve().parent
TPQ = 480
KEY = "C"  # key signature written into every MIDI file


def ticks(seconds, bpm):
    return round(seconds * bpm / 60 * TPQ)


def write_part_midi(pm, inst, loop_s, path):
    bpm = pm.get_tempo_changes()[1][0]
    sig = pm.time_signature_changes[0]
    end = ticks(loop_s, bpm)
    conductor = [
        (0, mido.MetaMessage("track_name", name=path.stem)),
        (0, mido.MetaMessage("set_tempo", tempo=mido.bpm2tempo(bpm))),
        (0, mido.MetaMessage("time_signature", numerator=sig.numerator, denominator=sig.denominator)),
        (0, mido.MetaMessage("key_signature", key=KEY)),
        (end, mido.MetaMessage("marker", text="loop_end")),
    ]
    channel = 9 if inst.is_drum else 0
    # Sort key: time, then note-offs (0) before controllers (1) before note-ons (2), so a pitch
    # re-struck at a chord change is released first.
    events = [(0, 1, mido.Message("program_change", channel=channel, program=inst.program))]
    for c in inst.control_changes:
        events.append((ticks(c.time, bpm), 1, mido.Message("control_change", channel=channel,
                                                           control=c.number, value=c.value)))
    for n in inst.notes:
        events.append((ticks(n.start, bpm), 2, mido.Message("note_on", channel=channel, note=n.pitch,
                                                            velocity=n.velocity)))
        events.append((ticks(n.end, bpm), 0, mido.Message("note_off", channel=channel, note=n.pitch,
                                                          velocity=0)))
    events.sort(key=lambda e: (e[0], e[1]))
    part = [(0, mido.MetaMessage("track_name", name=inst.name))] + [(t, m) for t, _, m in events]

    mid = mido.MidiFile(type=1, ticks_per_beat=TPQ)
    for track_events in (conductor, part):
        track, now = mido.MidiTrack(), 0
        for t, msg in track_events:
            track.append(msg.copy(time=t - now))
            now = t
        track.append(mido.MetaMessage("end_of_track", time=max(0, end - now)))
        mid.tracks.append(track)
    path.parent.mkdir(parents=True, exist_ok=True)
    mid.save(path)


def export(name):
    src = HERE / "output" / name / f"{name}.mid"
    if not src.is_file():
        sys.exit(f"missing {src}: run ./track {name} first")
    out = HERE / "output" / "fl_studio"
    pm = pretty_midi.PrettyMIDI(str(src))
    loop_s = render.loop_end_seconds(pm)

    for inst in pm.instruments:
        if inst.notes:
            write_part_midi(pm, inst, loop_s, out / "midi" / f"{render.stem_name(inst)}.mid")

    # Run render.py as is, catching the audio it would write as OGG.
    captured = {}
    render.write_ogg = lambda path, audio: captured.__setitem__(path, audio)
    render.render(src, out_dir=out / "_render")
    for path, audio in captured.items():
        if path.name.endswith("_loop_test.ogg"):
            continue
        wav = out / "wav" / ("full_mix.wav" if path.parent.name == "_render" else f"{path.stem}.wav")
        wav.parent.mkdir(parents=True, exist_ok=True)
        sf.write(wav, np.clip(audio, -1.0, 1.0), render.SAMPLE_RATE, subtype="PCM_24")
        print(f"wav: {wav.relative_to(HERE)} ({len(audio) / render.SAMPLE_RATE:.3f}s)")


if __name__ == "__main__":
    export(sys.argv[1] if len(sys.argv) > 1 else "deep_space_memory")
