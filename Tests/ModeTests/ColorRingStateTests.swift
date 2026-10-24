import Testing
@testable import Perfecto

/// The color ring as a live color surface: a cell and the tone marks are
/// kept, so every chord played after them is in their color.
@Suite("ColorRingState")
@MainActor
struct ColorRingStateTests {

    private func makeRingState() -> (PerformanceState, RecordingSink) {
        let sink = RecordingSink()
        let state = PerformanceState(sink: sink, clock: ManualClock())
        state.colorSurface = .ring
        return (state, sink)
    }

    @Test func nothingChosenPlaysTheTriad() {
        let (state, sink) = makeRingState()
        state.press(.degree(.I))
        #expect(sink.playCalls.last?.notes == [60, 64, 67])
    }

    @Test func aCellChosenWhileHeldRevoicesTheChord() {
        let (state, sink) = makeRingState()
        state.press(.degree(.V))
        state.ringChose(ColorRingPosition(height: .seventh, mode: .mixolydian))
        #expect(sink.playCalls.last?.notes == [67, 71, 74, 77])   // G7
    }

    @Test func theCellIsKeptForTheNextChord() {
        let (state, sink) = makeRingState()
        state.ringChose(ColorRingPosition(height: .seventh, mode: .mixolydian))
        state.press(.degree(.I))
        #expect(sink.playCalls.last?.notes == [60, 64, 67, 70])   // C7
        state.release(.degree(.I))
        state.press(.degree(.ii))
        #expect(sink.playCalls.last?.notes == [62, 66, 69, 72])   // D7
    }

    /// The own mode's cell, chosen on a home ring, follows the degree: each
    /// chord's diatonic 7th.
    @Test func theHomeRingsOwnCellFollowsTheDegree() {
        let (state, sink) = makeRingState()
        state.ringArrangement = .home
        state.ringChose(ColorRing.position(height: .seventh, sector: 5, arrangement: .home, key: state.key, degree: .I))
        state.press(.degree(.ii))
        #expect(sink.playCalls.last?.notes == [62, 65, 69, 72])   // Dm7
    }

    @Test func marksChangeTheChordBeingHeld() {
        let (state, sink) = makeRingState()
        state.press(.degree(.V))
        state.ringChose(ColorRingPosition(height: .ninth, mode: .mixolydian))
        state.toggleToneMove(.fifth, by: 1)
        state.toggleToneMove(.ninth, by: 1)
        #expect(sink.playCalls.last?.notes == [67, 71, 75, 77, 82]) // G7alt
        #expect(state.activeVoicingText == "G 9(♯5, ♯9)")
        state.toggleToneSkip(.seventh)
        #expect(Set(sink.playCalls.last?.notes.map { $0 % 12 } ?? []) == [7, 11, 3, 10])  // G B D♯ A♯, no F
    }

    @Test func resetGoesBackToThePlainChord() {
        let (state, sink) = makeRingState()
        state.press(.degree(.I))
        state.ringChose(ColorRingPosition(height: .seventh, mode: .ionian))
        state.toggleToneMove(.third, by: 1)
        state.resetRingColor()
        #expect(sink.playCalls.last?.notes == [60, 64, 67])
        #expect(state.toneMarks.isEmpty && state.ringPosition == nil)
    }

    @Test func switchingTheArrangementChangesNothingThatSounds() {
        let (state, sink) = makeRingState()
        state.press(.degree(.I))
        state.ringChose(ColorRingPosition(height: .ninth, mode: .dorian))
        let before = sink.playCalls.count
        state.ringArrangement = .home
        #expect(sink.playCalls.count == before)
        #expect(state.color(for: .I) == .grid(.ninth, .dorian))
    }

    // MARK: – Played, not kept

    @Test func unkeptACellPlaysOnlyWhileTheFingerIsOnTheRing() {
        let (state, sink) = makeRingState()
        state.keepsRingColor = false
        state.press(.degree(.V))
        state.ringChose(ColorRingPosition(height: .seventh, mode: .mixolydian))
        #expect(sink.playCalls.last?.notes == [67, 71, 74, 77])   // G7
        state.ringLifted()
        #expect(sink.playCalls.last?.notes == [67, 71, 74])       // back to G
        #expect(state.ringPosition == nil)
    }

    @Test func unkeptAMarkPlaysOnlyWhileItsButtonIsHeld() {
        let (state, sink) = makeRingState()
        state.keepsRingColor = false
        state.press(.degree(.I))
        state.pressToneMark(.move(.fifth, by: 1))
        #expect(sink.playCalls.last?.notes == [60, 64, 68])       // C aug
        state.pressToneMark(.skip(.third))
        #expect(sink.playCalls.last?.notes == [60, 68])
        state.releaseToneMark(.move(.fifth, by: 1))
        #expect(sink.playCalls.last?.notes == [60, 67])
        state.releaseToneMark(.skip(.third))
        #expect(sink.playCalls.last?.notes == [60, 64, 67])
        #expect(state.toneMarks.isEmpty)
    }

    /// A button of the other direction held over one already held takes
    /// over; lifting the first then leaves the second.
    @Test func unkeptTheLastMoveHeldIsTheOneThatPlays() {
        let (state, sink) = makeRingState()
        state.keepsRingColor = false
        state.press(.degree(.I))
        state.pressToneMark(.move(.fifth, by: 1))
        state.pressToneMark(.move(.fifth, by: -1))
        state.releaseToneMark(.move(.fifth, by: 1))
        #expect(sink.playCalls.last?.notes == [60, 64, 66])       // ♭5
    }

    @Test func keptAPressTurnsAMarkOnAndALiftLeavesIt() {
        let (state, sink) = makeRingState()
        state.press(.degree(.I))
        state.pressToneMark(.move(.fifth, by: 1))
        state.releaseToneMark(.move(.fifth, by: 1))
        #expect(sink.playCalls.last?.notes == [60, 64, 68])
        state.pressToneMark(.move(.fifth, by: 1))
        #expect(sink.playCalls.last?.notes == [60, 64, 67])
    }

    @Test func switchingKeepOffLeavesTheKeptColorAlone() {
        let (state, sink) = makeRingState()
        state.press(.degree(.I))
        state.ringChose(ColorRingPosition(height: .seventh, mode: .ionian))
        state.keepsRingColor = false
        #expect(sink.playCalls.last?.notes == [60, 64, 67])       // played: none yet
        state.keepsRingColor = true
        #expect(sink.playCalls.last?.notes == [60, 64, 67, 71])   // the kept Cmaj7 again
    }

    @Test func switchingSurfacesClearsTheRing() {
        let (state, _) = makeRingState()
        state.ringChose(ColorRingPosition(height: .ninth, mode: .dorian))
        state.toggleToneSkip(.fifth)
        state.colorSurface = .grid
        state.colorSurface = .ring
        #expect(state.ringPosition == nil && state.toneMarks.isEmpty)
    }
}
