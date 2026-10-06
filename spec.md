# Perfecto — iOS app specification (v1)

A chord performance instrument for iPhone. v1 covers the eight core performance modes and a small set of effects; some features are deferred or simplified per the decisions below. The music theory core is portable by purity: no platform dependencies, testable in isolation as pure functions of their inputs.

---

## 1. Goals and non-goals

**Goals**

- All eight primary performance modes (Play, Strum, Lead, Drone, Repeat, Sequencer, Looper, Mic Sample).
- Effects that work under every mode: an arpeggiator, chorus and reverb.
- Clean architectural seams so the music theory core remains portable by purity (no platform dependencies, testable in isolation).
- MIDI output for DAW integration.
- Both synthesis and sample-based sound engines, switchable at runtime.

**Non-goals for v1**

- Chord Hiro rhythm game (separate product surface).
- Ear Trainer (separate product surface).
- Tuner (utility, low priority).
- Auto-Drum (depends on chord-progression-aware logic).
- Companion-app preset editor.
- iPad or Mac Catalyst variants.
- App Store distribution.

**Deferred bucket** (designed for, shipped later)

- Drum module (Drum Mode + Drum Loops as a combined feature).
- Expansion of the looper from 2-track to 6-track.
- Expanded sample library beyond initial bundled instruments.

---

## 2. Platform and stack

| Decision | Choice |
|---|---|
| Platform | iOS 17+ |
| Device | iPhone, portrait + landscape |
| Language | Swift 6 |
| UI | SwiftUI |
| Audio | AudioKit 5.x |
| Architecture | MVVM with SwiftUI `@Observable` |
| MIDI | CoreMIDI via AudioKit `MIDIClient` |
| Distribution | Personal sideload (Xcode → device) |

---

## 3. High-level architecture

```
┌────────────────────────────────────────────────┐
│  SwiftUI Views                                  │
│  PerformanceView, SequencerView, LooperView,    │
│  Menu sheets (Key, Sound, Mode)                 │
├────────────────────────────────────────────────┤
│  ViewModels (@Observable)                       │
│  PerformanceState, LooperState, SequencerState  │
├────────────────────────────────────────────────┤
│  Performance Engine                             │
│  PerformanceMode protocol + per-mode impls      │
│  (PlayMode, StrumMode, LeadMode, DroneMode,     │
│   ArpeggioMode, RepeatMode, SequencerMode,      │
│   LooperMode, MicSampleMode)                    │
├────────────────────────────────────────────────┤
│  Music Theory Core   (PURE, no dependencies)    │
│  Key, Scale, Degree, ChordQuality, Voicing,     │
│  computeVoicing()                               │
├────────────────────────────────────────────────┤
│  ChordEventSink protocol                        │
│  ├── AudioSink   (drives oscillators/samplers)  │
│  └── MidiSink    (drives CoreMIDI out)          │
├────────────────────────────────────────────────┤
│  Audio Engine (AudioKit)                        │
│  SynthVoiceBank, SamplerVoiceBank, Effects,     │
│  Looper, MasterClock                            │
└────────────────────────────────────────────────┘
```

Key principles:

- The **Music Theory Core** is pure Swift (Int/Array only). No UIKit, no AudioKit, no Foundation beyond primitives. Testable in isolation as pure functions of their inputs.
- The **ChordEventSink** protocol decouples event generation from event consumption. Audio and MIDI receive the same events independently.
- The **MasterClock** is built from day one and drives all tempo-aware features (Arpeggio, Repeat, Sequencer, Looper, future Drum modes).
- Each **PerformanceMode** is one implementation of a protocol. Adding a mode = adding a file. No core changes.

---

## 4. Music Theory Core

### 4.1 Data types

```swift
enum PitchClass: Int { case C=0, Cs, D, Ds, E, F, Fs, G, Gs, A, As, B }

enum ScaleType {
    case major
    case naturalMinor
    case harmonicMinor
    case melodicMinor
    case majorPentatonic
    case minorPentatonic
    case blues
    case dorian
    case mixolydian
    case lydian

    var intervals: [Int] { /* semitone offsets from root */ }
}

struct Key {
    let root: PitchClass
    let scale: ScaleType
}

enum Degree: Int { case I = 1, ii, iii, IV, V, vi, viiDim }

enum JoystickMode { case `default`, extended, chromatic }
enum JoystickDirection {
    case center, up, upRight, right, downRight,
         down, downLeft, left, upLeft
}

enum ChordQuality {
    case major, minor, diminished, augmented
    case sus2, sus4, sus4_7
    case maj6, min6
    case maj7, min7, dom7, dom7s9, dom7b9, dom7alt, halfDim7, minMaj7
    case add9, add11
    case maj9, min9, dom9
    case min11
    case maj7s11, maj13, dom13, sixNine
}

enum Inversion { case root, first, second }

struct Voicing {
    let notes: [Int]        // MIDI note numbers, sorted low to high
    let bassNote: Int?      // optional slash-chord bass
}
```

### 4.2 Core function

