"""Pair each note of a score with the note a pianist played for it.

Uses parangonar's DualDTWNoteMatcher (JKU Linz) on partitura's note arrays.
Writes the alignment as JSON (for render.py) and as a match file, which the web viewer
Parangonda shows over a piano roll.

    .venv/bin/python align.py data/bwv846/score.musicxml out/bwv846/transcribed.mid out/bwv846/alignment
"""

import json
import sys
from collections import Counter
from pathlib import Path

import parangonar as pa
import partitura as pt


def main(score_path: str, midi_path: str, out_stem: str) -> None:
    score = pt.load_score(score_path)
    performance = pt.load_performance_midi(midi_path)
    score_notes = score.note_array(include_grace_notes=True)
    performed_notes = performance.note_array()

    alignment = pa.DualDTWNoteMatcher()(score_notes, performed_notes)

    Path(out_stem).parent.mkdir(parents=True, exist_ok=True)
    Path(f"{out_stem}.json").write_text(json.dumps(alignment, indent=1))
    pt.save_match(alignment, performance, score, f"{out_stem}.match", assume_unfolded=True)

    labels = Counter(a["label"] for a in alignment)
    print(
        f"{labels['match']} of {len(score_notes)} score notes matched, "
        f"{labels['deletion']} left out, {labels['insertion']} extra played notes"
        f" → {out_stem}.json, .match"
    )


if __name__ == "__main__":
    main(*sys.argv[1:4])
