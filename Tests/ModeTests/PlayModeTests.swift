import Testing
@testable import Perfecto

@Suite("PlayMode")
@MainActor
struct PlayModeTests {

    // MARK: – Helpers

    private func makeState(clock: ManualClock = ManualClock()) -> (PerformanceState, RecordingSink) {
        let sink = RecordingSink()
        let state = PerformanceState(sink: sink, clock: clock)
        return (state, sink)
    }

    // MARK: – Phase-exit test (spec §12.1)
    //
    // PlayMode.onButtonDown should emit exactly one playChord with the correct voicing
    // for the default key (C major) and degree I at octave 4 with no joystick.
    //
    // Expected: Cmaj (C-E-G) = [60, 64, 67]

    @Test func buttonDownPlaysCorrectVoicing() {
        let (state, sink) = makeState()
        state.press(degree: .I)

        #expect(sink.playCalls.count == 1)
        #expect(sink.playCalls.first?.notes == [60, 64, 67])
    }

    @Test func buttonUpStopsChord() {
        let (state, sink) = makeState()
        state.press(degree: .I)
        state.release(degree: .I)

        #expect(sink.calls.last?.kind == .stop)
        #expect(state.activeDegree == nil)
    }

    @Test func joystickChangeWhileHeldRecomputesVoicing() {
        let (state, sink) = makeState()
        state.press(degree: .I)          // Cmaj [60,64,67]
        sink.reset()
        state.joystickMoved(to: .right)  // → Cmaj7 [60,64,67,71]

        #expect(sink.playCalls.first?.notes == [60, 64, 67, 71])
    }

    @Test func joystickChangedWithNoHeldDegreeDoesNothing() {
        let (state, sink) = makeState()
        state.joystickMoved(to: .up)

        #expect(sink.calls.isEmpty)
    }

    @Test func pressingNewDegreeWhileHoldingPreviousReplaces() {
        let (state, sink) = makeState()
        state.press(degree: .I)   // Cmaj
        state.release(degree: .I)
        state.press(degree: .IV)  // Fmaj [65,69,72]

        #expect(sink.playCalls.last?.notes == [65, 69, 72])
    }
}
