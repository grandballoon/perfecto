Implementation Roadmap: Translating Specs into Code
This roadmap turns the new spec sections (Design Philosophy revision, MIDI, Testing, Logging, Permissions) into concrete changes to the existing Perfecto codebase. It's ordered for dependency reasons and grouped into phases that each produce something testable and shippable.

Reading this document: Each phase has a goal, a list of code changes, a list of doc changes, and a phase-exit test. Don't move on until the phase-exit test passes — that's the embodied form of "the spec is the source of truth."

Phase 0: Doc hygiene (before code changes)
Goal: get the spec, philosophy, and supporting docs into a consistent state so the rest of the roadmap has firm ground to stand on. No code changes.

What to do
Replace Design Philosophy section in current docs with the revised, Daisy-free version. The old version (in CLAUDE.md and possibly in spec.md) anchors the Music Theory Core's purity rule to the Daisy port. The new version anchors it to "pure function of its inputs, testable in isolation." Whichever file owns the canonical Design Philosophy, replace its content.

Remove the Daisy references from spec.md. Line 3 of the current spec.md says the music theory core is "designed to be portable to a Daisy Seed C++ implementation later." Replace with a statement about portability-via-purity that doesn't name a target. Look for other Daisy mentions (search "Daisy", "C++", "embedded") and remove them too.

Add the four new spec sections to spec.md as new top-level sections, in the order: Testing, MIDI, Logging & Beta, Permissions. (Testing first because the others reference it.)

Resolve the two open spec questions:

MIDI Note Off shape — per-note Note Off vs. CC 123 All Notes Off. The MIDI spec recommends per-note; confirm yes/no in writing.
Logging payload typing — heterogeneous-dictionary vs. sealed-enum-with-associated-values. Recommend sealed enum (per design philosophy). Decide and document.
Decide where bugbook.md, midi_debug.md, learnings.md live in relation to spec.md. They're project artifacts. Quick read of each to confirm none of them contradict the new specs; flag and reconcile if so.

Phase-exit test
A reader who has never seen the project, given only spec.md + CLAUDE.md + design philosophy, can describe:

How a permission flow works
What event types the logger emits
What goes on MIDI vs audio when a chord plays
What's in scope for v1 and what's not
Why the music theory core has no UI/AudioKit imports
If any of these is unclear from the docs, the gap is in the docs, not the reader. Fix the doc.

Phase 1: Test infrastructure foundation
Goal: build the recording-double pattern and helpers that all four new spec sections depend on. After this phase, you can write tests for anything new without scaffolding-as-you-go.

Why first
The Testing spec defines the recording-double pattern. Logging and Permissions specs reference it. MIDI spec's tests use it. If you build features first and tests second, you'll discover that your features aren't structured for the recording-double pattern (untestable seams, hidden state, etc.) and have to refactor. Build the test infrastructure first; let it shape the feature implementations.