```swift
func computeVoicing(
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

Pipeline:

1. Compute base triad from `(key, degree)` using `scale.intervals`.
2. Apply `(joystickMode, joystickDirection) → ChordQuality` lookup table.
3. Transform triad → final pitch set per quality (add 7th, replace 3rd with 4th, raise 5th, etc.).
4. Apply inversion (rotate, adjust octaves).
5. Apply global octave offset.
6. If `voiceLeading`, search nearby inversions/octaves to minimize total semitone movement from `previousVoicing`.
7. Return MIDI notes.

### 4.3 Joystick transformation table

The `(mode, direction) → ChordQuality` mapping is encoded as static data in `JoystickMap.swift`. Three modes × nine directions = 27 entries (center always returns base triad).

Each `ChordQuality` is itself a small set of transformation rules:

```swift
struct QualityTransform {
    let addDegrees: [Int]        // scale degrees to add (7, 9, 11, etc.)
    let replaceMap: [(Int, Int)] // (replace degree X with degree Y)
    let shiftMap: [(Int, Int)]   // (degree X, semitone offset)
}
```

This makes the transformations data-driven and unit-testable.

### 4.4 Testing

Every entry in the joystick transformation table becomes a test assertion. Example:

```swift
XCTAssertEqual(
    computeVoicing(
        key: Key(root: .C, scale: .major),
        degree: .I,
        joystickMode: .default,
        joystickDirection: .right,
        inversion: .root, octave: 4,
        voiceLeading: false, previousVoicing: nil
    ).notes,
    [60, 64, 67, 71]  // C-E-G-B = Cmaj7
)
```

Full table coverage: 10 scales × 12 keys × 7 degrees × 27 (mode, direction) × 3 inversions = ~68K combinations. Don't test all; test the structural rules + representative samples.

---

## 5. Audio engine

### 5.1 Voice architecture

- 6 polyphonic voices per chord (one per chord note + 2 headroom for held overlaps).
- Each voice is a `SynthVoice` (oscillator) or `SamplerVoice` (sample playback) depending on active sound preset.
- Per-voice ADSR envelope.
- Per-voice gain + pan.

### 5.2 Signal flow

```
Voices → ADSR → BassOsc → Filter → Chorus → Flanger → Delay → Reverb → Output
```

All effects implemented as AudioKit nodes (`Reverb`, `Delay`, `Chorus`, `Flanger`, `LowPassFilter`). Wet/dry per effect exposed to user.

**Built so far (2026-10-06):** chorus and reverb.
What is being played has an `EffectsChain` (its chorus, and how much of it goes to the reverb), and so has each loop track; they all send into one `SharedReverb`, and everything ends in the `MasterBus`:

```
Voices ─→ synth mix ─→ Chorus ─┬────────────────────→ dry ─┬─→ limiter ─→ Output
                               └─→ send ─┬─→ Reverb ───────┤
Each loop track ─→ Chorus ─┬─────────────│──────────→ dry ─┘
                           └─→ send ─────┘
```

One reverb costs the same however many loops play, and there is one room: its size is the size set now, also for loops closed earlier.
The `MasterBus` adds everything together and limits it, so a dense chord over several loops is turned down for as long as it would clip, not clipped; quieter sound passes untouched, 1 ms late (the limiter's look-ahead).

The loopers record the synth mix, before the effects.
When a take ends, its track's effects are set as the live ones are at that moment and then left alone.
So a finished loop keeps its chorus and its share of the reverb, as it keeps its key, octave and sound: choosing new ones changes only what is played next, whether the loop is playing or is stopped and started again later.
The reverb's size is the exception, because the room is shared.
Each effect has an on/off switch and two controls (chorus: amount, rate; reverb: mix, size), on the side panel's Effects page, behind the FX chit.
An effect that is off keeps running with none of the sound reaching it, so the graph is never rewired while the engine runs.
The reverb's mix is how much of the sound is sent into the reverb, not how much of the reverb is let out, so what is already ringing always dies away in its own time: a mix that is being played, or a reverb switched off, never cuts a tail short.
The low-pass filter that shapes a preset is per voice, part of each `SynthPatch`.

**Filter (played).** One more low-pass, `BrightnessFilter`, sits between the synth mix and everything after it:

```
Voices ─→ synth mix ─→ Filter ─┬─→ Chorus ─→ Reverb ─→ Output
                               └─→ loop capture
