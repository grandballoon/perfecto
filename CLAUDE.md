# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

**Perfecto** — an iOS chord performance instrument. The full v1 spec is in `spec.md`.

Stack: iOS 17+, iPhone (portrait + landscape), Swift 6, SwiftUI, an audio kernel of our own in C++ (no audio library), MVVM with `@Observable`, CoreMIDI.

## Architecture

The codebase is split into strict layers with no upward dependencies:

```
SwiftUI Views
    ↓
ViewModels (@Observable): PerformanceState, SequencerState, QuickLoopState
    ↓
Performance Engine: PerformanceMode protocol + 7 per-mode implementations
    ↓
Music Theory Core  ← PURE Swift only (Int/Array, no UIKit/AudioKit/Foundation)
    ↓
ChordEventSink protocol (receives ChordEvent)
    ├── Arpeggiator        →  one note at a time while it is on
    │     └── NotePlayer   →  chords become notes with ids; NoteSink protocol
    │           ├── KernelSink   →  KernelAudioUnit: the audio kernel (voices, chorus, reverb, limiter), run by AudioOutput
    │           └── MidiSink     →  CoreMIDI ("Perfecto" note source)
    └── MidiAnnouncerSink  →  ChordLink SysEx ("Perfecto Link"; see chordlink.md)
```

**Music Theory Core purity is a hard constraint.** It is pure Swift (Int/Array only), testable in isolation as pure functions of its inputs. Never add UIKit, AudioKit, or Foundation imports to anything under `Perfecto/Sources/MusicTheoryCore/`.

**ChordEventSink decouples event generation from consumption.** Every sink receives the same `ChordEvent`s independently — neither knows about the others or reads app state. A `ChordEvent` carries the voicing, its `Articulation` (block or strum), and the `ChordContext` that produced it; the protocol's doc states the contract (`playChord` replaces what is sounding).

**Below the chords are notes.** `NotePlayer` is the one place a chord becomes note-ons and note-offs (and where a strum is spread out), so audio and MIDI are `NoteSink`s that know nothing of chords. Every note has a `NoteID` chosen by its sender, and a sink ends only the note it is told to: one `NotePlayer` is one line of chords, and several can sound at once through the same sinks. Every note also carries its `NoteSound` (preset, filter, chorus, reverb), which is its player's: the keys' player follows the effects as played, and each layer's is given its chords' own, so a loop keeps the sound it was recorded with while the keys play another over it. The player also spreads a chord's notes a little from left to right (`NotePlayer.spread`). A change to a player's sound reaches the notes it holds (`noteChange`), which is how a slide is heard; a new chord's sound leaves the last chord's notes as they were (`startNotes(in:)`).

