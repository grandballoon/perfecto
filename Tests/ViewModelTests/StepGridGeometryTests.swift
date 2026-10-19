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

    /// A note's chit runs from its first cell to its last, gutters included.
    @Test func aChitSpansItsCells() {
        #expect(page.frame(of: 5..<6) == CGRect(x: 81, y: 51, width: 75, height: 45))
        #expect(page.frame(of: 5..<8) == CGRect(x: 81, y: 51, width: 237, height: 45))
        // The second bar's cells are placed from its own top.
        #expect(page.frame(of: 16..<18) == CGRect(x: 0, y: 0, width: 156, height: 45))
    }

    /// The selection's box is the one around its cells, in its bar.
    @Test func aSelectionIsBoxedByItsCells() {
        #expect(page.bounds(of: [5, 6, 7]) == CGRect(x: 81, y: 51, width: 237, height: 45))
        #expect(page.bounds(of: [5, 10]) == CGRect(x: 81, y: 51, width: 156, height: 96))
        #expect(page.bounds(of: [16, 17]) == CGRect(x: 0, y: 0, width: 156, height: 45))
    }

    /// The tip is over the selection, across its middle, a gutter away.
    @Test func aTipIsOverTheSelection() {
        let tip = page.frame(ofTip: CGSize(width: 60, height: 32), by: page.bounds(of: [5, 6]))
        #expect(tip == CGRect(x: 129, y: 13, width: 60, height: 32))
    }

    /// The top row has nothing of the bar over it, so its tip is under it.
    @Test func aTipIsUnderASelectionInTheTopRow() {
        let tip = page.frame(ofTip: CGSize(width: 60, height: 32), by: page.bounds(of: [1, 2]))
        #expect(tip == CGRect(x: 129, y: 51, width: 60, height: 32))
    }

    /// With every row selected the tip lies on the selection's top edge.
    @Test func aTipLiesOnASelectionOfEveryRow() {
        let tip = page.frame(ofTip: CGSize(width: 60, height: 32), by: page.bounds(of: Set(0..<16)))
        #expect(tip == CGRect(x: 129, y: 6, width: 60, height: 32))
    }

    /// A tip wider than what it is over stays inside the bar.
    @Test func aTipStaysInsideTheBar() {
        let size = CGSize(width: 120, height: 32)
        #expect(page.frame(ofTip: size, by: page.bounds(of: [4])).minX == 0)
        #expect(page.frame(ofTip: size, by: page.bounds(of: [7])).maxX == 318)
    }

    /// A bar's cells start under its header, bar after bar down the column.
    @Test func aBarsCellsStartUnderItsHeader() {
        #expect(page.cellsTop(ofBar: 0) == 0)
        #expect(column.cellsTop(ofBar: 0) == 26)
        #expect(column.cellsTop(ofBar: 2) == 494)  // two bars of 234, and a header
    }

    /// 7/8 is rows of 4, 4, 4 and 2 steps: the bar is four rows high, and a
    /// touch beside the short row lands on its last step.
    @Test func aShortLastRowIsStillARow() {
        let seven = StepGridGeometry(shape: StepGridShape(TimeSignature(beats: 7, unit: .eighth)),
                                     width: 318, cellHeight: 45)
        #expect(seven.barHeight == 198)
        #expect(seven.frame(of: 12..<14) == CGRect(x: 0, y: 153, width: 156, height: 45))
        #expect(seven.step(nearest: CGPoint(x: 310, y: 190), bars: 2) == 13)
        #expect(seven.step(nearest: CGPoint(x: 310, y: 198 + 10), bars: 2) == 17)
    }

    /// Six steps to a row where eighths go in threes.
    @Test func compoundTimeHasSixColumns() {
        let six = StepGridGeometry(shape: StepGridShape(TimeSignature(beats: 6, unit: .eighth)),
                                   width: 318, cellHeight: 45)
        #expect(six.cellWidth == 48)
        #expect(six.barHeight == 96)
        #expect(six.step(nearest: CGPoint(x: 310, y: 60), bars: 1) == 11)
    }

    /// A sweep's rectangle is taken between global indices, so one that
    /// crosses a bar boundary selects the rows on both sides of it.
    @Test func aSweepAcrossBarsSelectsTheRowsBetween() {
        let from = column.step(nearest: CGPoint(x: 10, y: 190), bars: 2)    // bar 0, last row
        let to = column.step(nearest: CGPoint(x: 100, y: 270), bars: 2)     // bar 1, first row
        #expect(column.shape.rectangle(from: from, to: to) == [12, 13, 16, 17])
    }
}
