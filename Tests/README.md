# Tests

## Layout

```
Tests/
├── Helpers/            — recording doubles shared across all test suites
│   ├── RecordingSink.swift       — ChordEventSink double; records play/stop calls
│   ├── RecordingNoteSink.swift   — NoteSink double; records the notes started and ended
│   ├── ManualClock.swift         — the app's SteppedClock under its test name; tick() and advance(beats:/seconds:) move time manually
│   ├── WaitUntil.swift           — waits for a condition instead of sleeping a fixed time
│   ├── HostedWindow.swift        — puts a view on screen in the test host's window, and redraws it
│   ├── KernelOfflineRig.swift    — the kernel's Audio Unit in an engine that renders offline
│   ├── Tone.swift                — a sine for an engine to hear at its input, and for measuring what was recorded
│   ├── RecordingLogger.swift     — Logger double (TODO Phase 3)
│   ├── StubPermissionGate.swift  — PermissionGate double (TODO Phase 4)
│   └── Expect+Voicing.swift      — #expect helpers for Voicing assertions
├── AudioTests/         — synth presets, the voice allocator, and the filter, effects chain, shared reverb, master bus and kernel unit in an offline engine
├── ModeTests/          — per-mode tests using recording doubles
│   └── PlayModeTests.swift
├── TimelineTests/      — the timeline: its edits, compile, and the player against a manual clock
├── ExportTests/        — the timeline as a Standard MIDI File, and as an audio file rendered through the kernel
├── ViewTests/          — real screens hosted in a window, redrawn while their state changes
├── UISpec/             — the UI spec: every screen drawn from the app's views as shapes and text (see below)
├── SinkTests/          — NotePlayerTests (chords into notes), MidiSinkTests
├── LoggingTests/       — (Phase 3) LoggerTests
└── PermissionTests/    — (Phase 4) MicrophonePermissionTests
```

The Music Theory Core has its own test suite under `Perfecto/Tests/MusicTheoryCoreTests/`, and the audio kernel under `Perfecto/Tests/PerfectoKernelTests/` (Swift Package tests, runnable via `swift test`).
The kernel's tests render it offline with no engine, and are built so that any memory allocated while rendering stops them.
`KernelAudioUnitTests`, here, checks the same kernel hosted as an Audio Unit in an offline engine.
`KernelLiveTests` runs the app's engine graph in real time on the simulator (no audio session): an engine treats a unit differently there than offline, and that difference once made the app silent.
`SampleRecorderTests` records and plays the mic sample through an offline engine that hears a tone.
`AudioOutputLiveTests` is the exception to the rule below: it opens and closes the mic through the app's own `AudioOutput`, with the real audio session.
On the simulator it passes whatever the engine does, since a session there always has an input; run it on a phone after changing `AudioGraph`, `AudioOutput` or `AudioSession`.

## Recording-double pattern

Tests never touch the audio hardware, CoreMIDI, or AVAudioSession (but for `AudioOutputLiveTests`, above).
`KernelAudioUnitTests` and `KernelSinkTests` run the audio kernel as the app hears it, in an engine that renders offline. The kernel's own tests are in the Perfecto package (`swift test` in `Perfecto/`).
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

## The UI spec

`scripts/export-ui-spec.sh [folder]` draws every screen of the app as vectors, not screenshots: a PDF and an SVG of each, and an `index.md` that lists them (by default in `build/ui-spec`).
The SVG files can be dropped into Figma or any other design tool, where the shapes and the text can be selected and measured.
`UISpecExportTests` does the drawing: it shows each screen in `SpecScreen`'s lists in a window, upright and on its side, and draws the window's layers into a PDF with `LayerDrawing`.
The script then makes the SVG files from the PDFs with MuPDF (`brew install mupdf-tools`).
A screen or state the spec should show is one more entry in `Tests/UISpec/SpecScreen.swift`.

The drawings are the app's own views, so they cannot drift from it, but they are one-way: nothing changed in a design tool comes back.
They leave out shadows, filters and masks (the index says which drawing had any), and the system's own controls (switches, sliders, segmented pickers) are drawn only roughly.
The text is real text in SF Mono, so a design tool without that font installed shows another in its place; the PDFs carry the glyphs themselves and always look right.
