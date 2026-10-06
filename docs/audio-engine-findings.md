# Audio engine findings

> **Status (2026-10-06): evaluation only.** Nothing here is implemented.
> This is the reasoning behind [audio-engine-spec.md](audio-engine-spec.md): the options weighed for the engine (part 1), and the data structures elsewhere in the repo that the engine lets us simplify or combine (part 2).
> Line counts are from the working tree on this date.
> Costs are estimates from reading the code, not measurements.

## Summary

- **Engine:** replace the AudioKit node graph with one render kernel that takes timed notes, each carrying its own sound (E1, option C).
- **Biggest simplification:** a note carries its sound, and effects are shared buses with per-note sends (D2). Nine effects chains become one, and "a loop keeps its sound" needs no machinery.
- **Biggest deletion:** once loops are notes (the sequencer restructuring), both audio loopers and everything around them go: about 900 production lines and 600 of tests (D3).
- **Mic-derived sound** (the mic sample, the vocoder) fits the same kernel through an audio input and capture buffers (E7), and is the one thing still looped as audio.
- **Biggest sound gains, in order:** a master limiter with headroom; voices with release tails and stealing; band-limited oscillators; velocity and stereo spread; sampled instruments.
- **Net size:** roughly 1,400 production lines removed across audio, clock and looper code, against a kernel of 1,500 to 2,500.
  The app does not get smaller overall; the layers above the kernel do, and six package dependencies are dropped.

## Part 1: engine options

### E1. How the sound is made

| Option | What it is | For | Against |
|---|---|---|---|
| A. Tune the node graph | Keep AudioKit; add a limiter, share the reverb, add a voice allocator over the existing `SynthVoice`s, build band-limited `Table`s. | Smallest change (300 to 500 lines). Fixes clipping and the nine reverbs at once. | Six audio units per voice: 64 voices would be about 400 nodes. Notes still start from the main thread, so timing stays as loose as it is. Per-note effect sends are not expressible without a chain per voice. |
| B. A ready-made polyphonic node | DunneAudioKit's `Synth`, or the Synth One kernel, as one node. | One node per engine, little code of ours. | Their patch models are not ours (no FM pair, no per-note sends or brightness), and we would be adapting our sound to someone else's kernel and its upkeep. |
| **C. One kernel of our own** | The spec. | Every item in the standard is reachable; the engine's input is five events and the mic; offline tests cover the whole path. | The most code, and real-time code is unforgiving. |
| D. Host instruments only | Make `AudioSink` an Audio Unit host and take all sound from third-party AUv3s or `AVAudioUnitSampler`. | Best sounds for the least DSP. | Per-note sound, shared sends and loop re-rendering depend on what each instrument exposes; the app has no sound of its own without downloads. |

**Verdict: C**, with A's first two changes done early in the current engine because they are cheap and the sequencer work will make layering denser before the kernel exists.
D is not rejected: hosting is goal 6 of the phase plan, and a kernel wrapped as an `AUAudioUnit` is the natural host-side peer for it.

### E2. How the kernel is hosted

| Option | For | Against |
|---|---|---|
| **`AUAudioUnit` subclass in `AVAudioEngine`** | Manual-rendering tests; an input bus; one step from an AUv3. | More boilerplate than a render block (buses, formats, allocation hooks). |
| `AVAudioSourceNode` render block | A dozen lines to host. | We write and own the lock-free event queue; no route to AUv3 without redoing it. |
| Raw `AURemoteIO`, no `AVAudioEngine` | Fewest layers. | We reimplement input routing, format conversion and offline rendering for no audible gain. |

**Verdict: `AUAudioUnit`.**
I first counted Apple's event queue in its favour; building the skeleton showed that queue carries MIDI, which has no room for a note's id or sound, so the kernel has a small lock-free queue of its own (about 80 lines, the same on every platform).
It has an input bus from the start (E7), since a unit with an input is a different type from one without.

### E3. Kernel language