```

It has a switch and one control, brightness, on the Effects page.
While a chord key is held and the filter follows the slide (below), the slide plays the brightness: the bottom of the key is dark and the top lets everything through.
Lifting the key returns it to the set brightness, which is also what the sequencer's steps sound at.
It sits before the loopers' capture point, so unlike the chorus and reverb its movement is recorded into a loop.
Off, it is bypassed.

**Played by the slide.** Every effect has a "slide plays" switch beside the one control the slide (8.4) can play: the filter's brightness (on by default), the chorus's amount, the reverb's mix and the arpeggiator's cycle (off by default).
While a chord key is held, the slide stands in for that control on every effect that is on and follows it, so one finger can play several at once; lifting the key returns each to its set value.
The cycle is played in steps, each with an equal share of the key's height: a bar at the bottom, then 2 beats, 1 beat, and half a beat at the top.
A loop keeps the chorus and the reverb's mix as they were set when it was closed, not as they were being played; only the filter's movement is recorded.
The settings a slide can play are `SlidePlayed`; `EffectsState` holds the set values and the slide and passes each effect on as played, so the audio, the arpeggiator and MIDI only ever see that.

**Key zones.** Every chord key can be divided into 2 to 4 zones, stacked from the bottom of the key to the top, each with an equal share of the slide (8.4).
Each zone names one effect, or none, and a value for that effect's played control: a cycle for the arpeggiator, an amount from 0 to 1 for the filter's brightness, the chorus's amount and the reverb's mix.
While the finger playing the chord is in a zone, that zone's effect is on with its control held at the zone's value, whether or not the effect is switched on and whatever it is set to.
Everywhere else on the key, and once the key is lifted, the effect is as set, and is still played by the slide if it follows it.
Zones are independent of one another, so one key can mix effects (a plain zone, an arpeggiated zone and a reverb zone) or play one effect at several values (an arpeggio at a bar, a beat and half a beat).
The zone is read from the moment the finger lands, so where a key is struck chooses the effect, and sliding from one zone to another under a held chord changes it; moving into or out of an arpeggiator zone sounds the held chord again, whole or as notes.
A finger must go a little past a zone's edge (4% of the slide) to leave the zone, so one resting on an edge does not switch back and forth.
Lifting the last key ends its chord before the zone's effect switches off, so the chord does not sound once more.
While the zones are on, every key shows a tick at each side where one zone gives way to the next.
A loop keeps the chorus and reverb as set, not as a zone was holding them.
The zones are set on the Effects page, in a "Key zones" card: a switch, the number of zones, and for each zone its effect and value.
They are off by default; switched on, the default is two zones, plain at the bottom and the arpeggiator at one beat at the top.

**Arpeggiator.** A note effect rather than a sound effect: it turns each chord into single notes in tempo before they reach the audio and MIDI sinks, so it works in every mode and is sent over MIDI.
The first note sounds on the press and the rest follow evenly, in one of four patterns (up, down, up/down, random).
One pass of the pattern takes one cycle (half a beat, 1 beat, 2 beats or 1 bar) however many notes the chord has, so adding a coloration makes the notes faster rather than the pass longer, and the pattern always comes round on the beat.
Changing the cycle while a chord is held changes the speed without starting the pattern again: the note that is due still comes when it was due and the ones after it follow at the new spacing.
Each note lasts until the next.
ChordLink still announces the whole chord.

### 5.3 Audio session

- 48kHz, 256-sample buffer (~5.3ms latency).
- `AVAudioSession` category: `.playAndRecord` (mic sample mode), `mixWithOthers` option enabled so the app coexists with DAWs.

### 5.4 Voice allocation

- Built (2026-10-06): 8 voices behind `VoiceAllocator`. A note takes the voice free longest, so released notes ring out; with every voice held it takes over the one held longest.
- New chord press interrupts previous chord in Play mode unless `Sustain` is on.
- Drone mode latches indefinitely until next press.

### 5.5 Sound preset format

```swift
struct SoundPreset {
    let id: String
    let displayName: String
    let category: SoundCategory   // .synth or .sample
    let synthConfig: SynthConfig?
    let sampleConfig: SampleConfig?
}

struct SynthConfig {
    let waveform: Waveform       // .sine, .saw, .square, .triangle, .fm
    let filterCutoff: Float
    let filterResonance: Float
    let adsr: ADSR
    let fmParams: FMParams?
}

