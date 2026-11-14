# Game music: style guide and pipeline

Every track for this game follows this file. The game is a calm space exploration game. Every
track belongs to exactly one of three moods: Deep Space (the main style), Wilds or Journey. The
mood is declared at the top of the track file as `MOOD = "deep_space"`, `"wilds"` or `"journey"`
(the pipeline refuses tracks without one). Pick the mood from where the track plays, then follow
that mood's section and the shared rules.

## Originality (all moods)

- Each mood names a game whose music it is inspired by. Borrow the *feel* (instrumentation,
  texture, pacing), never the notes.
- Write original melodies, progressions and arrangements only. Never quote, paraphrase or
  closely imitate a melody, hook or recognisable rhythm from an existing song, including the
  reference games.

## Mood 1: Deep Space (main style)

Feel: calm, empty, mysterious, slightly magical, liminal: floating alone somewhere very large and
very quiet. Reference feel: Brian Eno's *Apollo: Atmospheres and Soundtracks*, heard from far away:
distant and muffled, like dark ambient, dream ambient or liminal-spaces music. It sits quietly in
the background and never feels present or close.

All sounds come from the synthesis engine (`synth.py`), never the soundfont. The stem/instrument
name picks the voice (a voice name, or a voice name plus `_suffix` for extra stems, e.g.
`pad_high`):

| Voice      | Sound                                                       | Role                                      |
|------------|-------------------------------------------------------------|-------------------------------------------|
| `pad`      | Detuned saws, slow attack/release, lowpass slowly breathing | Main chord bed                            |
| `pad_sine` | Detuned sine layers, glassier                               | High, quiet colour layer                  |
| `drone`    | Very low sustained tone, slow beating, drift and swell      | Foundation, often a pedal through the loop |
| `bell`     | Soft FM bell, soft attack, long decay, dark echo            | Rare, distant twinkles                    |
| `chime`    | Higher, glassier, shorter FM chime                          | Even sparser, highest sparkle             |
| `texture`  | Band-passed noise, nearly silent with rare soft gusts      | Optional distant wind; leave out freely   |
| `felt_piano` | Soundfont piano rendered dry, then processed into a dim felt piano: attacks softened, steep lowpass, sustain blur, the space's reverb and wobble | Almost hidden melody inside the pads (the one exception to "synth only") |

- Effects are built into each voice (`fx_chain` in `synth.py`): a huge synthetic hall with
  mostly wet and little dry sound, a steep lowpass that cuts most high frequencies, slow chorus
  on pads, dark echo on bells, a slight pitch wobble, and at most a trace of octave-up shimmer
  (it brightens, which works against the dark feel). Tune voices and effects in `synth.py`, not
  per track.
- Every track picks a space with `song.space(...)`, which sets how far away and through what the
  music is heard (`SPACES` in `synth.py`):
  - `distant` (default): huge hall, lowpass around 2.2 kHz.
  - `dark`: heaviest muffling (around 900 Hz), biggest and darkest hall, no shimmer. For low,
    minor, slightly ominous tracks.
  - `dream`: warm and blurry, with deep chorus and slow wow. For soft major-7th washes.
  - `liminal`: music from another room, through a smaller room and a wall (lowpass around 1 kHz
    with a low-mid bump), on worn tape (strong wow, flutter, slight saturation). Eerie but calm.
  - `memory`: dream's warm blur with a little of liminal's tape wow and flutter. Sweet and
    sorrowful; made for the felt piano.
- Felt piano (`memory`-style tracks): a simple, sparse melody, a few notes per phrase, mostly
  descending, with long rests between phrases. Velocities about 20–28 (the voice's gain makes
  up for them); it should sit about 8–12 dB under the pads, never on top. Use
  `song.humanize(piano, timing=0.07, velocity=3)` so it isn't mechanical and
  `song.pedal(piano, chord_times + [loop_seconds])` for sustain, re-pedalled at chord changes.
  It replaces bells and wind; don't use both. This is the one sanctioned "melody" in Deep
  Space: barely there, not hummable.
- Bittersweet harmony (memory): major 7th and add9 chords with a borrowed minor iv (e.g. F to
  Fm in C) for the sorrowful moment; iv minor back to Imaj7/9 is a good loop point.