| Option | For | Against |
|---|---|---|
| **C++ behind a C-shaped interface** | The proven place for render code; sfizz links directly; compiles to WebAssembly for Harmonicland and to desktop plug-in formats. | A second language in the repo and a bridging boundary; Swift 6 concurrency checking stops at the boundary. |
| Swift with unsafe pointers | One language; patches and events are the same types on both sides. | Real-time safety is by discipline only: an accidental array copy, existential or reference count is a rare click that no compiler check catches. The performance annotations that would check it are still underscored and unofficial. Not portable to the browser. |

**Verdict: C++**, chosen on 2026-10-06.
It is half of the Harmonicland question in [own-instruments.md](own-instruments.md), which stays open.
If the suite is ruled out and one language matters more, Swift is workable for a kernel this small, with the allocation trap in debug builds as the guard.

### E4. Where sequences are played from

| Option | For | Against |
|---|---|---|
| A. Keep `Timer` ticks, stamp events "now" | No change. | Jitter of whatever the main run loop is doing; the looper-accuracy risk stays. |
| **B. A look-ahead scheduler in Swift, off the main actor** | One source of timed events for audio, MIDI and the playhead; edits are a new snapshot. | A window to tune; notes already scheduled must be cancellable when a chord changes. |
| C. The timeline lives in the kernel | Immune to any Swift-side stall; exact loop wrap for free. | MIDI and the playhead need the same events, so the timeline would be played twice by two implementations that must agree. |

**Verdict: B.** One pure function compiles a timeline to timed notes, and it also feeds the MIDI export, which closes the phase plan's finding that export and playback re-implement each other.
C is the fallback if stalls are still heard with a 200 ms window.

### E5. Effects per layer

| Option | For | Against |
|---|---|---|
| A. A chain per layer (today) | Each loop keeps every effect setting. | One reverb and chorus per layer, running whether on or not; does not extend to per-note effects. |
| **B. One chorus and one reverb, per-note sends** | Constant cost; per-note amounts are free; tails are never cut. | Size and rate are shared by everything sounding. |
| C. Two or three fixed reverbs with a send to each | Most of A's variety at a fixed cost. | More controls to explain to a player who is not a synth person. |

**Verdict: B**, with C as the known next step.

### E6. Sampled instruments

| Option | For | Against |
|---|---|---|
| Kernel sample source only | Small; enough for the mic sample and simple multisamples. | No velocity layers, round robins or release samples without growing into a sampler. |
| **sfizz inside the kernel** | Full SFZ, disk streaming, BSD-licensed; shares the sends and limiter. | A large C++ dependency; needs the C++ kernel. |
| `AVAudioUnitSampler` beside the kernel | No DSP of ours. | Outside the kernel's sends and note-level sound; SF2 and EXS, not SFZ as the spec planned. |

**Verdict:** the kernel's own source first, sfizz when bundled instruments arrive.

### E7. Sound from the mic: sampling and the vocoder

The vocoder is goal 4 of the phase plan: the mic shapes the chord synth.

| Option | For | Against |
|---|---|---|
| A. Nodes beside the kernel | The mic sample keeps `MicSampler`; the vocoder is a separate unit taking the kernel's output and the mic. | The vocoder would process the whole mix, not chosen notes, and sit outside the sends and limiter. Recording keeps its tap, file and lock. |
| **B. An audio input into the kernel** | The kernel records the mic into preallocated buffers at exact frames, and a buffer is a sampled sound. The vocoder is a bus inside the kernel: notes choose how much of themselves is carrier (a vocoder send), and its output feeds the same sends and limiter. | The kernel's unit becomes an effect type with an input; capture memory is a fixed budget. |
| C. Vocoder as a patch property | No new send. | A sound could not be played both plain and vocoded, and the played-control model (slide, zones) could not reach it. |

