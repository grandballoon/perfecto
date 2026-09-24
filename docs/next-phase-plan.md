# Next Phase Plan: Chord Grid, Tonnetz, Audio

> **Status (2026-09-24):** Phase 0b steps 1–4 done, step 5 partly; see "Updated plan" for what remains.
> This document supersedes the feature list in the chat that produced it.

## Goals

1. Replace the joystick/pad/list chord-color lookup (`JoystickMap`) with a 2-D grid computed by a pure function: X = stacked-third height, Y = brightness.
2. Second-pointer modifiers (sus, skip notes, bass note), counted by fingers on the grid or placed on a strip / chorded button row. Build both so they can be compared.
3. A standalone Tonnetz view.
4. A vocoder (mic modulating the chord synth).
5. Arpeggiation and reverb as effects.
6. AUv3: host a small set of high-quality third-party instruments in place of the built-in presets, then build our own.

## Why a Phase 0

Before adding features, the codebase was audited for what Jimmy Koppel ("The Three Levels of Software") calls errors of modular reasoning.
A module should be correct assuming only the *interfaces* of the modules it uses, never their implementations.
When code works only because of an implementation detail its dependency never promised, that is hidden coupling: a legal change on one side silently breaks the other.

The audit took an OCaml view: imagine each module has an `.mli` signature with abstract types, and ask which callers rely on something that signature would hide.

The result: the pure Music Theory Core is in good shape.
Most hidden coupling sits where the current features meet the six goals above: chord events, the chord-selection model, timing, and audio-graph ownership.
Building the features on top of these seams would multiply the coupling, so Phase 0 fixes the interfaces first.

## Audit findings, grouped by missing interface

Each group names the interface that should exist, the hidden couplings that its absence causes, and the goals it blocks.
Items marked **live bug** misbehave today.

### A. A chord event does not carry its own meaning

`ChordEventSink.playChord(Voicing)` passes only note numbers, so every sink that needs more has to recover it from somewhere else.

- **Live bug: ChordLink announces the wrong chord for sequencer steps.**
  The announcer's context provider ([PerfectoApp.swift:20-31](../App/PerfectoApp.swift)) reads the *live* `joystickMode`/`joystickDirection` from `PerformanceState`.
  `playSequencerStep` voices each step with its *own* mode and direction, so the frame's notes and its coloration disagree.
  The provider also depends on `activeDegree` being written before `sink.playChord` is called, a timing contract stated nowhere.
- The same provider hard-codes `inversion: .root, voiceLeading: false`, copying [PerformanceVoicing.swift](../Modes/PerformanceVoicing.swift) instead of reading it.
- **Live bug: Strum mode sends no MIDI and no ChordLink.**
  `PerformanceState.strumChord` calls the concrete `AudioSink.strumChord` instead of the sink protocol, but `stopChord` still goes to every sink, so MIDI receivers get releases with no matching note-ons.
  `strumChord` also ignores its `interval:` parameter and hard-codes 60 ms.
- **Live bug: notes above 127 corrupt the MIDI stream.**
  `Voicing.notes` is `[Int]` with no range rule.
  `MidiSink` uses `UInt8(clamping:)`, which clamps to 0–255, so note 139 is sent as byte 0x8B, a MIDI status byte.
  Reachable today: B major, vii, maj13, octave 7.
  `ChordWire` and `MidiFile` clamp to 127; `AudioSink` passes the raw value through.
- `AudioSink` has exactly 6 voices and plays `notes.prefix(6)`.
  That works only because today's largest shapes (13, maj13) have 6 notes.
  A 13th stack or a slash bass would sound in MIDI but be silently cut in audio.
- `Voicing.bassNote` exists, but nothing produces it and only `ChordWire` reads it.
  A bass-note modifier that sets it would be silent in audio, MIDI and exports.
- The contract "`playChord` replaces the previous chord" is unwritten.
  [CircleChordGridView.swift:90-100](../Views/CircleChordGridView.swift) relies on it when sliding between degrees, and `ChordRowView` sends release-then-press instead.
  A polyphonic sink (AUv3 host, vocoder carrier, two held chords) would hang notes.

**Interface to add:** a `ChordEvent` value that carries the voicing (with a range-checked MIDI note type), the semantic selection that produced it (see B), and the articulation (block, or strum with an interval).
Sinks receive this and never read view-model state.
The sink protocol states whether `play` replaces or adds.
Voice allocation in `AudioSink` is sized from the event, not from the chord table.

