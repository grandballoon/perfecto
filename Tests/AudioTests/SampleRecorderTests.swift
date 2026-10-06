import Foundation
import Testing
@testable import Perfecto

/// Recording the mic sample: the recorder asking the kernel for it, the
/// kernel (in an offline engine) doing it, and the sample kept on disk.
@MainActor
struct SampleRecorderTests {

    private let capture = SynthPreset.micCapture

    private func rig() throws -> KernelOfflineRig {
        try KernelOfflineRig(sounds: [SynthPreset.micSample.patch],
                             hearing: Tone(hz: 440, rate: KernelOfflineRig.rate))
    }

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "sample-\(UUID().uuidString).caf")
    }

    @Test func aRecordingIsStartedStoppedAndThenPlayable() throws {
        let rig = try rig()
        let logger = RecordingLogger()
        let recorder = SampleRecorder(unit: rig.unit, capture: capture, logger: logger)
        var listening: [Bool] = []
        var ended = 0
        recorder.listen = { listening.append($0) }
        recorder.onEnd = { ended += 1 }

        recorder.start()
        #expect(listening == [true])
        #expect(recorder.phase == .starting)
        try rig.render(4800)
        recorder.check()
        #expect(recorder.phase == .recording)

        recorder.stop()
        // The kernel has not rendered the stop yet: it is not over.
        recorder.check()
        #expect(recorder.phase == .stopping)
        #expect(ended == 0)

        try rig.render(5056)
        recorder.check()
        #expect(recorder.phase == .idle)
        #expect(listening == [true, false])
        #expect(ended == 1)
        #expect(abs(recorder.duration - 0.1) < 0.02)
        #expect(logger.events.contains { if case .sample_record_started = $0 { true } else { false } })
        #expect(logger.events.contains { if case .sample_recorded = $0 { true } else { false } })
    }

    @Test func aRecordingEndsByItselfWhenItIsFull() throws {
        let rig = try KernelOfflineRig(bufferSize: 4096, sounds: [SynthPreset.micSample.patch],
                                       hearing: Tone(hz: 440, rate: KernelOfflineRig.rate))
        let recorder = SampleRecorder(unit: rig.unit, capture: capture)
        var ended = 0
        recorder.onEnd = { ended += 1 }
        recorder.start()
        try rig.render(4096)
        recorder.check()
        #expect(recorder.phase == .recording)
        try rig.render(MicSampleState.longest * Int(KernelOfflineRig.rate) + 8192)
        recorder.check()
        #expect(recorder.phase == .idle)
        #expect(ended == 1)
        #expect(abs(recorder.duration - Double(MicSampleState.longest)) < 0.01)
    }

    @Test func aRecordingStartsOverWhenTheEngineIsStartedAgain() throws {
        let rig = try rig()
        let recorder = SampleRecorder(unit: rig.unit, capture: capture)
        var ended = 0
        recorder.onEnd = { ended += 1 }
        recorder.start()
        try rig.render(4800)
        recorder.check()

        // A new route: the engine stops, which ends the kernel's recording.
        rig.engine.stop()
        try rig.engine.start()
        recorder.engineStarted()
        recorder.check()
        #expect(recorder.phase == .starting)
        #expect(ended == 0)

        try rig.render(4800 + 2400)
        recorder.check()
        #expect(recorder.phase == .recording)
        recorder.stop()
        try rig.render(4800 + 2400 + 256)
        recorder.check()
        #expect(ended == 1)
        #expect(recorder.duration > 0.03)
    }

    @Test func theSampleIsPlayedAtEachNotesPitch() throws {
        let rig = try rig()
        let recorder = SampleRecorder(unit: rig.unit, capture: capture)
        recorder.start()
        try rig.render(24_000)
        recorder.stop()
        try rig.render(24_256)
        recorder.check()

        // Recorded at 440 Hz and heard as recorded at middle C: an octave
        // up, it is at 880.
        rig.unit.noteOn(1, note: 72, velocity: 1, sound: 0, at: 28_800)
        try rig.render(48_000)
        let heard = Recording(samples: Array(rig.output[31_200..<38_400]), sampleRate: KernelOfflineRig.rate)
        #expect(strength(of: 880, in: heard) > 0.2)
        #expect(strength(of: 440, in: heard) < 0.01)
    }

    @Test func theSampleIsKeptForTheNextLaunch() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let first = try rig()
        let recorder = SampleRecorder(unit: first.unit, capture: capture, url: url)
        recorder.start()
        try first.render(9600)
        recorder.stop()
        try first.render(9856)
        recorder.check()
        let recorded = first.unit.captured(capture)
        #expect(!recorded.samples.isEmpty)

        let made = KernelAudioUnit.makeNode()
        let next = SampleRecorder(unit: made.unit, capture: capture, url: url)
        #expect(next.duration == recorder.duration)
        #expect(made.unit.captured(capture) == recorded)
    }

    @Test func aRecordingOfNothingLeavesNoSampleBehind() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Recording(samples: [0.5, -0.5], sampleRate: 48_000).write(to: url)
        // Nothing is connected to the unit's input: it hears silence.
        let rig = try KernelOfflineRig()
        let recorder = SampleRecorder(unit: rig.unit, capture: capture, url: url)
        #expect(recorder.duration > 0)
        recorder.start()
        try rig.render(9600)
        recorder.stop()
        try rig.render(9856)
        recorder.check()
        #expect(recorder.duration == 0)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}

