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
  soft. `render.py` already softens highs (−3 dB shelf above 8 kHz).
- Large hall reverb on everything: `render.py` renders FluidSynth dry and applies the hall
  (`hall()`) with pedalboard. Tune it there, not per track.
- Loudness: the mix is normalised to −20 LUFS (peaks capped at −1 dBFS), and the same gain is
  applied to every stem. Override per track with `./track <name> --lufs N` only if needed.

## Seamless loops (required for every track)

- Compose the loop as a whole number of bars and end the track with `song.loop(bars)`, which
  writes a `loop_end` marker into the MIDI.
- `render.py` cuts the audio at `loop_end` and folds everything after it (held notes, releases,
  the reverb tail) back onto the start. The end of the loop therefore flows into its own
  beginning, with no gap or click. Notes may cross the loop point; e.g. a final chord can
  sustain into the downbeat.
- Check every track: the render prints a seam report (the sample jump at the loop point should
  be no bigger than the 99th-percentile step), then listen to `<name>_loop_test.ogg` (three
  loops back to back) at both seams.

## Pipeline and output

- `tracks/<name>.py` (snake_case): composition only. It defines `compose() -> Song` using
  `tracks/kit.py` (bars/beats timing, `PROGRAMS`, `scale()` with `LYDIAN`, `notes`, `chord`,
  `sustain` for tied pads, `swell` for CC11) and ends with
  `if __name__ == "__main__": kit.main(compose)`. `tracks/first_light.py` is the reference example.
- Each `song.instrument(name)` is one MIDI track and one stem. Instruments with the same name
  share a stem, e.g. name both celesta and glockenspiel `"bells"` for a combined stem.
- `render.py <file.mid>` renders any multi-track MIDI. It writes to `output/<name>/`:
  - `<name>.mid`: the composition (written by `kit.main`).
  - `<name>.ogg`: the full loop mix (48 kHz stereo Vorbis), the file for the game.
  - `stems/<instrument>.ogg`: one per stem, the same length as the mix, and summing to it.
  - `<name>_loop_test.ogg`: the mix three times in a row, for checking the seam.
- `output/` is git-ignored and inside this `.gdignore`d folder. Copy finished files to
  `game/res/music/` for the game and enable Loop in Godot's Import dock (offset 0).
- OGG is written with soundfile (this ffmpeg build has no libvorbis), in blocks, because
  libsndfile's Vorbis encoder segfaults on long single writes.

## Commands

Setup on a fresh clone (the venv and the 32 MB soundfont are git-ignored; FluidSynth via
`brew install fluid-synth`):

```sh
python3 -m venv .venv
.venv/bin/pip install pretty_midi mido numpy scipy pedalboard soundfile pyloudnorm
curl -fL -o soundfonts/GeneralUser-GS.sf2 \
  https://raw.githubusercontent.com/mrbumpy409/GeneralUser-GS/main/GeneralUser-GS.sf2
```

Run from `game/music/`:

```sh
./track <name>                               # compose tracks/<name>.py and render everything
./track --list                               # available tracks
.venv/bin/python render.py some.mid          # render an existing MIDI into output/some/
afplay output/<name>/<name>_loop_test.ogg    # listen to the seam
```

`test_setup.py` is the original toolchain smoke test.
