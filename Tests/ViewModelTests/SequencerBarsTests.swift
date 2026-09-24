import Foundation
import Testing
@testable import Perfecto

@Suite("SequencerState bars")
@MainActor
struct SequencerBarsTests {

    private func makeState() -> SequencerState {
        SequencerState(defaults: isolatedDefaults())
    }

    @Test func defaultsToOneBarOfSixteenSteps() {
        let state = makeState()
        #expect(state.bars == 1)
        #expect(state.steps.count == 16)
        #expect(state.currentPage == 0)
        #expect(state.chain)
    }

    @Test func growingKeepsExistingStepsAndAddsBlankOnes() {
        let state = makeState()
        state.steps[5].degree = .V
        state.setBars(4)
        #expect(state.steps.count == 64)
        #expect(state.steps[5].degree == .V)
        #expect(state.steps[40].degree == .I)
    }

    @Test func shrinkingClampsPageSelectionAndPlayhead() {
        let state = makeState()
        state.setBars(4)
        state.currentPage = 3
        state.currentStep = 50
        state.selectedSteps = [2, 20, 50]
        state.primaryStep = 50
        state.setBars(2)
        #expect(state.steps.count == 32)
        #expect(state.currentPage == 1)
        #expect(state.currentStep == -1)
        #expect(state.selectedSteps == [2, 20])
        #expect(state.primaryStep == 2)
    }

    @Test func addBarStepsThroughOptionsAndShowsTheNewBar() {
        let state = makeState()
        state.addBar()
        #expect(state.bars == 2)
        #expect(state.currentPage == 1)
        state.addBar()
        #expect(state.bars == 4)
        #expect(state.currentPage == 3)
        #expect(!state.canAddBar)
        state.addBar()                       // no-op at the maximum
        #expect(state.bars == 4)
    }

    @Test func playedStepsFollowChainMode() {
        let state = makeState()
        state.setBars(2)
        state.steps[20].degree = .V
        #expect(state.playedSteps.count == 32)

        state.chain = false
        state.currentPage = 1
        #expect(state.playedSteps.count == 16)
        #expect(state.playedSteps[4].degree == .V)
    }

    @Test func settingTheSameBarCountIsNotUndoable() {
        let state = makeState()
        state.setBars(1)
        #expect(!state.canUndo)
    }

    @Test func undoRestoresBarCountStepsAndSelection() {
        let state = makeState()
        state.setBars(4)
        state.steps[40].degree = .IV
        state.selectedSteps = [40]
        state.primaryStep = 40
        state.setBars(1)                     // drops bar 3, its step and selection
        state.undo()
        #expect(state.bars == 4)
        #expect(state.steps.count == 64)
        #expect(state.steps[40].degree == .IV)
        #expect(state.selectedSteps == [40])
        #expect(state.primaryStep == 40)
    }

    @Test func clearPatternKeepsThePatternLength() {
        let state = makeState()
        state.setBars(2)
        state.steps[20].degree = .V
        state.clearPattern()
        #expect(state.bars == 2)
        #expect(state.steps.count == 32)
        #expect(state.steps[20].degree == .I)
    }

    @Test func barsChainAndStepsPersist() {
        let defaults = isolatedDefaults()
        let original = SequencerState(defaults: defaults)
        original.setBars(2)
        original.chain = false
        original.steps[20].degree = .vi
        original.steps[20].gate = 0.3
        original.save()

        let reloaded = SequencerState(defaults: defaults)
        #expect(reloaded.bars == 2)
        #expect(!reloaded.chain)
        #expect(reloaded.steps.count == 32)
        #expect(reloaded.steps[20].degree == .vi)
        #expect(reloaded.steps[20].gate == 0.3)
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

    /// Data this build can't read (an unknown color, an unsupported length)
    /// leaves the default pattern instead of being partly interpreted.
    @Test func unreadablePatternsLoadAsEmpty() {
        let defaults = isolatedDefaults()
        let original = SequencerState(defaults: defaults)
        original.steps[0].degree = .V
        original.save()
        let key = "sequencer.pattern.v3"
        let saved = String(decoding: defaults.data(forKey: key)!, as: UTF8.self)

        defaults.set(Data(saved.replacingOccurrences(of: "\"default\"", with: "\"future\"").utf8),
                     forKey: key)
        #expect(SequencerState(defaults: defaults).steps == SequencerState(defaults: isolatedDefaults()).steps)

        defaults.set(Data(saved.replacingOccurrences(of: "\"bars\":1", with: "\"bars\":3").utf8),
                     forKey: key)
        #expect(SequencerState(defaults: defaults).bars == 1)
        #expect(SequencerState(defaults: defaults).steps[0].degree == .I)
    }
}
