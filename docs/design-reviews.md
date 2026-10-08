# Design Reviews

Each entry covers a scoped review. The four Koppel principles are: **Hidden Layer** (contracts visible in types/comments), **Embedded Design** (structure reflects intent), **Representable/Valid** (invalid states unrepresentable), **Data over Code** (prefer tables over branches).

Dispositions: **refactor now** (blocks current phase), **refactor later** (filed to a phase), **accept** (acknowledged, justified), **amend spec** (spec was the cause).

---

## Review 2 — Phase 1 end-of-phase (2026-05-20)

Scope: files changed or created in Phase 1 only — `MasterClock.swift`, `PerformanceState.swift`, `Tests/Helpers/*`, `Tests/ModeTests/PlayModeTests.swift`.

---

**H1 — `MasterClock.bpm` `didSet` has a subtle re-entry risk**
`bpm.didSet` calls `schedule()` if `isRunning`. `schedule()` is `@MainActor`. Since `didSet` runs on the same actor as the setter, this is safe. No re-entry issue in practice, but the pattern looks surprising at first glance. Comment in `didSet` would help.

Disposition: **Accept** — `@MainActor` guarantees sequential execution; no real risk.

---

**E1 — `PerformanceState.init` clock default uses a nil-coalescing pattern**
`clock ?? MasterClock()` reads cleanly, but a reader might wonder why not just overload. The choice is intentional — one init, not two — which is simpler given that `sink` and `engine` also have defaults. No issue.

Disposition: **Accept**

---

**R1 — `RecordingSink.stopChord()` records a sentinel `Voicing(notes: [])` for stops**
`stopChord()` on the protocol has no voicing argument, so the recording double uses an empty voicing as a sentinel. This means `stopCalls` returns `[Voicing]` but the voicings are meaningless. Callers should use `sink.calls.last?.kind == .stop` rather than `sink.stopCalls`. The API is slightly misleading.

Disposition: **Accept** — the alternative (a separate `[Int]` stop counter) is more work for no test benefit. Document the sentinel behavior in the property comment.

---

**D1 — `ManualClock` is pure data-over-code**
`tick()` fires a stored closure. No branching, no state machine, no timing logic. Correct.

Disposition: **Accept**

---

**Retrospective**
Phase 1 changes were small and clean. The `ClockTickable` restructure (`onTick` replacing delegate) simplified `PerformanceState` — removing the conformance extension at the bottom makes the class boundary easier to scan. The recording doubles pattern held up: `PlayModeTests` reads naturally and the seams were real (no mock-the-world scaffolding needed). Subsequent end-of-phase reviews will be even shorter since scope is inherently bounded.

---

## Review 1 — Phase 0.5 baseline (2026-05-20)

Scope: App/, Audio/, Core/, MIDI/, Modes/, Perfecto/Sources/MusicTheoryCore/, ViewModels/, Views/.

---

### Hidden Layer

**H1 — `MicSampler.recordingFile` is `nonisolated(unsafe)`**
The class comment and inline comment both state the contract: audio-thread writes stop before MainActor reads because `removeTap()` precedes any MainActor access. The `nonisolated(unsafe)` annotation flags the rule; the comment explains why it is safe. This is the Hidden Layer principle done correctly. Verify the comment stays accurate if `stopRecording` is edited.

Disposition: **Accept**

---

**H2 — `PerformanceState.engine` is `AudioSink?` with implicit nil semantics**
`engine` is nil when a non-AudioSink is injected (the test path). Several methods silently skip their audio-specific behavior in that case (`strumChord`, `setSynthPreset`, `looper`). The contract — "engine is nil only during testing; callers should treat nil as no-op" — is not stated anywhere. A reader of `strumChord` must infer it.

Disposition: **Refactor now** — resolved as part of M1 (mandatory injection). See executed refactors below.

---

**H3 — `qualityLabel` in `PerformanceState` duplicates JoystickMap direction semantics**
`qualityLabel` maps `(JoystickMode, JoystickDirection)` → display string. `JoystickMap` maps the same pair to actual interval data. Two tables for the same conceptual mapping; they can silently diverge. The authoritative source of "what does ↗ in Default mode mean?" is `JoystickMap`, but the display string lives separately.

Disposition: **Refactor later** (Phase 3) — when logged `chord_button_pressed` events also carry the quality label, consolidating the two tables becomes urgent.

---

