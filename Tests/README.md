# Tests

## Layout

```
Tests/
├── Helpers/            — recording doubles shared across all test suites
│   ├── RecordingSink.swift       — ChordEventSink double; records play/stop calls
│   ├── RecordingNoteSink.swift   — NoteSink double; records the notes started and ended
│   ├── ManualClock.swift         — ClockTickable double; tick() and advance(beats:/seconds:) move time manually
│   ├── WaitUntil.swift           — waits for a condition instead of sleeping a fixed time
│   ├── OfflineTone.swift         — renders a tone through real AudioKit nodes in an offline engine
│   ├── RecordingLogger.swift     — Logger double (TODO Phase 3)
│   ├── StubPermissionGate.swift  — PermissionGate double (TODO Phase 4)
│   └── Expect+Voicing.swift      — #expect helpers for Voicing assertions
├── AudioTests/         — synth presets, the voice allocator, and the filter, effects chain, shared reverb, master bus and kernel unit in an offline engine
├── ModeTests/          — per-mode tests using recording doubles
│   └── PlayModeTests.swift
├── TimelineTests/      — the timeline: its edits, compile, and the player against a manual clock
├── ExportTests/        — sequencer → Standard MIDI File rendering
├── ViewTests/          — real screens hosted in a window, redrawn while their state changes
├── SinkTests/          — NotePlayerTests (chords into notes), MidiSinkTests
├── LoggingTests/       — (Phase 3) LoggerTests
└── PermissionTests/    — (Phase 4) MicrophonePermissionTests
```

The Music Theory Core has its own test suite under `Perfecto/Tests/MusicTheoryCoreTests/`, and the audio kernel under `Perfecto/Tests/PerfectoKernelTests/` (Swift Package tests, runnable via `swift test`).
The kernel's tests render it offline with no engine, and are built so that any memory allocated while rendering stops them.
`KernelAudioUnitTests`, here, checks the same kernel hosted as an Audio Unit in an offline engine.

## Recording-double pattern

Tests never touch the audio hardware, CoreMIDI, or AVAudioSession.
`EffectsChainTests`, `MasterBusTests` and `BrightnessFilterTests` are the suites that run AudioKit nodes, in an engine that renders offline.
Everything else injects doubles:

```swift
let sink  = RecordingSink()
let clock = ManualClock()
let state = PerformanceState(sink: sink, clock: clock)

state.press(degree: .I)
#expect(sink.playCalls.first?.notes == [60, 64, 67])  // Cmaj

clock.tick()  // advance clock manually to test timing-dependent modes
```

## Running tests

**Music Theory Core and the audio kernel (run on macOS):**
```
cd Perfecto && swift test
```

**App tests (require device or simulator):**
Use Xcode → Product → Test (⌘U), or select the PerfectoTests scheme.