**Blocks:** goals 1, 2, 4, 5, 6.

### B. The chord selection is a set of joystick-shaped fields

The chord being played is scattered across `PerformanceState.joystickMode`, `joystickDirection` and `activeDegree`, and `makeVoicing` reads them implicitly.

- `JoystickMode` × `JoystickDirection` is threaded through `SequencerStep`, `playSequencerStep`, `performanceVoicing`, log strings, the ChordLink wire format and saved sequencer patterns.
- The direction/mode numbering table is copied in four places with nothing linking them: [ChordWire.swift:69-73](../Perfecto/Sources/MusicTheoryCore/ChordWire.swift), [SequencerState.swift:262-281](../ViewModels/SequencerState.swift) (persisted as `jmIdx`/`jdIdx` array positions in UserDefaults), [ChordColorBar.swift:25](../Views/ChordColorBar.swift), and the tests.
  `JoystickDirection` is not `CaseIterable`, so the copies can drift.
- `ChordWire` encodes with `firstIndex(of:) ?? 0`, so an enum case missing from its table encodes silently as major/center.
  It encodes `Degree` by `rawValue`, which contradicts its own header comment ("never by enum declaration order").
  `chordlink.md` documents numbering only for scales and directions.
- The only "selection changed" hook is `onJoystickChange`, and the nine modes handle it inconsistently: five re-voice, four ignore it (Looper even while a chord is held).
  Adding a modifier finger today means adding a hook to all nine modes.
- The view-side chord-color components (`ChordColorBar`, `ChordBarView`, `JoystickView.zoneFor`, `colorationTag`) can express only `JoystickDirection`.

**Interface to add:** a `ChordSpec` value type in the core (degree + color + modifiers), where "color" is the grid coordinate and modifiers are a set.
`computeVoicing` takes a `ChordSpec`.
Modes get one "spec changed" event.
Persistence and ChordLink encode `ChordSpec` with explicit, versioned numbering tables that fail loudly on unknown cases.
Chord-color views take a coordinate type, not `JoystickDirection`.

**Blocks:** goals 1, 2, 3.

### C. Scale theory lives outside the core

The core is pure and well tested, but callers repeat its math instead of asking it.

- **Live bug: in pentatonic scales, Lead mode plays vi and vii an octave low.**
  `leadNote` ([PerformanceState.swift:193-196](../ViewModels/PerformanceState.swift)) re-derives the degree offset and drops the `(degIdx / n) * 12` octave wrap that `computeVoicing` uses.
- **Live bug: degree buttons show major-key roman numerals in every scale.**
  In C natural minor the buttons read "ii" and "vii°" while the display, via `chordLabel`, reads "D dim" and "B♭ maj".
  The labels are copied in six places (`PerformanceView`, `ChordRowView`, `LooperView`, `DegreeRingView`, `CircleChordGridView`, and an unused `Degree.numeralLabel` in `SequencerState`).
  The case name `Degree.viiDim` bakes in the major scale.
- Two rules decide "is this key minor": `triadBase` uses the stacked third, `Key.midiKeySignature` uses `intervals.contains(3)`.
  In Blues they disagree: degree I plays C major while the exported file says C minor.
- "Stacked thirds" is undefined for scales with fewer than seven notes.
  In major pentatonic, degree ii stacks D–F♯–A, and F♯ is not in the scale.
- `MicSampleMode` transposes by `degree.index - 3` semitones, which depends on `Degree` declaration order and ignores the key.
- `KeyQuickController.isMajorish` puts theory in a view file.
- `TriadBase` has no augmented case, so the augmented triads of harmonic and melodic minor play as major triads with a perfect fifth.
  In C harmonic minor, III plays E♭–G–B♭, and B♭ is not in the scale (it should be E♭–G–B).
  Found while doing Phase 0b step 1; not fixed, because every `JoystickMap` entry would need an augmented shape.
  The grid function must handle this: its melodic- and harmonic-minor rows produce these chords directly.

**Interface to add:** core functions for degree offset, degree label (key-aware roman numeral), and key quality, used everywhere those facts are needed.
A written definition of what "height" and "brightness" mean for non-heptatonic scales (see Open decisions).

**Blocks:** goals 1, 3.

### D. Mode identity is a display string