**H4 — `LooperState` pending flags use comment-documented consumed-once protocol**
`pendingRecord`, `pendingStop`, `pendingClear` are set by UI and consumed by `LooperMode.onClockTick`. The comment on `LooperState` says "each flag is consumed once inside onClockTick." The protocol works but relies on `LooperMode` being the only consumer. If a second consumer is added, silent double-consumption will occur. The comment documents the contract correctly for now.

Disposition: **Accept** — document in LooperState that only LooperMode may consume these flags.

---

### Embedded Design

**E1 — `MidiSink` doc comment describes Network MIDI; the spec requires on-device virtual source**
The class comment begins: "Broadcasts chord voicings as MIDI note-on/off messages over WiFi using Apple's Network MIDI (RTP-MIDI, RFC 6295)." The spec (§7.1) defines an on-device virtual source via `MIDISourceCreateWithProtocol`. The code and spec are in direct conflict.

Disposition: **Refactor later** (Phase 2) — entire class will be rewritten per spec §7.

---

**E2 — `strumChord` and `setPreset` bypass `ChordEventSink` — design intent not visible**
`ChordEventSink` defines `playChord`/`stopChord`. `AudioSink` adds `strumChord` and `setPreset` outside the protocol. `PerformanceState.strumChord` does `if let engine { engine.strumChord(voicing) } else { sink.playChord(voicing) }`. The design intent — strumming is an audio-only embellishment; MIDI gets a regular note-on instead — is correct but only readable at the call site, not at the protocol boundary. Spec is silent on this.

Disposition: **Amend spec** — spec §7.2 amended to state that audio-only operations (strumChord, setPreset) bypass the ChordEventSink protocol. MidiSink receives the equivalent playChord. See amendments below.

---

**E3 — Mode→PerformanceState API surface is implicit**
The spec defines `PerformanceMode` (§6) but not the inverse: what methods modes are allowed to call on `PerformanceState`. The actual mode-facing API is: `startChord`, `armChord`, `stopAudioOnly`, `playNote`, `strumChord`, `leadNote`, `playSequencerStep`, `endChord`, and reads of `activeDegree`, `currentVoicing`, `bpm`. This is a real API contract; its absence from the spec makes it invisible to new mode authors.

Disposition: **Amend spec** — spec §6 amended with a mode-facing API table. See amendments below.

---

**E4 — `MicSampleMode` is a stub**
`MicSampleMode` accepts a `MicSampleState` in init but ignores it. All handlers are empty. `MicSampler` exists as a standalone class but is not wired into `AudioSink` or `PerformanceState`. The class is correctly shaped for Phase 4 but documents nothing about what it will eventually do.

Disposition: **Refactor later** (Phase 4) — wire up during permissions + MicSampler integration.

---

### Representable/Valid

**R1 — `activeDegree`/`currentVoicing`/`activeVoicingText` must stay in sync**
Three separate fields represent a single "chord currently held" concept. They are set together in `startChord`/`updateChord` and cleared together in `endChord`, but there is no type-level enforcement. A future edit that sets one without the others will produce inconsistent display state.

Could be: `enum ChordState { case idle; case holding(Degree, Voicing, displayText: String) }`

Disposition: **Refactor later** (Phase 1 test infrastructure) — tests will immediately surface any inconsistency; refactor if a test needs to assert on the combined state atomically.

---

**R2 — `MicSampler` state flags — invalid combinations possible**
Four flags: `isRecording`, `sampleURL`, `pendingURL`, `recordingFile`. Valid states are a small subset of 2⁴ combinations. The actual state machine has four states (idle, recording, loaded, failed) but is implemented with overlapping booleans.

Disposition: **Refactor later** (Phase 4) — the permissions rework will restructure this class anyway. Convert to a state enum at that point.

---

**R3 — `Voicing.bassNote` is `Int?`, not range-bounded**
A MIDI note is 0–127; `Int` accepts any value. In practice, `computeVoicing` never generates out-of-range notes and `AudioSink`/`MidiSink` clamp via `UInt8(clamping:)`. The absence of validation is safe for internal callers.

Disposition: **Accept** — internal code path; clamping at output boundary is sufficient.

---

**R4 — `SequencerState` UserDefaults encoding uses raw Int indices**
`save()`/`load()` encode `Degree`, `JoystickMode`, `JoystickDirection` as raw integers. If any enum gains or reorders cases, saved data silently decodes to wrong values. The format key is "seqSteps.v1" which implies versioning awareness, but there is no migration path.

