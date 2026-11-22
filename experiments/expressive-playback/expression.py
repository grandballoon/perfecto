"""The functional core: the score played at a pianist's timing, from an alignment.

Everything here is a pure function over plain values, tested by equality in test_expression.py.
The scripts around it (transcribe.py, align.py, render.py) read and write the files.

A score note is where it is written (beats); a performed note is what the pianist played (seconds).
The alignment pairs them: a score note the pianist played is matched, one they left out is missing,
and a note they played that is not in the score is extra, which is dropped, since what is played
back is the score.
A missing note is placed by the timing of the notes around it (`TimeMap`) and given the velocity
of its matched neighbours, so every note of the score sounds.
"""

from __future__ import annotations

from bisect import bisect_right
from dataclasses import dataclass
from statistics import median


@dataclass(frozen=True)
class ScoreNote:
    id: str
    pitch: int
    onset_beat: float
    duration_beat: float


@dataclass(frozen=True)
class PerformedNote:
    id: str
    pitch: int
    onset: float  # seconds
    duration: float  # seconds
    velocity: int


@dataclass(frozen=True)
class Pedal:
    down: float  # seconds
    up: float  # seconds


@dataclass(frozen=True)
class PlayedNote:
    """A score note as it is to be played: its place in the score and in time."""

    score_id: str
    pitch: int
    onset_beat: float
    onset: float  # seconds
    duration: float  # seconds
    velocity: int
    matched: bool  # False: placed by the notes around it


@dataclass(frozen=True)
class TimeMap:
    """Beats to seconds, piecewise linear through the score's onsets the pianist played."""

    beats: tuple[float, ...]
    seconds: tuple[float, ...]

    def time(self, beat: float) -> float:
        i = bisect_right(self.beats, beat) - 1
        i = min(max(i, 0), len(self.beats) - 2)
        b0, b1 = self.beats[i], self.beats[i + 1]
        t0, t1 = self.seconds[i], self.seconds[i + 1]
        return t0 + (beat - b0) * (t1 - t0) / (b1 - b0)


def matches(alignment: list[dict]) -> dict[str, str]:
    """Score note id → performed note id, for the notes the pianist played."""
    return {
        a["score_id"]: a["performance_id"]
        for a in alignment
        if a["label"] == "match"
    }


def time_map(score: list[ScoreNote], performed: dict[str, PerformedNote]) -> TimeMap:
    """Each score onset with a played note in it, at the median time its notes were played.

    The median keeps a chord's notes, played a little apart, at one moment, and makes the map
    rise with the score however loosely a chord was spread.
    """
    times: dict[float, list[float]] = {}
    for note in score:
        if note.id in performed:
            times.setdefault(note.onset_beat, []).append(performed[note.id].onset)
    beats: list[float] = []
    seconds: list[float] = []
    for beat in sorted(times):
        t = median(times[beat])
        if seconds and t <= seconds[-1]:
            continue  # out of order: a stray match; the onsets either side place it
        beats.append(beat)
        seconds.append(t)
    if len(beats) < 2:
        raise ValueError("an alignment needs at least two onsets played to have a tempo")
    return TimeMap(tuple(beats), tuple(seconds))


def nearest_velocity(note: ScoreNote, played: list[PlayedNote]) -> int:
    """The velocity of the matched note nearest in the score, for a note left out."""
    nearest = min(played, key=lambda p: (abs(p.onset_beat - note.onset_beat), abs(p.pitch - note.pitch)))
    return nearest.velocity


def performance(
    score: list[ScoreNote],
    performed: list[PerformedNote],
    alignment: list[dict],
) -> list[PlayedNote]:
    """Every score note, played as the pianist played it or placed among the notes they did."""
    by_id = {p.id: p for p in performed}
    paired = {s: by_id[p] for s, p in matches(alignment).items() if p in by_id}
    tempo = time_map(score, paired)

    played = [
        PlayedNote(
            score_id=n.id,
            pitch=n.pitch,
            onset_beat=n.onset_beat,
            onset=paired[n.id].onset,
            duration=paired[n.id].duration,
            velocity=paired[n.id].velocity,
            matched=True,
        )
        for n in score
        if n.id in paired
    ]
    placed = [
        PlayedNote(
            score_id=n.id,
            pitch=n.pitch,
            onset_beat=n.onset_beat,
            onset=tempo.time(n.onset_beat),
            duration=tempo.time(n.onset_beat + n.duration_beat) - tempo.time(n.onset_beat),
            velocity=nearest_velocity(n, played),
            matched=False,
        )
        for n in score
        if n.id not in paired
    ]
    return sorted(played + placed, key=lambda p: (p.onset, p.pitch))


def deadpan(score: list[ScoreNote], seconds_per_beat: float, velocity: int = 64) -> list[PlayedNote]:
    """The score at one steady tempo and one loudness: what the app plays now."""
    return sorted(
        (
            PlayedNote(
                score_id=n.id,
                pitch=n.pitch,
                onset_beat=n.onset_beat,
                onset=n.onset_beat * seconds_per_beat,
                duration=n.duration_beat * seconds_per_beat,
                velocity=velocity,
                matched=False,
            )
            for n in score
        ),
        key=lambda p: (p.onset, p.pitch),
    )


def average_seconds_per_beat(tempo: TimeMap) -> float:
    """The pianist's tempo over the whole piece, so a deadpan rendering lasts as long."""
    return (tempo.seconds[-1] - tempo.seconds[0]) / (tempo.beats[-1] - tempo.beats[0])


def pedal_intervals(changes: list[tuple[float, int]]) -> list[Pedal]:
    """Sustain-pedal presses from its controller's changes (seconds, 0–127; 64 and up is down)."""
    pedals: list[Pedal] = []
    down: float | None = None
    for time, value in sorted(changes):
        if value >= 64 and down is None:
            down = time
        elif value < 64 and down is not None:
            pedals.append(Pedal(down, time))
            down = None
    return pedals


SUSTAIN = 64


def midi_events(notes: list[PlayedNote], pedals: list[Pedal]) -> list[tuple[float, str, int, int]]:
    """The notes and pedal as timed MIDI messages: (seconds, kind, number, value), in order.

    At one moment a note-off goes before a note-on, so a key struck again is heard again,
    and the pedal goes down after the notes it catches.
    """
    order = {"note_off": 0, "pedal_up": 1, "note_on": 2, "pedal_down": 3}
    events = [(n.onset, "note_on", n.pitch, n.velocity) for n in notes]
    events += [(n.onset + n.duration, "note_off", n.pitch, 0) for n in notes]
    events += [(p.down, "pedal_down", SUSTAIN, 127) for p in pedals]
    events += [(p.up, "pedal_up", SUSTAIN, 0) for p in pedals]
    return sorted(events, key=lambda e: (e[0], order[e[1]], e[2]))


def shifted(notes: list[PlayedNote], pedals: list[Pedal]) -> tuple[list[PlayedNote], list[Pedal]]:
    """Notes and pedal moved together so the first note is at 0 (a recording's silence cut off)."""
    start = min(n.onset for n in notes)
    return (
        [PlayedNote(**{**n.__dict__, "onset": n.onset - start}) for n in notes],
        [Pedal(max(p.down - start, 0.0), p.up - start) for p in pedals if p.up > start],
    )