@MainActor
struct MicSampleStateTests {

    private func recorder() throws -> (SampleRecorder, KernelOfflineRig) {
        let rig = try KernelOfflineRig(hearing: Tone(hz: 440, rate: KernelOfflineRig.rate))
        return (SampleRecorder(unit: rig.unit, capture: SynthPreset.micCapture), rig)
    }

    @Test func recordingAndStoppingMakesASample() throws {
        let (recorder, rig) = try recorder()
        let state = MicSampleState(recorder: recorder, access: MicAccess(gate: StubPermissionGate(state: .granted)))
        var recorded = 0
        state.onRecorded = { recorded += 1 }
        #expect(!state.hasSample)

        state.toggle()
        #expect(state.isRecording)
        #expect(state.startedAt != nil)
        try rig.render(9600)
        recorder.check()
        state.toggle()
        try rig.render(9856)
        recorder.check()

        #expect(!state.isRecording)
        #expect(state.startedAt == nil)
        #expect(state.hasSample)
        #expect(!state.heardNothing)
        #expect(recorded == 1)
    }

    @Test func theMicIsAskedForTheFirstTime() async throws {
        let (recorder, _) = try recorder()
        let gate = StubPermissionGate(state: .undetermined, nextResult: .granted)
        let state = MicSampleState(recorder: recorder, access: MicAccess(gate: gate))
        state.toggle()
        #expect(try await waitUntil { state.isRecording })
        #expect(gate.requestCallCount == 1)
        #expect(!state.access.isRefused)
    }

    @Test func aRefusalIsSaidAndNothingIsRecorded() async throws {
        let (recorder, _) = try recorder()
        let gate = StubPermissionGate(state: .undetermined, nextResult: .denied)
        let state = MicSampleState(recorder: recorder, access: MicAccess(gate: gate))
        state.toggle()
        #expect(try await waitUntil { state.access.isRefused })
        #expect(!state.isRecording)

        // Refused already: it is not asked again.
        state.toggle()
        #expect(gate.requestCallCount == 1)
        #expect(!state.isRecording)
        #expect(recorder.phase == .idle)
    }

    @Test func aRecordingOfNothingIsSaid() throws {
        let rig = try KernelOfflineRig()
        let recorder = SampleRecorder(unit: rig.unit, capture: SynthPreset.micCapture)
        let state = MicSampleState(recorder: recorder, access: MicAccess(gate: StubPermissionGate(state: .granted)))
        var recorded = 0
        state.onRecorded = { recorded += 1 }
        state.toggle()
        try rig.render(9600)
        state.toggle()
        try rig.render(9856)
        recorder.check()
        #expect(state.heardNothing)
        #expect(!state.hasSample)
        #expect(recorded == 0)
    }
}
