"""First Light: C Lydian waltz, 78 BPM, 16-bar loop. Celesta theme, flute answer in the second half."""
import kit
from kit import Song

# (bass, upper voicing) per bar. "D/C" is the Lydian II-over-I colour.
CMAJ7 = ("C2", ["C3", "G3", "E4", "B4"])
D_C = ("C2", ["C3", "A3", "D4", "F#4"])
AM9 = ("A1", ["A2", "E3", "C4", "G4", "B4"])
GMAJ7 = ("G1", ["G2", "D3", "B3", "F#4"])
EM7 = ("E2", ["E2", "B2", "G3", "D4"])
DADD9 = ("D2", ["D3", "A3", "E4", "F#4"])

CHORDS = [CMAJ7, D_C, CMAJ7, DADD9,
          AM9, GMAJ7, EM7, DADD9,
          CMAJ7, D_C, GMAJ7, AM9,
          EM7, GMAJ7, DADD9, D_C]


def compose():
    song = Song(bpm=78, beats_per_bar=3)
    celesta = song.instrument("celesta")
    glock = song.instrument("glockenspiel")
    harp = song.instrument("harp")
    strings = song.instrument("strings")
    choir = song.instrument("choir")
    flute = song.instrument("flute")

    for bar, (bass, upper) in enumerate(CHORDS):
        # Waltz: harp bass on 1, then eighths up and back through the voicing an octave higher.
        for i, p in enumerate([bass, upper[1], upper[2], upper[3], upper[2], upper[1]]):
            song.note(harp, kit.pitch(p) + (12 if i else 0), bar, i * 0.5, 1.5 if i == 0 else 1.0,
                      vel=60 if i == 0 else 44)
        song.sustain(strings, [bass] + upper[:4], bar, 0, 3, vel=52)
        if bar % 2 == 0:
            song.sustain(choir, [kit.pitch(p) + 12 for p in upper[-3:]], bar, 0, 6, vel=38)
    for phrase in range(4):
        song.swell(strings, phrase * 4, 0, 6, 72, 98)
        song.swell(strings, phrase * 4 + 2, 0, 6, 98, 76)

    # Theme (bars 0-7): celesta, leaning on F# (the Lydian #4).
    song.notes(celesta, 0, [(0, 1.5, "G5"), (1.5, 0.5, "A5"), (2, 1, "B5")], vel=62)
    song.notes(celesta, 1, [(0, 2, "F#5"), (2, 1, "E5")], vel=58)
    song.notes(celesta, 2, [(0, 1, "D5"), (1, 1, "E5"), (2, 1, "G5")], vel=58)
    song.notes(celesta, 3, [(0, 3, "A5")], vel=60)
    song.notes(celesta, 4, [(0, 1.5, "C6"), (1.5, 0.5, "B5"), (2, 1, "A5")], vel=62)
    song.notes(celesta, 5, [(0, 2, "B5"), (2, 1, "F#5")], vel=58)
    song.notes(celesta, 6, [(0, 2, "G5"), (2, 1, "E5")], vel=56)
    song.notes(celesta, 7, [(0, 3, "F#5")], vel=56)

    # Answer (bars 8-15): flute takes the line, celesta sparkles an octave up on the off-bars.
    song.notes(flute, 8, [(0, 1, "E5"), (1, 1, "F#5"), (2, 1, "G5")], vel=58)
    song.notes(flute, 9, [(0, 2, "A5"), (2, 1, "F#5")], vel=60)
    song.notes(flute, 10, [(0, 1.5, "B5"), (1.5, 0.5, "A5"), (2, 1, "G5")], vel=62)
    song.notes(flute, 11, [(0, 3, "E5")], vel=56)
    song.notes(flute, 12, [(0, 1, "G5"), (1, 1, "B5"), (2, 1, "D6")], vel=60)
    song.notes(flute, 13, [(0, 2, "B5"), (2, 1, "A5")], vel=58)
    song.notes(flute, 14, [(0, 1.5, "F#5"), (1.5, 0.5, "E5"), (2, 1, "D5")], vel=56)
    song.notes(flute, 15, [(0, 3, "E5")], vel=50)  # sustains into the downbeat of the loop
    for bar, figure in [(9, ["A6", "F#6", "D6"]), (11, ["E6", "C6", "A5"]),
                        (13, ["F#6", "D6", "B5"]), (15, ["A6", "F#6", "E6"])]:
        song.notes(celesta, bar, [(1 + i * 0.5, 0.5, p) for i, p in enumerate(figure)], vel=44)

    # Glockenspiel: one soft bell at the top of each phrase.
    for bar, p in [(0, "G6"), (4, "C7"), (8, "E6"), (12, "G6")]:
        song.note(glock, p, bar, 0, 1, vel=36)

    song.loop(16)
    return song


if __name__ == "__main__":
    kit.main(compose)