**The audio kernel makes every sound** (`docs/audio-engine-spec.md` has the design and what is still to build). It is portable C++ behind a C interface (`Perfecto/Sources/PerfectoKernel`): timed events in, samples out, and nothing in its render call allocates, locks or waits; its tests are built to stop on any allocation made while rendering. An event takes effect on exactly the frame it names, however rendering is divided into calls. A note names its sound, one of the patches the kernel was given (`perfecto_kernel_set_sound`, before playing: it builds the patch's wavetables), and has its own brightness, pan, and chorus and reverb sends, which a note change glides. The kernel has the 64 voices and chooses which to give up. The voices are added into one chorus and one reverb (`MixBus.hpp`) and a look-ahead limiter, whose 1.5 ms is the kernel's latency. `KernelAudioUnit` hosts it as an Audio Unit, and the render block is Objective-C++ (`PerfectoKernelHost`) so the render thread never runs Swift. `KernelSink` is the `NoteSink` in front of it: it loads the presets as kernel sounds (`SynthPatch.kernelPatch`) and turns a `NoteSound` into the kernel's numbers. `AudioGraph` is the engine and what is connected in it: the unit has an input, and an engine in real time renders it only while something is connected there, so a silent source always is (`KernelLiveTests` runs the graph in real time). `AudioOutput` keeps it running across route changes, and `AudioSession` is the one place the session is configured.

**The kernel records, too.** It has four captures (30 seconds each, one channel), and a capture event starts or stops recording its input into one on an exact frame. A recording that ends is made ready to play (cut to its sound, brought to full level), and a patch can name a capture in place of its operators, played faster or slower by pitch: that is the mic sample (`SynthPreset.micSample`), a sound like any other, so it is played, sequenced and looped as notes. `SampleRecorder` asks for the recording, watches the kernel for its end, opens the mic only meanwhile (through `AudioOutput`), and keeps the sample on disk; `MicSampleState` is what the Sound panel shows of it. Whatever needs the mic asks `MicAccess`, which puts the system's question once through `PermissionGate`.

**The vocoder is an effect that hears.** A note's send to it (`VocoderSettings`, on `NoteSound` like the others) is the share of the note that is not heard itself but shaped by the voice at the kernel's input, through a bank of bands (`Vocoder.hpp`). `PerformanceState` opens the mic while the vocoder, or a key zone of it, is on (`EffectsState.hearsTheMic`, `AudioOutput.isVocoding`); on the speaker the device's echo cancelling is switched on with it. With the vocoder off or nothing to hear, notes sent to it are heard whole.

**MasterClock drives everything timed.** Repeat, the timeline (sequences and loops), the arpeggiator and strums all use it; nothing between a key and its notes sleeps or keeps a timer of its own. It is behind a `ClockTickable` protocol so test doubles can replace it without changing callers. Modes count its ticks (sixteenths); anything finer or off that grid asks it for a call: over and over (`every(beats:)`, as the arpeggiator does), or once (`after(beats:)` for a step's gate, `after(seconds:)` for a strum's notes and Repeat's gap). Both clocks keep their calls in a `ClockSchedule`, which makes them in the order they fall due (a tick first) and times a call asked for inside another from that call's due time, so the real clock and `ManualClock` follow the same rules and timing tests never wait on real time.

**Notes carry times.** Every note-on, note-off and change is stamped with the moment it takes effect (`ClockTickable.time`: inside a call of the clock's, the moment that call was due, however late the main thread got to it). `KernelSink` turns the moment into the kernel's frame (each render tells `PerfectoKernelHost` when it is for) and `MidiSink` into a MIDI timestamp. What the clock plays (a layer's `NotePlayer`) adds a short lead (`NotePlayer.sequencedLead`, 50 ms), so its notes are always sent ahead of their moment and sound on exactly their frame: the timeline is heard that much after the clock's position, all of it alike. The keys' player has no lead, since a key sounds at once; what the clock does on its behalf (a strum's later notes, a live arpeggio, Repeat) is stamped but has usually just passed, so it is as punctual as the main thread. A loop recorded over layers is placed where it was heard, the lead earlier than the clock had it (`QuickLoopState`).

**Effects are layers, not modes**, so they work under every mode. The arpeggiator is a note effect: a `ChordEventSink` in front of the note sinks, so audio and MIDI hear the same notes, while ChordLink still hears the whole chord. One pass over a chord takes one cycle (`ArpeggioCycle`) however many notes it has. The filter, chorus, reverb and vocoder are sound effects, and each note has its own amounts of them (`NoteSound`): the kernel has one chorus, one reverb and one vocoder that notes send into, and a limiter that keeps layers from clipping. The chorus's speed and the reverb's size are the only settings notes share; they follow the note played last. An effect's settings are plain data (`ArpeggiatorSettings`, `ChorusSettings`, `ReverbSettings`), edited through `EffectsState`, which can be read as set (`asSet`) or as played (`asPlayed`). Adding a sound effect = a settings struct, a field on `NoteSound` and its place in the kernel's mix, and a card in `EffectsPanel`.

**Key gestures play effects.** What a finger does on a chord key beyond pressing it is a control, read in the same place fingers become keys (`ChordKeyTouches`) and reported by `ChordKeySurface` beside the key changes, so every layout gets it. The first is the slide: how far up its key the finger is (`ChordKeySlide`, 0 at the bottom to 1 at the top). `PerformanceState` keeps one per held key and hands the active key's to `EffectsState.slide`, by the same rule as the chord (the most recent press). Every effect's settings are `SlidePlayed`: each has a `followsSlide` switch and names the one control the slide stands in for (the filter's brightness, the chorus's amount, the reverb's mix, the arpeggiator's cycle), and lifting returns to the set value. `EffectsState` keeps the set values and passes every effect on as played, so nothing downstream knows about the slide: the `Arpeggiator` gets its settings, and each `EffectsControl` gets the sound effects (the keys' `NotePlayer` makes them its notes' sound, `MidiSink` sends CC 74, 93 and 91). A loop being recorded keeps the effects as played when each chord started, and a slide inside a held chord as changes on the note (`SoundChange`). Because a played value jumps back on lifting, a played control must not cut what is already sounding: the reverb's mix is a send into the reverb, and a new arpeggiator cycle takes effect from the next note. Adding a gesture = a reading in `ChordKeyTouches` and a value on `EffectsState`; making a setting playable = conforming it to `SlidePlayed` and a switch on its card.

**Key zones play effects by where a key is struck.**
They are a second use of the slide, not a second gesture: `KeyZoneSettings` divides the slide into 2 to 4 equal zones, and each `KeyZone` names one effect (or none) and the place on the slide its played control is held at.
A finger in a zone switches that effect on at that value, whatever it is set to (`SlidePlayed.held(at:)`); out of the zone, or lifted, the effect is as set, and still played by the slide if it follows it.
Zones are independent, so a key can mix effects or play one effect at several values (an arpeggio at three speeds).
`EffectsState` works out the zone the finger is in (`zone`, which sticks a little at its edges so a resting finger cannot flicker between two) and passes the effects on as played, so nothing downstream knows about zones either.
Because a zone switches an effect on and off, the last key up ends its chord before its slide ends (`PerformanceState.release`), or the arpeggiator switching off would sound the chord once more.
`ChordKeySurface` marks the zone edges on every key, at the places `ChordKeySlide.share(at:)` gives, so the marks and the reading cannot disagree.
A zone's value is a place on the slide for every effect, so a new `SlidePlayed` effect can be zoned with no more than a row in the Key zones card.

**Sequences and loops are one timeline** (`docs/sequencer-spec.md` has the design and what is still to build). A `Timeline` is notes in layers, in ticks (480 to a quarter note), so anything played loosely is kept as played; a note is a chord at a time, with its own key, octave, sound and effects or the live ones, setting by setting. Edits are changes to that value (`TimelineEdits`), and `compile` turns a layer into the chords to play, for playback and the MIDI export alike. `TimelinePlayer` runs the timeline against the clock under whatever mode is on (it is not a mode), each layer through a `LayerVoice` of its own: an arpeggiator and a `NotePlayer`, so layers overlap one another and the keys. `SequencerState` owns the timeline (undo, saving) and says which layer is on screen; its edits apply to the notes on the selected steps. A note belongs to the step whose line its start is nearest and is on every step it is drawn across (`TimelineNote.step`, `steps`), so a chord played a little early is on its beat and what an edit changes is what the grid shows selected. `StepGridShape` arranges the steps in rows of a beat by the time signature, and `Layer.chits` cuts the notes into the pieces drawn, so the grid, its touches and the edits cannot disagree. `SequencerStep` is only the old saved format now. Play mode's LOOP button (`QuickLoopState`) records what the keys play as a `LoopTake` and adds it as a layer: the first loop sets the length and the tempo (`Timeline.fit`), later ones fold onto it. A loop is notes played again, not recorded audio, so it can be opened and edited in the sequencer.

**Adding a performance mode = one file plus one `ModeKind` case.** Each mode implements `PerformanceMode`; its `ModeKind` gives the display name and the `ModeSurface` (screen) it uses, and `PerformanceState.makeMode` builds it. Views decide by kind or surface, never by display name. `PerformanceState` enforces the button contract documented on `PerformanceMode` (the most recent press is active; lifting it hands the chord back to the press held beneath it), and every chord layout is played through `ChordKeySurface`, which tracks each finger (`ChordKeyTouches`) so all layouts get several fingers and sliding; layouts only draw keys and mark them with `chordKey(_:)`.

**Every setting lives in the menu, a side panel, not in sheets.** `SidePanel` slides over the leading edge of `PerformanceView`, covers only its own width (`SidePanelLayout`) and takes only the touches that land on it, so the keys still showing beside it play as usual and a setting can be heard while it is changed. `SidePanelButton`, in the top leading corner, is the one way in; `SidePanelState` says which page is open and reopens the menu where it was left. A new setting goes on a page (`KeyPanel`, `SoundPanel`, `EffectsPanel`, `SetupPanel`), not behind its own button or sheet.

**Musical time is stated once** in `MusicalTime` (steps per beat, beats per bar, tempo range); nothing restates "16" or "4".

## Key data types

```swift
// Music Theory Core
PitchClass, ScaleType (10 scales; the Key panel offers the 7 heptatonic ones), Key, Degree (I–vii°)
ChordSpec { degree, color: ChordColor }   // which chord, independent of key and voicing
ChordColor .joystick(JoystickMode, JoystickDirection)  — 3 modes × 9 directions; shapes live in JoystickMap
           .grid(StackHeight, HeptatonicMode?)          — thirds stacked through a mode; nil = the degree's own
HeptatonicMode  // the 21 modes of major / melodic minor / harmonic minor; byBrightness orders the grid's rows
ChordGrid, GridPosition  // a finger's cell → ChordColor, resolved against the degree that plays
Voicing { notes: [Int], bassNote: Int? }  // MIDI notes: sorted, unique, always within 0...127

// The central function
func computeVoicing(key:spec:inversion:octave:voiceLeading:previousVoicing:) -> Voicing

// App layer
ChordContext { key, spec, octave, inversion, voiceLeading }  // built by performanceContext(...)
ChordEvent { voicing, articulation, context }             // what every sink receives
```

## Build order

Implement in this sequence — each step is independently testable:

1. Music Theory Core + unit tests (foundation; no UI/audio)
2. A sine wave on device
3. A synth voice + audio sink + minimal PerformanceView (press button → hear chord)
4. JoystickView wiring
5. Key sheet + Sound sheet
6. Non-clock modes: Play, Strum, Lead, Drone
7. MasterClock + Repeat mode + the arpeggiator
8. MidiSink (test with GarageBand)
9. Sequencer mode + screen
10. Loops (first built as a sample-accurate audio looper; now layers of the timeline)
11. Mic Sample (first a mode on AudioKit; now a sound, a recording the kernel plays at each note's pitch)
12. Effects chain + controls
13. SamplerVoice + bundled SFZ instruments
14. Haptics, polish, edge cases

## Testing

The `JoystickMap` table, the chord grid (`stackThirds`, `tertianChordName`, `ChordGrid`) and `computeVoicing` are the core testable surfaces. Every entry in the joystick transformation table becomes a test assertion on `Voicing.notes`. Full combinatorial space is ~68K; test structural rules + representative samples, not exhaustive coverage.

Swift Testing (`@Test`, `#expect`) is the default for all new test files.

```swift
#expect(
    computeVoicing(key: Key(root: .C, scale: .major),
                   spec: ChordSpec(degree: .I, color: .joystick(.default, .right)),
                   inversion: .root, octave: 4, voiceLeading: false, previousVoicing: nil).notes
    == [60, 64, 67, 71]  // Cmaj7
)
```

Core tests live in `Perfecto/Tests/MusicTheoryCoreTests/` and the kernel's in `Perfecto/Tests/PerfectoKernelTests/` (both run on the Mac with `swift test` in `Perfecto/`); app tests live in `Tests/` (run with `xcodebuild … test` on a simulator; see `Tests/README.md`).

## Audio session

- 48kHz, 256-sample buffer (~5.3ms latency)
- `AVAudioSession` category: `.playback` with `mixWithOthers` — app must coexist with DAWs. While the mic sample is being recorded or the vocoder is on it is `.playAndRecord` (to the speaker, built-in mic), and goes back after
- Loops playing in the background need background audio: `.playback` mode + `UIBackgroundModes` entitlement

## MIDI

App registers as a virtual MIDI source named "Perfecto". Channel 1, velocity 100 fixed in v1. The sound effects' amounts are sent as CC 74 (filter), 93 (chorus) and 91 (reverb) while each is on; no other CC messages. No MIDI input, program change, or clock sync in v1.

## V1 scope

- Modes: Play, Strum, Lead, Drone, Repeat, Sequencer; loops (up to 6 layers) are recorded in Play mode and under every mode
- Effects: arpeggiator, filter, chorus, reverb, vocoder; each can be played by sliding on the chord keys, or switched on from a zone of them
- Drum module deferred
- The 7 heptatonic scales (pentatonic and blues hidden for now), all 12 keys, all 3 joystick modes (28 chord types), all 3 inversions
- Synth engine (14 presets; each a `SynthPatch` in `SynthPreset`) + sample engine (SFZ, ≤250MB bundle)
- MIDI out
- Light + dark mode

## Logging

When adding a feature, identify its load-bearing events and emit `LogEvent` cases for them. Event types live in `Perfecto/Sources/Logging/LogEvent.swift`. Pass `Logger` via constructor injection; production uses `FileLogger`, tests use `RecordingLogger`.

## Known risks (watch for)

- **Virtual joystick zone detection** — 8 zones by thumb-drag is harder than physical; may need visual zone-highlighting or wider deadbands. Prototype early.
- **Loop timing** — the timeline's notes are sent 50 ms ahead and sounded on their exact frames. A main thread held up for longer than that makes a note late (it then sounds at once); `TimelineTimingTests` checks the frames with a clock that is always late. What the keys set going on the clock (a live arpeggio, Repeat) is still only as punctual as the main thread.
- **Inversion + voice leading + chord lock interactions** — subtle; write explicit test cases for combinations before shipping.