**Verdict: B.**
A vocoded phrase is not notes, so it cannot be a loop of notes.
It is looped by capturing the vocoder's output and playing that buffer with one loop-length note, which revises D3: audio looping survives for mic-derived sound only, and without a looper.

Limits that are the phone's, not the design's: the mic hears the speaker, so on the speaker the vocoder runs with voice processing on, at lower quality (decided 2026-10-06); a Bluetooth mic forces call quality.

## Part 2: data structures

Each entry says what exists, the reasonable ways to change it, and the effect on size, efficiency and sound.

### D1. Chords above, notes below

**Today.** `ChordEventSink` is both the chord-level interface (ChordLink wants the whole chord) and the note-level one (audio and MIDI want notes).
So each note sink re-derives notes from chords: `AudioSink` and `MidiSink` each keep a `strumTask` and their own record of what is sounding, `startNotes` sleeps between strummed notes, `SequencerMode` has a `gateTask`, `RepeatMode` a `retriggerTask`, and the `Arpeggiator` emits one-note "chords".
"`playChord` replaces what is sounding" also makes every sink monophonic in chords, which is what stops layers.

| Option | Effect |
|---|---|
| A. Add a layer and a time to `ChordEvent` | Layers and timing become possible, but every sink still expands chords and tracks its own sounding notes, now per layer. |
| **B. A note-level sink under one expander** | One `NotePlayer` per layer turns chord events into timed notes with ids (strum onsets, gate lengths, arpeggio steps as times) and remembers what it started. Sinks become stateless: `noteOn`, `noteChange`, `noteOff`. ChordLink stays on `ChordEventSink`, unchanged. |

**Verdict: B.** It removes four task-based timers and two duplicate note ledgers (about 80 lines), and it is the seam both the sequencer and the kernel need.
Sound: strum spacing and gate lengths become exact.

### D2. One sound per note

**Today.** A sound is spread over `SynthPreset` (set on all voices), `FilterSettings` (one `BrightnessFilter` before the capture point), `ChorusSettings` and `ReverbSettings` (an `EffectsChain` after it), `SoundEffects` (the two that a loop keeps), and two protocols, `EffectsControl` and `AudioEffects`, whose only difference is `setLoopEffects`.
The filter sits before the loopers' tap and the chain after it purely so that a loop records brightness as played but effects as set.

**Change.** One value, sent with each note:

```swift
struct NoteSound: Equatable, Sendable {
    var patch: PatchID
    var brightness: Float   // 1 when the filter is off
    var chorusSend: Float   // 0 when the chorus is off
    var reverbSend: Float   // 0 when the reverb is off
    var vocoderSend: Float  // 0 when the vocoder is off; 1 is carrier only
}
```

The settings structs stay as the panel's model; `NoteSound` is what they come to once the slide and zones are applied.

- `SoundEffects`, `AudioEffects`, `setLoopEffects`, `Looper.liveEffects`, `BrightnessFilter` and eight of nine `EffectsChain`s go.
- `EffectsControl` shrinks from three methods to one (`setSound`), and `MidiSink` already sends only the controllers whose value changed.
- "Before or after the capture point" stops being a design question.
- The rule that a played control must not cut what is sounding holds by construction: sends feed shared effects.

Sound: nine reverbs to one frees most of the effects CPU, and per-note brightness means an arpeggio or a loop no longer has its tails re-filtered by the next note's slide.
Cost: reverb size and chorus rate are shared (E5).

### D3. Loops

**Today.** Two `Looper`s (2 tracks for Looper mode, 6 for the play-mode loop), `LoopCapture`, `LoopMath`, `LoopTake`, the `LoopTracks` protocol, `LooperMode`, `LooperState` with its three `pending…` mailboxes, and `QuickLoopState`: 897 lines, plus 626 of tests.
Takes are `[[Float]]`, grown buffer by buffer under a lock, and `playInPhase` copies the remainder of the loop each time a track starts.

