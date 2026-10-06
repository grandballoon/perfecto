# Tests

## Layout

```
Tests/
├── Helpers/            — recording doubles shared across all test suites
│   ├── RecordingSink.swift       — ChordEventSink double; records play/stop calls
│   ├── ManualClock.swift         — ClockTickable double; tick() advances time manually
│   ├── WaitUntil.swift           — waits for a condition instead of sleeping a fixed time
│   ├── OfflineTone.swift         — renders a tone through real AudioKit nodes in an offline engine
│   ├── RecordingLogger.swift     — Logger double (TODO Phase 3)
│   ├── StubPermissionGate.swift  — PermissionGate double (TODO Phase 4)
│   └── Expect+Voicing.swift      — #expect helpers for Voicing assertions
├── AudioTests/         — synth presets, loop arithmetic, and the looper, filter, effects chain, shared reverb and master bus in an offline engine
├── ModeTests/          — per-mode tests using recording doubles
│   └── PlayModeTests.swift
├── ExportTests/        — sequencer → Standard MIDI File rendering
├── ViewTests/          — real screens hosted in a window, redrawn while their state changes
├── SinkTests/          — (Phase 2) MidiSinkTests
├── LoggingTests/       — (Phase 3) LoggerTests
└── PermissionTests/    — (Phase 4) MicrophonePermissionTests
```

The Music Theory Core has its own test suite under `Perfecto/Tests/MusicTheoryCoreTests/` (Swift Package tests, runnable via `swift test`).

## Recording-double pattern

Tests never touch the audio hardware, CoreMIDI, or AVAudioSession.
`LooperTests`, `EffectsChainTests`, `MasterBusTests` and `BrightnessFilterTests` are the suites that run AudioKit nodes, in an engine that renders offline.
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

**Music Theory Core (pure Swift, runs on macOS):**
```
cd Perfecto && swift test
```

**App tests (require device or simulator):**
Use Xcode → Product → Test (⌘U), or select the PerfectoTests scheme.
