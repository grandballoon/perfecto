> **Legacy document.** Written in July 2026, before the ongoing refactor; kept for reference only.
> It may not match the current code — check the source before relying on it.

# Data Structures

This section catalogs the major data shapes in the repo, grouped by architectural layer (see the diagram in [CLAUDE.md](../../CLAUDE.md)).
Each entry names the abstract type, gives its definition, and lists where it is defined and used.

## Music Theory Core

These are pure Swift value types (Int/Array only, no UIKit/AudioKit/Foundation).
They are the foundation the whole app is built on and are exhaustively unit-tested in isolation.

### `PitchClass`

Enum (Int-backed, 0–11). One of the twelve chromatic pitch classes (`C = 0` … `B = 11`), plus a `name` string.
Defined in [PitchClass.swift](../../Perfecto/Sources/MusicTheoryCore/PitchClass.swift).
Used everywhere a note or key root is named: as the root of a `Key`, as the reference point for MIDI note math in `computeVoicing`, and in chord-label display (`PerformanceState.displayText`).

```swift
public enum PitchClass: Int, CaseIterable, Hashable, Identifiable, Sendable {
    case C = 0, Cs, D, Ds, E, F, Fs, G, Gs, A, As, B
    public var id: Int { rawValue }
    public var name: String { /* "C", "C#", … */ }
}
```

### `ScaleType`

Enum (10 cases). The available scales — major, natural/harmonic/melodic minor, major/minor pentatonic, blues, dorian, mixolydian, lydian.
Carries a `displayName` and, load-bearingly, an `intervals: [Int]` array of semitone offsets that defines the scale.
Defined in [Scale.swift](../../Perfecto/Sources/MusicTheoryCore/Scale.swift).
Used by `computeVoicing` (to place chord roots and detect chord quality), by lead-note math in `PerformanceState`, and in the Key sheet UI.

```swift
public enum ScaleType: CaseIterable, Hashable, Identifiable, Sendable {
    case major, naturalMinor, harmonicMinor, melodicMinor,
         majorPentatonic, minorPentatonic, blues, dorian, mixolydian, lydian
    public var id: Self { self }
    public var displayName: String { /* "Major", "Natural Minor", … */ }
    public var intervals: [Int] {
        switch self {
        case .major:        return [0, 2, 4, 5, 7, 9, 11]
        case .naturalMinor: return [0, 2, 3, 5, 7, 8, 10]
        // … one semitone-offset array per scale
        }
    }
}
```

### `Key`

Struct (value type). A `root: PitchClass` + `scale: ScaleType` pair — the current tonal context.
Defined in [Key.swift](../../Perfecto/Sources/MusicTheoryCore/Key.swift).
Held as mutable state on `PerformanceState`; consumed by `computeVoicing`; edited via the Key sheet and the radial/swipe key selectors ([KeyQuickSelect.swift](../../Views/KeyQuickSelect.swift)).

```swift
public struct Key: Equatable, Hashable, Sendable {
    public let root: PitchClass
    public let scale: ScaleType
}
```

### `Degree`

Enum (Int-backed, 1–7). A Nashville-number scale degree (`I`, `ii`, `iii`, `IV`, `V`, `vi`, `viiDim`), with an `index` (zero-based) and a `numeralLabel`.
Defined in [Degree.swift](../../Perfecto/Sources/MusicTheoryCore/Degree.swift); `numeralLabel` extension in [SequencerState.swift](../../ViewModels/SequencerState.swift).
Identifies which chord button was pressed — threaded through the whole `PerformanceMode` interface, stored in each `SequencerStep`, and displayed on chord buttons.

```swift
public enum Degree: Int, CaseIterable, Hashable, Sendable {
    case I = 1, ii, iii, IV, V, vi, viiDim
    public var index: Int { rawValue - 1 }   // zero-based index into scale intervals
}
```

### `JoystickMode`, `JoystickDirection`, `Inversion`

