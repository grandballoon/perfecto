# Phase 0.5: Initial design review (drop-in roadmap addition)

*This phase is inserted between Phase 0 (Doc Hygiene) and Phase 1 (Test Infrastructure). It establishes the baseline for the ongoing review practice defined in the Design Philosophy doc's Practice section.*

---

## Goal

Apply the four Koppel principles' diagnostic questions to the existing Perfecto codebase. Produce a findings list with dispositions, and update the spec where the spec is what's causing violations. This is the **first review** — subsequent end-of-phase reviews are smaller and scoped to recent changes.

The point isn't to refactor everything. It's to establish a baseline of what's known to be violated and why, so the roadmap's later phases either fix the violations as they touch the relevant code or carry them forward consciously.

## Scope

The existing codebase as it stands at start of Phase 0.5:

- `App/` — entry point
- `Audio/` — `AudioSink`, `Looper`, `MicSampler`, `SynthVoice`, `SynthPreset`
- `Core/` — `Clock/MasterClock`, `Events/ChordEventSink`, `Events/CompositeSink`
- `MIDI/` — `MidiSink`
- `Modes/` — all nine performance modes + protocol
- `Perfecto/Sources/MusicTheoryCore/` — the pure music theory package
- `ViewModels/` — `PerformanceState`, `LooperState`, `SequencerState`, `MicSampleState`
- `Views/` — all SwiftUI views

Out of scope for this first review: test files, project config, Info.plist.

## What to do

1. Read each file in the scope above with the principle questions in mind. Take notes.
2. Compile findings into `design-reviews.md` (first entry).
3. For each finding, assign a disposition: refactor now, refactor later, accept, amend spec.
4. Execute the "refactor now" items.
5. For "amend spec" items, write the spec change before continuing.
6. For "refactor later" items, file them into the appropriate later phase of the roadmap.

## Likely findings (predictions, to be confirmed by the actual review)

Having read parts of the existing codebase while writing the roadmap, here are findings I'd expect this review to surface. They're predictions, not pre-judgments — each should be reconfirmed by actually walking the code with the questions in mind. If the review finds them not to be problems, document why; that's also a useful outcome.

### Hidden Layer

- **`MicSampler.recordingFile` is `nonisolated(unsafe)`** with a comment explaining the contract (audio-thread writes stop before MainActor reads, guaranteed by `removeTap()` ordering). The comment is doing real work — this is the Hidden Layer principle done correctly. Verify the comment still matches the code after any edits.
- **`Voicing.notes` is documented as "sorted low to high"** in the type, and the constructor enforces it via `notes.sorted()`. Also correct. Verify nothing downstream assumes anything stronger (deduplicated, in-key, etc.).
- **`PerformanceState.engine` is implicitly assumed non-nil for some methods** but is declared `AudioSink?`. The contract — "when is engine nil and what should consumers do?" — is not in the type. Worth either making it non-optional or documenting the cases.
- **`MasterClock` integration is implicit** — `PerformanceState` calls `clock.start()` / `clock.stop()` based on `mode.requiresClock`, but the contract "clock is always stopped between modes that don't need it" is not asserted anywhere.

### Embedded Design

- **`MidiSink` says it's for Network MIDI in its doc comment** but the spec is for on-device virtual source. The code and the (forthcoming) spec disagree. Phase 2 reconciles by rewriting the code; the disagreement itself is a current finding.
- **`AudioSink` has a `strumChord` method** that's not part of the `ChordEventSink` protocol. `PerformanceState.strumChord` checks `if let engine` and calls `engine.strumChord(voicing)`, else falls back to `sink.playChord(voicing)`. The design intent ("strumming is an audio-side embellishment, not a music-theoretic operation") isn't visible in the protocol; it's encoded in the conditional. Either lift `strum` into the protocol or accept that audio-specific behaviors break the abstraction (with a comment explaining why).
- **`PerformanceState` has many methods on its public surface** (`startChord`, `armChord`, `stopAudioOnly`, `playNote`, `strumChord`, `leadNote`, `playSequencerStep` ...) that are described as "for the modes to call." This is the Mode → State boundary, and the methods are growing as new modes need new things. Worth asking: is `PerformanceState` doing too much, or is the boundary right but undocumented?

### Representable/Valid

- **`Voicing.bassNote` is `Int?`** rather than something domain-typed. A MIDI note is 0–127; an `Int` accepts any value. The constructor doesn't validate. Probably fine in practice; flag as "accept" with a note about why.
- **`PerformanceMode` is `any PerformanceMode` in `PerformanceState`** — existential, not generic. This means modes are reference-types stored polymorphically. The protocol requires `AnyObject`, which means modes must be classes. This is forced by the design (`mode = newMode` mutation needs reference semantics for clean swap), but it means a mode's internal state outlives the swap unless `deactivate` cleans up. Worth checking each mode's `deactivate` for completeness.
- **`activeDegree: Degree?`** in `PerformanceState` — when nil, the state is "no chord held." When non-nil, a chord is held. But other state (`currentVoicing`, `activeVoicingText`) is also nilled/reset in tandem and could drift. Could be modeled as `enum ChordState { case idle, holding(Degree, Voicing, displayText: String) }`.
- **`MicSampler` has multiple "is in state X" flags** (`isRecording`, `sampleURL`, `pendingURL`, `recordingFile`). The valid combinations are a subset of all combinations. A state-machine enum (`Idle`, `RequestingPermission`, `Recording`, `Loaded(URL)`, `Failed`) would make invalid combinations unrepresentable.