- Views pick screens by comparing `mode.name` to `"Sequencer"`, `"Looper"` or `"Mic Sample"`: [PerformanceView.swift](../Views/PerformanceView.swift) in eight places, [SequencerView.swift:215-218](../Views/SequencerView.swift), and `ModeSheet.swift:62`.
  Renaming or localizing a mode silently drops its screen.
- CLAUDE.md says "adding a performance mode = adding one file".
  In practice it also takes a `ModeSheet` entry and string branches in two views.
- **Live bug: tapping SEQ in the landscape sequencer stops playback.**
  SequencerView's copy of the PLAY/SEQ toggle lacks the `mode.name != "Sequencer"` guard that PerformanceView has, so it re-runs `setMode` and `SequencerMode.deactivate`.
- `ModeSheet` and `SoundSheet` are never presented, so Looper, Mic Sample, Strum and the preset picker are unreachable in the running app.
  `JoystickView` and `loopControlColumn` are dead code.

**Interface to add:** a mode-kind value (not a string) and a mode-to-surface mapping, so the secondary UI (color grid, Tonnetz, modifier strip) is a swappable component chosen by data, not by `if` chains in `PerformanceView`.

**Blocks:** goals 2, 3, and the "swappable secondary UI" goal from `plan.md`.

### E. Press/release pairing is unstated

- `PlayMode.onButtonUp` ends the chord whatever degree was released.
  With two fingers down, lifting either one ends the other's chord.
- Chord surfaces send different event sequences for the same gesture (see A).
- **Live bug: [ChordColorBar.swift:44](../Views/ChordColorBar.swift) fires a haptic and `onChange` on every touch move in the sequencer when no steps are selected.**
  Its dedupe assumes the caller echoes the new direction back into `selected`, which SequencerView skips on that path.
  Its doc says it "owns no state"; the echo requirement is written nowhere.

**Interface to add:** a written pointer contract (every press is paired with a release for the same pointer; releases name what they release; how many chords may sound at once), and one gesture adapter shared by all chord surfaces.

**Blocks:** goal 2 directly (multi-finger is exactly this), and goal 3.

### F. Musical time has no single owner

- `SequencerMode` and `LooperMode` hard-code a bar as 16 ticks, assuming `ticksPerBeat == 4`.
  `ClockTickable` exposes `ticksPerBeat` so it can change, and `SequencerState.stepsPerBar` exists but is unused.
  At 24 PPQN (likely for an arpeggiator), the sequencer would play 1/96 notes.
- Tempo lives in two places: `MasterClock.bpm` clamps to 20–300, `PerformanceState.bpm` does not.
  Gates and the export use the unclamped one.
  At bpm ≤ 0, the `UInt64` conversion in the gate timer traps.
- `MasterClock.onTick` holds one handler and replaces it, so an arpeggiator effect cannot listen alongside a mode.
  Arpeggio and Repeat never reset their `tickCount` on press, so beat phase depends on when the mode was activated.
- Repeat's gap and the sequencer gate use `Task.sleep` instead of the clock.
- Export duplicates live playback's timing rules instead of sharing them.
  [SequencerMidiRenderer.swift:67-90](../Export/SequencerMidiRenderer.swift) re-implements gate, tie and rest from `SequencerMode`, and the two already differ: ties merge in export but retrigger live, export clamps the gate to at least one tick, and voice leading starts from `nil` in export but from the last voicing live.
  The fidelity test checks onset pitches only, so it doesn't catch this.
- `LooperMode` treats a `Timer` + `Task` hop as sample-accurate; `ClockTickable` never promises that.

**Interface to add:** the clock owns tempo and clamping; a musical-time type (bars, beats, steps) derived from `ticksPerBeat`; a clock that supports several subscribers; one pure "schedule these steps" function used by both live playback and export.

**Blocks:** goal 5 (arpeggiation and tempo-synced effects), and the Looper accuracy risk in CLAUDE.md.

### G. The audio graph and session have no single owner

