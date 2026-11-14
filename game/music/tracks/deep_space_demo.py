"""Deep Space demo: a 60 s loop exercising every synth voice. E pedal, open chords every 12 s,
an E Lydian moment in the middle, sparse bells. A reference for the engine, not a game track."""
import kit
from kit import Song

MOOD = "deep_space"

# One chord every 3 bars (12 s at 60 BPM, 4/4: one beat = one second).
CHORDS = [
    ["B2", "E3", "F#3", "B3"],          # Esus2, open
    ["E3", "B3", "F#4", "A#4"],         # E Lydian: add9 #11, the magical moment
    ["C#3", "G#3", "D#4", "E4"],        # C#m add9, a shadow
    ["B2", "C#3", "F#3", "E4"],         # Bsus2 over E
    ["E3", "F#3", "B3", "D#4"],         # Emaj9 without third, unresolved
]

# (second, pitch, velocity): sparse, irregular, never a tune.
BELLS = [(3.5, "B5", 48), (14.0, "A#5", 52), (21.5, "F#5", 40), (33.0, "E5", 46),
         (44.5, "C#6", 42), (52.0, "F#5", 38)]
CHIMES = [(17.0, "D#7", 34), (39.0, "B6", 30)]


def compose():
    song = Song(bpm=60, beats_per_bar=4)
    drone = song.instrument("drone")
    pad = song.instrument("pad")
    glass = song.instrument("pad_sine")
    bell = song.instrument("bell")
    chime = song.instrument("chime")
    wind = song.instrument("texture")

    # Drone through the whole loop; its release folds into the start.
    song.note(drone, "E1", 0, 0, 60, vel=80)
    song.note(drone, "B1", 0, 0, 60, vel=50)

    for i, chord in enumerate(CHORDS):
        song.chord(pad, chord, i * 3, 0, 12, vel=70)
    # Glass layer only on the Lydian chord, high and quiet.
    song.chord(glass, ["E4", "A#4", "D#5"], 3, 0, 12, vel=55)
    # Pad opens up during the Lydian moment, then closes again.
    song.swell(pad, 3, 0, 6, 64, 88, cc=74)
    song.swell(pad, 4, 2, 10, 88, 60, cc=74)

    for second, p, vel in BELLS:
        song.note(bell, p, 0, second, 1, vel)
    for second, p, vel in CHIMES:
        song.note(chime, p, 0, second, 1, vel)

    song.note(wind, "C5", 0, 0, 60, vel=60)
    song.loop(15)
    return song


if __name__ == "__main__":
    kit.main(compose)