struct SampleConfig {
    let sfzPath: String          // path to bundled SFZ
}
```

### 5.6 Initial sound library

Bundled at ship:

- 14 synth presets, grouped as the Sound page lists them:
  - Keys: electric piano, glass keys, organ, clav
  - Pads: sine pad, warm pad, strings
  - Plucked: pluck, bell, kalimba
  - Synth: saw lead, square lead, brass, synth bass
- Each preset is a `SynthPatch`: plain data naming up to two oscillators, an optional FM pair, an optional low-pass filter and an amplitude envelope.
  Every `SynthVoice` has the same fixed signal path (oscillators + FM → filter → envelope), so changing sound only changes parameters and never rewires the audio graph.
  Filter cutoff and FM depth can sweep after each note starts, which is what separates a pluck from a pad on the same oscillator.
- Choosing a sound on the Sound page plays nothing by itself: the keys beside the panel stay playable, and the next chord is heard in the new sound.
- 3 sample-based instruments (TBD, sourced before v1 ship):
  - Salamander Grand Piano (CC-BY, ~120MB compressed)
  - 1–2 more from CC-licensed libraries (strings + electric piano are likely picks)

Total bundle target: under 250MB.

---

## 6. Performance modes (v1 scope)

All modes conform to `PerformanceMode` protocol:

```swift
protocol PerformanceMode {
    var requiresClock: Bool { get }
    func onButtonDown(degree: Degree, state: PerformanceState)
    func onButtonUp(degree: Degree, state: PerformanceState)
    func onJoystickChange(direction: JoystickDirection, state: PerformanceState)
    func onClockTick(state: PerformanceState)
}
```

The mode-facing API on `PerformanceState` — what modes are permitted to call — is:

| Method | Purpose |
|---|---|
| `startChord(degree:)` | Compute voicing + play + update display |
| `armChord(degree:)` | Compute voicing + update display, no audio (for clock-driven modes) |
| `stopSounding()` | Stop the chord on every sink (audio + MIDI + ChordLink note-off/release) without clearing the OLED display or active gesture (rhythmic retriggering) |
| `playNote(_:)` | Play a single MIDI note (arpeggiator) |
| `strumChord(degree:)` | Play chord with strum timing |
| `leadNote(degree:)` | Play single scale note for Lead mode |
| `playSequencerStep(degree:joystickMode:joystickDirection:)` | Play a step with explicit joystick overrides |
| `endChord()` | Stop audio + clear display + clear active degree |
| `activeDegree` (read) | Currently held degree, if any |
| `currentVoicing` (read) | Currently sounding voicing |
| `bpm` (read) | Current tempo (for gate calculations) |

Modes must not call any other methods on `PerformanceState`. This list is the contract.

| Mode | Behavior | Clock-driven |
|---|---|---|
| Play | Chord sustains while held | No |
| Strum | Chord plays as quick arpeggio on press | No (one-shot timing) |
| Lead | Buttons play single melody notes | No |
| Drone | Press latches chord on; press again to release | No |
| Repeat | Chord retriggers rhythmically at tempo | Yes |
| Sequencer | Bars of 16 chord steps play back at tempo | Yes |
| Looper | 2-track audio looper, sample-accurate | Yes |
| Mic Sample | Record audio from mic, play back via chord buttons | No (playback timing) |

Arpeggio was a mode in the original plan; it is now an effect that works under every mode (see 5.2).

### 6.1 Sequencer

- A pattern is any number of bars of 16 steps.
  There are no preset lengths: bars are added at the end and removed one at a time.
- Each step holds: chord degree + chord color + gate + rest flag.
- Playback repeats either the whole pattern or a loop: the steps that were selected when the loop was set.
  The loop is captured from the selection and then independent of it, so steps can be selected and edited while it plays.
  A loop need not be one run of steps; exactly its steps play, in order.
- The grid has two layouts, chosen in Settings: numbered pages (one bar at a time) or one scrolling column of every bar.
  Steps are selected by tap and by drag in both; in the scrolling column one finger selects and two fingers scroll.
- Tempo + swing controls.
- Save/load presets to UserDefaults (in v1; SwiftData later).

### 6.2 Looper (2-track v1)

- Sample-accurate recording at the audio buffer level.
- Per-track: record, play, stop, clear, mute, volume.
- Count-in: 1 bar metronome before recording starts.
- Loop length: first track's length defines the bar; subsequent tracks must be exact multiples.
- Quantized loop boundaries (snap record-end to nearest bar).

Architecture is designed for 6 tracks; v1 caps the UI at 2.

### 6.2.1 Play-mode loop

The first looping the app offers lives in Play mode: one LOOP button, no clock and no count-in.

- Tap LOOP to start a take, tap again to close it; it loops from that moment.
- The first take sets the loop's length.
  Each later take (up to 6 layers) is folded onto that length at the point in the loop where it was played, so layers stay in time with each other however long they play.
  A take longer than the loop layers over itself.
- Each layer has a numbered chit: tap to silence it or bring it back (it rejoins in time).
  A trash chit after the layers switches them to deleting: while it is on, tapping a layer removes it.
  Holding the trash chit offers to clear every loop at once.
  Deleting every layer frees the length, so the next take sets a new one.
- A first take shorter than half a second is dropped as an accidental double tap.
- A loop holds the synth as it sounded when recorded, and the effects that were on when it was closed, so layers can differ in key, octave, sound and effects; loops are never re-recorded into later takes.

How it keeps time: `LoopCapture` taps the synth mix and stamps every buffer with the engine's sample clock, so a take starts and ends at exact samples.
`Looper` schedules every layer on one sample grid (cycles begin at an anchor, every loop-length frames) and `LoopMath` holds the arithmetic as pure functions.
`LooperTests` runs the real looper in an offline engine and checks every rendered frame.

### 6.3 Mic Sample

- Record mic input to in-memory buffer (max 10s).
- Playback via chord buttons; each degree plays the sample pitch-shifted by the scale interval.
- One sample slot in v1 (multi-slot in deferred bucket).

---

## 7. MIDI

### 7.1 Architecture: on-device virtual source

`MidiSink` creates a CoreMIDI virtual source named "Perfecto" using `MIDISourceCreateWithProtocol`. Events are sent via `MIDIReceivedEventList` (UMP-wrapped MIDI 1.0).

The primary consumer in v1 is **GarageBand running on the same iPhone**. The virtual source appears automatically in GarageBand's MIDI source list; the user enables it once in GarageBand's settings.

Network MIDI (RTP-MIDI to a Mac DAW) is **deferred to v1.x**. The current `MidiSink` implementation targets on-device only.

### 7.2 Protocol conformance

`MidiSink` conforms to `ChordEventSink`:

```swift
final class MidiSink: ChordEventSink {
    func playChord(_ voicing: Voicing) { /* Note On for each note */ }
    func stopChord(_ voicing: Voicing) { /* Note Off for each note */ }
}
```

`MidiSink` has a `MidiBackend` seam for testing — the real CoreMIDI calls are behind that protocol, so byte-construction logic is testable without CoreMIDI.

Strumming (`strumChord`) and preset changes (`setPreset`) are audio-only operations called directly on `AudioSink`, bypassing `ChordEventSink`. `MidiSink` receives a standard `playChord` for any strum event. This is intentional: MIDI has no concept of strum timing or waveform tables.

### 7.3 Note Off behavior

**Per-note Note Off.** When a chord is released, `MidiSink` sends an individual Note Off message for each pitch that was sounding. CC 123 (All Notes Off) is not used.

When `playChord` is called while a chord is already held, `MidiSink` sends Note Off for all previous notes before sending Note On for the new chord.

### 7.3.1 Effect controllers

The sound effects' amounts are sent on channel 1 as they are played, each time one reaches a new value: the filter's brightness as CC 74 (0 dark to 127 open), the chorus's amount as CC 93 and the reverb's mix as CC 91.
A chord's starting values are sent ahead of its notes.
Switching an effect off sends its resting value once (127 for the filter, 0 for the chorus and reverb); an effect never switched on sends nothing.

### 7.4 Fixed parameters (v1)

- Channel: 1 (fixed; not configurable in v1)
- Velocity: 100 (fixed in v1)
- MIDI protocol: MIDI 1.0 (wrapped in UMP for `MIDISourceCreateWithProtocol`)

### 7.5 GarageBand setup

GarageBand requires a one-time manual step. On first launch, the app displays a setup hint:

1. Open GarageBand → create or open a Smart Piano track.
2. Tap the MIDI settings icon → enable "Perfecto" as a MIDI input source.
3. Return to Perfecto. Chord presses now sound in GarageBand.

The app shows this hint as a dismissible card on first run and as a "Where's my sound?" link on the menu's Setup page.

### 7.6 What's NOT in MIDI v1

- MIDI input (driving the app from external controllers).
- CC messages for joystick state. (The only controllers sent are the effects' amounts, 7.3.1.)
- Program change for sound preset switching.
- MIDI clock sync.
- Network MIDI / RTP-MIDI to Mac DAW (deferred to v1.x).

All listed as v1.x or v2 candidates.

---

## 8. UI

### 8.1 Style

Key UI principles:

- **Chord button colors encode quality**: warm tones for major (I, IV, V), cool tones for minor (ii, iii, vi), purple for diminished (vii°).
- **OLED-style chord display** at top center: monospace, amber-on-black, shows chord name + spelled-out notes.
- **Three function buttons** (Key/Sound/Mode) in gray/orange/red mirror the device's physical buttons.
- **Virtual joystick** is a circular drag zone with a visible thumb stick. 8 directional zones + center deadband.
- **Looper track row** at the bottom shows 6 indicator pills; lit when track has content.

### 8.2 Light + dark modes

Both supported. Color tokens via SwiftUI's adaptive color system. Dark mode uses deep-stop ramps (800/900) for fills and light stops (100/200) for text; light mode does the inverse.

### 8.3 Performance screen layout (portrait)

```
┌──────────────────────────┐
│  KEY        SOUND   MODE │   status bar (state, not interactive)
│  C Major  Saw Lead   Play│
├──────────────────────────┤
│      ┌───────────┐       │
│      │  Cmaj7    │       │   OLED-style chord display
│      │ C-E-G-B   │       │
│      └───────────┘       │
├──────────────────────────┤
│   [KEY] [SOUND] [MODE]   │   function buttons (open sheets)
├──────────────────────────┤
│   ┌──┐┌──┐┌──┐┌──┐       │
│   │ I││ii││iii││IV│      │   top row of chord buttons
│   └──┘└──┘└──┘└──┘       │
│   ┌──┐┌──┐┌──┐           │
│   │ V││vi│vii°│          │   bottom row
│   └──┘└──┘└──┘           │
├──────────────────────────┤
│  ┌─────┐                 │
│  │  ●  │       [VOL]     │   joystick + volume slider
│  └─────┘                 │
├──────────────────────────┤
│  [○][●][○][○][○][○]      │   looper track indicators
└──────────────────────────┘
```

### 8.4 Interaction details

- **Chord buttons**: minimum 60×60pt. Multi-touch (press multiple for layered chords).
- **Key gestures**: what a finger does on a chord key, beyond pressing it, is a control. The first is the slide: how far up its key the finger is, 0 at the bottom to 1 at the top, with the top and bottom 15% of the key already reading as all the way. It is read from the moment the finger lands, so where a key is struck matters, and it plays every effect that follows it (5.2). Sliding onto another key still changes chord. With several keys held, the slide that is heard is the most recent press's, as the chord is. The slide can also be read in steps: key zones (5.2) divide it into bands, each of which switches an effect on.
- **Joystick**: `DragGesture` in a circular bounded region. Drag direction maps to one of 9 zones. Released = snaps back to center. Tap (no drag) = "click" event for looper control.
- **Volume wheel**: vertical slider with smooth tracking.
- **Menu button**: top leading corner, a sliders icon. It opens the menu (8.5) where it was left, and closes it. It is the one way to every setting.
- **Haptic feedback**: light haptic on chord button press (Core Haptics).

### 8.5 Side panel and menu sheets

- **Menu (side panel)**: slides over the leading edge and covers only part of the screen. The keys still showing beside it play as usual, so a key, a sound or an effect can be heard while it is changed. One panel, four pages (Key, Sound, Effects, Setup), switched by tabs at its top; opened and closed by the menu button, which stays in its corner on top of the panel.
- **Setup page**: chord layout, chord color surface, sequencer bar layout.
- **Key page**: 12 keys × 7 scales grid + octave selector. Pentatonic and blues are hidden for now: chords on scales with fewer than seven notes aren't defined yet.
- **Sound page**: synth presets + sampled instruments, with category headers.
- **Mode sheet**: list of 9 modes + mode-specific settings panel below.

---

## 9. Project structure

```
Perfecto/
├── Sources/                        ← separate Swift Packages (compiler-enforced isolation)
│   ├── MusicTheoryCore/            ← pure Swift: Int/Array only, no platform deps
│   │   ├── PitchClass.swift
│   │   ├── Scale.swift
│   │   ├── Key.swift
│   │   ├── Chord.swift
│   │   ├── JoystickMap.swift
│   │   └── ComputeVoicing.swift
│   ├── Logging/                    ← Foundation only (no UIKit, AudioKit)
│   │   ├── Logger.swift
│   │   ├── LogEvent.swift
│   │   ├── FileLogger.swift
│   │   └── RingBuffer.swift
│   └── Permissions/                ← Foundation + AVFoundation only
│       ├── PermissionGate.swift
│       └── MicrophonePermissionGate.swift
├── App/
│   └── PerfectoApp.swift
├── Core/
│   ├── Events/
│   │   ├── ChordEvent.swift
│   │   └── ChordEventSink.swift
│   └── Clock/
│       └── MasterClock.swift
├── Audio/
│   ├── AudioSink.swift
│   ├── SynthVoice.swift
│   ├── SamplerVoice.swift
│   ├── EffectsChain.swift
│   ├── Looper.swift
│   └── MicSampler.swift
├── MIDI/
│   └── MidiSink.swift
├── Modes/
│   ├── PerformanceMode.swift
│   ├── PlayMode.swift
│   ├── StrumMode.swift
│   ├── LeadMode.swift
│   ├── DroneMode.swift
│   ├── ArpeggioMode.swift
│   ├── RepeatMode.swift
│   ├── SequencerMode.swift
│   ├── LooperMode.swift
│   └── MicSampleMode.swift
├── ViewModels/
│   ├── PerformanceState.swift
│   ├── LooperState.swift
│   ├── SequencerState.swift
│   └── MicSampleState.swift
├── Views/
│   ├── PerformanceView.swift
│   ├── ChordButton.swift
│   ├── JoystickView.swift
│   ├── VolumeSlider.swift
│   ├── OLEDDisplay.swift
│   ├── SidePanel/
│   │   ├── SidePanel.swift
│   │   ├── KeyPanel.swift
│   │   ├── SoundPanel.swift
│   │   ├── SetupPanel.swift
│   │   └── EffectsPanel.swift
│   ├── Sheets/
│   │   └── ModeSheet.swift
│   ├── Permissions/
│   │   ├── PrePromptView.swift
│   │   ├── SettingsRedirectView.swift
│   │   └── PermissionFlowView.swift
│   └── LooperTrackRow.swift
├── Resources/
│   ├── Samples/                    ← sample libraries (format TBD; see §5.5)
│   └── Presets/                    ← synth preset JSON
└── Tests/
    ├── Helpers/                    ← recording doubles, shared across all test targets
    │   ├── RecordingSink.swift
    │   ├── ManualClock.swift
    │   ├── RecordingLogger.swift
    │   ├── StubPermissionGate.swift
    │   └── XCTAssert+Voicing.swift
    ├── MusicTheoryTests/
    ├── ModeTests/
    ├── SinkTests/
    ├── LoggingTests/
    ├── PermissionTests/
    └── SMOKE_TEST.md
