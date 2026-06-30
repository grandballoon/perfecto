# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

**Perfecto** — an iOS chord performance instrument. The full v1 spec is in `spec.md`.

Stack: iOS 17+, iPhone (portrait + landscape), Swift 6, SwiftUI, AudioKit 5.x, MVVM with `@Observable`, CoreMIDI.

## Architecture

The codebase is split into strict layers with no upward dependencies:

```
SwiftUI Views
    ↓
ViewModels (@Observable): PerformanceState, LooperState, SequencerState
    ↓
Performance Engine: PerformanceMode protocol + 9 per-mode implementations
    ↓
Music Theory Core  ← PURE Swift only (Int/Array, no UIKit/AudioKit/Foundation)
    ↓
ChordEventSink protocol
    ├── AudioSink  →  AudioKit engine
    └── MidiSink   →  CoreMIDI
```

**Music Theory Core purity is a hard constraint.** It is pure Swift (Int/Array only), testable in isolation as pure functions of its inputs. Never add UIKit, AudioKit, or Foundation imports to anything under `Core/MusicTheory/`.

**ChordEventSink decouples event generation from consumption.** `AudioSink` and `MidiSink` both receive the same `ChordEvent`s independently — neither knows about the other.

**MasterClock drives all tempo-aware modes.** Arpeggio, Repeat, Sequencer, and Looper all use it. It is behind a `ClockTickable` protocol so test doubles can replace it without changing callers.

**Adding a performance mode = adding one file.** Each mode implements `PerformanceMode`; no core changes are needed.

## Key data types

```swift
// Music Theory Core
PitchClass, ScaleType (10 scales), Key, Degree (I–vii°)
JoystickMode (.default, .extended, .chromatic)  — three modes × 9 directions = 27 chord transformations
ChordQuality  — 30+ qualities; encoded as QualityTransform (addDegrees, replaceMap, shiftMap)
Voicing { notes: [Int], bassNote: Int? }  // MIDI note numbers

// The central function
func computeVoicing(key:degree:joystickMode:joystickDirection:inversion:octave:voiceLeading:previousVoicing:) -> Voicing
```

## Build order

Implement in this sequence — each step is independently testable:

1. Music Theory Core + unit tests (foundation; no UI/audio)
2. AudioKit "hello sine wave" on device
3. SynthVoice + AudioSink + minimal PerformanceView (press button → hear chord)
4. JoystickView wiring
5. Key sheet + Sound sheet
6. Non-clock modes: Play, Strum, Lead, Drone
7. MasterClock + Arpeggio, Repeat modes
8. MidiSink (test with GarageBand)
9. Sequencer mode + screen
10. Looper (2-track, sample-accurate) — heaviest piece
11. Mic Sample mode
12. Effects chain + controls
13. SamplerVoice + bundled SFZ instruments
14. Haptics, polish, edge cases

## Testing

The `(joystickMode, direction) → ChordQuality` mapping table and `computeVoicing` are the core testable surfaces. Every entry in the joystick transformation table becomes a test assertion on `Voicing.notes`. Full combinatorial space is ~68K; test structural rules + representative samples, not exhaustive coverage.

Swift Testing (`@Test`, `#expect`) is the default for all new test files.

```swift
XCTAssertEqual(
    computeVoicing(key: Key(root: .C, scale: .major), degree: .I,
                   joystickMode: .default, joystickDirection: .right,
                   inversion: .root, octave: 4, voiceLeading: false, previousVoicing: nil).notes,
    [60, 64, 67, 71]  // Cmaj7
)
```

Tests live in `Tests/MusicTheoryTests/` and `Tests/ModeTests/`.

## Audio session

- 48kHz, 256-sample buffer (~5.3ms latency)
- `AVAudioSession` category: `.playAndRecord` with `mixWithOthers` — app must coexist with DAWs
- Looper requires background audio: `.playback` mode + `UIBackgroundModes` entitlement

## MIDI

App registers as a virtual MIDI source named "Perfecto". Channel 1, velocity 100 fixed in v1. No MIDI input, CC messages, program change, or clock sync in v1.

## V1 scope

- Modes 1–9: Play, Strum, Lead, Drone, Arpeggio, Repeat, Sequencer, Looper (2-track), Mic Sample
- Drum module deferred
- All 10 scales, all 12 keys, all 3 joystick modes (28 chord types), all 3 inversions
- Synth engine (8 presets) + sample engine (SFZ, ≤250MB bundle)
- MIDI out
- Light + dark mode

## Logging

When adding a feature, identify its load-bearing events and emit `LogEvent` cases for them. Event types live in `Perfecto/Sources/Logging/LogEvent.swift`. Pass `Logger` via constructor injection; production uses `FileLogger`, tests use `RecordingLogger`.

## Known risks (watch for)

- **Virtual joystick zone detection** — 8 zones by thumb-drag is harder than physical; may need visual zone-highlighting or wider deadbands. Prototype early.
- **Looper sample-accuracy** — small timing bugs cause audible drift. Test against a metronome reference throughout, not just at the end.
- **Inversion + voice leading + chord lock interactions** — subtle; write explicit test cases for combinations before shipping.