Enums. `JoystickMode` (`default`/`extended`/`chromatic`) selects a chord-color palette; `JoystickDirection` is the 8-way + center thumb position; `Inversion` (`root`/`first`/`second`) selects chord inversion.
Defined in [JoystickTypes.swift](../../Perfecto/Sources/MusicTheoryCore/JoystickTypes.swift).
The `(mode, direction)` pair is the key into the joystick transformation table; used by `computeVoicing`, `PerformanceState`, `SequencerStep`, and the joystick UI ([JoystickView.swift](../../Views/JoystickView.swift)).

```swift
public enum JoystickMode: Hashable, Sendable {
    case `default`, extended, chromatic
}

public enum JoystickDirection: Hashable, Sendable {
    case center, up, upRight, right, downRight, down, downLeft, left, upLeft
}

public enum Inversion: Sendable {
    case root, first, second
}
```

### `JoystickOutcome` / `JoystickMap`

`JoystickOutcome` is a struct of three interval arrays (`major`/`minor`/`dim`) — the chord to build depending on the base triad quality of the degree.
`JoystickMap` is the static lookup that maps every `(JoystickMode, JoystickDirection)` to a `JoystickOutcome` via three hardcoded tables.
Defined in [JoystickMap.swift](../../Perfecto/Sources/MusicTheoryCore/JoystickMap.swift) (internal, not public).
This is the encoded "27 chord transformations" table; consumed only by `computeVoicing`, and asserted in [JoystickMapTests.swift](../../Perfecto/Tests/MusicTheoryCoreTests/JoystickMapTests.swift).

```swift
// Chord intervals (semitones from chord root) per joystick direction,
// with a variant for each base triad quality.
struct JoystickOutcome: Sendable {
    let major: [Int]
    let minor: [Int]
    let dim:   [Int]
}

enum JoystickMap {
    static func outcome(mode: JoystickMode, direction: JoystickDirection) -> JoystickOutcome

    private static let defaultTable:   [JoystickDirection: JoystickOutcome] = [ /* … */ ]
    private static let extendedTable:  [JoystickDirection: JoystickOutcome] = [ /* … */ ]
    private static let chromaticTable: [JoystickDirection: JoystickOutcome] = [ /* … */ ]
}
```

### `Voicing`

Struct (value type). The central output of the theory core: `notes: [Int]` (MIDI note numbers, kept sorted) + optional `bassNote: Int?` for slash chords.
Defined in [Voicing.swift](../../Perfecto/Sources/MusicTheoryCore/Voicing.swift).
Produced by `computeVoicing` and passed across the `ChordEventSink` boundary to audio and MIDI. Every mode, both sinks, and the theory tests traffic in `Voicing`.

```swift
public struct Voicing: Equatable, Sendable {
    public let notes: [Int]      // MIDI note numbers, sorted low to high
    public let bassNote: Int?    // optional slash-chord bass

    public init(notes: [Int], bassNote: Int? = nil) {
        self.notes = notes.sorted()
        self.bassNote = bassNote
    }
}
```

`computeVoicing(key:degree:joystickMode:joystickDirection:inversion:octave:voiceLeading:previousVoicing:) -> Voicing` in [ComputeVoicing.swift](../../Perfecto/Sources/MusicTheoryCore/ComputeVoicing.swift) is the pure function that combines all of the above into a `Voicing`.

```swift
public func computeVoicing(
    key: Key,
    degree: Degree,
    joystickMode: JoystickMode,
    joystickDirection: JoystickDirection,
    inversion: Inversion,
    octave: Int,
    voiceLeading: Bool,
    previousVoicing: Voicing?
) -> Voicing
```

## Events & Clock

### `ChordEventSink`

Protocol (`@MainActor`, class-bound). The decoupling seam: `playChord(_:)` / `stopChord()`. Producers (modes) never know who consumes.
Defined in [ChordEventSink.swift](../../Core/Events/ChordEventSink.swift).
Implemented by `AudioSink`, `MidiSink`, and `CompositeSink` ([CompositeSink.swift](../../Core/Events/CompositeSink.swift)), which fans one event out to many sinks. `RecordingSink` is the test double.

```swift
@MainActor
protocol ChordEventSink: AnyObject {
    func playChord(_ voicing: Voicing)
    func stopChord()
}
```

### `ClockTickable` / `MasterClock`