```

---

## 10. Build order

Suggested sequence. Each step produces something testable.

1. **Music Theory Core + unit tests.** Pure Swift, no UI, no audio. Build `computeVoicing` and tests against the joystick transformation tables. This is the foundation.
2. **AudioKit "hello sine wave"**. Verify audio output works on device.
3. **SynthVoice + AudioSink + minimal PerformanceView.** Press chord button → hear chord. No joystick yet, no modes, no menus. Default key.
4. **JoystickView + joystick wiring.** Press chord + drag joystick = transformed chord.
5. **Key sheet + Sound sheet.** Switching works.
6. **Mode protocol + Play/Strum/Lead/Drone modes** (non-clock-driven).
7. **MasterClock + Arpeggio/Repeat modes** (clock-driven, simple).
8. **MidiSink wired in alongside AudioSink.** Test with GarageBand.
9. **Sequencer mode + Sequencer screen.**
10. **Looper (2-track, sample-accurate).** This is the heaviest single piece.
11. **Mic Sample mode.**
12. **Effects chain wired up + effect controls in UI.**
13. **SamplerVoice + bundled SFZ instruments.**
14. **Polish, haptics, edge cases.**

---

## 11. Known risks and open questions

- **Virtual joystick fidelity.** Distinguishing 8 directional zones by thumb-drag is harder than a physical stick. May need visual zone-highlighting feedback or larger deadbands. Test early.
- **Looper sample-accuracy.** Unforgiving. Small timing bugs produce audible drift. Plan for careful testing with metronome reference.
- **Looper loop-boundary click/thump.** Observed during UX testing. Likely causes in order of probability: (1) waveform discontinuity at loop point — last sample doesn't connect smoothly to first sample (zero-crossing problem); (2) NodeRecorder partial buffer write at quantized stop; (3) AudioPlayer buffer rescheduling gap; (4) chord note sustain cut abruptly at record-stop, producing a rhythmic click on each loop restart. Fix candidates: apply a short fade-out/fade-in (2–5ms) at loop boundaries; force a note-off before stopping recording; or switch to AVAudioPlayerNode scheduled buffers with crossfade. Revisit during fine-tuning and UX testing.
- **Background audio.** Decide whether the looper keeps playing when backgrounded. Probably yes; needs `.playback` audio session and `UIBackgroundModes` entitlement.
- **Sample library sourcing.** Pick 3 CC-licensed sample sets before v1 ships. Salamander Piano + 2 TBD. This is curation work, not coding.
- **iOS audio latency floor.** ~5ms is the practical lower bound on iPhone. Imperceptible for chord performance; worth measuring on first real-device run to confirm buffering choices.
- **Inversions + voice leading + chord lock interactions.** Subtle. Need explicit test cases for the combinations.

---

## 12. Testing

### 12.1 Philosophy

Tests are organized by what they test, not how they test it. The Music Theory Core's pure functions get full-coverage unit tests. UI interactions, audio output quality, and MIDI-to-GarageBand round-trips are covered by manual smoke tests. Everything in between uses a **recording-double pattern** to keep tests fast, deterministic, and free of hardware dependencies.

Swift Testing (`@Test`, `#expect`) is the default for all new test files. Existing XCTest files are converted to Swift Testing as part of Phase 1.

