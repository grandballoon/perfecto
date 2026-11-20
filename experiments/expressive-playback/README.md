# Expressive playback experiments

Trying ways to play a score as a pianist would, offline, before anything is built into the app.
The research behind it is in the Knowledge base doc, under "Research: expressive MIDI playback of scores".

This first experiment lines up a real pianist's recording with the score.
It plays every note of the score at the moment, length and velocity the pianist played it, with their sustain pedal.

## Run it

```sh
./run.sh
```

The first run makes a Python environment and downloads about 200 MB: the recording, the score and the transcription model.
Transcribing takes about two minutes on an M2, and its result is kept; aligning and rendering take seconds.

## What it makes

Everything lands in `out/bwv846/`:

| File | What it is |
|---|---|
| `performed.mid` | The score at the pianist's timing, velocity and pedal: the thing to listen to. |
| `deadpan.mid` | The score at the pianist's average tempo, one velocity, no pedal: what the app plays now. |
| `transcribed.mid` | What the transcriber heard in the recording, extra notes and all. |
| `alignment.json`, `alignment.match` | Which played note is each score note. The match file opens in the Parangonda web viewer. |
| `performance.json` | The performed score as data, one entry per score note: the shape the app would import. |

Open the MIDI files in GarageBand (or play them through Pianoteq) and compare them with the recording, `data/bwv846/ishizaka.flac`.

## The steps

1. `transcribe.py`: the recording to MIDI, with Kong et al.'s high-resolution piano transcription (notes, velocities and the sustain pedal).
2. `align.py`: each score note paired with a played note, by parangonar's `DualDTWNoteMatcher` on partitura's note arrays.
3. `render.py`: the score played by the alignment, through `expression.py`.

`expression.py` is the functional core: pure functions over values, tested by equality in `test_expression.py`.
The three scripts are the shell that reads and writes files.
A score note the pianist left out is placed by the timing of the notes around it and given the velocity of the nearest note played.
A note the pianist played that is not in the score is dropped, since what is played back is the score.

```sh
.venv/bin/python -m pytest -q
```

## First result: Prelude 1 in C, BWV 846

- 556 notes and 29 pedal presses transcribed from a 2:43 recording.
- 548 of the score's 549 notes matched; 1 left out and 8 extra notes played (or heard by the transcriber).

## Sources and licenses

- Recording: Kimiko Ishizaka, Open Well-Tempered Clavier, Book 1, from Wikimedia Commons; public domain.
- Score: the ASAP dataset's MusicXML of BWV 846; CC BY-NC-SA 4.0, fine for experiments but not for shipping in the app.
  The Open Well-Tempered Clavier's own score is CC0, but musescore.com refuses scripted downloads, so it is not fetched here.
- Transcription model: Kong et al., from Zenodo.
- Data, models and output are not committed (`.gitignore`); `run.sh` fetches them again.