| Option | Effect |
|---|---|
| **A. Loops are timeline layers; the audio loopers are deleted** | All of the above goes. A loop is notes with their `NoteSound`, so it is editable, follows tempo, and costs kilobytes. The mic sample loops as notes of a sampled sound (D9). |
| B. Keep one audio `Looper` for the mic only | Keeps about 630 lines and the capture tap for one mode that is unreachable in the UI today. |
| C. Keep both audio and event loops | Two answers to "what is a loop", and the sequencer could edit only one of them. |

**Verdict: A**, as part of the sequencer restructuring rather than the engine work.
The cost moves from memory to voices: six layers re-rendered live is why the pool is 64.
What is lost: a loop is no longer a recording, so anything not expressible as notes is not in it; a slide inside a held note is kept, recorded as note changes (decided 2026-10-06).
The exception is sound that comes from the mic, which is captured by the kernel and looped as one long note of a sampled sound (E7); that is 23 MB per stereo minute, within a fixed budget of buffers.
Between the sequencer restructuring and the kernel's capture (steps 5 and 11 of the spec's sequence) there is no audio looping at all, which costs nothing today because the mic sample mode has no entry point in the UI.

### D4. The clock

**Today.** `MasterClock` runs a tick `Timer` plus one `Timer` per `every(beats:)` repeat, with a 5 ms "same moment" rule and a `repeatsAfterTick` list to order a repeat after a tick that falls due with it.
`ClockTickable` exposes ticks, repeats and a resolution; `ManualClock` re-implements all of it for tests.

**Change.** `Transport`, a value: tempo, and the frame at which beat 0 fell.
Beats to frames and back are arithmetic.
The scheduler asks each source "what is due before frame *n*", and sources answer from pure functions.

- `ClockRepeat`, the same-moment rule, the ordering rule and per-repeat timers go (about 70 lines of `MasterClock`, and the matching part of `ManualClock`).
- The arpeggiator's `noteRepeat`, `repeatSpacing` and `noteDue` rescheduling go (about 50 lines); what remains is "the notes of this chord between two beat positions".
- Modes that count ticks (`RepeatMode`, `SequencerMode`, `LooperMode`) ask for beat positions instead.
- Tests stop needing a fake clock for most timing rules, since they are functions of a beat range.

Sound: this is the timing fix. Jitter drops from run-loop scale (milliseconds, more under load) to none.

### D5. Oscillators and FM as two operators

**Today.** A voice has two `DynamicOscillator`s and a separate `FMOscillator` pair, and `SynthPatch` has `oscillators: [Oscillator]` and `fm: FM?`.
No shipped preset uses both at once.

| Option | Effect |
|---|---|
| **A. Two operators** | Each has a wave, a frequency ratio and a level, and a patch states one modulation index sweep from the second into the first (0 for none). `SynthPatch.FM` merges into `Oscillator`; the kernel has one source loop, not two. FM patches gain detune and non-sine waves. |
| B. Keep both | Four oscillators' worth of state per voice for patches that use two. |

**Verdict: A.** The 14 presets map across unchanged: the FM patches are a sine modulating a sine, the rest have index 0.
Octave and detune fold into the ratio at note-on, as `SynthVoice.noteOn` already computes.

### D6. Presets as data

**Today.** `SynthPreset` is an enum with three exhaustive switches (name, category, patch).
The v1 spec's `SoundPreset` also needs sampled instruments, which the enum cannot hold.

**Change.** A `Sound` value (`id`, `name`, `category`, and a source that is either a `SynthPatch` or a sample set), with the built-ins as one list.
The kernel's patch table is that list.
This is about 30 lines smaller, and adding a sound is one entry, not three switch arms.
Saved references use the `id`, as `rawValue` does now.

### D7. `EffectsState`

**Today.** Four near-identical `didSet`s, a `follows` switch and a `send` switch over `EffectKind`, and four `send…` functions.