- Both `looper` and `quickLooper` record from the same `synthMixer` bus; AVAudioEngine allows one tap per bus, and nothing stops both recording at once.
  (Based on AudioKit's documented one-tap limit; not yet reproduced on a device.)
- [Looper.swift:82-93](../Audio/Looper.swift) rewires `AudioPlayer`'s internal nodes by hand, relying on AudioKit implementation details.
  `Settings.sampleRate`, a global, is written by both `Looper` and `AudioSink`.
- `setPreset` adds and removes mixer inputs at runtime, contradicting the Looper's "no dynamic graph changes" rule.
- Route changes restart the engine even in External Synth mode, so plugging in headphones doubles GarageBand's sound.
- `MicSampler` uses `engine.avEngine.inputNode` directly and depends on `AudioSink` having set `.playAndRecord`.
  Mic recording state has two writers (`PerformanceState` and `MicSampleMode`).
- Modes and views reach the audio layer directly: `LooperMode`, `MicSampleMode` and `LooperView` call `Looper`/`MicSampler` methods through public `PerformanceState.looper`/`quickLooper`.
  `LooperView` then updates `looperState` separately, so a failed `startPlayback` leaves UI and audio disagreeing.
- Track counts are duplicated: `QuickLoopState.maxLoops = 6` must match `AudioSink`'s `trackCount: 6`.
- Loops capture only `synthMixer`; an instrument or reverb inserted after it would be missing from loops.
- The 48 kHz / 256-frame session in CLAUDE.md is never configured; latency is AudioKit's default.
- The initial `SynthVoice` envelope doesn't match the `.sinePad` preset the UI shows, because `setPreset` isn't called at start-up.

**Interface to add:** one audio-graph owner with named insertion points (instrument slot → effects chain → loop capture point → output; an input bus for mic and vocoder) and one session owner.
Modes and views send intents to it; nothing outside it touches AudioKit nodes or `Settings`.

**Blocks:** goals 4, 5, 6.

### H. Smaller couplings

- Ring geometry (angles, 0.38/0.27/0.22 ratios, `nearest()`) is copied between `CircleChordGridView` and `DegreeRingView`.
  Bar heights and paddings are kept in sync between `PerformanceView` and `SequencerView` only by comments.
  `KeyQuickMetrics` is the pattern to follow.
- MIDI channel and velocity are literals in `MidiSink` and again in `SequencerMidiRenderer`.
- Octave bounds (2...7) are enforced only in `KeySheet`.
- Tests pinned to implementation: `SequencerMidiRendererTests` expects `byteCount == 345`; `ChordNamingTests.swift:107-121` tests `JoystickMap`/`ChordShape` directly.
- `project.yml:31` still points at `PocketChord/Sources/...`; regenerating with xcodegen would break the build.
- The core's sources compile into the app module, so `internal` doesn't hide `JoystickMap` from app code.
- `CLAUDE.md` describes a `ChordQuality` enum and `QualityTransform` that no longer exist.

### Well-encapsulated; leave alone

- Music Theory Core purity: no imports under `MusicTheoryCore/` or `Core/Events/`.
- `Voicing.init` enforces sorted notes; no client assumes `notes[0]` is the root.
- `chordLabel` and `chordQualityName` come from the same shape as the notes.
- `MidiFile`, the `ChordWire` decoder and golden frame, `MidiBackend`/`SysExTransport`, `PermissionGate`, `CompositeSink`.
- `performanceVoicing` as the one voicing policy shared by live playback and export.
- `SequencerState` and `QuickLoopState` keep their state private behind intent methods.
- `ClockTickable` + `ManualClock`.
- `ComputeVoicingTests` and `JoystickMapTests` assert through `computeVoicing`, so they carry over to the grid as a regression oracle.

## Updated plan

### Phase 0a: fix live bugs

Each fix starts with an end-to-end repro, as CLAUDE.md requires.

1. ~~Strum sends no MIDI/ChordLink (A).~~ Fixed in Phase 0b step 2. Not reachable from the UI (nothing presents the mode sheet), so it was confirmed by code reading, with a regression test through `StrumMode`.
2. ~~MIDI notes above 127 go out as status bytes (A).~~ Fixed in Phase 0b step 2. Reproduced first: B major, octave 7, vii with ↘ sent note 132 (0x84).
3. ~~ChordLink announces the live joystick instead of the sequencer step's color (A).~~ Fixed in Phase 0b step 2. Reproduced first: a G7 step was announced as `.center` with G7's notes.
4. ~~Tapping SEQ in the landscape sequencer stops playback (D).~~ Fixed in Phase 0b step 3 (`selectMode` ignores the active mode). Reproduced first through the call the button makes.
5. ~~`ChordColorBar` fires haptics on every move with no steps selected (E).~~ Fixed in Phase 0b step 3: the bar dedupes by the section under the finger, like `DegreeRingView`. SwiftUI gestures aren't unit-testable here, so this one was confirmed by code reading.
5a. ~~With two fingers down, lifting the earlier one ends the later chord (E).~~ Found and fixed in Phase 0b step 3; reachable with the grid layout's buttons. Reproduced first: hold I, hold IV, lift I stopped IV.
6. ~~Lead mode octave error in pentatonic scales (C).~~ No longer reachable now that pentatonic scales are hidden; `leadNote` uses `ScaleType.offset(of:)` since Phase 0b step 1.
7. ~~Degree buttons show major-key numerals in every scale (C).~~ Fixed in Phase 0b step 1 (`degreeNumeral`).
8. Route change restarts the engine in External Synth mode (G).
9. Initial synth envelope doesn't match the shown preset (G).
10. Two loopers can tap the same bus (G), after a device repro.

Several of these disappear naturally with Phase 0b; fix them there if the interface work comes first, but each still gets its repro and a regression test.

### Phase 0b: interfaces, in dependency order

1. **`ChordSpec` + core scale functions** (B, C). Pure, in the core, with rule-based tests. `computeVoicing` takes a `ChordSpec`. The current joystick becomes one way to build a `ChordSpec`, so behaviour is unchanged.
   *Done (2026-09-24).* Added `ChordSpec` (degree + `ChordColor`), `ScaleType.semitones(atStep:)`/`offset(of:)`, `degreeNumeral`, and `Key.isMinor` (now used by the MIDI key signature and the key quick-select).
   One shape lookup (`chordShape`) feeds both the notes and the label.
   Modifiers are deferred to goal 2, which adds them to `ChordSpec`.
   Still joystick-shaped, left for later steps: `PerformanceState.joystickMode`/`joystickDirection`, `SequencerStep`'s stored fields and persistence (step 4), `ChordAnnouncement` (steps 2 and 4), and `MicSampleMode`'s `degree.index - 3` transpose (a behaviour decision; the mode is unreachable today).
2. **`ChordEvent` + sink contract** (A). Range-checked MIDI notes, articulation, semantic spec carried to sinks. Deletes the context provider and the strum bypass. Voice count sized from the event.
   *Done (2026-09-24).* `Voicing` keeps every note in 0–127 by folding octaves, and has unique notes.
   `ChordEvent` carries the voicing, an `Articulation` (block or strum), and the `ChordContext` that produced the notes; `performanceContext` is the one voicing policy.
   The sink protocol documents its contract (`playChord` replaces what is sounding).
   `startNotes` realizes articulation for both audio and MIDI.
   The audio voice pool is `AudioSink.polyphony` (8), and notes beyond it are logged as `audio_notes_dropped`.
   Lead and arpeggio notes still announce the chord they belong to with a one-note voicing; ChordLink v2 (step 4) should decide whether single notes get their own frame kind.
   Strum timing still uses `Task.sleep` (group F).
3. **Pointer contract + shared gesture adapter** (E), and **mode kind + mode-to-surface mapping** (D). Together these make the secondary UI swappable.
   *Done (2026-09-24).* `ModeKind` identifies modes (display name, summary, `ModeSurface`); views route by surface and toggle with `selectMode`, which ignores the active mode.
   `PerformanceMode`'s doc states the button contract, and `PerformanceState` enforces it: it tracks `heldDegrees`, and a mode hears `onButtonUp` only for the most recent press.
   All chord surfaces (button, circle, row) report through `movePointer(from:to:)`, which presses the new degree before releasing the old, so slides have no gap and no double stop.
   The mode sheet is still never presented (Open decision 4).
4. **Versioned persistence and ChordLink v2** (B), coordinated with Harmonicland through `chordlink.md`. Explicit numbering tables for every enum on the wire, failing loudly on unknown cases.
   *Done for v1 (2026-09-24).* ChordWire encodes through tables that a test proves cover every case (a missing case traps instead of encoding as 0), numbers degrees by table rather than raw value, and rejects octaves above 8 and non-ascending notes, as `chordlink.md` requires.
   Sequencer steps store a `ChordColor`; patterns save as JSON under `sequencer.pattern.v3`, enums by case name and `Degree` by its now-explicit raw value. Unreadable data (unknown case, unsupported bar count) loads as the empty pattern. The v1/v2 formats are no longer read.
   **ChordLink v2 moves to goal 1:** its purpose is carrying grid coordinates and modifiers, which don't exist yet. The wire format is unchanged, so Harmonicland needs no code change; its copy of `chordlink.md` needs the same edit to the Perfecto-side architecture section (Harmonicland's current branch has no copy).