`ClockTickable` is a protocol (`bpm`, `start`, `stop`, `onTick`) abstracting the tempo clock; `MasterClock` is the production `Timer`-based implementation firing at 1/16-note resolution.
Defined in [MasterClock.swift](../../Core/Clock/MasterClock.swift). `ManualClock` is the test double ([ManualClock.swift](../../Tests/Helpers/ManualClock.swift)).
Drives all tempo-aware modes: Arpeggio, Repeat, Sequencer, Looper. Owned by `PerformanceState`.

```swift
@MainActor
protocol ClockTickable: AnyObject {
    var bpm: Double { get set }
    func start()
    func stop()
    func onTick(_ handler: @escaping @MainActor () -> Void)
}

@MainActor
final class MasterClock: ClockTickable {   // Timer firing one tick per 1/16 note
    var bpm: Double = 120
    var isRunning: Bool { timer != nil }
}
```

### `PerformanceMode`

Protocol (`@MainActor`, class-bound). The strategy interface for the nine performance modes: `name`, `requiresClock`, and lifecycle callbacks (`onButtonDown/Up`, `onJoystickChange`, `onClockTick`, `deactivate`).
Defined in [PerformanceMode.swift](../../Modes/PerformanceMode.swift).
Implemented once per file under [Modes/](../../Modes/) (Play, Strum, Lead, Drone, Arpeggio, Repeat, Sequencer, Looper, MicSample). `PerformanceState` holds the active one and forwards user input to it.

```swift
@MainActor
protocol PerformanceMode: AnyObject {
    var name: String { get }
    var requiresClock: Bool { get }
    func onButtonDown(degree: Degree, state: PerformanceState)
    func onButtonUp(degree: Degree, state: PerformanceState)
    func onJoystickChange(direction: JoystickDirection, state: PerformanceState)
    func onClockTick(state: PerformanceState)
    func deactivate(state: PerformanceState)
}
```

## ViewModels / State

All are `@Observable @MainActor` reference types — the mutable UI-facing state.

### `PerformanceState`

The central app-state object: current `Key`, `octave`, `joystickMode`, `synthPreset`, `bpm`, `chordGridLayout`, the active `PerformanceMode`, and read-only "what's playing now" fields (`activeDegree`, `currentVoicing`, `activeVoicingText`).
Owns the child states (`SequencerState`, `LooperState`, `MicSampleState`, `QuickLoopState`) and the injected sink/clock/logger/mic-gate.
Defined in [PerformanceState.swift](../../ViewModels/PerformanceState.swift).
The environment object for the entire performance UI ([PerformanceView.swift](../../Views/PerformanceView.swift) and its children).

```swift
@Observable @MainActor
final class PerformanceState {
    var key = Key(root: .C, scale: .major)
    var octave = 4
    var joystickMode: JoystickMode = .default
    var synthPreset: SynthPreset = .sinePad
    var bpm: Double = 120
    var chordGridLayout: ChordGridLayout = .circle
    var isExternalSynth: Bool = false

    private(set) var mode: any PerformanceMode = PlayMode()
    private(set) var joystickDirection: JoystickDirection = .center
    private(set) var activeDegree: Degree? = nil
    private(set) var currentVoicing: Voicing? = nil
    private(set) var activeVoicingText = "—"

    let sequencerState = SequencerState()
    let looperState    = LooperState()
    let micSampleState = MicSampleState()
    let quickLoopState: QuickLoopState
    // + injected sink / engine / clock / logger / micGate
}
```

### `SequencerStep` / `SequencerState`

`SequencerStep` is a struct: `degree`, `joystickMode`, `joystickDirection`, `gate` (hold fraction), `isRest`. One per 1/16 note.
`SequencerState` holds the `[SequencerStep]` pattern (1/2/4 bars × 16 steps), playhead/edit cursors, `bars`/`currentPage`/`chain` pagination, an undo stack, and `UserDefaults` persistence (v1→v2 migration).
Defined in [SequencerState.swift](../../ViewModels/SequencerState.swift).
Backs the Sequencer mode and its editor grid ([SequencerView.swift](../../Views/SequencerView.swift)).

