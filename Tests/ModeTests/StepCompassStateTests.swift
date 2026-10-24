import Testing
@testable import Perfecto

/// The step compass as a live color surface: a place played colors the
/// chord while it is held, even when it comes down before the chord, and a
/// kept walk is each degree's own.
@Suite("StepCompassState")
@MainActor
struct StepCompassStateTests {

    private func makeCompassState() -> (PerformanceState, RecordingSink) {
        let sink = RecordingSink()
        let state = PerformanceState(sink: sink, clock: ManualClock())
        return (state, sink)
    }

    @Test func nothingHeldPlaysTheTriad() {
        let (state, sink) = makeCompassState()
        state.press(.degree(.I))
        #expect(sink.playCalls.last?.notes == [60, 64, 67])
        #expect(state.color(for: .I) == .base)
    }

    /// A place that comes down before the chord colors its first sound:
    /// the chord is never heard plain.
    @Test func aPlaceHeldBeforeTheChordColorsItFromTheStart() {
        let (state, sink) = makeCompassState()
        state.compassPressed(CompassPlace(.add, 1))
        state.press(.degree(.V))
        #expect(sink.playCalls.count == 1)
        #expect(sink.playCalls.last?.notes == [67, 71, 74, 77])   // G7
    }

    @Test func aPlacePressedWhileHeldRecolorsTheChordAndLiftingGoesBack() {
        let (state, sink) = makeCompassState()
        state.press(.degree(.V))
        state.compassPressed(CompassPlace(.raise, 1))
        #expect(sink.playCalls.last?.notes == [67, 72, 74])       // Gsus4
        state.compassLifted(CompassPlace(.raise, 1))
        #expect(sink.playCalls.last?.notes == [67, 71, 74])
    }

    /// The place held stays the same as the chord changes, and means the
    /// new chord's own step.
    @Test func aHeldPlaceIsEachChordsOwn() {
        let (state, sink) = makeCompassState()
        state.compassPressed(CompassPlace(.add, 1))
        state.press(.degree(.ii))
        #expect(sink.playCalls.last?.notes == [62, 65, 69, 72])   // Dm7
        state.release(.degree(.ii))
        state.press(.degree(.I))
        #expect(sink.playCalls.last?.notes == [60, 64, 67, 71])   // Cmaj7
        #expect(state.activeVoicingText == "C maj7")
    }

    @Test func liftingAnotherPlaceLeavesTheLatest() {
        let (state, sink) = makeCompassState()
        state.press(.degree(.V))
        state.compassPressed(CompassPlace(.add, 1))
        state.compassPressed(CompassPlace(.add, 2))
        state.compassLifted(CompassPlace(.add, 1))
        #expect(sink.playCalls.last?.notes == [67, 71, 74, 81])   // G add9
    }

    /// Kept, each tap is a step from the last, and the walk is each
    /// degree's own: two adds are G9 on V and Dm9 on ii.
    @Test func aKeptWalkStepsFromTheLastAndFollowsTheDegree() {
        let (state, sink) = makeCompassState()
        state.keepsCompassColor = true
        state.compassPressed(CompassPlace(.add, 1))
        state.compassLifted(CompassPlace(.add, 1))
        state.compassPressed(CompassPlace(.add, 1))
        state.press(.degree(.V))
        #expect(sink.playCalls.last?.notes == [67, 71, 74, 77, 81])   // G9
        state.release(.degree(.V))
        state.press(.degree(.ii))
        #expect(sink.playCalls.last?.notes == [62, 65, 69, 72, 76])   // Dm9
        state.compassCleared()
        #expect(sink.playCalls.last?.notes == [62, 65, 69])
    }

    @Test func theOriginIsThePlainChordOrTheWalk() {
        let (state, _) = makeCompassState()
        #expect(state.compassOrigin(for: .V) == ChordTones([0, 4, 7]))
        state.keepsCompassColor = true
        state.compassPressed(CompassPlace(.add, 1))
        #expect(state.compassOrigin(for: .V) == ChordTones([0, 4, 7, 10]))
    }

    @Test func switchingKeepClearsTheCompass() {
        let (state, _) = makeCompassState()
        state.compassPressed(CompassPlace(.add, 1))
        state.keepsCompassColor = true
        #expect(state.compassPlaces.isEmpty)
        state.compassPressed(CompassPlace(.add, 1))
        #expect(state.compassPlaces == [CompassPlace(.add, 1)])
        state.keepsCompassColor = false
        #expect(state.compassPlaces.isEmpty)
    }

    @Test func theRankingChangesWhatAPlacePlays() {
        let (state, sink) = makeCompassState()
        state.press(.degree(.I))
        state.compassPressed(CompassPlace(.add, 1))
        #expect(sink.playCalls.last?.notes == [60, 64, 67, 71])   // Cmaj7
        state.compassRanking = .common
        #expect(sink.playCalls.last?.notes == [60, 64, 67, 70])   // C7
    }

    @Test func thePlacesMakeACross() {
        let cells = CompassPlace.all.map { StepCompassGrid.cell(of: $0) }
        #expect(Set(cells.map { "\($0.column),\($0.row)" }).count == CompassPlace.all.count)
        #expect(cells.allSatisfy { $0.column == 2 || $0.row == 2 })
        #expect(StepCompassGrid.cell(of: CompassPlace(.add, 1)) == (2, 1))
        #expect(StepCompassGrid.cell(of: CompassPlace(.lower, 2)) == (0, 2))
    }
}
