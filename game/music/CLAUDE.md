# Game music: style guide and pipeline

Every track for this game follows this file. The game is a calm space exploration game. Every
track belongs to exactly one of three moods (Galaxy, Wilds, Journey), declared at the top of the
track file as `MOOD = "galaxy"`, `"wilds"` or `"journey"` (the pipeline refuses tracks without
one). Pick the mood from where the track plays, then follow that mood's section and the shared
rules.

## Originality (all moods)

- Each mood names a game whose music it is inspired by. Borrow the *feel* (instrumentation,
  texture, pacing), never the notes.
- Write original melodies, progressions and arrangements only. Never quote, paraphrase or
  closely imitate a melody, hook or recognisable rhythm from an existing song, including the
  reference games.

## Mood 1: Galaxy (hub, menus, safe areas)

Feel: magical, floating, wonder at something vast. Inspired by the feel of Super Mario Galaxy:
orchestral, sparkling, spacious, gently playful.

| Instrument     | kit name                    | GM program (GeneralUser GS)      | Typical role                   |
|----------------|-----------------------------|----------------------------------|--------------------------------|
| Celesta        | `celesta`                   | 8 Celeste                        | Lead melody, sparkles          |
| Harp           | `harp`                      | 46 Orchestral Harp               | Waltz arpeggios, rolled chords |
| Glockenspiel   | `glockenspiel`              | 9 Glockenspiel                   | Sparse accents, octave above   |
| Strings        | `strings` / `strings_slow`  | 48 Fast Strings / 49 Slow Strings | Pads, bass, swells, answers   |
| Soft choir pad | `choir` / `choir_pad`       | 52 Concert Choir / 91 Space Voice | Long held chords, low in mix  |

- Harmony: Lydian mode (major scale with a raised 4th: C Lydian = C D E F# G A B). Let the #4
  be heard. Major 7th, add9 and maj7#11 chords, and the Lydian II major chord over the tonic
  (D/C). Good motions: Imaj7 ↔ II/I vamps, Imaj7 → vim7 → Vmaj7 → iiim7 → IIadd9. Avoid strong
  V7 → I cadences, diminished tension and minor-key drama. Phrases may end on the 9th or #11.
- Tempo: 70–90 BPM, often a 3/4 waltz (harp or low strings on beat 1, light harp/celesta on
  2–3); 4/4 for variety.
- Reference example: `tracks/first_light.py`.

## Mood 2: Wilds (exploring planets)

Feel: lonely, peaceful, sparse. Inspired by the feel of Breath of the Wild's field music:
mostly space and silence, the player's own footsteps matter more than the music.

| Instrument                | kit name                                     | GM program                                  |
|---------------------------|----------------------------------------------|---------------------------------------------|
| Solo piano                | `piano`                                      | 0 Grand Piano                               |
| Soft pads underneath      | `strings_slow` / `warm_pad` / `halo_pad`     | 49 Slow Strings / 89 Warm Pad / 94 Halo Pad |
| Occasional bell or flute  | `celesta`, `vibraphone`, `tubular_bells`, `flute` | 8 / 11 / 14 / 73                       |

- Texture: short, scattered piano phrases (2–6 notes, a fragment or a few soft chord tones)
  with long silences between them, often 2–6 bars. Never a continuous melody, never a steady
  accompaniment pattern. Phrases don't repeat exactly within a loop.
- The pad holds very quietly underneath (velocity ~30–45), changing chord rarely (every 4–8
  bars). It may drop out for stretches too.
- Bell or flute: at most a handful of single notes per loop, as punctuation after a piano
  phrase, never a melody of its own.
- Harmony: open and ambiguous rather than functional: sus2/sus4, add9, open fifths, a major 7th
  over a pedal; modes like Lydian, Mixolydian or Aeolian with no strong cadences.
- Tempo: free-feeling and slow. Write on a slow grid (50–66 BPM, 4/4) but place notes off the
  grid (vary onsets by ~0.05–0.3 beats, vary note lengths and velocities 30–70) so nothing feels
  metric. Loops are long (about 1.5–3 minutes) so the silence pattern doesn't feel repetitive.

## Mood 3: Journey (traveling, discovery moments)

Feel: adventurous, folky, warm. Inspired by the feel of classic Zelda games like Ocarina of
Time: a singable wind melody over light, rhythmic accompaniment.

| Instrument           | kit name                          | GM program / kit                       | Typical role                    |
|----------------------|-----------------------------------|----------------------------------------|---------------------------------|
| Ocarina or flute     | `ocarina` / `flute` / `pan_flute` | 79 Ocarina / 73 Flute / 75 Pan Flute   | Melody                          |
| Harp                 | `harp`                            | 46 Orchestral Harp                     | Broken-chord accompaniment      |
| Pizzicato strings    | `pizzicato`                       | 45 Pizzicato Strings                   | Bass line and offbeat chords    |
| Light percussion     | `percussion`                      | drum kit 40 Brush                      | Soft hand percussion            |

- Percussion: `song.instrument("percussion")` is a drum track; its notes are names from
  `kit.PERC` (`shaker`, `tambourine`, `bongo_hi`, `conga_lo`, `woodblock_hi`, `triangle`, …).
  Keep it light: shaker/tambourine patterns and soft hand drums at velocity ~30–60. No drum
  kit (kick, snare, cymbals) and no crashes.
- Harmony: Dorian (C D Eb F G A Bb: minor with a raised 6th, `kit.DORIAN`) or Mixolydian
  (C D E F G A Bb: major with a flat 7th, `kit.MIXOLYDIAN`). Use the modal chords: Dorian
  i → IV (Dm → G), Mixolydian I → bVII (C → Bb), avoiding the major V → I cadence that would
  turn the mode into plain major/minor.
- Melody: stepwise, singable, folk-like phrases in 2- and 4-bar units, with clear call and
  answer. Rhythmic but not busy.
- Tempo: 90–110 BPM, in 6/8 (the pulse is the dotted quarter: `Song(bpm=3 * pulse,
  beats_per_bar=6, beat_unit=8)`, beats are eighths) or 4/4 (`Song(bpm, 4)`).

## Shared rules (all moods)

- Soft dynamics: MIDI velocities about 30–90 (Wilds lower), nothing above 100. Shape phrases
  with velocity and swells (`song.swell`, CC11), not loudness jumps.
- Nothing harsh: no sharp attacks stacked in the same register, no distortion, synth leads,
  brass stabs or drum kits; keep bells sparse and soft. `render.py` already softens highs
  (−3 dB shelf above 8 kHz).
- Large hall reverb on everything: `render.py` renders FluidSynth dry and applies the hall
  (`hall()`) with pedalboard. Tune it there, not per track.
- Loudness: the mix is normalised to −20 LUFS (peaks capped at −1 dBFS), and the same gain is
  applied to every stem. Override per track with `./track <name> --lufs N` only if needed
  (e.g. a very sparse Wilds track may need a lower target so its piano notes aren't too loud).
- Use only the mood's instruments unless the user asks for others.
- Every track loops seamlessly and ships as an OGG mix plus stems (below).

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

- `tracks/<name>.py` (snake_case): composition only. It sets `MOOD` and defines `compose() -> Song` using
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
