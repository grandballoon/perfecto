import CoreGraphics
import Testing
@testable import Perfecto

/// Touch → step mapping for the sequencer grid. With a 318pt-wide column the
/// cells are 75pt wide on an 81pt pitch; rows are 45pt on a 51pt pitch.
@Suite("StepGridGeometry")
@MainActor
struct StepGridGeometryTests {

    /// The paged layout: one bar, no header.
    private let page = StepGridGeometry(width: 318, cellHeight: 45)
    /// The scroll layout: bars under 26pt headers, 10pt apart (a 234pt pitch).
    private let column = StepGridGeometry(width: 318, cellHeight: 45,
                                          headerHeight: 26, barGap: 10)

    @Test func cellsDivideTheWidthBetweenTheGutters() {
        #expect(page.cellWidth == 75)
        #expect(page.barHeight == 198)
        #expect(column.barHeight == 224)
    }

    @Test func pointsInsideCellsMapToThoseCells() {
        #expect(page.step(nearest: CGPoint(x: 10, y: 10), bars: 1) == 0)
        #expect(page.step(nearest: CGPoint(x: 310, y: 10), bars: 1) == 3)
        #expect(page.step(nearest: CGPoint(x: 100, y: 60), bars: 1) == 5)
        #expect(page.step(nearest: CGPoint(x: 310, y: 190), bars: 1) == 15)
    }

    @Test func pointsOutsideTheGridClampToTheNearestCell() {
        #expect(page.step(nearest: CGPoint(x: -40, y: -40), bars: 1) == 0)
        #expect(page.step(nearest: CGPoint(x: 900, y: 900), bars: 1) == 15)
        #expect(page.step(nearest: CGPoint(x: 100, y: 900), bars: 1) == 13)
    }

    @Test func barsStackUnderTheirHeaders() {
        // First row of bar 0 starts below its header.
        #expect(column.step(nearest: CGPoint(x: 10, y: 30), bars: 3) == 0)
        // Bar 1 starts at y = 234; its second row at 234 + 26 + 51.
        #expect(column.step(nearest: CGPoint(x: 10, y: 270), bars: 3) == 16)
        #expect(column.step(nearest: CGPoint(x: 100, y: 315), bars: 3) == 21)
        // Last cell of bar 2.
        #expect(column.step(nearest: CGPoint(x: 310, y: 2 * 234 + 220), bars: 3) == 47)
    }

    @Test func headersAndGapsResolveToANeighbouringRow() {
        // In bar 1's header: its first row.
        #expect(column.step(nearest: CGPoint(x: 10, y: 240), bars: 3) == 16)
        // In the gap under bar 0: bar 0's last row.
        #expect(column.step(nearest: CGPoint(x: 10, y: 228), bars: 3) == 12)
        // Below the last bar (the "add bar" row): the last bar's last row.
        #expect(column.step(nearest: CGPoint(x: 10, y: 5000), bars: 3) == 44)
    }

    /// Taps act only on rows of cells, so the controls in headers and below
    /// the bars keep their own taps.
    @Test func tapsLandOnlyOnRowsOfCells() {
        #expect(column.step(at: CGPoint(x: 100, y: 315), bars: 3) == 21)
        #expect(column.step(at: CGPoint(x: 300, y: 10), bars: 3) == nil)     // bar 0's header
        #expect(column.step(at: CGPoint(x: 300, y: 240), bars: 3) == nil)    // bar 1's header
        #expect(column.step(at: CGPoint(x: 10, y: 228), bars: 3) == nil)     // gap under bar 0
        #expect(column.step(at: CGPoint(x: 10, y: 3 * 234 + 20), bars: 3) == nil)  // "add bar" row
        #expect(column.step(at: CGPoint(x: -5, y: 60), bars: 3) == nil)
    }

    /// A sweep's rectangle is taken between global indices, so one that
    /// crosses a bar boundary selects the rows on both sides of it.
    @Test func aSweepAcrossBarsSelectsTheRowsBetween() {
        let from = column.step(nearest: CGPoint(x: 10, y: 190), bars: 2)    // bar 0, last row
        let to = column.step(nearest: CGPoint(x: 100, y: 270), bars: 2)     // bar 1, first row
        #expect(SequencerState.rectangle(from: from, to: to) == [12, 13, 16, 17])
    }
}
