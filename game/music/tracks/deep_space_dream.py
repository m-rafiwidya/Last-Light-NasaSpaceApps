"""Deep Space, dream variation: 30 s loop, warm blurry major-7th washes, gentle and nostalgic.
Fmaj9 -> Dbmaj7 (the nostalgic bVI) -> Bbmaj9."""
import kit
from kit import Song

MOOD = "deep_space"

# (pad voicing, glass layer) every 10 s.
CHORDS = [
    (["F2", "C3", "E3", "A3"], ["G4", "C5", "E5"]),      # Fmaj9
    (["Db3", "F3", "Ab3", "C4"], ["F4", "Ab4", "C5"]),   # Dbmaj7
    (["Bb2", "F3", "A3", "D4"], ["A4", "C5", "D5"]),     # Bbmaj9
]


def compose():
    song = Song(bpm=60, beats_per_bar=3)
    song.space("dream")
    drone, pad, glass, bell = (song.instrument(n) for n in ("drone", "pad", "pad_sine", "bell"))

    song.note(drone, "F1", 0, 0, 30, vel=55)
    for i, (low, high) in enumerate(CHORDS):
        song.chord(pad, low, 0, i * 10, 10, vel=70)
        song.chord(glass, high, 0, i * 10 + 1.5, 9.5, vel=48)  # blooms in a little later

    song.note(bell, "E5", 0, 6.0, 1, vel=30)
    song.note(bell, "C5", 0, 19.5, 1, vel=26)
    song.loop(10)
    return song


if __name__ == "__main__":
    kit.main(compose)
