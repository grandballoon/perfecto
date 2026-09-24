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

    // MARK: – Tap toggling

    @Test func tapSelectsStep() {
        let state = emptySelection()
        state.toggleStepSelection(5)
        #expect(state.selectedSteps == [5])
        #expect(state.primaryStep == 5)
    }

    @Test func tapOnSelectedStepDeselectsIt() {
        let state = emptySelection()
        state.toggleStepSelection(5)
        state.toggleStepSelection(5)
        #expect(state.selectedSteps.isEmpty)
        #expect(state.primaryStep == nil)
    }

    @Test func multipleTapsAccumulateSelection() {
        let state = emptySelection()
        state.toggleStepSelection(1)
        state.toggleStepSelection(9)
        state.toggleStepSelection(14)
        #expect(state.selectedSteps == [1, 9, 14])
        #expect(state.primaryStep == 14)
    }

    @Test func deselectingPrimaryFallsBackToAnotherSelectedStep() {
        let state = emptySelection()
        state.toggleStepSelection(3)
        state.toggleStepSelection(7)
        state.toggleStepSelection(7)   // deselect the current primary
        #expect(state.selectedSteps == [3])
        #expect(state.primaryStep == 3)
    }

    @Test func deselectAllEmptiesSelectionAndPrimary() {
        let state = emptySelection()
        state.toggleStepSelection(2)
        state.toggleStepSelection(11)
        state.deselectAll()
        #expect(state.selectedSteps.isEmpty)
        #expect(state.primaryStep == nil)
    }

    // MARK: – Drag sweeps

    @Test func sweepAddsToExistingSelection() {
        let state = emptySelection()
        state.toggleStepSelection(12)
        state.addToSelection([0, 1, 2], primary: 2)
        #expect(state.selectedSteps == [0, 1, 2, 12])
        #expect(state.primaryStep == 2)
    }

    @Test func sweepOverSelectedStepDoesNotDeselectIt() {
        let state = emptySelection()
        state.toggleStepSelection(1)
        state.addToSelection([0, 1, 2], primary: 2)
        #expect(state.selectedSteps.contains(1))
    }

    // MARK: – Undo

    @Test func undoRevertsTapSelection() {
        let state = emptySelection()
        state.toggleStepSelection(5)
        state.undo()
        #expect(state.selectedSteps.isEmpty)
        #expect(state.primaryStep == nil)
    }

    @Test func undoRevertsTapDeselection() {
        let state = emptySelection()
        state.toggleStepSelection(5)
        state.toggleStepSelection(5)
        state.undo()
        #expect(state.selectedSteps == [5])
        #expect(state.primaryStep == 5)
    }

    @Test func undoRevertsSweep() {
        let state = emptySelection()
        state.toggleStepSelection(12)
        state.addToSelection([0, 1, 2], primary: 2)
        state.undo()
        #expect(state.selectedSteps == [12])
        #expect(state.primaryStep == 12)
    }

    @Test func undoRevertsDeselectAll() {
        let state = emptySelection()
        state.toggleStepSelection(3)
        state.toggleStepSelection(9)
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

    @Test func redundantSweepIsNotUndoable() {
        let state = emptySelection()
        state.toggleStepSelection(2)
        state.addToSelection([2], primary: 2)   // no-op: already selected, same primary
        state.undo()   // reverts the tap, since the sweep pushed nothing
        #expect(state.selectedSteps.isEmpty)
        #expect(!state.canUndo)
    }

    @Test func editSelectedStepsAppliesToEveryStepAcrossBars() {
        let state = emptySelection()
        state.setBars(2)
        state.toggleStepSelection(3)
        state.toggleStepSelection(20)   // on the second bar
        state.editSelectedSteps { $0.degree = .vi }
        #expect(state.steps[3].degree == .vi)
        #expect(state.steps[20].degree == .vi)
        #expect(state.steps[4].degree == .I)
    }

    @Test func clearPatternIsOneUndoStep() {
        let state = emptySelection()
        state.toggleStepSelection(4)
        state.steps[4].degree = .V
        state.clearPattern()
        #expect(state.selectedSteps.isEmpty)
        #expect(state.steps[4].degree == .I)
        state.undo()
        #expect(state.selectedSteps == [4])
        #expect(state.primaryStep == 4)
        #expect(state.steps[4].degree == .V)
    }

    @Test func undoRestoresStepsAndSelectionTogether() {
        let state = emptySelection()
        state.toggleStepSelection(7)
        state.snapshot()   // as the step editor does before a chord edit
        state.steps[7].degree = .IV
        state.undo()
        #expect(state.steps[7].degree == .I)
        #expect(state.selectedSteps == [7])
        #expect(state.primaryStep == 7)
    }

    // MARK: – Rectangle geometry (4-column grid)

    @Test func rectangleAcrossRowSelectsRowRun() {
        #expect(SequencerState.rectangle(from: 4, to: 7) == [4, 5, 6, 7])
    }

    @Test func rectangleDownColumnSelectsColumnRun() {
        #expect(SequencerState.rectangle(from: 1, to: 13) == [1, 5, 9, 13])
    }

    @Test func rectangleDiagonalSelectsFullBlock() {
        #expect(SequencerState.rectangle(from: 0, to: 10) == [0, 1, 2, 4, 5, 6, 8, 9, 10])
    }

    @Test func rectangleIsCornerOrderIndependent() {
        #expect(SequencerState.rectangle(from: 10, to: 0) ==
                SequencerState.rectangle(from: 0, to: 10))
    }

    @Test func rectangleOfSingleCellIsThatCell() {
        #expect(SequencerState.rectangle(from: 6, to: 6) == [6])
    }
}
