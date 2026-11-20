#!/bin/sh
# Prelude 1 in C (BWV 846), from a public domain recording to the score played at its timing.
# Downloads on first run: the recording (41 MB), the score (270 KB) and the transcriber (165 MB).
set -eu
cd "$(dirname "$0")"

if [ ! -d .venv ]; then
  python3 -m venv .venv
  .venv/bin/pip install -q -r requirements.txt
fi

mkdir -p models data/bwv846 out/bwv846
[ -f models/kong_note_pedal.pth ] || curl -sL -o models/kong_note_pedal.pth \
  "https://zenodo.org/record/4034264/files/CRNN_note_F1%3D0.9677_pedal_F1%3D0.9186.pth?download=1"
[ -f data/bwv846/ishizaka.flac ] || curl -sL -A "perfecto-experiment/0.1" -o data/bwv846/ishizaka.flac \
  "https://upload.wikimedia.org/wikipedia/commons/6/6b/Kimiko_Ishizaka_-_Bach-_Well-Tempered_Clavier%2C_Book_1_-_01_Prelude_No._1_in_C_major%2C_BWV_846.flac"
[ -f data/bwv846/score.musicxml ] || curl -sL -o data/bwv846/score.musicxml \
  "https://raw.githubusercontent.com/fosfrancesco/asap-dataset/master/Bach/Prelude/bwv_846/xml_score.musicxml"

[ -f out/bwv846/transcribed.mid ] || .venv/bin/python transcribe.py data/bwv846/ishizaka.flac out/bwv846/transcribed.mid
.venv/bin/python align.py data/bwv846/score.musicxml out/bwv846/transcribed.mid out/bwv846/alignment
.venv/bin/python render.py data/bwv846/score.musicxml out/bwv846/transcribed.mid out/bwv846/alignment.json out/bwv846