```swift
struct SequencerStep {
    var degree: Degree = .I
    var joystickMode: JoystickMode = .default
    var joystickDirection: JoystickDirection = .center
    var gate: Double = 0.75     // fraction of step to hold chord (0...1)
    var isRest: Bool = false
}

@Observable @MainActor
final class SequencerState {
    var steps: [SequencerStep] = Array(repeating: SequencerStep(), count: 16)
    var currentStep: Int = -1   // -1 = stopped; else global playhead index
    var selectedStep: Int = 0   // step being edited
    var isPlaying: Bool = false
    var swing: Double = 0
    private(set) var bars: Int = 1   // 1, 2, or 4 pages of 16 steps
    var currentPage: Int = 0
    var chain: Bool = true
    // + undo stack and UserDefaults persistence (v1 → v2 migration)
}
```

### `LoopTrack` / `TrackPhase` / `LooperState`

`TrackPhase` is an enum (`empty`/`recording`/`playing`/`stopped`). `LoopTrack` is a struct: `phase`, `isMuted`, `volume`.
`LooperState` holds the two tracks, `loopLengthTicks`, and one-shot pending command flags (`pendingRecord/Stop/Clear`) that `LooperMode` consumes on the clock tick.
Defined in [LooperState.swift](../../ViewModels/LooperState.swift).
Backs the 2-track Looper mode and [LooperView.swift](../../Views/LooperView.swift).

```swift
enum TrackPhase: Equatable { case empty, recording, playing, stopped }

struct LoopTrack {
    var phase: TrackPhase = .empty
    var isMuted: Bool = false
    var volume: Float = 1.0
    var hasContent: Bool { phase != .empty }
}

@Observable @MainActor
final class LooperState {
    var tracks: [LoopTrack] = [LoopTrack(), LoopTrack()]
    var loopLengthTicks: Int = 0   // track 0 sets it; track 1 quantizes to multiples
    // one-shot command flags consumed by LooperMode on the clock tick:
    var pendingRecord: Int? = nil
    var pendingStop:   Int? = nil
    var pendingClear:  Int? = nil
}
```

### `QuickLoopEntry` / `QuickLoopState`

`QuickLoopEntry` is an `Identifiable` struct (`id`, `trackIndex`, `isPlaying`). `QuickLoopState` is a small state machine (`Phase` = `idle`/`recording`) managing up to six overdub loops on the `quickLooper`.
Defined in [QuickLoopState.swift](../../ViewModels/QuickLoopState.swift).
Powers the one-button quick-loop overlay; unit-tested in [QuickLoopStateTests.swift](../../Tests/ViewModelTests/QuickLoopStateTests.swift).

```swift
struct QuickLoopEntry: Identifiable {
    let id = UUID()
    let trackIndex: Int
    var isPlaying: Bool = true
}

@Observable @MainActor
final class QuickLoopState {
    enum Phase: Equatable { case idle, recording }
    private(set) var phase: Phase = .idle
    private(set) var loops: [QuickLoopEntry] = []
    static let maxLoops = 6
}
```

### `MicSampleState` / `PermissionFlowStep`

`PermissionFlowStep` enum (`prePrompt`/`settingsRedirect`/`restricted`); `MicSampleState` holds `isRecording`, `hasContent`, and the active `permissionFlow`.
Defined in [MicSampleState.swift](../../ViewModels/MicSampleState.swift).
Backs Mic Sample mode and its permission flow UI ([MicSampleView.swift](../../Views/MicSampleView.swift), [PermissionFlowView.swift](../../Views/PermissionFlowView.swift)).

```swift
enum PermissionFlowStep { case prePrompt, settingsRedirect, restricted }

@Observable @MainActor
final class MicSampleState {
    var isRecording: Bool = false
    var hasContent:  Bool = false
    var permissionFlow: PermissionFlowStep? = nil
}
```

### UI layout/style enums

`ChordGridLayout` (`grid`/`circle`/`horizontalBar`, in [PerformanceState.swift](../../ViewModels/PerformanceState.swift)) and `KeyQuickStyle` (`wheel`/`swipe`, in [KeyQuickSelect.swift](../../Views/KeyQuickSelect.swift)) are stored on `PerformanceState` and choose which chord-grid / key-selector presentation the views render.

