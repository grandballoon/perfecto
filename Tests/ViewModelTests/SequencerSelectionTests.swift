import Foundation
import Testing
@testable import Perfecto

@Suite("SequencerState selection")
@MainActor
struct SequencerSelectionTests {

    // MARK: – Helpers

    /// Returns a state with an empty selection, so each test builds its own.
    private func emptySelection() -> SequencerState {
        let state = SequencerState(defaults: isolatedDefaults())
        state.selectedSteps = []
        state.primaryStep = nil
        return state
    }

    // MARK: – Initial state

    @Test func defaultSelectionIsFirstStep() {
        let state = SequencerState(defaults: isolatedDefaults())
        #expect(state.selectedSteps == [0])
        #expect(state.primaryStep == 0)
    }

    // MARK: – Taps

    /// What a tap on a step does.
    private func tap(_ step: Int, in state: SequencerState) {
        state.select([step], primary: step)
    }

    @Test func tapSelectsStep() {
        let state = emptySelection()
        tap(5, in: state)
        #expect(state.selectedSteps == [5])
        #expect(state.primaryStep == 5)
    }

    @Test func aTapSelectsItsStepAndNoOther() {
        let state = emptySelection()
        tap(1, in: state)
        tap(9, in: state)
        tap(14, in: state)
        #expect(state.selectedSteps == [14])
        #expect(state.primaryStep == 14)
    }

    @Test func aTapOnTheSelectedStepLeavesItSelected() {
        let state = emptySelection()
        tap(5, in: state)
        tap(5, in: state)
        #expect(state.selectedSteps == [5])
        #expect(state.primaryStep == 5)
    }

    @Test func aTapOnOneStepOfASweepSelectsThatStepAlone() {
        let state = emptySelection()
        state.select([0, 1, 2], primary: 2)
        tap(1, in: state)
        #expect(state.selectedSteps == [1])
        #expect(state.primaryStep == 1)
    }

    @Test func deselectAllEmptiesSelectionAndPrimary() {
        let state = emptySelection()
        state.select([2, 11], primary: 11)
        state.deselectAll()
        #expect(state.selectedSteps.isEmpty)
        #expect(state.primaryStep == nil)
    }

    /// Deselecting is a change of what is selected, not of the notes.
    @Test func deselectAllLeavesTheNotesAsTheyWere() {
        let state = emptySelection()
        tap(4, in: state)
        state.editSelectedChords { ChordSpec(degree: .V, color: $0.color) }
        let timeline = state.timeline
        state.deselectAll()
        #expect(state.timeline == timeline)
        #expect(state.steps[4].degree == .V)
    }

    // MARK: – Drag sweeps

    @Test func aSweepSelectsItsStepsAndNoOthers() {
        let state = emptySelection()
        tap(12, in: state)
        state.select([0, 1, 2], primary: 2)
        #expect(state.selectedSteps == [0, 1, 2])
        #expect(state.primaryStep == 2)
    }

    @Test func aSweepOverASelectedStepKeepsIt() {
        let state = emptySelection()
        tap(1, in: state)
        state.select([0, 1, 2], primary: 2)
        #expect(state.selectedSteps == [0, 1, 2])
    }

    // MARK: – Undo

    @Test func undoRevertsTapSelection() {
        let state = emptySelection()
        tap(5, in: state)
        state.undo()
        #expect(state.selectedSteps.isEmpty)
        #expect(state.primaryStep == nil)
    }

    @Test func undoRevertsSweep() {
        let state = emptySelection()
        tap(12, in: state)
        state.select([0, 1, 2], primary: 2)
        state.undo()
        #expect(state.selectedSteps == [12])
        #expect(state.primaryStep == 12)
    }

    @Test func undoRevertsDeselectAll() {
        let state = emptySelection()
        state.select([3, 9], primary: 9)
        state.deselectAll()
        state.undo()
        #expect(state.selectedSteps == [3, 9])
        #expect(state.primaryStep == 9)
    }

    @Test func deselectAllOnEmptySelectionIsNotUndoable() {
        let state = emptySelection()
        state.deselectAll()
        #expect(!state.canUndo)
    }

    @Test func aTapOnTheSelectedStepIsNotUndoable() {
        let state = emptySelection()
        tap(2, in: state)
        tap(2, in: state)   // no-op: already the selection, same primary
        state.undo()   // reverts the first tap, since the second pushed nothing
        #expect(state.selectedSteps.isEmpty)
        #expect(!state.canUndo)
    }

    @Test func aChordEditAppliesToEverySelectedStepAcrossBars() {
        let state = emptySelection()
        state.addBar()
        state.select([3, 20], primary: 20)   // 20 is on the second bar
        state.editSelectedChords { ChordSpec(degree: .vi, color: $0.color) }
        #expect(state.steps[3].degree == .vi)
        #expect(state.steps[20].degree == .vi)
        #expect(state.steps[4].isRest)
    }

    @Test func clearPatternIsOneUndoStep() {
        let state = emptySelection()
        tap(4, in: state)
        state.steps[4] = SequencerStep(degree: .V)
        state.clearPattern()
        #expect(state.selectedSteps.isEmpty)
        #expect(state.steps[4].isRest)
        state.undo()
        #expect(state.selectedSteps == [4])
        #expect(state.primaryStep == 4)
        #expect(state.steps[4].degree == .V)
    }

    @Test func undoRestoresStepsAndSelectionTogether() {
        let state = emptySelection()
        tap(7, in: state)
        state.snapshot()   // as the step editor does before a chord edit
        state.steps[7] = SequencerStep(degree: .IV)
        state.undo()
        #expect(state.steps[7].degree == .I)
        #expect(state.selectedSteps == [7])
        #expect(state.primaryStep == 7)
    }

    // MARK: – Rectangle geometry (4-column grid)

    @Test func rectangleAcrossRowSelectsRowRun() {
        #expect(StepGridShape().rectangle(from: 4, to: 7) == [4, 5, 6, 7])
    }

    @Test func rectangleDownColumnSelectsColumnRun() {
        #expect(StepGridShape().rectangle(from: 1, to: 13) == [1, 5, 9, 13])
    }

    @Test func rectangleDiagonalSelectsFullBlock() {
        #expect(StepGridShape().rectangle(from: 0, to: 10) == [0, 1, 2, 4, 5, 6, 8, 9, 10])
    }

    @Test func rectangleIsCornerOrderIndependent() {
        #expect(StepGridShape().rectangle(from: 10, to: 0) ==
                StepGridShape().rectangle(from: 0, to: 10))
    }

    @Test func rectangleOfSingleCellIsThatCell() {
        #expect(StepGridShape().rectangle(from: 6, to: 6) == [6])
    }
}
