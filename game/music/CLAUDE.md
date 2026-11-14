# Game music: style guide and pipeline

Every track for this game follows this file. The game is a calm space exploration game; the
music should feel floating, curious and wondering, never tense or urgent.

## Originality

- Reference feel: Super Mario Galaxy (orchestral, sparkling, spacious, gently playful).
- Write original melodies, progressions and arrangements only. Never quote, paraphrase or
  closely imitate a melody or hook from an existing song, from Galaxy or anywhere else. Borrow
  the mood and the instrumentation, not the notes.

## Instruments

Use only this palette (General MIDI programs in `soundfonts/GeneralUser-GS.sf2`, 0-based as in
pretty_midi):

| Instrument        | GM program                      | Stem group | Typical role                     |
|-------------------|---------------------------------|------------|----------------------------------|
| Celesta           | 8                               | `bells`    | Lead melody, sparkles            |
| Glockenspiel      | 9                               | `bells`    | Doubling accents, octave above   |
| Harp              | 46 (Orchestral Harp)            | `harp`     | Arpeggios, rolled chords         |
| Strings           | 48 / 49 (String Ensemble 1 / 2) | `strings`  | Sustained pads, bass, swells     |
| Soft choir pad    | 52 (Choir Aahs) / 91 (Pad 4 choir) | `choir` | Long held chords, low in the mix  |
| Flute             | 73                              | `flute`    | Secondary melody, answers phrases |

Don't add other instruments (no drums, brass, synth leads or distorted sounds) unless the user
asks for them.

## Harmony

- Lydian mode as home: major scale with a raised 4th (C Lydian = C D E F# G A B). Let the #4
  be heard in melodies and voicings; it is the "wondering" colour.
- Chords: major 7th (Cmaj7), add9 (Cadd9), maj7#11, and the Lydian II major chord (D/C over a
  C pedal). Favour open, spread voicings with a 5th or 10th in the bass.
- Good motions: Imaj7 ↔ II/I vamps, Imaj7 → IVmaj7 → IIImin7 → IIadd9, slow pedal-point
  movement. Avoid strong dominant V7 → I cadences, diminished tension and minor-key drama.
- Mood: suspended, floating, unhurried. Phrases can end on the 9th or #11 instead of the root.

## Tempo and metre

- Mostly 70–90 BPM. Use 3/4 waltz feel often (harp or low strings on beat 1, light
  celesta/harp on beats 2–3); 4/4 is fine for variety.
- Write with a steady tempo; a track's loop length must be whole bars.

## Dynamics and production

- Soft dynamics: MIDI velocities about 40–90, nothing above 100. Shape phrases with velocity
  and string swells (CC11 expression), not loudness jumps.
- Nothing harsh: no sharp attacks stacked in the same register, keep glockenspiel sparse and
  soft, gently roll off highs above ~10 kHz on the master if bells sparkle too much.
- Large hall reverb on everything, applied in Python with pedalboard
  (e.g. `Reverb(room_size≈0.85, damping≈0.5, wet_level≈0.3, dry_level≈0.7)`). Render FluidSynth
  dry (`-R 0 -C 0`) so pedalboard's hall is the only reverb.
- Master peak normalised to about −3 dBFS, with the same gain applied to every stem.

## Seamless loops (required for every track)

1. Compose the loop as an exact number of bars. Loop length in samples is
   `round(bars * beats_per_bar * 60 / bpm * sample_rate)`.
2. Write the MIDI with the loop played **twice** back to back, then render and add reverb.
3. Keep only the **second** copy, from `loop_len` to `2 * loop_len` samples. It starts with the
   reverb and release tails carried in from the first copy, so the end flows back into the
   start without a gap or click.
4. Check the joint: play `audio[-2s:] + audio[:2s]` back to back and listen; there must be no
   click, dip or level jump. Notes that sustain over the loop point are fine.

## Output

Per track `<name>` (snake_case):

- `tracks/<name>.py`: the composition script (pretty_midi → FluidSynth → pedalboard → files).
- `out/<name>/`: working files (`.mid`, dry and wet `.wav`); git-ignored.
- Game files in `../res/music/<name>/`:
  - `<name>.ogg`: full mix.
  - `stems/<group>.ogg`: one per stem group used (`bells`, `harp`, `strings`, `choir`, `flute`).
- Stems: render each group separately from the same MIDI (only that group's instruments), run
  each through the same reverb and loop cut, and build the full mix as the sum of the stems so
  stems and mix line up sample-exactly and have identical length.
- Write OGG with soundfile, not ffmpeg (this ffmpeg build has no libvorbis):
  `sf.write(path, audio, 48000, format="OGG", subtype="VORBIS", compression_level=0.4)`.
- In Godot, enable looping on each imported OGG (Import dock → Loop, offset 0).

## Commands

Setup on a fresh clone (the venv and the 32 MB soundfont are git-ignored; FluidSynth via
`brew install fluid-synth`):

```sh
python3 -m venv .venv && .venv/bin/pip install pretty_midi mido numpy scipy pedalboard soundfile
curl -fL -o soundfonts/GeneralUser-GS.sf2 \
  https://raw.githubusercontent.com/mrbumpy409/GeneralUser-GS/main/GeneralUser-GS.sf2
```

Run from `game/music/`:

```sh
.venv/bin/python tracks/<name>.py                      # compose + render + export
fluidsynth -ni -q -R 0 -C 0 -r 48000 -F out.wav soundfonts/GeneralUser-GS.sf2 in.mid
afplay out/<name>/<name>.wav                           # listen
```

`test_setup.py` is the smoke test for the toolchain. This folder has a `.gdignore`, so Godot
does not import anything here; only files copied to `game/res/music/` reach the game.
