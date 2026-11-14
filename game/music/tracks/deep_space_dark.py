"""Deep Space, dark variation: 30 s loop, low D pedal, minor and unresolved, slightly ominous.
The Eb chord over the D pedal (Phrygian bII) is the ominous colour."""
import kit
from kit import Song

MOOD = "deep_space"

# One chord every 10 s (60 BPM: one beat = one second).
CHORDS = [
    ["D2", "A2", "E3", "F3"],     # Dm add9, low and close
    ["D2", "Eb3", "G3", "Bb3"],   # Eb over D: the shadow
    ["D2", "A2", "E3"],           # Dsus2, no third: unresolved
]


def compose():
    song = Song(bpm=60, beats_per_bar=3)
    song.space("dark")
    drone, pad, bell, wind = (song.instrument(n) for n in ("drone", "pad", "bell", "texture"))

    song.note(drone, "D1", 0, 0, 30, vel=85)
    song.note(drone, "A1", 0, 0, 30, vel=45)
    for i, chord in enumerate(CHORDS):
        song.chord(pad, chord, 0, i * 10, 10, vel=72)
    song.swell(pad, 0, 10, 10, 64, 50, cc=74)  # the shadow chord closes the filter further
    song.swell(pad, 0, 20, 10, 50, 64, cc=74)

    song.note(bell, "F4", 0, 7.0, 1, vel=26)   # two distant bells, low
    song.note(bell, "A4", 0, 22.5, 1, vel=22)
    song.note(wind, "G4", 0, 0, 30, vel=45)    # barely there
    song.loop(10)
    return song


if __name__ == "__main__":
    kit.main(compose)