```swift
enum ChordGridLayout: CaseIterable { case grid, circle, horizontalBar }
enum KeyQuickStyle: String, CaseIterable { case wheel, swipe }
```

## Audio & MIDI (sink implementations)

### `SynthPreset`

Enum (Int-backed, 8 cases). The synth presets (Saw Lead, Square Bass, Sine Pad, …), each carrying its `Table` waveform and ADSR/amplitude `AUValue`s.
Defined in [SynthPreset.swift](../../Audio/SynthPreset.swift).
Stored on `PerformanceState`; applied by `AudioSink.setPreset`; chosen in the Sound sheet ([SoundSheet.swift](../../Views/Sheets/SoundSheet.swift)).

```swift
enum SynthPreset: Int, CaseIterable, Identifiable, Sendable {
    case sawLead, squareBass, sinePad, triangleBell, fmBell, fmBass, pluck, brass
    var id: Int { rawValue }
    var name: String    { /* "Saw Lead", … */ }
    var table: Table    { /* waveform per preset */ }
    var attack: AUValue  // + decay, sustain, release, amplitude (ADSR)
}
```

### `AudioSink`, `Looper`, `MicSampler`

Reference types wrapping the AudioKit graph. `AudioSink` drives six polyphonic `SynthVoice`s and owns two `Looper`s (2-track + 6-track quick-loop) and a `MicSampler`.
`Looper` manages per-track `NodeRecorder`/`AudioPlayer` arrays for sample-accurate recording/playback.
Defined in [AudioSink.swift](../../Audio/AudioSink.swift), [Looper.swift](../../Audio/Looper.swift), [MicSampler.swift](../../Audio/MicSampler.swift).
The audio consumer of `Voicing` events; the Looper/MicSampler back their respective modes.

```swift
@MainActor
final class AudioSink: ChordEventSink {
    private let engine     = AudioEngine()
    private var voices:    [SynthVoice] = []   // six polyphonic voices
    private let synthMixer = Mixer()
    private(set) var looper:      Looper!      // 2-track
    private(set) var quickLooper: Looper!      // 6-track quick-loop
    private(set) var micSampler:  MicSampler!
}

@MainActor
final class Looper {
    let outputMixer = Mixer()
    private let synthSource: Node
    private var recorders:    [NodeRecorder?]
    private var players:      [AudioPlayer]
    private var trackVolumes: [Float]
}

@MainActor
final class MicSampler {
    let outputMixer = Mixer()
    private let player:       AudioPlayer
    private let pitchShifter: TimePitch
    nonisolated(unsafe) private var recordingFile: AVAudioFile?
}
```

### `MidiBackend` / `CoreMidiBackend` / `MidiSink`

`MidiBackend` is a protocol (`sendNoteOn/Off`) separating byte construction from CoreMIDI transport; `CoreMidiBackend` is the production implementation (virtual "Perfecto" source, channel 1, velocity 100); `MidiSink` adapts `ChordEventSink` onto it.
Defined in [MidiSink.swift](../../MIDI/MidiSink.swift). `RecordingMidiBackend` is the test double ([RecordingMidiBackend.swift](../../Tests/Helpers/RecordingMidiBackend.swift)).
The MIDI consumer of `Voicing` events, tested against GarageBand.

```swift
@MainActor
protocol MidiBackend: AnyObject {
    func sendNoteOn(note: UInt8, velocity: UInt8, channel: UInt8)
    func sendNoteOff(note: UInt8, velocity: UInt8, channel: UInt8)
}

@MainActor
final class CoreMidiBackend: MidiBackend {   // virtual "Perfecto" source
    private var client:     MIDIClientRef   = 0
    private var source:     MIDIEndpointRef = 0
    private var outputPort: MIDIPortRef     = 0
}

@MainActor
final class MidiSink: ChordEventSink {
    private let backend: any MidiBackend
    private var activeNotes: [UInt8] = []
}
```

## Permissions & Logging (cross-cutting)

### `PermissionState` / `PermissionGate`

