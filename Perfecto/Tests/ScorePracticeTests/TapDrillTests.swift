import Testing
@testable import ScorePractice

@Suite("Tap drill")
struct TapDrillTests {

    /// Taps `pitches` one after another.
    private func tapping(_ drill: TapDrill, _ pitches: [Int]) -> (TapDrill, [TapOutcome]) {
        var drill = drill
        var outcomes: [TapOutcome] = []
        for pitch in pitches {
            let outcome: TapOutcome
            (drill, outcome) = drill.tapping(pitch)
            outcomes.append(outcome)
        }
        return (drill, outcomes)
    }

    @Test func aRunsStepsAreTappedInTheOrderOfTheScore() {
        let drill = TapDrill([Passage(.right, from: 2, to: 4)], in: scale)
        #expect(drill.steps.map(\.pitches) == [[76], [77], [79]])
        let (after, outcomes) = tapping(drill, [76, 77])
        #expect(outcomes == [.stepDone, .stepDone])
        #expect(after.current?.pitches == [79])
        #expect(after.current?.onset == 4)
    }

    @Test func aWrongNoteIsToldAndTheStepWaitsForTheRightOne() {
        let drill = TapDrill([Passage(.right, from: 0, to: 1)], in: scale)
        let (after, outcomes) = tapping(drill, [74, 73, 72])
        #expect(outcomes == [.wrong, .wrong, .stepDone])
        #expect(after.index == 1)
        #expect(after.mistakes == 2)
    }

    @Test func aChordIsDoneWhenEachOfItsNotesIsTappedInAnyOrder() {
        let drill = TapDrill([Passage(.left, from: 0, to: 1)], in: scale)
        #expect(drill.current?.pitches == [48, 55])
        let (after, outcomes) = tapping(drill, [55, 55, 48])
        // A note of the chord tapped again is still right, and no further.
        #expect(outcomes == [.right, .right, .stepDone])
        #expect(after.current?.pitches == [53])
        #expect(after.mistakes == 0)
    }

    @Test func theLastNoteFinishesAPassAndTheNextTapBeginsAnother() {
        let drill = TapDrill([Passage(.right, from: 6, to: 7)], in: scale)
        let (after, outcomes) = tapping(drill, [83, 60, 84])
        #expect(outcomes == [.stepDone, .wrong, .passed(mistakes: 1)])
        #expect(after.index == 0)
        #expect(after.passes == 1)
        #expect(after.mistakes == 0)
        #expect(tapping(after, [83]).1 == [.stepDone])
    }

    @Test func runsThatOverlapAreTappedStraightThroughEachStepOnce() {
        let drill = TapDrill([Passage(.right, from: 3, to: 4), Passage(.right, from: 0, to: 3)], in: scale)
        #expect(drill.steps.map(\.onset) == [0, 1, 2, 3, 4])
    }

    @Test func aRunOfBothHandsTapsBothHandsNotesOfAStepAsOne() {
        let drill = TapDrill([Passage(.both, from: 4, to: 4)], in: scale)
        #expect(drill.current?.pitches == [53, 79])
        #expect(drill.current?.notes.map(\.hand) == [.left, .right])
    }

    @Test func theNextNotesAreLitOnlyWhenShownAndTheTappedOnesAlways() {
        let drill = TapDrill([Passage(.left, from: 0, to: 0)], in: scale)
        let (after, _) = tapping(drill, [48])
        #expect(after.lights(showingNext: true)
                == [48: [KeyLight(hand: .left, kind: .sounding(since: 1))],
                    55: [KeyLight(hand: .left, kind: .next)]])
        #expect(after.lights(showingNext: false)
                == [48: [KeyLight(hand: .left, kind: .sounding(since: 1))]])
    }

    @Test func beginningAgainKeepsThePassesAndForgetsTheMistakes() {
        let drill = TapDrill([Passage(.right, from: 0, to: 0)], in: scale)
        let (after, _) = tapping(drill, [72, 60])
        let again = after.restarted()
        #expect(again.passes == 1)
        #expect(again.mistakes == 0)
        #expect(again.index == 0)
    }

    @Test func movingThePlayheadTakesTheDrillToTheStepStruckThen() {
        let drill = TapDrill([Passage(.right, from: 2, to: 5)], in: scale)
        let (partway, _) = tapping(drill, [76, 60])
        #expect(partway.moved(to: 4.5).current?.pitches == [79])
        #expect(partway.moved(to: 4.5).mistakes == 1)
        // Before the run, it is at its first step; after it, its last.
        #expect(partway.moved(to: 0).index == 0)
        #expect(partway.moved(to: 7).index == 3)
    }

    @Test func nothingToTapMakesEveryTapWrong() {
        let drill = TapDrill(steps: [])
        #expect(drill.isEmpty)
        #expect(drill.tapping(60).1 == .wrong)
        #expect(drill.lights(showingNext: true).isEmpty)
    }

    @Test func aNoteIsNamedAsAPianistReadsIt() {
        #expect(pitchName(60) == "C4")
        #expect(pitchName(66) == "F♯4")
        #expect(pitchName(21) == "A0")
        #expect(pitchName(108) == "C8")
    }
}