- Keep everything far away: soft attacks (the voices' attacks are already slow), no bright
  notes in high registers, bells high only if the space muffles them anyway.
- Never: choir, orchestral or acoustic instruments (except the processed `felt_piano`), drums or percussion, fast rhythms, arpeggiator
  patterns, or a clear hummable melody. Bells are isolated notes, not tunes.
- Harmony: slow chord changes, every 8–16 seconds; pads crossfade through their long releases.
  Suspended and open chords (sus2, sus4, add9, open fifths, major 7th or 9th without the third),
  often over a drone pedal. Use Lydian (raised 4th, e.g. E F# G# A# B C# D#) for the magical
  moments. Leave things unresolved: no cadences, and the loop never "arrives".
- Space and silence: lots of room between events. Bells and chimes are rare (2–4 per minute) and
  soft, at irregular times. Evolve very slowly with `song.swell(..., cc=74)` (pad brightness) and `cc=11`
  (volume) over tens of seconds.
- Timing: write at `Song(60, 4)`, so one beat is one second and one bar is 4 seconds; a chord
  every 2–4 bars. Loops of about 1–3 minutes.
- Velocities: pads 50–80, drone 50–90, bells and chimes 20–35, texture 40–50 (if used at all).
  Voice gains in `synth.py` already set the balance: at these velocities bells sit roughly
  5–12 dB under the pads and the wind's rare gusts peak near −30 dB.
- References: `tracks/deep_space_dark.py`, `deep_space_dream.py`, `deep_space_liminal.py`
  (30 s comparison loops, one per space), `deep_space_memory.py` (60 s, felt piano), and
  `deep_space_demo.py` (every voice, default space).

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
- Large reverb on everything. Deep Space voices have theirs built in (`synth.py`); soundfont
  instruments (Wilds, Journey) are rendered dry by FluidSynth and get the hall (`hall()` in
  `render.py`).
- Loudness: the mix is normalised to −26 LUFS, quiet background level (peaks capped at
  −1 dBFS), and the same gain is applied to every stem. Override per track with `./track <name> --lufs N` only if needed
  (e.g. a very sparse Wilds track may need a lower target so its piano notes aren't too loud).
- Use only the mood's instruments unless the user asks for others.
- Every track loops seamlessly and ships as an OGG mix plus stems (below).

## UI sound effects

`ui_sounds.py` builds the game's UI sounds in two alternative sets (the user is comparing them):
`.venv/bin/python ui_sounds.py [soft|felt] [names...]` writes `output/ui_<set>/<name>.wav`
(48 kHz, 24-bit, stereo, no loops) and `output/ui_<set>/_preview.wav` (every sound in order with
gaps; the order and times print in the terminal).

- `soft`: warm and round. Hover, click, toggle and slider are pure sine droplets (no overtones,
  a tiny upward glide, 30–120 ms audible); confirm, back and notification are short pad_sine
  blooms.
- `felt`: the memory track's felt piano (FluidSynth piano, softened, dimmed). Taps are short
  notes with a firm damper and almost no blur (80–230 ms audible); confirm, back and
  notification are two soft muted notes.
- Shared by both: error (low muffled sine thud falling G2 to C2), menu_open/menu_close (Cadd9
  pad swell, filter opening/closing, under 1 s) and game_start (Cmaj7#11 pad swell with a soft
  pad_sine layer, about 3 s).
- Never: bells, chimes, FM or anything that rings or sounds metallic (the user rejected them).
- Tuning: every pitched sound is a scale degree of `KEY_ROOT` in `SCALE` (currently C Lydian,
  matching the memory/liminal loops). If the main music settles in another key, change those two
  lines and re-render.
- Character: soft and gentle, a little clearer than the music (lowpass about 5 kHz instead of
  1–2 kHz), the same synthetic hall with short decays, nothing above about 3 kHz to speak of.
- Direction: positive actions rise (confirm, toggle_on, notification), back and cancel fall
  (back, toggle_off).
- Response: taps and droplets start within about 6 ms (felt toggles about 14 ms); only the
  swells fade in.
- Levels: each sound is peak-normalised to its entry in `LEVELS` (hover −32 and slider_tick
  −36 dBFS, up to game_start −15). Keep new sounds in that ladder: frequent sounds quietest.
- Variations: `hover` and `click` have three each (`_1` to `_3`, different scale notes); the game
  should pick one at random per play.

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
  `if __name__ == "__main__": kit.main(compose)`. `tracks/deep_space_demo.py` is the reference example.
- Each `song.instrument(name)` is one MIDI track and one stem. Instruments with the same name
  share a stem (e.g. two `"pad"` instruments).
- Stems whose name is a synth voice (`pad`, `pad_sine`, `drone`, `bell`, `chime`, `texture`, or
  one of those plus `_suffix`) are synthesised by `synth.py` with their effects; any other name
  is a soundfont instrument (`PROGRAMS`, `DRUM_KITS` in `kit.py`) rendered by FluidSynth. In the
  synth, CC11 is volume and CC74 brightness (64 = neutral), and every LFO is snapped to whole
  cycles per loop, so modulation continues seamlessly across the loop point.
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