### Data over Code

- **`SynthPreset` is an enum** with cases for `.sinePad`, etc. Per the spec there are several presets. The associated data (waveform table, envelope settings) lives on the cases. This is data-over-code done right. Verify by looking at `SynthPreset.swift` — if there's a giant `switch self` returning different data per case, that's the table form; if it's a `switch self` returning different code paths, that's a smell.
- **`JoystickMap.outcome` is a table.** Already correct. Verify it's the *only* source of the joystick → quality mapping in the codebase; if any consumer has a local `if direction == .up { ... }`, that's a duplicate.
- **The "what triggers each mode" decision tree is scattered.** Each mode has its own `onButtonDown`/`onButtonUp`/`onJoystickChange`/`onClockTick` logic. The shared structure (most modes need `state.startChord(degree:)` on press, `state.endChord()` on release, with mode-specific twists) is implicit. Worth scanning whether the modes are repeating themselves; if so, the shared parts should be `PerformanceMode` defaults or helper functions.

### Modularity (cross-cutting)

The four principles together speak to modularity. Specific seams worth examining:

- **`Core/MusicTheory/` ↔ everything else.** The package boundary is enforced by Swift Package Manager — anything in the app target can import the package, but nothing in the package can import UIKit, AudioKit, etc. The compiler enforces this; verify the package manifest actually closes this loop.
- **`ChordEventSink` ↔ `AudioSink` / `MidiSink`.** The protocol defines `playChord`/`stopChord`. `AudioSink` adds public methods (`strumChord`, `setPreset`) consumers reach for via downcast. The seam is leaky. Acknowledge or fix.
- **`PerformanceMode` ↔ `PerformanceState`.** Modes get a reference to the full `PerformanceState` and can call any of its many methods. The boundary is broad. Could be narrower with a `ModeContext` protocol exposing only what modes need; could also be fine — broader is sometimes simpler, and "what modes need" keeps growing. Worth examining whether the breadth is causing pain.
- **`PerformanceState` ↔ `AudioSink` and `MidiSink`.** Currently `PerformanceState` constructs them in its initializer when none is injected. That makes `PerformanceState` non-testable without spinning up real audio/MIDI. Inject always (no default `AudioSink()` in `init`); construct the production composite at the app level.

## Spec amendments that may emerge

If the review finds violations whose root cause is the spec, those become spec changes. Likely candidates based on the predictions above:

- **`ChordEventSink` should define `strumChord` and `setPreset`,** *or* the spec should explicitly state that audio-only operations bypass the sink protocol (and `MidiSink` therefore doesn't handle them). Current code mixes these without saying which is intended.
- **The Mode → PerformanceState API should be specified explicitly.** Right now modes call ad-hoc methods on PerformanceState; the spec defines `PerformanceMode` but not the inverse interface. Either narrow it (`ModeContext` protocol) or document it as broad-by-design.
- **The `PerformanceState` initializer should require sinks be injected.** The current "auto-construct if nil" path is a testability problem. Spec should mandate dependency injection.

## Disposition guidance

For Phase 0.5 specifically:

- **Refactor now** is reserved for things that block Phase 1 (the test infrastructure). The "always inject sinks" finding is one — without it, the test infrastructure can't drive `PerformanceState` cleanly.
- **Refactor later** items get filed into Phases 2–4 as appropriate (e.g. `MidiSink` doc comment vs. spec mismatch → Phase 2).
- **Accept as known** items go in the review log with their justification, and don't return until something changes.
- **Amend spec** items get the spec change done in Phase 0.5 itself, before Phase 1 begins.

## Phase-exit test

A populated first entry in `design-reviews.md` containing:

- At least 8 findings across the four principles
- A disposition on each
- Spec changes made for any "amend spec" items, with diffs to `spec.md`
- A short retrospective: "what does this review tell me about how to structure the next ones?" — calibration for the practice itself.

If the review produces zero findings, the questions weren't applied seriously. Try again with a narrower scope.

## What this changes about subsequent phases

End-of-phase reviews are now part of every phase's phase-exit test. Each phase exits with:

1. Whatever the phase's own exit test specifies (currently in the roadmap)
2. **Plus** a brief review (10–20 minutes, scoped to what changed) added to `design-reviews.md`

The first review (this phase) is the longest; subsequent ones are short because the scope is small and the questions are familiar.