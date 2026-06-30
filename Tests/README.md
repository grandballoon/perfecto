# Tests

## Layout

```
Tests/
├── Helpers/            — recording doubles shared across all test suites
│   ├── RecordingSink.swift       — ChordEventSink double; records play/stop calls
│   ├── ManualClock.swift         — ClockTickable double; tick() advances time manually
│   ├── RecordingLogger.swift     — Logger double (TODO Phase 3)
│   ├── StubPermissionGate.swift  — PermissionGate double (TODO Phase 4)
│   └── Expect+Voicing.swift      — #expect helpers for Voicing assertions
├── ModeTests/          — per-mode tests using recording doubles
│   └── PlayModeTests.swift
├── SinkTests/          — (Phase 2) MidiSinkTests
├── LoggingTests/       — (Phase 3) LoggerTests
└── PermissionTests/    — (Phase 4) MicrophonePermissionTests
```

The Music Theory Core has its own test suite under `Perfecto/Tests/MusicTheoryCoreTests/` (Swift Package tests, runnable via `swift test`).

## Recording-double pattern

Tests never touch real AudioKit, CoreMIDI, or AVAudioSession. Instead they inject doubles:

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