Disposition: **Refactor later** (post-Phase 1) — add a migration shim or encode as strings before first TestFlight distribution.

---

### Data over Code

**D1 — `SynthPreset` — data split across six separate switch statements**
Six computed properties (`table`, `attack`, `decay`, `sustain`, `release`, `amplitude`) each contain an 8-case switch. Adding a preset requires editing six locations. The data is logically a table of 8 rows × 6 columns but is implemented as 6 separate columns of switches.

Disposition: **Refactor later** — not blocking anything; isolated in SynthPreset.swift. When a 9th preset is added, this will become painful enough to fix.

---

**D2 — `JoystickMap.outcome` is a pure data table**
The actual transformation data lives in three static dictionaries keyed by direction. This is the data-over-code pattern done correctly. No branching logic about what a direction "means" — the table is the answer.

Disposition: **Accept** (correct)

---

**D3 — `qualityLabel` is a parallel code-over-data string table**
See H3. Three nested switch statements that mirror the structure of JoystickMap but return strings instead of interval data.

Disposition: **Refactor later** (Phase 3) — already filed under H3.

---

### Modularity

**M1 — `PerformanceState` constructs its own sinks by default**
`init(sink: (any ChordEventSink)? = nil)` builds `AudioSink()` and `MidiSink()` when no sink is provided. This means forgetting to pass a test double in a test silently creates a real AudioKit engine. The production sink construction belongs at the app boundary.

Disposition: **Refactor now** — executed. See below.

---

**M2 — `ChordEventSink` seam is leaky**
Audio-only operations (`strumChord`, `setPreset`) are called directly on `AudioSink`, bypassing the protocol. This is the correct behavior (MidiSink should not attempt to strum or change presets), but the leakiness is intentional. See E2.

Disposition: **Accept** — amended in spec, justified by design.

---

**M3 — `PerformanceMode` receives full `PerformanceState`**
Modes can call any public method on `PerformanceState`. The boundary is broad. A `ModeContext` protocol could narrow it, but the mode-facing API is already growing organically and narrowing it now would require updating nine mode files. The breadth is not yet causing pain.

Disposition: **Accept** — document the mode-facing API in spec (see E3 amendment) so the boundary is at least explicit even if broad.

---

## Executed refactors

### M1 — Mandatory sink injection in `PerformanceState`

**Change:** `init(sink: (any ChordEventSink)? = nil)` → `init(sink: any ChordEventSink, engine: AudioSink? = nil)`

Production `AudioSink` + `MidiSink` construction moved to `PerfectoApp`. Tests pass a `RecordingSink` (Phase 1) as `sink` and omit `engine`.

**Why it matters for Phase 1:** `RecordingsSink` was already passable via the optional param, but the default-construct path meant a typo or omission would spin up real AudioKit silently. Mandatory injection makes the test double an explicit choice, not an afterthought.

Files changed: `ViewModels/PerformanceState.swift`, `App/PerfectoApp.swift`

---

## Spec amendments

### Amendment 1 — Audio-only operations bypass ChordEventSink (→ spec §7.2)

Added: "Strumming (`strumChord`) and preset changes (`setPreset`) are audio-only operations called directly on `AudioSink`, bypassing `ChordEventSink`. `MidiSink` receives a standard `playChord` for any strum event. This is intentional: MIDI has no concept of strum timing or waveform tables."

### Amendment 2 — Mode-facing API documented (→ spec §6)

Added mode-facing API table to §6.

---

## Retrospective

**What did this review find that wasn't predicted?**

- `SequencerState` UserDefaults encoding (R4) — raw integer encoding with no migration shim is a quiet timebomb before TestFlight.
- `MicSampleMode` being a complete stub (E4) — the class exists and compiles, which can give a false impression that Mic Sample mode is implemented.
- The `qualityLabel` / `JoystickMap` duplication (H3/D3) — two tables for the same conceptual mapping. Not critical yet but will diverge silently.

**What did the review NOT find that was predicted?**

- `PerformanceState.engine` nil contract was predicted to be "implicit" — it is, but the nil semantics are actually clear to a careful reader of the init. The refactor (M1) fixes this at the source anyway.

**How to structure subsequent reviews?**

- End-of-phase reviews should scope to *changed files only*. This full-codebase review took ~45 minutes; a scoped review should take 10–15.
- File a finding even when the answer is "Accept." The record that something was examined is as valuable as the finding.
- Flag stub classes explicitly. `MicSampleMode` being empty is not a bug but should be tracked as a known gap.