### 12.2 Recording-double pattern

Test doubles in Perfecto are *recording* doubles: they conform to the same protocols as production implementations but capture their inputs rather than doing real work. Assertions run against captured calls.

Core doubles (live in `Tests/Helpers/`):

- `RecordingSink` — conforms to `ChordEventSink`; records `playChord` and `stopChord` calls
- `ManualClock` — conforms to `ClockTickable`; exposes `tick()` to advance time manually
- `RecordingLogger` — conforms to `Logger`; records `log(_:)` calls
- `StubPermissionGate` — conforms to `PermissionGate`; configured to return a preset state

### 12.3 ClockTickable protocol

`MasterClock` must be behind a protocol so `ManualClock` can replace it in mode tests:

```swift
protocol ClockTickable: AnyObject {
    var bpm: Double { get set }
    func start()
    func stop()
    func onTick(_ handler: @escaping @MainActor () -> Void)
}
```

`MasterClock` and `ManualClock` both conform. `PerformanceState` accepts a `ClockTickable` injection; the production default is `MasterClock`.

### 12.4 File organization

```
Tests/
├── Helpers/
│   ├── RecordingSink.swift
│   ├── ManualClock.swift
│   ├── RecordingLogger.swift
│   ├── StubPermissionGate.swift
│   └── XCTAssert+Voicing.swift
├── MusicTheoryTests/       (Swift Testing)
│   ├── ComputeVoicingTests.swift
│   ├── JoystickMapTests.swift
│   └── ScaleTests.swift
├── ModeTests/              (Swift Testing)
├── SinkTests/              (Swift Testing)
│   └── MidiSinkTests.swift
├── LoggingTests/           (Swift Testing)
│   └── LoggerTests.swift
├── PermissionTests/        (Swift Testing)
│   └── MicrophonePermissionTests.swift
└── SMOKE_TEST.md
```

