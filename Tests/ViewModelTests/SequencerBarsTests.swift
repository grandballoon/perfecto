import Foundation
import Testing
@testable import Perfecto

@Suite("SequencerState bars")
@MainActor
struct SequencerBarsTests {

    private func makeState(bars: Int = 1) -> SequencerState {
        let state = SequencerState(defaults: isolatedDefaults())
        for _ in 1..<bars { state.addBar() }
        return state
    }

    @Test func defaultsToOneBarOfSixteenStepsLoopingWhole() {
        let state = makeState()
        #expect(state.barCount == 1)
        #expect(state.steps.count == 16)
        #expect(state.focusedBar == 0)
        #expect(state.loopSteps.isEmpty)
        #expect(state.layout == .paged)
    }

    // MARK: – Adding and removing bars

    @Test func addBarAppendsABlankBarAndShowsIt() {
        let state = makeState()
        state.steps[5].degree = .V
        state.addBar()
        #expect(state.barCount == 2)
        #expect(state.steps[5].degree == .V)
        #expect(state.steps[20] == SequencerStep())
        #expect(state.focusedBar == 1)
    }

    /// No preset lengths: a pattern is as long as the bars added to it.
    @Test func barsCanBeAddedWithoutLimit() {
        let state = makeState(bars: 7)
        #expect(state.barCount == 7)
        #expect(state.steps.count == 112)
    }

    @Test func removingABarMovesLaterBarsAndTheirCursorsUp() {
        let state = makeState(bars: 3)
        state.steps[40].degree = .IV
        state.selectedSteps = [2, 20, 40]
        state.primaryStep = 40
        state.loopSelection()
        state.currentStep = 41
        state.focusedBar = 2

        state.removeBar(1)

        #expect(state.barCount == 2)
        #expect(state.steps[24].degree == .IV)
        #expect(state.selectedSteps == [2, 24])
        #expect(state.loopSteps == [2, 24])
        #expect(state.primaryStep == 24)
        #expect(state.currentStep == 25)
        #expect(state.focusedBar == 1)
    }

    @Test func removingTheBarUnderThePrimaryStepFallsBackToAnotherSelectedStep() {
        let state = makeState(bars: 2)
        state.selectedSteps = [3, 20]
        state.primaryStep = 20
        state.removeBar(1)
        #expect(state.selectedSteps == [3])
        #expect(state.primaryStep == 3)
        #expect(state.focusedBar == 0)
    }

    /// The playhead steps back to just before the removed bar, so the next
    /// tick plays what moved into its place.
    @Test func removingTheBarBeingPlayedContinuesWithTheBarThatFollowed() {
        let state = makeState(bars: 3)
        state.currentStep = 20
        state.removeBar(1)
        #expect(state.currentStep == 15)
        #expect(state.step(after: state.currentStep) == 16)
    }

    @Test func removingTheBarThatHeldTheLoopLoopsTheWholePattern() {
        let state = makeState(bars: 2)
        state.selectedSteps = [16, 17]
        state.loopSelection()
        state.removeBar(1)
        #expect(state.loopSteps.isEmpty)
        #expect(state.playOrder == Array(0..<16))
    }

    @Test func theLastBarCannotBeRemoved() {
        let state = makeState()
        #expect(!state.canRemoveBar)
        state.removeBar(0)
        #expect(state.barCount == 1)
        #expect(!state.canUndo)
    }

    @Test func undoRestoresARemovedBarWithItsStepsSelectionAndLoop() {
        let state = makeState(bars: 3)
        state.steps[40].degree = .IV
        state.selectedSteps = [40]
        state.primaryStep = 40
        state.loopSelection()
        state.removeBar(2)
        state.undo()
        #expect(state.barCount == 3)
        #expect(state.steps[40].degree == .IV)
        #expect(state.selectedSteps == [40])
        #expect(state.primaryStep == 40)
        #expect(state.loopSteps == [40])
    }

    @Test func undoingAnAddedBarKeepsTheFocusedBarInsideThePattern() {
        let state = makeState()
        state.addBar()
        state.undo()
        #expect(state.barCount == 1)
        #expect(state.focusedBar == 0)
    }

    @Test func clearPatternKeepsThePatternLength() {
        let state = makeState(bars: 2)
        state.steps[20].degree = .V
        state.clearPattern()
        #expect(state.barCount == 2)
        #expect(state.steps[20].degree == .I)
    }

    // MARK: – Loop

    @Test func theWholePatternPlaysWhenNoLoopIsSet() {
        let state = makeState(bars: 2)
        #expect(state.playOrder == Array(0..<32))
        #expect(state.step(after: -1) == 0)
        #expect(state.step(after: 31) == 0)
    }

    @Test func loopSelectionPlaysExactlyTheSelectedStepsInOrder() {
        let state = makeState(bars: 2)
        state.steps[20].degree = .V
        state.selectedSteps = [20, 4, 5]
        state.loopSelection()
        #expect(state.playOrder == [4, 5, 20])
        #expect(state.playedSteps.map(\.degree) == [.I, .I, .V])
        #expect(state.step(after: -1) == 4)
        #expect(state.step(after: 5) == 20)
        #expect(state.step(after: 20) == 4)
    }

    /// The loop is captured, not tied to the selection: steps can go on being
    /// selected and edited while it plays.
    @Test func theLoopOutlivesLaterSelectionChanges() {
        let state = makeState()
        state.selectedSteps = [4, 5, 6, 7]
        state.loopSelection()
        state.deselectAll()
        state.toggleStepSelection(12)
        #expect(state.loopSteps == [4, 5, 6, 7])
    }