5. **Musical time** (F). Clock owns tempo; multi-subscriber ticks; one scheduling function for live and export.
   *Partly done (2026-09-24).* `MusicalTime` states steps per beat, beats per bar and the tempo range once; `PerformanceState.bpm` is `private(set)` and clamped with the clock's range.
   The sequencer counts ticks per step from `ticksPerBeat` (which must be a multiple of 4), the looper's default bar is `beatsPerBar × ticksPerBeat`, and the export's step length no longer follows the clock's resolution.
   Tie behaviour now matches the export: a tied step into the same chord holds it instead of re-striking (reproduced first; `SequencerStep.continues` is the one rule both use). **Audible change**: listen to tied repeats in the sequencer.
   Deferred to goal 5, where the listeners exist: a multi-subscriber clock, and moving gates, Repeat's gap and strum spacing off `Task.sleep` onto a clock fine enough to carry them (an audio-thread clock, which also serves the Looper accuracy risk).
6. **Audio graph owner** (G). Named insertion points and one session owner. Only needed before goals 4–6, so it can move later.
7. Clean up H alongside whichever step touches each file, and update `CLAUDE.md` to match.

### Phase 1: features

| Goal | Depends on (Phase 0b step) |
|---|---|
| 1. Chord-color grid | 1, 2, 3, 4 |
| 2. Second-pointer modifiers | 1, 2, 3 |
| 3. Tonnetz view (standalone) | 1, 3 |
| 4. Vocoder | 2, 6 |
| 5. Arpeggiation and reverb as effects | 5, 6 |
| 6. AUv3 hosting, then own instruments | 2, 6; own instruments also need the Harmonicland decision in [own-instruments.md](own-instruments.md) |

