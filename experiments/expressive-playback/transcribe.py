"""Transcribe a solo piano recording to MIDI: notes, velocities and the sustain pedal.

Uses Kong et al.'s high-resolution piano transcription (note F1 0.97, pedal F1 0.92 on MAESTRO).

    .venv/bin/python transcribe.py data/bwv846/ishizaka.flac out/bwv846/transcribed.mid
"""

import sys
from pathlib import Path

import librosa
import torch
from piano_transcription_inference import PianoTranscription, sample_rate

CHECKPOINT = Path(__file__).parent / "models" / "kong_note_pedal.pth"


def main(audio_path: str, midi_path: str) -> None:
    Path(midi_path).parent.mkdir(parents=True, exist_ok=True)
    audio, _ = librosa.load(audio_path, sr=sample_rate, mono=True)
    device = torch.device("mps" if torch.backends.mps.is_available() else "cpu")
    transcriber = PianoTranscription(device=device, checkpoint_path=str(CHECKPOINT))
    result = transcriber.transcribe(audio, midi_path)
    notes = result["est_note_events"]
    pedals = result["est_pedal_events"]
    print(f"{len(notes)} notes and {len(pedals)} pedal presses → {midi_path}")


if __name__ == "__main__":
    main(*sys.argv[1:3])
