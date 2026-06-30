import Foundation
import Testing
@testable import Perfecto

@Suite("Microphone Permission")
@MainActor
struct MicrophonePermissionTests {

    // MARK: StubPermissionGate behaviour

    @Test func stubStartsUndetermined() {
        let gate = StubPermissionGate(state: .undetermined)
        #expect(gate.state == .undetermined)
    }

    @Test func stubRequestUpdatesStateAndReturnsResult() async {
        let gate = StubPermissionGate(state: .undetermined, nextResult: .granted)
        let result = await gate.requestSystemPrompt()
        #expect(result == .granted)
        #expect(gate.state == .granted)
        #expect(gate.requestCallCount == 1)
    }

    @Test func stubDeniedFlowDoesNotRequest() async {
        let gate = StubPermissionGate(state: .denied, nextResult: .denied)
        #expect(gate.state == .denied)
        #expect(gate.requestCallCount == 0)
    }

    // MARK: MicSampleState permission flow

    @Test func undeterminedGateSetsPrePromptFlow() {
        let micState = MicSampleState()
        let gate     = StubPermissionGate(state: .undetermined)
        let sink     = RecordingSink()
        let state    = PerformanceState(sink: sink, micGate: gate)

        state.startMicRecording()

        #expect(micState.permissionFlow == nil)  // state.micSampleState, not local
        #expect(state.micSampleState.permissionFlow == .prePrompt)
    }

    @Test func deniedGateSetsSettingsRedirectFlow() {
        let gate  = StubPermissionGate(state: .denied)
        let sink  = RecordingSink()
        let state = PerformanceState(sink: sink, micGate: gate)

        state.startMicRecording()

        #expect(state.micSampleState.permissionFlow == .settingsRedirect)
    }

    @Test func restrictedGateSetsRestrictedFlow() {
        let gate  = StubPermissionGate(state: .restricted)
        let sink  = RecordingSink()
        let state = PerformanceState(sink: sink, micGate: gate)

        state.startMicRecording()

        #expect(state.micSampleState.permissionFlow == .restricted)
    }

    // MARK: NoopPermissionGate

    @Test func noopGateIsAlwaysGranted() async {
        let gate   = NoopPermissionGate()
        let result = await gate.requestSystemPrompt()
        #expect(gate.state == .granted)
        #expect(result == .granted)
    }
}