`PermissionState` enum (`undetermined`/`granted`/`denied`/`restricted`); `PermissionGate` protocol (`state`, `requestSystemPrompt()`).
Defined in [PermissionGate.swift](../../Perfecto/Sources/Permissions/PermissionGate.swift); real mic gate in [MicrophonePermissionGate.swift](../../Perfecto/Sources/Permissions/MicrophonePermissionGate.swift), test double `StubPermissionGate`.
Injected into `PerformanceState`; gates Mic Sample recording.

```swift
enum PermissionState { case undetermined, granted, denied, restricted }

@MainActor
protocol PermissionGate: AnyObject {
    var state: PermissionState { get }
    func requestSystemPrompt() async -> PermissionState
}
```

### `LogEvent`

Enum (`Encodable`) — the closed set of load-bearing events (audio session, MIDI, sinks, performance, permissions, diagnostics), each with structured payload fields. Supporting enums: `MidiNoteKind`, `SinkKind`, `ChordSource`, `PrePromptChoice`.
Defined in [LogEvent.swift](../../Perfecto/Sources/Logging/LogEvent.swift); emitted through the `Logger` protocol ([Logger.swift](../../Perfecto/Sources/Logging/Logger.swift)) — `FileLogger` in production, `RecordingLogger` in tests.
Injected throughout the audio, MIDI, and performance layers.

```swift
enum MidiNoteKind: String, Codable { case noteOn, noteOff }
enum SinkKind:     String, Codable { case audio, midi, composite }
enum ChordSource:  String, Codable { case button, sequencer, arpeggio, looper }

enum LogEvent {
    // Audio session
    case audio_session_activated(category: String, mode: String, sampleRate: Double)
    // MIDI
    case midi_note_sent(note: Int, velocity: Int, channel: Int, kind: MidiNoteKind)
    // Performance
    case chord_played(notes: [Int], source: ChordSource)
    case chord_stopped(notes: [Int], source: ChordSource)
    // … audio / MIDI / sink / permission / diagnostic cases, each with a payload
}
extension LogEvent: Encodable { /* flat JSON: "type" + payload fields */ }

@MainActor
protocol Logger { func log(_ event: LogEvent) }
```

# Overall Project Architecture

Perfecto is a SwiftUI chord-performance instrument built as a strict, one-directional stack of layers.
Each layer depends only on the layers below it; nothing reaches upward.
The design goal is that the hard part — the music theory — is a set of pure functions that can be reasoned about and tested in complete isolation, while everything that touches the outside world (audio, MIDI, the OS, the screen) sits at the edges behind protocols that can be swapped for test doubles.

## The layer stack

```
SwiftUI Views
    ↓  (user gestures: button press, joystick drag, sheet edits)
ViewModels (@Observable @MainActor): PerformanceState + child states
    ↓  (delegates input to the active mode)
Performance Engine: PerformanceMode protocol + 9 implementations
    ↓  (calls computeVoicing, emits Voicing via the sink)
Music Theory Core  ← PURE Swift (Int/Array only; no UIKit/AudioKit/Foundation)
    ↓  (ChordEventSink boundary)
ChordEventSink protocol
    ├── AudioSink  →  AudioKit engine  →  speakers
    └── MidiSink   →  CoreMIDI         →  external apps (e.g. GarageBand)
```

The **Music Theory Core** ([Perfecto/Sources/MusicTheoryCore/](../../Perfecto/Sources/MusicTheoryCore/)) is the load-bearing center and a hard purity boundary: it is pure Swift with no framework imports, so `computeVoicing` and the joystick tables are unit-testable as plain functions of their inputs.
Keeping AudioKit/Foundation out of this layer is a deliberate constraint, not an accident — it is what makes the theory exhaustively testable and keeps the interesting logic decoupled from the audio graph.

Everything above the core is `@MainActor`, because it is either UI or drives UI-observable state.

## How a chord is played (the main data flow)

