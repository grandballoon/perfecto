import Testing
@testable import Perfecto

/// The chord grid as a live color surface: Play mode colors held chords from
/// the grid exactly as it does from the joystick.
@Suite("ColorSurface")
@MainActor
struct ColorSurfaceTests {

    private func makeGridState() -> (PerformanceState, RecordingSink) {
        let sink = RecordingSink()
        let state = PerformanceState(sink: sink, clock: ManualClock())
        state.colorSurface = .grid
        return (state, sink)
    }

    /// The own-mode row of the 7th column, on any degree.
    private func seventh(_ state: PerformanceState, _ degree: Degree) -> GridPosition {
        let row = ChordGrid.rows(key: state.key, degree: degree)
            .firstIndex(of: ChordGrid.ownMode(key: state.key, degree: degree))!
        return GridPosition(height: .seventh, row: row)
    }

    @Test func noFingerOnTheGridPlaysTheTriad() {
        let (state, sink) = makeGridState()
        state.press(degree: .I)
        #expect(sink.playCalls.last?.notes == [60, 64, 67])
        #expect(state.activeVoicingText == "C maj")
    }

    @Test func movingOnTheGridWhileHeldRevoicesTheChord() {
        let (state, sink) = makeGridState()
        state.press(degree: .V)
        state.gridMoved(to: seventh(state, .V))
        #expect(sink.playCalls.last?.notes == [67, 71, 74, 77])   // G7
        #expect(state.activeVoicingText == "G 7")

        state.gridMoved(to: nil)
        #expect(sink.playCalls.last?.notes == [67, 71, 74])       // back to G
    }

    /// A cell means a row relative to the degree that plays: the same finger
    /// position is each degree's own diatonic seventh.
    @Test func gridPositionResolvesAgainstThePressedDegree() {
        let (state, sink) = makeGridState()
        state.gridMoved(to: seventh(state, .ii))
        state.press(degree: .ii)
        #expect(sink.playCalls.last?.notes == [62, 65, 69, 72])   // Dmin7
        #expect(state.color(for: .ii) == .grid(.seventh, nil))
    }

    @Test func gridMoveWithNoHeldDegreeDoesNothing() {
        let (state, sink) = makeGridState()
        state.gridMoved(to: GridPosition(height: .ninth, row: 0))
        #expect(sink.calls.isEmpty)
    }

    @Test func switchingSurfacesResetsBoth() {
        let sink = RecordingSink()
        let state = PerformanceState(sink: sink, clock: ManualClock())
        state.joystickMoved(to: .right)
        state.colorSurface = .grid
        #expect(state.color(for: .I) == .grid(.triad, nil))
        state.gridMoved(to: GridPosition(height: .ninth, row: 0))
        state.colorSurface = .joystick
        #expect(state.color(for: .I) == .base)
    }

    /// Steps edited on the grid carry a grid color, which the sequencer plays
    /// as stored even after the surface is switched back.
    @Test func sequencerPlaysAGridStep() {
        let sink = RecordingSink()
        let clock = ManualClock()
        let state = PerformanceState(sink: sink, clock: clock)
        let seq = SequencerState(defaults: isolatedDefaults())
        seq.steps[0] = SequencerStep(degree: .IV, color: .grid(.ninth, nil))
        state.setMode(SequencerMode(seq))
        seq.isPlaying = true
        clock.tick()
        #expect(sink.playCalls.first?.notes == [65, 69, 72, 76, 79])   // Fmaj9
    }
}
