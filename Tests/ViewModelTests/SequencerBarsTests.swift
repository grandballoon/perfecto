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

    /// A new sequence is one empty bar.
    @Test func defaultsToOneBarOfSixteenStepsLoopingWhole() {
        let state = makeState()
        #expect(state.barCount == 1)
        #expect(state.steps.count == 16)
        #expect(state.steps.allSatisfy { $0.isRest })
        #expect(state.timeline.isEmpty)
        #expect(state.focusedBar == 0)
        #expect(state.loopSteps.isEmpty)
        #expect(state.layout == .paged)
    }

    // MARK: – Adding and removing bars

    @Test func addBarAppendsABlankBarAndShowsIt() {
        let state = makeState()
        state.steps[5] = SequencerStep(degree: .V)
        state.addBar()
        #expect(state.barCount == 2)
        #expect(state.steps[5].degree == .V)
        #expect(state.steps[20] == SequencerStep(isRest: true))
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
        state.steps[40] = SequencerStep(degree: .IV)
        state.selectedSteps = [2, 20, 40]
        state.primaryStep = 40
        state.loopSelection()
        state.currentStep = 41
        state.focusedBar = 2

        state.removeBar(1)

        #expect(state.barCount == 2)
        #expect(state.steps[24].degree == .IV)
        #expect(state.selectedSteps == [2, 24])
        #expect(state.loopSteps == Set(2...24))
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

    /// The playhead steps back to just before the removed bar, so what
    /// moved into its place is next.
    @Test func removingTheBarBeingPlayedContinuesWithTheBarThatFollowed() {
        let state = makeState(bars: 3)
        state.currentStep = 20
        state.removeBar(1)
        #expect(state.currentStep == 15)
    }

    @Test func removingTheBarThatHeldTheLoopLoopsTheWholePattern() {
        let state = makeState(bars: 2)
        state.selectedSteps = [16, 17]
        state.loopSelection()
        state.removeBar(1)
        #expect(state.loopSteps.isEmpty)
        #expect(state.timeline.playedRange == 0..<16 * TimelineTime.ticksPerStep)
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
        state.steps[40] = SequencerStep(degree: .IV)
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
        state.steps[20] = SequencerStep(degree: .V)
        state.clearPattern()
        #expect(state.barCount == 2)
        #expect(state.steps[20].degree == .I)
    }

    // MARK: – Loop

    @Test func theWholePatternPlaysWhenNoLoopIsSet() {
        let state = makeState(bars: 2)
        #expect(state.loopSteps.isEmpty)
        #expect(state.timeline.playedRange == 0..<32 * TimelineTime.ticksPerStep)
    }

    /// The loop is one stretch of time: from the first selected step to
    /// the last, whatever lies between.
    @Test func loopSelectionPlaysTheStretchFromTheFirstSelectedStepToTheLast() {
        let state = makeState(bars: 2)
        state.selectedSteps = [20, 4, 5]
        state.loopSelection()
        #expect(state.loopSteps == Set(4...20))
        #expect(state.timeline.playedRange == 4 * TimelineTime.ticksPerStep ..< 21 * TimelineTime.ticksPerStep)
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
        original.steps[40] = SequencerStep(degree: .vi)
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
        original.steps[0] = SequencerStep(degree: .V)
        original.save()
        let key = "sequencer.timeline.v1"
        let saved = String(decoding: defaults.data(forKey: key)!, as: UTF8.self)
        #expect(saved.contains("\"default\""))
        let blank = SequencerState(defaults: isolatedDefaults()).steps

        defaults.set(Data(saved.replacingOccurrences(of: "\"default\"", with: "\"future\"").utf8),
                     forKey: key)
        #expect(SequencerState(defaults: defaults).steps == blank)

        let stepsOnly = isolatedDefaults()
        let ragged = Array(repeating: SequencerStep(degree: .V), count: 17)
        let raggedJSON = String(decoding: try JSONEncoder().encode(ragged), as: UTF8.self)
        stepsOnly.set(Data("{\"steps\":\(raggedJSON)}".utf8), forKey: "sequencer.pattern.v4")
        #expect(SequencerState(defaults: stepsOnly).steps == blank)
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

    /// A pattern saved as steps is read once into the timeline, and from
    /// then on the timeline is what is saved.
    @Test func aPatternSavedAsStepsBecomesTheFirstLayer() throws {
        let defaults = isolatedDefaults()
        var steps = Array(repeating: SequencerStep(), count: 16)
        steps[2] = SequencerStep(degree: .V, gate: 1)
        steps[3] = SequencerStep(degree: .V, gate: 0.5)
        steps[5].isRest = true
        let stepsJSON = String(decoding: try JSONEncoder().encode(steps), as: UTF8.self)
        defaults.set(Data("{\"steps\":\(stepsJSON)}".utf8), forKey: "sequencer.pattern.v4")

        let state = SequencerState(defaults: defaults)
        #expect(state.steps == steps)
        // The tied pair is one held note.
        let held = state.timeline.layers[0].notes.first { $0.chord.degree == .V }
        #expect(held?.length == TimelineTime.ticksPerStep * 3 / 2)

        state.steps[0] = SequencerStep(degree: .IV)
        #expect(SequencerState(defaults: defaults).steps[0].degree == .IV)
    }
}