    @Test func loopSelectionAgainMovesTheLoopToTheNewSelection() {
        let state = makeState()
        state.selectedSteps = [0, 1]
        state.loopSelection()
        state.selectedSteps = [8, 9]
        state.loopSelection()
        #expect(state.loopSteps == [8, 9])
    }

    @Test func loopAllReturnsToTheWholePatternAndUndoBringsTheLoopBack() {
        let state = makeState()
        state.selectedSteps = [4, 5]
        state.loopSelection()
        state.loopAll()
        #expect(state.loopSteps.isEmpty)
        state.undo()
        #expect(state.loopSteps == [4, 5])
    }

    @Test func loopChangesThatChangeNothingAreNotUndoable() {
        let state = makeState()
        state.loopAll()                      // already the whole pattern
        state.selectedSteps = []
        state.loopSelection()                // nothing selected
        #expect(!state.canUndo)
        #expect(state.loopSteps.isEmpty)

        state.selectedSteps = [3]
        state.loopSelection()
        state.loopSelection()                // same loop again
        state.undo()
        #expect(!state.canUndo)
    }

    // MARK: – Logging

    @Test func barAndLoopChangesAreLogged() {
        let logger = RecordingLogger()
        let state = SequencerState(defaults: isolatedDefaults(), logger: logger)
        state.addBar()
        state.selectedSteps = [1, 2, 3]
        state.loopSelection()
        state.loopAll()
        state.removeBar(0)

        var logged: [String] = []
        for event in logger.events {
            switch event {
            case let .sequencer_bars_changed(barCount): logged.append("bars \(barCount)")
            case let .sequencer_loop_changed(stepCount): logged.append("loop \(stepCount)")
            default: break
            }
        }
        #expect(logged == ["bars 2", "loop 3", "loop 0", "bars 1"])
    }

    // MARK: – Persistence

    @Test func stepsBarsAndLoopPersist() {
        let defaults = isolatedDefaults()
        let original = SequencerState(defaults: defaults)
        original.addBar()
        original.addBar()
        original.steps[40].degree = .vi
        original.steps[40].gate = 0.3
        original.selectedSteps = [38, 39, 40]
        original.loopSelection()

        let reloaded = SequencerState(defaults: defaults)
        #expect(reloaded.barCount == 3)
        #expect(reloaded.steps[40].degree == .vi)
        #expect(reloaded.steps[40].gate == 0.3)
        #expect(reloaded.loopSteps == [38, 39, 40])
    }

    @Test func layoutPersists() {
        let defaults = isolatedDefaults()
        SequencerState(defaults: defaults).layout = .scroll
        #expect(SequencerState(defaults: defaults).layout == .scroll)
    }

    @Test func stepColorsPersistByName() {
        let defaults = isolatedDefaults()
        let original = SequencerState(defaults: defaults)
        original.steps[3] = SequencerStep(degree: .ii, color: .joystick(.chromatic, .upLeft),
                                          gate: 1, isRest: false)
        original.steps[4].isRest = true
        original.save()

        let reloaded = SequencerState(defaults: defaults)
        #expect(reloaded.steps == original.steps)
    }

    /// A pattern saved by the build with preset bar counts keeps its steps;
    /// its bar count and chain flag are no longer needed.
    @Test func v3PatternsLoadTheirSteps() throws {
        let defaults = isolatedDefaults()
        var steps = Array(repeating: SequencerStep(), count: 32)
        steps[20].degree = .V
        let stepsJSON = String(decoding: try JSONEncoder().encode(steps), as: UTF8.self)
        defaults.set(Data("{\"bars\":2,\"chain\":false,\"steps\":\(stepsJSON)}".utf8),
                     forKey: "sequencer.pattern.v3")

        let state = SequencerState(defaults: defaults)
        #expect(state.barCount == 2)
        #expect(state.steps[20].degree == .V)
        #expect(state.loopSteps.isEmpty)
    }

    /// Data this build can't read (an unknown color, a length that isn't whole
    /// bars) leaves the default pattern instead of being partly interpreted.
    @Test func unreadablePatternsLoadAsEmpty() throws {
        let defaults = isolatedDefaults()
        let original = SequencerState(defaults: defaults)
        original.steps[0].degree = .V
        original.save()
        let key = "sequencer.pattern.v4"
        let saved = String(decoding: defaults.data(forKey: key)!, as: UTF8.self)
        let blank = SequencerState(defaults: isolatedDefaults()).steps

        defaults.set(Data(saved.replacingOccurrences(of: "\"default\"", with: "\"future\"").utf8),
                     forKey: key)
        #expect(SequencerState(defaults: defaults).steps == blank)

        let ragged = Array(repeating: SequencerStep(degree: .V), count: 17)
        let raggedJSON = String(decoding: try JSONEncoder().encode(ragged), as: UTF8.self)
        defaults.set(Data("{\"steps\":\(raggedJSON)}".utf8), forKey: key)
        #expect(SequencerState(defaults: defaults).steps == blank)
    }

    /// A saved loop naming steps the pattern doesn't have is dropped to the
    /// steps that exist.
    @Test func savedLoopStepsOutsideThePatternAreIgnored() throws {
        let defaults = isolatedDefaults()
        let stepsJSON = String(decoding: try JSONEncoder().encode(
            Array(repeating: SequencerStep(), count: 16)), as: UTF8.self)
        defaults.set(Data("{\"steps\":\(stepsJSON),\"loopSteps\":[3,99]}".utf8),
                     forKey: "sequencer.pattern.v4")
        #expect(SequencerState(defaults: defaults).loopSteps == [3])
    }
}