### 12.5 What's not unit-tested

Some things are covered by manual smoke test (`Tests/SMOKE_TEST.md`) rather than automated tests:

- Audio output quality (pitch, timbre, loudness) — must be heard
- MIDI-to-GarageBand round-trip — requires a real device with GarageBand running
- UI layout, animations, gesture zones
- Performance under sustained load

Run the smoke test checklist before every TestFlight upload.

---

## 13. Logging

### 13.1 Purpose

Structured event logging for remote diagnostics. Beta users can send a log file to the developer via a hidden gesture. The log file is readable without a debugger attached and contains enough detail to reconstruct any session.

### 13.2 Logger protocol

```swift
@MainActor
protocol Logger {
    func log(_ event: LogEvent)
}
```

Production uses `FileLogger`. Tests use `RecordingLogger`.

### 13.3 LogEvent — sealed enum

All loggable events are cases of `LogEvent`. The compiler enforces exhaustive handling in every `switch`. Payload fields are named and typed, not stringly typed.

```swift
enum LogEvent: Codable {
    // Audio session
    case audio_session_activated(category: String, mode: String, sampleRate: Double)
    case audio_session_failed(status: Int32)
    case audio_route_changed(to: String, reason: String)
    case audio_session_interrupted(reason: String)
    case audio_session_resumed(reason: String)
    case audio_engine_started
    case audio_engine_stopped
    case audio_engine_failed(message: String)

    // MIDI
    case midi_source_created(name: String, status: Int32)
    case midi_note_sent(note: Int, velocity: Int, channel: Int, kind: MidiNoteKind)
    case midi_send_failed(status: Int32, attemptedNote: Int?)

    // Sinks
    case sink_attached(kind: SinkKind)
    case sink_detached(kind: SinkKind)
    case sink_error(kind: SinkKind, message: String)

    // Performance
    case mode_changed(from: String, to: String)
    case mode_clock_required(mode: String, clockRunning: Bool)
    case chord_button_pressed(degree: Int, key: String, joystick: String, resultingNotes: [Int])
    case chord_played(notes: [Int], source: ChordSource)
    case chord_stopped(notes: [Int], source: ChordSource)

    // Permissions
    case permission_state_observed(permission: String, state: String)
    case permission_pre_prompt_shown(permission: String, feature: String)
    case permission_pre_prompt_response(permission: String, choice: PrePromptChoice)
    case permission_system_prompt_requested(permission: String)
    case permission_system_prompt_response(permission: String, granted: Bool)
    case permission_settings_redirect_shown(permission: String)
    case permission_settings_redirect_taken(permission: String)

    // Diagnostics
    case theory_unexpected_voicing(degree: Int, key: String, notes: [Int])
}
```

