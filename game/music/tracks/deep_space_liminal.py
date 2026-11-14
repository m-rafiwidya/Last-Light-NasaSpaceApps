"""Deep Space, liminal variation: 30 s loop, music from another room on worn tape, eerie but calm.
Cmaj7 -> Abmaj7 over C (one note shifts, the room tilts) -> Cmaj7#11."""
import kit
from kit import Song

MOOD = "deep_space"

CHORDS = [
    ["C3", "G3", "B3", "E4"],     # Cmaj7
    ["C3", "Ab3", "Eb4", "G4"],   # Abmaj7 over C: eerie
    ["C3", "G3", "B3", "F#4"],    # Cmaj7#11: the Lydian lift, still unresolved
]


def compose():
    song = Song(bpm=60, beats_per_bar=3)
    song.space("liminal")
    drone, pad, glass, chime = (song.instrument(n) for n in ("drone", "pad", "pad_sine", "chime"))

    song.note(drone, "C2", 0, 0, 30, vel=50)
    for i, chord in enumerate(CHORDS):
        song.chord(pad, chord, 0, i * 10, 10, vel=72)
    song.chord(glass, ["B4", "F#5"], 0, 21, 9, vel=40)

    song.note(chime, "G5", 0, 8.0, 1, vel=30)    # a music box somewhere else
    song.note(chime, "F#5", 0, 24.0, 1, vel=26)
    song.loop(10)
    return song


if __name__ == "__main__":
    kit.main(compose)
