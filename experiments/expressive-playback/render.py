"""Play the score at a pianist's timing: the shell around expression.py.

Reads the score, the transcription and the alignment, and writes:
- performed.mid: every score note at the onset, length and velocity the pianist played it,
  with their sustain pedal;
- deadpan.mid: the score at the pianist's average tempo, one velocity and no pedal, for comparison
  (what the app plays now);
- performance.json: the performed score as data, one entry per score note, which is the shape
  the app would import.

    .venv/bin/python render.py data/bwv846/score.musicxml out/bwv846/transcribed.mid \
        out/bwv846/alignment.json out/bwv846
"""

import json
import sys
from pathlib import Path

import mido
import partitura as pt

import expression as ex

TICKS_PER_BEAT = 480
MICROSECONDS_PER_BEAT = 500_000  # 120 bpm: a second is 960 ticks


def read_score(path: str) -> list[ex.ScoreNote]:
    notes = pt.load_score(path).note_array(include_grace_notes=True)
    return [
        ex.ScoreNote(str(n["id"]), int(n["pitch"]), float(n["onset_beat"]), float(n["duration_beat"]))
        for n in notes
    ]


def read_performance(path: str) -> list[ex.PerformedNote]:
    notes = pt.load_performance_midi(path).note_array()
    return [
        ex.PerformedNote(
            str(n["id"]), int(n["pitch"]), float(n["onset_sec"]), float(n["duration_sec"]), int(n["velocity"])
        )
        for n in notes
    ]


def read_pedal(path: str) -> list[ex.Pedal]:
    changes, now = [], 0.0
    for message in mido.MidiFile(path):  # iterating a file yields delta times in seconds
        now += message.time
        if message.type == "control_change" and message.control == ex.SUSTAIN:
            changes.append((now, message.value))
    return ex.pedal_intervals(changes)


def write_midi(path: Path, notes: list[ex.PlayedNote], pedals: list[ex.Pedal]) -> None:
    track = mido.MidiTrack([mido.MetaMessage("set_tempo", tempo=MICROSECONDS_PER_BEAT, time=0)])
    ticks_per_second = TICKS_PER_BEAT * 1_000_000 / MICROSECONDS_PER_BEAT
    last = 0
    for seconds, kind, number, value in ex.midi_events(notes, pedals):
        tick = round(seconds * ticks_per_second)
        delta, last = tick - last, tick
        if kind in ("note_on", "note_off"):
            track.append(mido.Message(kind, note=number, velocity=value, time=delta))
        else:
            track.append(mido.Message("control_change", control=number, value=value, time=delta))
    file = mido.MidiFile(ticks_per_beat=TICKS_PER_BEAT)
    file.tracks.append(track)
    file.save(path)


def main(score_path: str, midi_path: str, alignment_path: str, out_dir: str) -> None:
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    score = read_score(score_path)
    performed = read_performance(midi_path)
    alignment = json.loads(Path(alignment_path).read_text())

    played, pedals = ex.shifted(ex.performance(score, performed, alignment), read_pedal(midi_path))
    by_id = {p.id: p for p in performed}
    paired = {s: by_id[p] for s, p in ex.matches(alignment).items() if p in by_id}
    flat = ex.deadpan(score, ex.average_seconds_per_beat(ex.time_map(score, paired)))

    write_midi(out / "performed.mid", played, pedals)
    write_midi(out / "deadpan.mid", flat, [])
    (out / "performance.json").write_text(
        json.dumps(
            {
                "notes": [n.__dict__ for n in played],
                "pedal": [p.__dict__ for p in pedals],
            },
            indent=1,
        )
    )
    missing = sum(not n.matched for n in played)
    print(
        f"{len(played)} notes ({missing} placed from their neighbours), {len(pedals)} pedal presses"
        f" → {out}/performed.mid, deadpan.mid, performance.json"
    )


if __name__ == "__main__":
    main(*sys.argv[1:5])
