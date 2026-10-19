# Data shapes and interfaces

The major data types and protocols in Perfecto, layer by layer, from the music theory core up to the view models.
Each block shows a type's stored fields and the members that define its contract; computed helpers and doc comments are in the source.
`CLAUDE.md` says how the layers fit together, and each heading here names the file to read for the rest.

## Contents

1. [Music theory core](#1-music-theory-core)
2. [Chord events](#2-chord-events)
3. [Notes](#3-notes)
4. [Effects](#4-effects)
5. [Sounds](#5-sounds)
6. [The audio kernel (C interface)](#6-the-audio-kernel-c-interface)
7. [The clock](#7-the-clock)
8. [The timeline](#8-the-timeline)
9. [Performance modes](#9-performance-modes)
10. [MIDI and ChordLink](#10-midi-and-chordlink)
11. [Logging and permissions](#11-logging-and-permissions)
12. [View models](#12-view-models)
13. [Touch and layout](#13-touch-and-layout)
14. [What is saved](#14-what-is-saved)

## 1. Music theory core

`Perfecto/Sources/MusicTheoryCore/`.
Pure Swift (Int and Array only), every type `Sendable`.

```swift
enum PitchClass: Int { case C = 0, Cs, D, Ds, E, F, Fs, G, Gs, A, As, B }

enum ScaleType {
    case major, naturalMinor, harmonicMinor, melodicMinor
    case majorPentatonic, minorPentatonic, blues
    case dorian, mixolydian, lydian
    var intervals: [Int]          // semitones above the tonic
    var isHeptatonic: Bool
}

struct Key { let root: PitchClass; let scale: ScaleType }

enum Degree: Int { case I = 1, ii, iii, IV, V, vi, viiDim }   // raw values are saved

struct Inversion { var steps: Int }   // steps rolled from root position; .root, .first and .second are 0, 1 and 2
```

Which chord, independent of key and voicing:

```swift
struct ChordSpec { let degree: Degree; let color: ChordColor }

enum ChordColor {
    case joystick(JoystickMode, JoystickDirection)
    case grid(StackHeight, HeptatonicMode?)   // nil mode = the degree's own diatonic mode
    static let base = ChordColor.joystick(.default, .center)
}

enum JoystickMode      { case `default`, extended, chromatic }
enum JoystickDirection { case center, up, upRight, right, downRight, down, downLeft, left, upLeft }

enum StackHeight: Int  { case triad = 3, seventh = 4, ninth = 5, eleventh = 6, thirteenth = 7 }

enum HeptatonicMode {
    case ionian, dorian, phrygian, lydian, mixolydian, aeolian, locrian               // major
    case melodicMinor, dorianFlat2, lydianAugmented, lydianDominant,
         mixolydianFlat6, locrianNatural2, altered                                    // melodic minor
    case harmonicMinor, locrianNatural6, ionianSharp5, dorianSharp4,
         phrygianDominant, lydianSharp2, ultralocrian                                 // harmonic minor
    var intervals: [Int]
}

struct GridPosition { let height: StackHeight; let row: Int }   // a cell of the chord grid, row from the top

enum TriadBase { case major, minor, dim }
```

The joystick's table (internal to the core):

```swift
struct ChordShape      { let intervals: [Int]; let name: String }
struct JoystickOutcome { let major, minor, dim: ChordShape; let action: String }
```

The notes that sound:

```swift
struct Voicing {
    let notes: [Int]       // MIDI notes: sorted, unique, always within 0...127
    let bassNote: Int?
    static let midiRange = 0...127
}

func computeVoicing(key: Key, spec: ChordSpec, inversion: Inversion, octave: Int,
                    voiceLeading: Bool, previousVoicing: Voicing?) -> Voicing
```

`ChordGrid` (an enum of functions) maps a `GridPosition` to a `ChordColor` and back for a given key and degree.

## 2. Chord events

`Core/Events/ChordEventSink.swift`.

```swift
struct ChordContext {
    let key: Key
    let spec: ChordSpec
    let octave: Int
    let inversion: Inversion
    let voiceLeading: Bool
}

enum Articulation: Codable {
    case block
    case strum(interval: Double)   // seconds between notes, low to high
}

struct ChordEvent {
    let voicing: Voicing
    let articulation: Articulation
    let context: ChordContext
}

@MainActor protocol ChordEventSink: AnyObject {
    func playChord(_ event: ChordEvent)   // replaces whatever is sounding
    func stopChord()
}
```

Implementations: `Arpeggiator`, `NotePlayer`, `MidiAnnouncerSink`, `CompositeSink`.
`performanceContext(key:octave:spec:)` (`Modes/PerformanceVoicing.swift`) is the one place a `ChordContext` is built.

## 3. Notes

`Core/Events/NoteSink.swift`.

```swift
struct NoteID: Hashable { var number: UInt64; static func next() -> NoteID }

struct NoteSound {
    var preset = SynthPreset.initial
    var chorus = ChorusSettings()
    var reverb = ReverbSettings()
    var delay = DelaySettings()
    var vocoder = VocoderSettings()
    var brightness: Float = 1      // 0 dark ... 1 the whole sound
    var pan: Float = 0             // -1 left ... 1 right
}

@MainActor protocol NoteSink: AnyObject {
    func noteOn(_ id: NoteID, note: Int, sound: NoteSound, at time: TimeInterval)
    func noteChange(_ id: NoteID, sound: NoteSound, at time: TimeInterval)
    func noteOff(_ id: NoteID, at time: TimeInterval)
}

@MainActor protocol SoundControl: AnyObject {
    var sound: NoteSound { get set }      // a change reaches the notes being held
    func startNotes(in sound: NoteSound)  // for the notes to come only
}
```

`time` is a moment of the device's uptime (`ClockTickable.time`).
Implementations of `NoteSink`: `KernelSink`, `MidiSink`.
`NotePlayer` is the `ChordEventSink` that turns chords into these calls.

## 4. Effects

`Audio/AudioEffects.swift`, `Core/Events/Arpeggiator.swift`, `Core/Events/SlidePlayed.swift`, `Core/Events/EffectChoice.swift`, `Core/Events/KeyZones.swift`.

```swift
enum EffectKind: String, Codable { case arpeggiator, chorus, reverb, vocoder }

protocol EffectSettings {
    static var kind: EffectKind { get }
    var isOn: Bool { get set }
    var isPlayed: Bool { get }                  // whether a slide would change how it sounds
    func played(by slide: Float?) -> Self       // as it sounds with a finger at slide
    func held(at value: Float) -> Self          // as it sounds from a key zone: switched on
}

protocol SlidePlayed: EffectSettings {
    var followsSlide: Bool { get }
    func playing(_ slide: Float) -> Self   // these settings with the played control at slide (0...1)
}
```

Every settings struct is `Equatable, Codable, Sendable, EffectSettings`; all amounts run 0...1.
The chorus and the reverb are each one sound, on or off: their amounts are constants, not settings.
The arpeggiator and the vocoder are `SlidePlayed`.

```swift
struct ChorusSettings  { var isOn = false; static let amount: Float = 0.6; static let rate: Float = 0.35 }
struct ReverbSettings  { var isOn = false; static let mix: Float = 0.3; static let size: Float = 0.4 }
struct VocoderSettings { var isOn = false; var amount: Float = 1; var followsSlide = false }

struct ArpeggiatorSettings {
    var isOn = false
    var pattern: ArpeggioPattern = .up
    var cycle: ArpeggioCycle = .beat
    var followsSlide = false
}
enum ArpeggioPattern: String, Codable { case up, down }   // Arpeggio 1 and Arpeggio 2; a saved pattern that is gone decodes as up
enum ArpeggioCycle: String, Codable   { case halfBeat, beat, twoBeats, bar }
```

| Effect | Played control |
| --- | --- |
| Arpeggiator | `cycle` |
| Vocoder | `amount` |

An effect as it is offered where one is chosen (the play screen's effect fields, a key zone):

```swift
enum EffectChoice { case arpeggio(ArpeggioPattern), chorus, reverb, vocoder }   // kind: EffectKind

struct EffectSlots {                       // the play screen's effect fields
    var kinds: [EffectKind?]               // the effect in each; nil is an empty field; never none
    var canAdd: Bool
    func choices(for slot: Int) -> [EffectChoice?]
}
```

Key zones:

```swift
struct KeyZone {
    var effect: EffectChoice?; var value: Float = 0.5 // value: a place on the slide
    var key: Key?; var octave: Int?                   // nil: the key or octave chosen
}

struct KeyZoneSettings {
    static let counts = 2...4
    var isOn = false
    var zones = [KeyZone(), KeyZone(effect: .arpeggiator)]   // bottom of the key to the top
}
```

What follows the sound effects as played (`NotePlayer`, `MidiSink`):

```swift
@MainActor protocol EffectsControl: AnyObject {
    func setChorus(_ played: ChorusSettings)
    func setReverb(_ played: ReverbSettings)
    func setDelay(_ played: DelaySettings)
    func setVocoder(_ played: VocoderSettings)
    func setBrightness(_ played: Float)
}
protocol TempoControl { func setTempo(_ bpm: Double) }   // KernelSink: the delay's echoes are 0.75 of a beat apart
```

## 5. Sounds

`Audio/SynthPreset.swift`, `Audio/SynthPatch.swift`, `Audio/Recording.swift`.

```swift
enum SynthPreset: String, Codable {
    case electricPiano, glassKeys, organ, clav         // keys
    case sinePad, warmPad, strings, pulsePad, sweepPad // pads
    case pluck, bell, kalimba, marimba                 // plucked
    case sawLead, squareLead, soloLead, driveLead, flute, superSaw, polySynth, brass, stab, crunch // synth
    case synthBass, subBass, fmBass, reeseBass, wobbleBass, acidBass  // bass
    case micSample                                     // recorded
    static let initial = SynthPreset.sinePad
    static let micCapture = 0
    var patch: SynthPatch
    enum Category: String { case keys, pads, plucked, synth, bass, recorded }
}

struct SynthPatch {
    var oscillators: [Oscillator] = []   // at most 2
    var fm: FM? = nil
    var sample: Sample? = nil            // with one, oscillators and FM are not heard
    var unison: Unison? = nil            // several copies of the sources, out of tune with each other
    var driftCents: Float = 0            // how far each oscillator wanders, differently for every note
    var noise: Sweep? = nil              // noise beside the sources, as a share of the level
    var glide: Float = 0                 // seconds to slide in from the note before, when there is no gap
    var drive: Float = 0                 // 0...1, into a soft limit after the filter
    var filter: Filter? = nil
    var lfo: LFO? = nil                  // moves a held note: pitch, pulse width, cutoff
    var envelope: Envelope
    var level: Float

    enum Wave { case sine, triangle, square, sawtooth, pulse(width: Float), harmonics([Float]) }
    struct Sweep      { var from: Float; var to: Float; var time: Float }
    struct Oscillator { var wave: Wave; var level: Float = 1; var octave: Int = 0; var detuneCents: Float = 0 }
    struct FM         { var carrier: Float = 1; var modulator: Float; var index: Sweep; var level: Float = 1 }
    struct Filter     { var cutoff: Sweep; var resonance: Float = 0; var isSteep = true }
    struct Unison     { var voices: Int; var spreadCents: Float }   // at most 7
    struct LFO        { var rate: Float; var rise: Float = 0; var pitchCents: Float = 0; var pulseWidth: Float = 0; var cutoffOctaves: Float = 0 }
    struct Envelope   { var attack, decay, sustain, release: Float }
    struct Sample     { var capture: Int; var root: Int = 60 }
}

struct Recording { var samples: [Float]; var sampleRate: Double }   // one channel
```

`SynthPatch.kernelPatch` (`Audio/Kernel/KernelSound.swift`) turns a patch into the kernel's `PerfectoPatch`.
`KernelAudioUnit.Playing` is a note's numbers as the kernel takes them:

```swift
struct Playing { var brightness: Float = 1; var chorus: Float = 0; var reverb: Float = 0; var vocoder: Float = 0; var delay: Float = 0 }
```

## 6. The audio kernel (C interface)

`Perfecto/Sources/PerfectoKernel/include/PerfectoKernel.h`.
Timed events in, samples out; time is a count of frames since `prepare`.

```c
typedef struct { float from, to, time; } PerfectoSweep;

typedef enum { PerfectoWaveSine, PerfectoWaveTriangle, PerfectoWaveSquare,
               PerfectoWaveSawtooth, PerfectoWavePulse, PerfectoWavePartials } PerfectoWave;

typedef struct {
    PerfectoWave wave;
    float pulse_width;
    float partials[16];
    float ratio;        // frequency as a multiple of the note's
    float level;
} PerfectoOperator;

typedef struct {
    PerfectoOperator operators[2];
    bool modulates;  PerfectoSweep index;                 // operator 2 bends operator 1, or is mixed with it
    int32_t unison;  float spread;                        // copies of the operators (at most 7), across ±spread cents
    float drift;                                          // cents each operator wanders, differently for every note
    PerfectoSweep noise;  float glide;  float drive;      // noise beside the operators; seconds of glide; 0...1 of drive
    bool filtered;   PerfectoSweep cutoff;  float resonance;  bool steep;
    PerfectoLfo lfo;                                      // { rate, rise, pitch, pulse_width, cutoff }
    float attack, decay, sustain, release;
    float level;
    bool sampled;    int32_t capture;  float root;        // a capture in place of the operators
} PerfectoPatch;

typedef enum { PerfectoEventNoteOn = 1, PerfectoEventNoteOff, PerfectoEventNoteChange,
               PerfectoEventCaptureStart, PerfectoEventCaptureStop } PerfectoEventType;

typedef enum { PerfectoCaptureInput = 0, PerfectoCaptureVocoder = 1 } PerfectoCaptureSource;

typedef struct {
    uint64_t time;        // the frame the event takes effect on
    uint64_t note_id;
    PerfectoEventType type;
    int32_t note;         // MIDI note; or which capture
    float velocity;
    int32_t sound;        // which sound; or what to record
    float brightness, pan, chorus, reverb, vocoder, delay;
} PerfectoEvent;
```

| Group | Functions |
| --- | --- |
| Lifetime | `perfecto_kernel_create`, `_destroy`, `_prepare(sample_rate)` |
| Sounds | `_set_sound(sound, patch)`, `_sound_count`, `_voice_count` |
| Events | `_send(event) -> bool`, `_event_capacity`, `_time`, `_latency` |
| Render | `_render(in, in_channels, out, out_channels, frames)` |
| Captures | `_capture_count`, `_capture_capacity`, `_capturing`, `_captures_ended`, `_capture_length`, `_capture_rate`, `_capture_read`, `_capture_load` |
| Mix | `_set_chorus_rate`, `_set_reverb_tail`, `_set_reverb_predelay`, `_set_reverb_damping`, `_set_vocoder` |

## 7. The clock

`Core/Clock/MasterClock.swift`.

```swift
enum MusicalTime {
    static let stepsPerBeat = 4
    static let beatsPerBar = 4
    static let stepsPerBar = stepsPerBeat * beatsPerBar
    static let tempoRange = 20.0...300.0
}

@MainActor final class ClockCall { func cancel() }

@MainActor protocol ClockTickable: AnyObject {
    var bpm: Double { get set }
    var ticksPerBeat: Int { get }          // default: MusicalTime.stepsPerBeat
    var beats: Double { get }              // how far the music has got
    var time: TimeInterval { get }         // now, in device uptime; inside a call, when it was due
    func start()
    func stop()
    func onTick(_ handler: @escaping @MainActor () -> Void)
    func every(beats: Double, _ handler: @escaping @MainActor () -> Void) -> ClockCall
    func after(beats: Double, first: Bool, _ handler: @escaping @MainActor () -> Void) -> ClockCall
    func after(seconds: Double, _ handler: @escaping @MainActor () -> Void) -> ClockCall
}
```

Implementations: `MasterClock` (real time) and `SteppedClock` (offline rendering; `ManualClock` in tests), both over a `ClockSchedule`.

## 8. The timeline

`Core/Timeline/`.
Time is whole ticks, 480 to a quarter note (`TimelineTime.ticksPerBeat`); a step is a sixteenth, 120 ticks.

```swift
struct Timeline: Codable {
    var signature = TimeSignature.common
    var barCount = 1
    var layers: [Layer] = [Layer()]     // at most Timeline.maxLayers (6)
    var loop: Range<Int>?               // the ticks that repeat; nil repeats everything
}

struct TimeSignature: Hashable, Codable {
    var beats: Int
    var unit: Unit                      // .quarter = 4, .eighth = 8
    static let common = TimeSignature(beats: 4, unit: .quarter)
}

struct Layer: Identifiable, Codable {
    let id: UUID
    var notes: [TimelineNote]           // in order, never overlapping
    var isMuted = false
    var volume: Float = 1
}

struct TimelineNote: Codable {
    var start: Int                      // ticks from the start of the timeline
    var length: Int                     // ticks, at least 1
    var chord: ChordSpec
    var pitch = NotePitch.chord
    var articulation = Articulation.block
    var playing = NotePlaying()
    var changes: [SoundChange] = []     // a slide played while the note was held
}

enum NotePitch: Codable { case chord, lead }

struct NotePlaying: Codable {           // nil = whatever is chosen now
    var key: Key?
    var octave: Int?
    var preset: SynthPreset?
    var effects: NoteEffects?
}

struct NoteEffects: Codable {
    var arpeggiator = ArpeggiatorSettings()
    var chorus = ChorusSettings()
    var reverb = ReverbSettings()
    var delay = DelaySettings()         // absent in older saved timelines
    var vocoder = VocoderSettings()     // absent in older saved timelines
    var brightness: Float = 1           // played by the slide; absent in older saved timelines
    // a saved "filter", and a saved chorus's or reverb's amounts, are left unread
}

struct SoundChange: Codable { var offset: Int; var effects: NoteEffects }   // offset: ticks after the note's start
```

Compiling a layer into what is played (`TimelineCompile.swift`):

```swift
struct LiveSettings { var key: Key; var octave: Int; var preset: SynthPreset; var effects: NoteEffects }

struct TimedChord {
    var start: Int
    var end: Int
    var event: ChordEvent
    var preset: SynthPreset
    var effects: NoteEffects
    var changes: [SoundChange]
}

extension Timeline { func compile(layer id: Layer.ID, live: LiveSettings) -> [TimedChord] }
```

Playing it (`TimelinePlayer.swift`, `LayerVoice.swift`):

```swift
@MainActor protocol TimelineVoice: AnyObject {
    func play(_ chord: TimedChord)   // replaces whatever the voice is sounding
    func stop()
}
```

`TimelinePlayer` holds a `timeline`, the `live` settings and one `TimelineVoice` per layer (`LayerVoice`: an arpeggiator and a `NotePlayer`).

Edits are mutating functions on the values (`TimelineEdits.swift`):

| On | Edits |
| --- | --- |
| `Layer` | `insert`, `clear`, `place`, `rest`, `join`, `split`, `lengthen`, `hold`, `snap`, `edit(notesOn:)` |
| `Timeline` | `addBar`, `removeBar`, `trimEmptyBars`, `doubleBars`, `halveBars`, `setSignature`, `setLoop`, `addLayer`, `duplicateLayer`, `removeLayer`, `edit(layer:)` |

Recording a loop (`LoopTake.swift`):

```swift
struct LoopTake {
    let start: Double    // the clock's position, in beats, when the take began
    mutating func chordStarted(_ event: ChordEvent, pitch: NotePitch, playing: NotePlaying, at beats: Double)
    mutating func chordEnded(at beats: Double)
}
```

Drawing the grid (`ViewModels/StepGridShape.swift`, `Views/StepGridGeometry.swift`):

```swift
struct StepGridShape { var stepsPerBar: Int; var columns: Int }   // rows of one felt beat

struct NoteChit: Identifiable {     // one row's piece of a note
    var steps: Range<Int>
    var note: TimelineNote
    var isHead: Bool
    var isTail: Bool
}

struct StepGridGeometry {
    var shape = StepGridShape()
    var width: CGFloat
    var cellHeight: CGFloat
    var headerHeight: CGFloat = 0
    var barGap: CGFloat = 0
}
```

Exporting (`Export/`):

```swift
struct SequencerPattern { var timeline: Timeline; var live: LiveSettings; var bpm: Double }
```

`SequencerMidiRenderer` renders a pattern to a `MidiFile`, and `TimelineAudioRenderer` to a 24-bit WAV file.

## 9. Performance modes

`Modes/PerformanceMode.swift`.

```swift
enum ModeKind    { case play, strum, lead, drone, `repeat`, sequencer }
enum ModeSurface { case chords, sequencer }

@MainActor protocol PerformanceMode: AnyObject {
    var kind: ModeKind { get }
    var requiresClock: Bool { get }
    func onButtonDown(key: ChordKey, state: PerformanceState)
    func onButtonUp(key: ChordKey, state: PerformanceState)
    func onColorChange(state: PerformanceState)
    func onClockTick(state: PerformanceState)     // default: nothing
    func activate(state: PerformanceState)        // default: nothing
    func deactivate(state: PerformanceState)      // default: ends the chord
}
```

Implementations: `PlayMode`, `StrumMode`, `LeadMode`, `DroneMode`, `RepeatMode`, `SequencerMode`.

## 10. MIDI and ChordLink

`MIDI/`, and in the core `MidiFile.swift` and `ChordWire.swift`.

```swift
@MainActor protocol MidiBackend: AnyObject {      // CoreMidiBackend, NoopMidiBackend
    func sendNoteOn(note: UInt8, velocity: UInt8, channel: UInt8, at time: TimeInterval)
    func sendNoteOff(note: UInt8, velocity: UInt8, channel: UInt8, at time: TimeInterval)
    func sendControlChange(controller: UInt8, value: UInt8, channel: UInt8)
}

@MainActor protocol SysExTransport: AnyObject {   // CoreMidiSysExTransport, NoopSysExTransport
    func send(_ frame: [UInt8])                   // one whole frame, F0 ... F7
}
```

The ChordLink frame (`chordlink.md` has the wire spec):

```swift
struct ChordAnnouncement {
    let key: Key
    let degree: Degree
    let joystickMode: JoystickMode
    let joystickDirection: JoystickDirection
    let inversion: Inversion
    let octave: Int
    let voiceLeading: Bool
    let voicing: Voicing
}

enum ChordWire { enum Frame { case chord(ChordAnnouncement), release } }
```

A Standard MIDI File:

```swift
struct MidiFile  { var ticksPerQuarter: Int; var tracks: [MidiTrack]; func encoded() -> [UInt8] }
struct MidiTrack { var events: [MidiEvent]; var length: Int }
struct MidiEvent {
    var tick: Int
    var kind: Kind
    enum Kind {
        case noteOn(channel: Int, note: Int, velocity: Int)
        case noteOff(channel: Int, note: Int)
        case tempo(bpm: Double)
        case timeSignature(numerator: Int, denominator: Int)
        case keySignature(MidiKeySignature)
        case trackName(String)
        case marker(String)
    }
}
struct MidiKeySignature { let sharps: Int; let isMinor: Bool }
```

## 11. Logging and permissions

`Perfecto/Sources/Logging/`, `Perfecto/Sources/Permissions/`.

```swift
@MainActor protocol Logger { func log(_ event: LogEvent) }   // FileLogger; RecordingLogger in tests
```

`LogEvent` is one enum, encoded flat as JSON with a `type` field.
Its cases, by group:

| Group | Cases |
| --- | --- |
| Audio session | `audio_session_activated`, `_failed`, `_interrupted`, `_resumed`, `audio_route_changed`, `audio_engine_started`, `_stopped`, `_failed` |
| MIDI | `midi_source_created`, `midi_note_sent`, `midi_send_failed`, `midi_network_session_enabled`, `chordlink_frame_sent` |
| Sinks | `sink_attached`, `sink_detached`, `sink_error` |
| Performance | `mode_changed`, `mode_clock_required`, `chord_button_pressed`, `chord_played`, `chord_stopped` |
| Sequencer | `sequencer_bars_changed`, `sequencer_signature_changed`, `sequencer_loop_changed` |
| Sound | `sound_changed`, `effect_switched`, `key_zones_switched` |
| Mic sample | `sample_record_started`, `sample_recorded` |
| Looper | `loop_record_started`, `loop_recorded`, `loop_take_discarded`, `loop_cleared` |
| Export | `sequencer_midi_exported`, `timeline_audio_exported` |
| Permissions | `permission_state_observed`, `permission_pre_prompt_shown`, `_response`, `permission_system_prompt_requested`, `_response`, `permission_settings_redirect_shown`, `_taken` |
| Diagnostics | `theory_unexpected_voicing` |

Its field enums: `MidiNoteKind`, `SinkKind`, `ChordSource`, `EffectKind`, `ChordLinkFrameKind`, `PrePromptChoice`.

```swift
enum PermissionState { case undetermined, granted, denied, restricted }

@MainActor protocol PermissionGate: AnyObject {   // MicrophonePermissionGate, NoopPermissionGate
    var state: PermissionState { get }
    func requestSystemPrompt() async -> PermissionState
}
```

## 12. View models

`ViewModels/`, all `@Observable @MainActor`.
The fields below are the state each one holds; their methods are in the source.

```swift
final class PerformanceState {
    var key: Key                          // C major
    var octave: Int                       // 4
    var joystickMode: JoystickMode
    var synthPreset: SynthPreset
    var bpm: Double                       // 120, within MusicalTime.tempoRange
    var mode: any PerformanceMode
    var chordGridLayout: ChordGridLayout
    var colorSurface: ColorSurface
    var joystickDirection: JoystickDirection
    var gridPosition: GridPosition?
    var activeDegree: Degree?
    var heldKeys: [ChordKey]              // oldest first; the last is the active press
    var currentVoicing: Voicing?
    var isExternalSynth: Bool

    let sequencerState: SequencerState
    let quickLoopState: QuickLoopState
    let effects: EffectsState
    let micSample: MicSampleState
    let micAccess: MicAccess
}

enum ChordGridLayout     { case grid, circle, horizontalBar }   // chosen in Setup
enum ChordKeyArrangement { case grid, circle, row }             // what a layout gives a screen
enum ColorSurface        { case joystick, grid }
enum SurfaceShape        { case bar, grid }
```

```swift
final class EffectsState {
    var arpeggiator: ArpeggiatorSettings   // as set
    var chorus: ChorusSettings
    var reverb: ReverbSettings
    var vocoder: VocoderSettings
    var zones: KeyZoneSettings
    var slide: Float?                      // the active key's slide; nil while no key is held
    var zone: Int?                         // the zone the finger is in
    var slots: EffectSlots                 // the play screen's effect fields
}
```

```swift
final class SequencerState {
    var timeline: Timeline
    var layerID: Layer.ID                  // the layer on screen
    var currentStep: Int                   // -1 while stopped
    var selectedSteps: Set<Int>
    var primaryStep: Int?
    var isPlaying: Bool
    var focusedBar: Int
    var layout: SequencerLayout            // .paged or .scroll
}

final class QuickLoopState {
    var phase: Phase                       // .idle or .recording
    weak var host: (any LoopHost)?
}
struct QuickLoopEntry: Identifiable { let id: Layer.ID; var isPlaying: Bool }

@MainActor protocol LoopHost: AnyObject {  // PerformanceState
    var loopSequencer: SequencerState? { get }
    var bpm: Double { get }
    func setBPM(_ value: Double)
    var clockBeats: Double { get }
    var layerLead: Double { get }
    var playedNow: NotePlaying { get }
    func endChord()
}

final class MicSampleState {
    var isRecording: Bool
    var startedAt: Date?
    var duration: TimeInterval             // 0 is no sample
    var heardNothing: Bool
}

final class SidePanelState { var page: SidePanelPage? }        // nil while the menu is closed
enum SidePanelPage: String { case key, sound, effects, setup }
```

`SampleRecorder.Phase` is `.idle`, `.starting`, `.recording` or `.stopping`.

## 13. Touch and layout

`Views/ChordKeyTouches.swift`.

```swift
struct ChordKeyChange { var released: Degree? = nil; var pressed: Degree? = nil }

struct ChordKeySlide {
    var key: Degree
    var height: Float     // 0 at the bottom of the key, 1 at the top
}

struct ChordKeyTouches<Touch: Hashable> {
    var frames: [Degree: CGRect] = [:]
    mutating func touch(_ touch: Touch, at point: CGPoint) -> ChordKeyChange
}
```

`SidePanelLayout` holds the side panel's sizes (`maxWidth` 320, `maxShare` 0.62).

## 14. What is saved

| What | Where | Shape |
| --- | --- | --- |
| The timeline | `UserDefaults`, `sequencer.timeline.v1` | `Timeline` as JSON |
| Old step patterns (read once) | `UserDefaults`, `sequencer.pattern.v4`, `sequencer.pattern.v3` | `{ steps: [SequencerStep], loopSteps: [Int]? }` |
| The sequencer's layout | `UserDefaults`, `sequencer.layout` | `SequencerLayout` raw value |
| The mic sample | Application Support, `mic-sample.caf` (`SampleRecorder`) | `Recording` |
| The log | Caches, `perfecto.log` (`FileLogger`), the last 5000 lines | `{ timestamp, session_id, event: LogEvent }` as JSON, one per line |

```swift
struct SequencerStep: Codable {   // the old saved format, and a layer read one step at a time
    var degree: Degree = .I
    var color: ChordColor = .base
    var gate: Double = TimelineNote.enteredGate   // 0.75
    var isRest: Bool = false
}
```

Saved enums are encoded by case name (`Degree` by its explicit raw value), so reordering a Swift enum does not change what saved data means.
