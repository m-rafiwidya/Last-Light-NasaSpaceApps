"""Composition helpers for track files: bars/beats instead of seconds, Lydian scales, ties, swells.

A track file defines `compose() -> Song` and ends with `if __name__ == "__main__": kit.main(compose)`.
Each `song.instrument(name, ...)` becomes one MIDI track; render.py makes one stem per name
(instruments sharing a name are rendered into the same stem).
"""
import sys
from pathlib import Path

import pretty_midi

# General MIDI programs (0-based) in GeneralUser GS for the game's palette (see CLAUDE.md moods).
PROGRAMS = {
    "celesta": 8,
    "glockenspiel": 9,
    "music_box": 10,
    "vibraphone": 11,
    "tubular_bells": 14,
    "piano": 0,
    "harp": 46,
    "pizzicato": 45,
    "strings": 48,
    "strings_slow": 49,
    "choir": 52,
    "choir_pad": 91,     # Space Voice
    "warm_pad": 89,
    "halo_pad": 94,
    "flute": 73,
    "pan_flute": 75,
    "ocarina": 79,
}

# Drum kits (MIDI channel 10, bank 128). Brush is the soft one for light percussion.
DRUM_KITS = {"percussion": 40, "orchestral_percussion": 48}

# GM percussion notes for light hand percussion.
PERC = {
    "bongo_hi": 60, "bongo_lo": 61, "conga_hi": 63, "conga_lo": 64, "tambourine": 54,
    "shaker": 82, "maracas": 70, "cabasa": 69, "claves": 75, "woodblock_hi": 76,
    "woodblock_lo": 77, "triangle": 81, "triangle_muted": 80, "rim": 37, "brush_tap": 38,
}

LYDIAN = (0, 2, 4, 6, 7, 9, 11)
IONIAN = (0, 2, 4, 5, 7, 9, 11)
DORIAN = (0, 2, 3, 5, 7, 9, 10)
MIXOLYDIAN = (0, 2, 4, 5, 7, 9, 10)
MOODS = ("galaxy", "wilds", "journey")

LOOP_END_TEXT = "loop_end"
OUTPUT = Path(__file__).resolve().parent.parent / "output"


def pitch(name):
    """'C4' -> 60, 'F#5' -> 78, 'Bb3' -> 58."""
    return pretty_midi.note_name_to_number(name)


def scale(root, degree, mode=LYDIAN):
    """MIDI pitch of a 0-based scale degree above `root` (a MIDI number or name); degrees may be
    negative or above 6 to move by octaves."""
    root = pitch(root) if isinstance(root, str) else root
    octave, step = divmod(degree, len(mode))
    return root + 12 * octave + mode[step]


class Song:
    """`bpm` counts the beat unit: Song(84, 4) is 4/4 at quarter = 84; 6/8 at dotted quarter = 100
    is Song(300, 6, 8), with beats as eighths."""

    def __init__(self, bpm, beats_per_bar=3, beat_unit=4):
        self.bpm = bpm
        self.beats_per_bar = beats_per_bar
        self.midi = pretty_midi.PrettyMIDI(initial_tempo=bpm * 4 / beat_unit)  # MIDI tempo is per quarter
        self.midi.time_signature_changes.append(pretty_midi.TimeSignature(beats_per_bar, beat_unit, 0.0))

    def t(self, bar, beat=0.0):
        """Seconds at a 0-based bar and beat (beats can be fractional)."""
        return (bar * self.beats_per_bar + beat) * 60.0 / self.bpm

    def instrument(self, name, program=None):
        """Add a MIDI track; `program` defaults to PROGRAMS[name], or DRUM_KITS[name] for a drum
        track (notes are then PERC sounds)."""
        drum = name in DRUM_KITS
        if program is None:
            program = DRUM_KITS[name] if drum else PROGRAMS[name]
        inst = pretty_midi.Instrument(program=program, is_drum=drum, name=name)
        self.midi.instruments.append(inst)
        return inst

    def note(self, inst, p, bar, beat, beats, vel=64):
        if isinstance(p, str):
            p = PERC[p] if inst.is_drum else pitch(p)
        start = self.t(bar, beat)
        inst.notes.append(pretty_midi.Note(vel, p, start, start + beats * 60.0 / self.bpm))

    def notes(self, inst, bar, events, vel=64):
        """Melody shorthand: events are (beat, beats, pitch) or (beat, beats, pitch, vel) from `bar`;
        beats past the bar line just carry into the following bars."""
        for e in events:
            self.note(inst, e[2], bar, e[0], e[1], e[3] if len(e) > 3 else vel)

    def chord(self, inst, pitches, bar, beat, beats, vel=56, roll=0.0):
        """Block chord, or rolled upwards by `roll` beats between notes (harp)."""
        for i, p in enumerate(pitches):
            self.note(inst, p, bar, beat + i * roll, beats - i * roll, vel)

    def sustain(self, inst, pitches, bar, beat, beats, vel=56):
        """Held chord that ties into the same pitches already sounding (no re-attack), for pads."""
        start, end = self.t(bar, beat), self.t(bar, beat + beats)
        for p in pitches:
            p = pitch(p) if isinstance(p, str) else p
            held = [n for n in inst.notes if n.pitch == p and abs(n.end - start) < 1e-6]
            if held:
                held[0].end = end
            else:
                inst.notes.append(pretty_midi.Note(vel, p, start, end))

    def swell(self, inst, bar, beat, beats, start=70, end=100, steps=12, cc=11):
        """Linear CC ramp (default CC11 expression) for string/choir swells."""
        for i in range(steps + 1):
            value = round(start + (end - start) * i / steps)
            inst.control_changes.append(
                pretty_midi.ControlChange(cc, value, self.t(bar, beat + beats * i / steps)))

    def loop(self, bars):
        """Mark the loop length. Everything sounding after this point (held notes, release, reverb)
        is folded back onto the start by render.py, so notes may cross the loop point."""
        self.midi.text_events.append(pretty_midi.Text(LOOP_END_TEXT, self.t(bars)))


def main(compose):
    """Write output/<track>/<track>.mid for the calling track file and return its path."""
    module = sys.modules[compose.__module__]
    name = Path(module.__file__).stem
    if getattr(module, "MOOD", None) not in MOODS:
        sys.exit(f"{name}: set MOOD to one of {', '.join(MOODS)} at the top of the track file")
    song = compose()
    out = OUTPUT / name / f"{name}.mid"
    out.parent.mkdir(parents=True, exist_ok=True)
    song.midi.write(str(out))
    print(f"MIDI: {out}")
    return out
