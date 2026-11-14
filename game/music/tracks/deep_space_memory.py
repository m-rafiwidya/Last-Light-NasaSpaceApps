"""Deep Space, memory variation: 60 s loop, sweet and sorrowful. Dream pads with a little tape wow,
and an almost hidden felt piano. Cmaj9 -> Em7 -> Am9 -> Fmaj7 -> Fm(add9), the borrowed minor iv;
the loop's return from Fm to Cmaj9 is the bittersweet resolution."""
import kit
from kit import Song

MOOD = "deep_space"

# (pad voicing, glass layer) every 12 s (60 BPM: one beat = one second).
CHORDS = [
    (["C3", "G3", "B3", "E4"], ["G4", "B4", "D5"]),      # Cmaj9
    (["E3", "B3", "D4", "G4"], ["B4", "D5"]),            # Em7
    (["A2", "E3", "G3", "C4"], ["G4", "B4", "E5"]),      # Am9
    (["F2", "C3", "E3", "A3"], ["G4", "C5", "E5"]),      # Fmaj7 (9 on top)
    (["F2", "C3", "G3", "Ab3"], ["Ab4", "C5", "G5"]),    # Fm add9: the sorrowful moment
]

# Piano phrases: (second, pitch, seconds, velocity). A few notes each, mostly falling, long rests.
PIANO = [
    (2.0, "E5", 1.5, 26), (3.5, "D5", 1.5, 24), (5.0, "B4", 1.5, 23), (6.5, "G4", 4.0, 22),
    (15.0, "B4", 1.2, 24), (16.2, "A4", 1.3, 22), (17.5, "G4", 1.5, 21), (19.0, "E4", 4.0, 20),
    (26.5, "C5", 1.2, 25), (27.7, "B4", 1.8, 23), (29.5, "E4", 4.0, 20),
    (38.0, "A4", 1.3, 24), (39.3, "G4", 1.2, 22), (40.5, "E4", 4.5, 20),
    (48.5, "C5", 1.3, 26), (49.8, "Ab4", 1.7, 24), (51.5, "G4", 5.0, 21),   # over Fm
]


def compose():
    song = Song(bpm=60, beats_per_bar=4)
    song.space("memory")
    drone, pad, glass, piano = (song.instrument(n) for n in ("drone", "pad", "pad_sine", "felt_piano"))

    song.note(drone, "C2", 0, 0, 60, vel=45)
    for i, (low, high) in enumerate(CHORDS):
        song.chord(pad, low, 0, i * 12, 12, vel=70)
        song.chord(glass, high, 0, i * 12 + 2, 10, vel=44)

    for second, p, seconds, vel in PIANO:
        song.note(piano, p, 0, second, seconds, vel)
    song.humanize(piano, timing=0.07, velocity=3, seed=3)
    song.pedal(piano, [i * 12 for i in range(5)] + [60])
    song.loop(15)
    return song


if __name__ == "__main__":
    kit.main(compose)
