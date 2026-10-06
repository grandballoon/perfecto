import Testing
@testable import Perfecto

/// How steps are arranged in rows and bars, and how a layer's notes are cut
/// into the chits the grid draws.
@Suite("StepGridShape")
struct StepGridShapeTests {

    private let common = StepGridShape()
    private let sevenEight = StepGridShape(TimeSignature(beats: 7, unit: .eighth))
    private let sixEight = StepGridShape(TimeSignature(beats: 6, unit: .eighth))
    private let I = ChordSpec(degree: .I, color: .base)

    private func note(step: Int, steps: Int = 1) -> TimelineNote {
        TimelineNote(start: step * 120, length: steps * 120, chord: I)
    }

    @Test func aBarIsRowsOfABeat() {
        #expect(common.rowsPerBar == 4 && common.columns == 4)
        #expect(sixEight.rowsPerBar == 2 && sixEight.columns == 6)
        #expect(sevenEight.rowsPerBar == 4)
        #expect((0..<4).map(sevenEight.columns(inRow:)) == [4, 4, 4, 2])
    }

    /// Every step has a cell and every cell gives back its step, in every
    /// signature offered.
    @Test func stepsAndCellsAgree() {
        for signature in TimeSignature.offered {
            let shape = StepGridShape(signature)
            for step in 0..<3 * shape.stepsPerBar {
                let cell = shape.cell(of: step)
                #expect(shape.step(row: cell.row, column: cell.column) == step, "\(signature.label) step \(step)")
                #expect(cell.column < shape.columns(inRow: cell.row % shape.rowsPerBar))
            }
        }
    }

    @Test func aShortRowEndsBeforeTheOthers() {
        // 7/8: steps 12 and 13 are the last row; the next bar starts on a new row.
        #expect(sevenEight.cell(of: 13) == (3, 1))
        #expect(sevenEight.cell(of: 14) == (4, 0))
        // A touch past the end of the short row is on its last step.
        #expect(sevenEight.step(row: 3, column: 3) == 13)
    }

    @Test func aSweepOverAShortRowTakesOnlyTheStepsThatAreThere() {
        // From step 10 (row 2, column 2) to step 17 (row 4, column 3).
        #expect(sevenEight.rectangle(from: 10, to: 17) == [10, 11, 16, 17])
        // Down the first columns, across the bar line.
        #expect(sevenEight.rectangle(from: 8, to: 15) == [8, 9, 12, 13, 14, 15])
    }

    @Test func aRunOfStepsIsCutWhereRowsEnd() {
        #expect(common.rows(of: 2..<3) == [2..<3])
        #expect(common.rows(of: 2..<9) == [2..<4, 4..<8, 8..<9])
        #expect(sevenEight.rows(of: 11..<16) == [11..<12, 12..<14, 14..<16])
    }

    // MARK: – Chits

    @Test func aNoteIsOneChitAsWideAsItsSteps() {
        let chits = Layer(notes: [note(step: 1, steps: 2), note(step: 3)]).chits(in: common, stepCount: 16)
        #expect(chits.map(\.steps) == [1..<3, 3..<4])
        #expect(chits.allSatisfy { $0.isHead && $0.isTail })
    }

    @Test func aNoteHeldPastARowsEndIsAPieceInEachRow() {
        let chits = Layer(notes: [note(step: 2, steps: 8)]).chits(in: common, stepCount: 16)
        #expect(chits.map(\.steps) == [2..<4, 4..<8, 8..<10])
        #expect(chits.map(\.isHead) == [true, false, false])
        #expect(chits.map(\.isTail) == [false, false, true])
    }

    @Test func aNotePlayedOffTheGridIsDrawnOnItsNearestStepAndMarked() {
        let loose = TimelineNote(start: 110, length: 250, chord: I)      // 110...360
        let chits = Layer(notes: [loose, note(step: 4)]).chits(in: common, stepCount: 16)
        #expect(chits.map(\.steps) == [1..<3, 4..<5])
        #expect(chits.map(\.isOffGrid) == [true, false])
    }

    /// Played just before the loop comes round, a note is nearest a line
    /// past the last step. It is drawn on the last step, not lost.
    @Test func aNoteNearestTheEndIsDrawnOnTheLastStep() {
        let last = TimelineNote(start: 1900, length: 20, chord: I)
        #expect(last.step == 16)
        let chits = Layer(notes: [last]).chits(in: common, stepCount: 16)
        #expect(chits.map(\.steps) == [15..<16])
    }

    @Test func aNoteHeldToTheEndStopsAtTheLastStep() {
        let chits = Layer(notes: [note(step: 14, steps: 2)]).chits(in: common, stepCount: 16)
        #expect(chits.map(\.steps) == [14..<16])
    }
}