Goal 1 starts by checking that the grid function reproduces today's 38 qualities, using the existing `computeVoicing` tests as the oracle, before any UI work.

**Goal 1 progress (2026-09-24).** The X axis is built: `diatonicMode(key:degree:)` reads a degree's seven-note mode, and `stackThirds(_:height:)` stacks triad → 7 → 9 → 11 → 13 through any mode ([TertianStack.swift](../Perfecto/Sources/MusicTheoryCore/TertianStack.swift)).
A perfect 11 over a major 3rd drops the 3rd in the 11 column (C11) and the 11 in the 13 column (C13), so no two columns repeat.
Stacking through the diatonic mode already fixes the augmented-III problem and reaches dim7, maj9, min13 and 9sus4-style 11 chords.
**Open: the Y axis.** A single one-note-per-step brightness ladder (Lydian → Locrian, continuing to Lydian augmented and the altered scale at the ends) can't reach Lydian dominant, melodic minor, harmonic minor or Phrygian dominant, because those change notes out of the ladder's order.
Covering them means either rows sorted by brightness with some two-note jumps, or a second brightness dimension.
This needs a decision before `ChordColor` gets a grid case and before any UI.

## Open decisions

1. **Grid on non-heptatonic scales.** Resolved for now (2026-09-24): the Key sheet offers only the seven-note scales (`ScaleType.isHeptatonic`), so the grid only needs to handle seven-note scales. The pentatonic and blues cases stay in `ScaleType` so ChordWire numbering is unchanged. Revisit if they return; harmonizing from a parent seven-note scale is the likely answer.
2. **ChordLink v1 compatibility.** Keep decoding v1 frames in Harmonicland during the transition, or switch both repos at once.
3. **Saved sequencer patterns.** Resolved (2026-09-24): testers have no saved patterns, so no migration is needed. Still version the storage format so later changes can migrate.
4. **Unreachable modes.** Looper, Mic Sample and Strum have no entry point in the UI. Decide whether to restore them before or during Phase 1, since the vocoder and the effects need a home.
5. **Arpeggiation.** It exists as a mode ([ArpeggioMode.swift](../Modes/ArpeggioMode.swift)). Goal 5 assumes it becomes a layer usable with any mode; confirm.
6. **"Third-party downloads" in goal 6.** AUv3 apps the player installs and Perfecto hosts, or sample libraries bundled with the app.