What to do
Code: new files
Perfecto/Tests/Helpers/
├── RecordingSink.swift        — conforms to ChordEventSink, records calls
├── ManualClock.swift          — replaces Timer-based MasterClock in tests
├── RecordingLogger.swift      — placeholder; will conform to Logger protocol
│                                 (Logger doesn't exist yet — see Phase 3)
├── StubPermissionGate.swift   — placeholder; PermissionGate doesn't exist yet
└── XCTAssert+Voicing.swift    — custom assertions (or its Swift Testing equivalent)
For now RecordingLogger.swift and StubPermissionGate.swift can be empty files with // TODO Phase 3 and // TODO Phase 4 markers, so the directory shape is right and you don't have to remember.

Code: convert existing Music Theory Core tests to Swift Testing
The existing ComputeVoicingTests.swift, JoystickMapTests.swift, ScaleTests.swift are XCTest. Convert them to Swift Testing as a learning exercise — they're small, the conversion is mechanical, and you'll have hands-on familiarity with the new framework before writing real new tests in it.

If conversion is too disruptive (existing tests are currently green and you don't want to risk breaking them), write new tests in Swift Testing and leave the existing ones in XCTest. The two coexist. The Testing spec's "test files named after spec sections" rule applies to new files; old ones can be renamed in a separate sweep.

Code: introduce ClockTickable protocol for MasterClock (if not already there)
Per the design philosophy doc, MasterClock should be behind a small interface so a ManualClock test double can replace it in mode tests. Check if MasterClock is already protocol-backed; if not, extract a protocol and make MasterClock and ManualClock both conform.

Mode tests use ManualClock; production uses MasterClock. Initial state of PerformanceState instantiates MasterClock by default but accepts a ClockTickable injection for tests.

Doc: write a short Tests/README.md
Document the recording-double pattern, the file organization, and how to run tests. New contributors (and future you) need this.

Phase-exit test
Write one new test using the new helpers, in Swift Testing, that doesn't exist yet. Suggestion: a test for PlayMode.onButtonDown that uses RecordingSink and asserts a playChord was emitted with the expected voicing. This exercises:

Recording-double pattern works
A PerformanceMode can be tested in isolation
Swift Testing is the new default
The seam between PerformanceState and ChordEventSink is real
If you can't write this test cleanly, the seams need work before proceeding.

Phase 2: MIDI rework (on-device virtual source)
Goal: rebuild MidiSink against the spec. The current implementation is for WiFi network MIDI (RTP-MIDI to a Mac DAW); the spec is for on-device virtual MIDI source consumed by GarageBand on the same iPhone. These are different mechanisms.

Why second
MIDI is the most concrete spec-to-code translation, with the fewest dependencies. The new MidiSink is a few hundred lines and has clear test boundaries. It validates the Phase-1 test infrastructure on a real subsystem.

You also explicitly named GarageBand interop as the proximal goal — getting it working confirms the spec is right before depending on it for the rest of v1.

What to do
Code: rewrite MIDI/MidiSink.swift
The current MidiSink:

Uses MIDINetworkSession.default() for RTP-MIDI over WiFi
Uses old MIDISourceCreate + MIDIPacketList
No tests
Logs to print()
The spec-aligned MidiSink:

Creates a virtual source via MIDISourceCreateWithProtocol (new API, MIDI 1.0 protocol)
Sends events via MIDIReceivedEventList (UMP-wrapped MIDI 1.0)
Has a MidiBackend seam (real CoreMIDI in production, RecordingMidiBackend in tests) so the byte-construction logic is testable without CoreMIDI
Emits log events (per Phase 3) — for now, leave a // TODO emit log event marker
Per-note Note Off (confirmed in Phase 0)
Decide what to do with the Network MIDI feature. Two options:

Option A: replace entirely. The spec doesn't mention network MIDI; the current implementation is replaced. Faster, cleaner, fits v1 scope.
Option B: keep alongside. Network MIDI for Mac DAW use case; virtual source for GarageBand use case. Both are useful. More code, but no loss of capability.
Recommend Option A for v1. Network MIDI can come back as a v1.x feature if you miss it.

Code: write tests
Perfecto/Tests/SinkTests/MidiSinkTests.swift. Per Phase 1, these go in Swift Testing with RecordingMidiBackend.

Test cases (a representative set, not exhaustive):

playChord emits Note On for each note in the Voicing
stopChord emits Note Off for each note previously held
Bass note (when present) gets its own Note On in addition to the chord notes
Calling playChord while a chord is already held emits Note Off for the previous one first
MIDI source is created with name "Perfecto" (verify at init)
Code: in-app GarageBand setup hint
Per the MIDI spec, GarageBand requires a manual step to enable Perfecto as a MIDI source. Build the first-run tip / help screen. This is a small SwiftUI view; defer the design polish, just get information visible. A "Where's my sound?" link in the Settings sheet is fine for now.

Doc: update midi_debug.md
The current midi_debug.md probably documents Network MIDI troubleshooting. Update or replace with on-device GarageBand troubleshooting steps that match the new implementation.

Phase-exit test
Real-device test (not simulator — CoreMIDI is finicky in simulator):

Install Perfecto on a phone
Open Perfecto, leave running
Open GarageBand, create a Smart Piano project
In GarageBand's MIDI settings, enable "Perfecto"
Press a chord button in Perfecto — GarageBand sounds
Switch to Perfecto via the multitasking switcher, press chords — GarageBand still sounds
If this works end to end on a real device, the MIDI spec is implementable. Move on.

Phase 3: Logging infrastructure
Goal: build the structured-event logging system the Logging spec defines. After this phase, you can diagnose remote bug reports by reading a log file.

Why third
Permissions (Phase 4) emits log events. Phase 3 must precede Phase 4 to avoid implementing Permissions twice (once without logging, once with). MIDI events also want to be logged, but the Phase 2 // TODO emit log event markers are cheap to fill in later.

Prerequisite
Phase 0 question: payload typing decision. Don't start Phase 3 until that's resolved.

What to do
Code: new files
Perfecto/Sources/Logging/        (new module — see "module-or-folder" note below)
├── Logger.swift                 — protocol
├── LogEvent.swift               — sealed enum with associated values
├── FileLogger.swift             — production implementation (NDJSON to Caches)
└── RingBuffer.swift             — if needed, or fold into FileLogger

Perfecto/Tests/Helpers/RecordingLogger.swift   — fills the Phase-1 placeholder

Perfecto/Tests/LoggingTests/
└── LoggerTests.swift            — event-shape tests, encoder/decoder roundtrip
Module-or-folder note: the Music Theory Core lives in its own Swift Package at Perfecto/Sources/MusicTheoryCore. Logging could be a similar package (compiler-enforced isolation, no UI imports, etc.) or just a folder in the app target. Logging's dependencies are minimal — Foundation only — which makes the package treatment cheap and enforces the discipline.

Code: Logger protocol
@MainActor
protocol Logger {
    func log(_ event: LogEvent)
}
LogEvent is a sealed enum per Phase 0 decision:

enum LogEvent: Codable {
    case audio_session_activated(category: String, mode: String, sampleRate: Double)
    case audio_session_failed(status: Int32)
    case audio_route_changed(to: String, reason: String)
    case audio_session_interrupted(reason: String)
    case audio_session_resumed(reason: String)
    case audio_engine_started
    case audio_engine_stopped
    case audio_engine_failed(message: String)

    case midi_source_created(name: String, status: Int32)
    case midi_note_sent(note: Int, velocity: Int, channel: Int, kind: MidiNoteKind)
    case midi_send_failed(status: Int32, attemptedNote: Int?)

    case sink_attached(kind: SinkKind)
    case sink_detached(kind: SinkKind)
    case sink_error(kind: SinkKind, message: String)

    case mode_changed(from: String, to: String)
    case mode_clock_required(mode: String, clockRunning: Bool)
    case chord_button_pressed(degree: Int, key: String, joystick: String, resultingNotes: [Int])
    case chord_played(notes: [Int], source: ChordSource)
    case chord_stopped(notes: [Int], source: ChordSource)

    case permission_state_observed(permission: String, state: String)
    case permission_pre_prompt_shown(permission: String, feature: String)
    case permission_pre_prompt_response(permission: String, choice: PrePromptChoice)
    case permission_system_prompt_requested(permission: String)
    case permission_system_prompt_response(permission: String, granted: Bool)
    case permission_settings_redirect_shown(permission: String)
    case permission_settings_redirect_taken(permission: String)

    case theory_unexpected_voicing(degree: Int, key: String, notes: [Int])
}
This is the full event catalog from the Logging spec, in code. Adding events later requires adding cases; the compiler tells you everywhere consumers need to handle them.

Code: FileLogger
NDJSON, Caches directory, append-only ring buffer (last N events). Wrap event records with timestamp + session ID at write time:

private struct WrappedEvent: Encodable {
    let timestamp: Date
    let session_id: UUID
    let event: LogEvent  // tagged enum encoded with discriminator
}
Encoder strategy is .iso8601 for dates. Single line per event, terminating newline.

Code: emit log events at all the marked points
Now go through:

AudioSink — every audio_session_, audio_route_, audio_engine_* event
MidiSink — fill in the Phase-2 // TODO emit log event markers
PerformanceState — mode_changed, chord_button_pressed, chord_played, chord_stopped
(Permissions code emits permission_*, but that's Phase 4)
Pass a Logger through the constructors. In production, FileLogger; in tests, RecordingLogger.

Code: in-app "Send Logs" via five-finger tap
A debug menu accessible via a hidden gesture. SwiftUI's .gesture(...) with a MagnificationGesture or TapGesture(count: 5) on the title bar. When tapped, present a share sheet with the log file. (See UIKit primer for UIActivityViewController bridging.)

Doc: update CLAUDE.md with the logging convention
Add a line like "When adding a feature, identify the load-bearing events and add log events for them. The event types are in Perfecto/Sources/Logging/LogEvent.swift."

Phase-exit test
End-to-end: install on a real device, run the app, press chord buttons, change modes, change keys, plug/unplug headphones, force-quit GarageBand mid-session. Then five-finger-tap the title bar, send the log file to your laptop via AirDrop, and read it.

You should be able to reconstruct every action you took from the log file alone. If you can't, the gap is what events are missing — add them and re-run.

Phase 4: Permissions
Goal: implement the three-stage permission flow per the Permissions spec, generalize to a PermissionGate abstraction, retrofit the existing MicSampler direct call.

Why fourth
The existing MicSampler already calls AVAudioApplication.requestRecordPermission() at line 41, but does so without the spec's three-stage flow — no pre-prompt, no settings redirect, no four-state handling. This works for a developer running the app on a known device; it fails the moment a TestFlight user denies the prompt once and then wonders why Mic Sample mode is silent forever.

Phase 4 fixes this by extracting the permission flow into a reusable abstraction and pointing MicSampler (and any future feature needing permissions) at it.

What to do
Code: new files
Perfecto/Sources/Permissions/    (or top-level Permissions/ folder)
├── PermissionGate.swift         — protocol + PermissionState enum
└── MicrophonePermissionGate.swift — AVAudioApplication-backed implementation

Perfecto/Tests/Helpers/StubPermissionGate.swift  — fills the Phase-1 placeholder

Views/Permissions/
├── PrePromptView.swift          — Stage 1
├── SettingsRedirectView.swift   — Stage 3
└── PermissionFlowView.swift     — coordinator that dispatches based on state

Perfecto/Tests/PermissionTests/
└── MicrophonePermissionTests.swift
Code: protocol
enum PermissionState {
    case undetermined, granted, denied, restricted
}

@MainActor
protocol PermissionGate {
    var state: PermissionState { get }
    func requestSystemPrompt() async -> PermissionState
}

@MainActor
final class MicrophonePermissionGate: PermissionGate {
    private let logger: Logger  // injected
    // ... implementation per AVAudioApplication primer
}
Code: rewire MicSampler
Currently MicSampler.startRecording() calls AVAudioApplication.requestRecordPermission() directly. Remove that direct call. The permission check happens before MicSampler is given the green light to record. The flow becomes:

User taps "Record" in Mic Sample mode
    ↓
PerformanceState (or MicSampleState) checks micGate.state
    ↓
If .undetermined: show PrePromptView
If .denied:       show SettingsRedirectView
If .granted:      call micSampler.startRecording()
If .restricted:   show "can't be enabled" view
MicSampler no longer knows about permissions; it just records when told to.

Code: Info.plist
Confirm NSMicrophoneUsageDescription exists with feature-focused copy. Add if missing.

Doc: update CLAUDE.md permissions section
Note that new features needing permissions go through PermissionGate, never directly through the system API.

Phase-exit test
Five separate test scenarios on a real device:

Fresh install. Tap Mic Sample mode. See pre-prompt. Tap Continue. See system prompt. Tap Allow. Recording works.
Fresh install. Tap Mic Sample mode. See pre-prompt. Tap Not Now. No system prompt. State remains .undetermined.
Tap Mic Sample mode again. Pre-prompt shows again. Tap Continue. System prompt. Tap Don't Allow.
Tap Mic Sample mode. See settings-redirect view. Tap Open Settings. iOS Settings opens. Toggle Mic on. Return to Perfecto. State is now .granted, Mic Sample mode is usable.
Five-finger tap, send logs. Confirm every step above appears as a permission_* event in the log.
If all five work, Phase 4 is done.

Phase 5: Living docs and steady-state operations
Goal: establish the ongoing maintenance pattern. Less prescriptive than the earlier phases.

What to do
Resolve the SFZ question. Spec mentions SFZ; AVAudioUnitSampler doesn't support it natively. Either pre-convert your sample library to SF2/DLS, integrate sfizz, or change the spec. Don't leave this hanging.

Decide on Swift 6 strict concurrency level. Per the Swift 6 primer, complete mode is the goal; targeted or minimal are stepping stones. Confirm the project setting is what you want.

CI / automation. Out of scope for this roadmap, but worth flagging: at some point you'll want Xcode Cloud or fastlane running tests on every push and publishing TestFlight builds. Not v1.

Manual smoke-test checklist. Per the Testing spec, things not unit-tested (UI, audio output, MIDI to GarageBand) are covered by manual smoke testing. Write the checklist — one page, ten items — and run it before each TestFlight upload.

learnings.md is empty. It probably shouldn't be. As you implement the phases above, note the things you learned that aren't yet captured anywhere — gotchas, surprising behaviors, decisions and their rationale. Future you and future contributors will thank you.

What I still need to finish this roadmap fully
These are concrete unknowns; without them the roadmap is at the right shape but loose on a few specifics. None block starting Phase 0, but each would tighten a later phase.

Information about the codebase
Contents of CLAUDE.md and spec.md in full. I read the project structure and key files (PerformanceState, AudioSink, MicSampler, MidiSink) but only the first 80 lines of spec.md. There may be sections in spec.md that already cover MIDI, Logging, Permissions, or Testing — in which case Phase 0's "add new sections" becomes "merge with existing." If you can share the rest of spec.md, the merge plan can be concrete.

Contents of bugbook.md, midi_debug.md, learnings.md. These may contain decisions or workarounds that contradict or refine the new specs. Worth a read to reconcile in Phase 0.

Whether MasterClock is protocol-backed or concrete. Phase 1 includes a possible-no-op step ("introduce ClockTickable if not already there") because I don't know. If you can show Core/Clock/MasterClock.swift, I can confirm.

What Package.swift (in Perfecto/Perfecto/Package.swift) declares. This determines whether the Music Theory Core is genuinely a separate Swift package (in which case Logging could follow the same pattern) or just a folder with a Package.swift artifact from an earlier structure.

Whether the existing Music Theory tests pass under Swift 6 strict concurrency. If not, Phase 1's "convert to Swift Testing" exercise may surface more work than expected.

The state of Info.plist. Does it already have NSMicrophoneUsageDescription? UIBackgroundModes with audio? ITSAppUsesNonExemptEncryption? These three are the most common TestFlight-upload blockers.

Decisions you (Luke) need to make
MIDI Note Off shape (Phase 0 question). Spec recommends per-note; confirm.

Logging payload typing (Phase 0 question). Spec recommends sealed enum; confirm.

Network MIDI: keep or drop? (Phase 2 decision). Recommend drop for v1.

SFZ vs SF2/DLS for sample library (Phase 5 question, but earlier decisions in audio engine architecture may depend on it). Worth thinking about now even if not deciding.

Where new modules live: separate Swift Packages, or folders in the app target? (Affects Phases 3 and 4). Recommend separate packages for Logging and Permissions, same as MusicTheoryCore. Stronger isolation, compiler-enforced.

Swift Testing rollout: convert existing XCTest, or only new code? (Phase 1). Recommend convert as a learning exercise on the existing small tests, then strictly Swift Testing going forward.

External validations
Phase 2 phase-exit test requires a real iPhone and a real GarageBand install. Confirm you have both.

Phase 3 phase-exit test requires you to actually read your own logs. Useful exercise; budget time for it.

Phase 4 phase-exit test requires testing with a fresh install (or simulated fresh state) to verify the .undetermined flow. Erase Perfecto from the device and reinstall, or use the simulator's "Reset Location & Privacy" feature.

Timing and effort (very rough)
These are estimates, not commitments. Calibrate to your own velocity after Phase 0.

Phase	Code time	Test time	Doc time	Total
0 Doc hygiene	0	0	1–2 days	1–2 days
1 Test infrastructure	1–2 days	1 day	0.5 day	2.5–3.5 days
2 MIDI rework	2–3 days	1 day	0.5 day	3.5–4.5 days
3 Logging	3–4 days	1–2 days	0.5 day	4.5–6.5 days
4 Permissions	2–3 days	1–2 days	0.5 day	3.5–5.5 days
5 Living docs	(ongoing)	(ongoing)	(ongoing)	continuous
Total to end of Phase 4: roughly 2–3 weeks at sustained pace. Less if you focus, more if you're learning Swift 6 concurrency or AudioKit specifics in parallel.

The biggest risk is Phase 2's MIDI-to-GarageBand validation — if the GarageBand setup proves harder than the spec assumes, that's where to slow down and verify on real hardware before depending on it.