**Change, given D2.** The three sound effects are sent as one `NoteSound` computed in one place (`playedSound`), and the arpeggiator is the one remaining special case.
Both switches go, and three of the four `send…` functions become one.
`SlidePlayed`, `KeyZoneSettings` and the zone hysteresis are already minimal and stay as they are.

### D8. `AudioSink`

**Today.** One class owns the audio session, the engine, the voice pool, both loopers, the mic sampler, the effects and route changes.
`Settings.sampleRate`, a global, is written in three places to keep AudioKit in step with the hardware.

**Change.** `AudioSession` owns the session and route changes; the sink is a thin sender of timed notes to the kernel.
With AudioKit gone the sample-rate global goes with it, and the sample rate is stated once, by the session.
This is the "one graph owner and one session owner" interface from group G of the phase plan.

### D9. The mic sample

**Today.** `MicSampler` records to a file through its own tap, plays through `AudioPlayer` and `TimePitch`, and is reached directly by `MicSampleMode` and `PerformanceState`.

| Option | Effect |
|---|---|
| **A. A recorded buffer is a sound** | The recording becomes a sample set in the `Sound` list and is played, looped, sequenced and given effects like any patch. `MicSampler` is replaced by the kernel's capture (E7). Higher notes play shorter. |
| B. Keep `TimePitch` beside the kernel | Duration is preserved, but the mic sample stays outside notes, sends and loops. |

**Verdict: A**, chosen on 2026-10-06.

### D10. Sequencer steps, pattern and export

`SequencerStep`, `SequencerPattern` (the export's copy) and the timing rules in `SequencerMode` and `SequencerMidiRenderer` describe the same thing three times.
This belongs to the sequencer restructuring, and the engine only fixes what it must produce: a list of timed notes from the one compile function of E4.
Named here so the two pieces of work agree on that type.

### Looked at and left alone

- `Voicing`, `ChordSpec`, `ChordColor`, `ChordContext`: small, pure, and already the single statement of what they describe. A `NoteSound` beside the context on an event is all the engine adds.
- `Articulation`: its `onset(ofNote:)` is exactly what the note expander needs.
- `SlidePlayed`: a key-path version would save a few lines for the three `Float` controls but not fit the arpeggiator's cycle, so two mechanisms would replace one.
- `LoopMath`: correct and well tested; it is deleted with the audio loopers (D3), not improved.

## What goes, by file

| File | Lines | Fate |
|---|---|---|
| `Audio/Looper.swift`, `LoopCapture.swift`, `LoopMath.swift` | 630 | Deleted (D3) |
| `Modes/LooperMode.swift`, `ViewModels/LooperState.swift`, `QuickLoopState.swift` | 267 | Replaced by timeline layers (D3) |
| `Audio/SynthVoice.swift` | 131 | Replaced by the kernel |
| `Audio/EffectsChain.swift`, `BrightnessFilter.swift` | 119 | Replaced by the kernel's sends (D2) |
| `Audio/MicSampler.swift` | 116 | Replaced by the kernel's capture (D9, E7) |
| `Core/Clock/MasterClock.swift` | 163 | Becomes `Transport` and the scheduler (D4) |
| `Core/Events/Arpeggiator.swift` | 192 | Loses its scheduling, about 50 lines (D4) |
| `Audio/AudioSink.swift` | 210 | Splits into session owner and sender (D8) |
| `ViewModels/EffectsState.swift` | 158 | Loses about 40 lines (D7) |

## Dependencies between the pieces

- D1 comes first; D2, D3 and D4 each need it.
- D3 and D10 are the sequencer restructuring; D1 and D4's `Transport` are shared with it.
- D2 can be done in the current engine only in part (a shared reverb, E1 option A); per-note sends need the kernel.
- D5 and D6 are independent and can be done at any time, including before the kernel.
- E3 (language) must be settled before the kernel, and nothing else waits on it.
- E7's input bus is part of the kernel's first version; capture and the vocoder come after parity.
- The full sequence, with what each step needs and how it is checked, is section 6 of the spec.
