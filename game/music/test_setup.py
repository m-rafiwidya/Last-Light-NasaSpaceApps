"""Smoke test: C major chord on celesta, harp and strings -> MIDI -> WAV (FluidSynth) -> reverb (pedalboard)."""
import subprocess
from pathlib import Path

import numpy as np
import pedalboard
import pretty_midi
import soundfile as sf

HERE = Path(__file__).parent
SOUNDFONT = HERE / "soundfonts" / "GeneralUser-GS.sf2"
OUT = HERE / "out"
OUT.mkdir(exist_ok=True)

pm = pretty_midi.PrettyMIDI(initial_tempo=80)
for program, start in [(8, 0.0), (46, 0.0), (48, 0.0)]:  # GM: Celesta, Orchestral Harp, String Ensemble 1
    inst = pretty_midi.Instrument(program=program)
    for i, pitch in enumerate([60, 64, 67, 72]):  # C4 E4 G4 C5
        offset = i * 0.15 if program == 46 else 0.0  # harp rolls the chord
        inst.notes.append(pretty_midi.Note(velocity=80, pitch=pitch, start=start + offset, end=4.0))
    pm.instruments.append(inst)

mid = OUT / "test_chord.mid"
wav = OUT / "test_chord.wav"
pm.write(str(mid))
subprocess.run(["fluidsynth", "-ni", "-q", "-g", "0.6", "-r", "48000", "-F", str(wav), str(SOUNDFONT), str(mid)], check=True)

audio, sr = sf.read(wav)
board = pedalboard.Pedalboard([pedalboard.Reverb(room_size=0.7, wet_level=0.25)])
wet = board(audio.T.astype(np.float32), sr).T
sf.write(OUT / "test_chord_reverb.wav", wet, sr)

print(f"MIDI:   {mid}")
print(f"WAV:    {wav}  ({len(audio) / sr:.1f}s, {sr} Hz, peak {np.abs(audio).max():.2f})")
print(f"Reverb: {OUT / 'test_chord_reverb.wav'}")