1. The user presses a chord button in a **View**. The view calls `state.press(degree:)` on `PerformanceState`.
2. `PerformanceState` does not implement any playing behavior itself — it **delegates** to the currently active `PerformanceMode` via `mode.onButtonDown(degree:state:)`. This is the Strategy pattern: swapping the mode swaps the entire input-handling behavior without the view or state changing.
3. The mode (e.g. `PlayMode`) calls back into `PerformanceState` (e.g. `startChord(degree:)`), which invokes the pure `computeVoicing(...)` to turn `(key, degree, joystick, octave, …)` into a `Voicing` (a list of MIDI notes).
4. `PerformanceState` hands the `Voicing` to its injected `ChordEventSink` via `sink.playChord(voicing)`.
5. In production the sink is a `CompositeSink` wrapping `[AudioSink, MidiSink]`, so the one event fans out to both consumers independently — audio makes sound through the AudioKit graph, MIDI sends note-ons over CoreMIDI. Neither knows the other exists.

Releasing the button runs the same path in reverse (`onButtonUp` → `endChord` → `sink.stopChord()`).

## Two ways modes are driven

Modes fall into two categories, distinguished by their `requiresClock` flag:

- **Gesture-driven** (Play, Strum, Lead, Drone, Mic Sample): react directly to button/joystick callbacks.
- **Clock-driven** (Arpeggio, Repeat, Sequencer, Looper): react to a steady pulse. `PerformanceState` owns a `ClockTickable` (production: `MasterClock`, a `Timer` at 1/16-note resolution) and forwards every tick to `mode.onClockTick(state:)`. `SequencerMode`, for example, advances its playhead on each tick and calls `state.playSequencerStep(...)` — the same `computeVoicing` → sink path, just triggered by the clock instead of a finger.

Putting the clock behind the `ClockTickable` protocol lets tests substitute a `ManualClock` and step time deterministically, which is essential for the sample-accuracy-sensitive Looper and Sequencer.

## Dependency injection and testability

The composition root is [PerfectoApp.swift](../../App/PerfectoApp.swift): it constructs the concrete `FileLogger`, `AudioSink`, `MidiSink`, and `MicrophonePermissionGate`, wraps the two sinks in a `CompositeSink`, and injects them all into a single `PerformanceState`.
That `PerformanceState` (and its child states) are then handed to the view tree via SwiftUI's `.environment(...)`.

Every outward-facing dependency crosses a protocol seam, and each has a production implementation and a test double:

| Seam | Production | Test double |
| --- | --- | --- |
| `ChordEventSink` | `AudioSink`, `MidiSink`, `CompositeSink` | `RecordingSink` |
| `ClockTickable` | `MasterClock` | `ManualClock` |
| `MidiBackend` | `CoreMidiBackend` | `RecordingMidiBackend` |
| `PermissionGate` | `MicrophonePermissionGate` | `StubPermissionGate` |
| `Logger` | `FileLogger` | `RecordingLogger` |

Because of this, `PerformanceState` and every mode can be exercised in tests with no audio hardware, no MIDI stack, and no OS permission prompts — the mode logic asserts against a `RecordingSink`'s captured `Voicing`s and a `RecordingLogger`'s captured `LogEvent`s.

## Extensibility: adding a mode is adding a file

The `PerformanceMode` protocol is the extension point for the instrument's core feature set.
A new mode is a single new file under [Modes/](../../Modes/) implementing the protocol; no changes to the core, the views, or `PerformanceState`'s public surface are required.
Similarly, a new performance instrument (say a different synth engine or a network sink) is a new `ChordEventSink` conformance dropped into the `CompositeSink` list.
This is the payoff of the layered design: the parts most likely to grow (modes, sinks) grow by addition, not by modification.

## Cross-cutting concerns

- **Logging** is threaded through every outward-facing layer via constructor-injected `Logger`. Modes and sinks emit structured `LogEvent` cases at their load-bearing moments (chord played/stopped, audio session activated, MIDI note sent, permission decisions), giving an end-to-end trace of a performance without `print` debugging.
- **Permissions** (currently just microphone, for Mic Sample mode) live behind `PermissionGate` so the permission flow can be unit-tested and so the rest of the app never touches `AVFoundation` authorization APIs directly.
- **Audio session management** is concentrated in `AudioSink`, which owns the 48 kHz `.playAndRecord` session (with `mixWithOthers` so Perfecto coexists with DAWs) and handles route-change/interruption recovery so the higher layers never think about it.