### 13.4 FileLogger

Writes one NDJSON line per event to the Caches directory. Each line wraps the event with a timestamp and session ID:

```swift
private struct WrappedEvent: Encodable {
    let timestamp: Date   // ISO 8601
    let session_id: UUID
    let event: LogEvent
}
```

Append-only ring buffer: keeps the last 5000 events; older events are discarded. The file is not user-visible; it's surfaced only via the share gesture.

### 13.5 "Send Logs" gesture

Five-finger tap anywhere on the main performance view. Opens `UIActivityViewController` with the log file as the attachment. Users send via AirDrop, Mail, or iMessage. No server; no analytics.

### 13.6 Emission points

Every load-bearing event should be logged. At minimum:

- `AudioSink` — all `audio_session_*`, `audio_route_*`, `audio_engine_*` events
- `MidiSink` — all `midi_*` events
- `PerformanceState` — `mode_changed`, `chord_button_pressed`, `chord_played`, `chord_stopped`
- Permission flow — all `permission_*` events

Pass `Logger` via constructor injection. Production passes `FileLogger`; tests pass `RecordingLogger`.

### 13.7 Module location

`Perfecto/Sources/Logging/` — a separate Swift Package (same pattern as `MusicTheoryCore`). Foundation-only dependency. No UIKit, AudioKit, or AVFoundation imports inside the package.

---

## 14. Permissions

### 14.1 Scope

v1 has one runtime permission: microphone access for Mic Sample mode. All permissions go through `PermissionGate`; no feature calls system permission APIs directly.

### 14.2 PermissionGate protocol

```swift
enum PermissionState {
    case undetermined, granted, denied, restricted
}

@MainActor
protocol PermissionGate {
    var state: PermissionState { get }
    func requestSystemPrompt() async -> PermissionState
}
```

### 14.3 Three-stage permission flow

**Stage 1 — Pre-prompt** (state is `.undetermined`):
A full-screen or sheet view explaining why the permission is needed, with "Continue" and "Not Now" buttons. "Not Now" leaves state `.undetermined` and dismisses with no system dialog. "Continue" advances to Stage 2.

**Stage 2 — System prompt**:
The standard iOS permission dialog. Result is `.granted` or `.denied`.

**Stage 3 — Settings redirect** (state is `.denied`):
Explains that permission was denied. Provides a deep link directly to the app's Settings page. When the user toggles the permission on and returns, the gate re-reads state and returns `.granted`.

### 14.4 MicrophonePermissionGate

```swift
@MainActor
final class MicrophonePermissionGate: PermissionGate {
    private let logger: Logger
    var state: PermissionState { /* reads AVAudioApplication */ }
    func requestSystemPrompt() async -> PermissionState { /* AVAudioApplication.requestRecordPermission */ }
}
```

Every state transition emits a `permission_*` log event.

### 14.5 Integration with MicSampler

`MicSampler` does not check permissions directly. The check happens in `PerformanceState` (or `MicSampleState`) before `startRecording()` is called:

```
User taps "Record" in Mic Sample mode
  → check micGate.state
  → .undetermined  →  show PrePromptView
  → .denied        →  show SettingsRedirectView
  → .granted       →  micSampler.startRecording()
  → .restricted    →  show "can't be enabled" view
```

### 14.6 Info.plist requirement

`NSMicrophoneUsageDescription` must use feature-focused copy — not generic:

> "Mic Sample mode records a short audio clip that you play back via the chord buttons."

### 14.7 Module location

`Perfecto/Sources/Permissions/` — a separate Swift Package. Imports Foundation and AVFoundation only. No AudioKit imports inside the package.

---

## 15. Sign-off

This spec reflects decisions made in conversation on 2026-05-11. Scope locked at:

- Modes 1–9 (Play, Strum, Lead, Drone, Arpeggio, Repeat, Sequencer, Looper, Mic Sample).
- Drum module deferred.
- 2-track looper in v1, 6-track later.
- Synth + sample sound engines, both in v1.
- All 7 seven-note scales (pentatonic and blues hidden for now), all 3 joystick modes (28 chord types), all 12 keys.
- MIDI out in v1.
- iPhone portrait only.
- Light + dark modes.