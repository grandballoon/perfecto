import CoreGraphics
import Testing
@testable import Perfecto

/// The compass is drawn and read by the same frames: a point in a cell is
/// read back as what is there, and a gap or a corner is nothing, so a
/// finger sliding across one stays where it was.
@Suite("StepCompassGrid")
struct StepCompassGridTests {

    private let size = CGSize(width: 260, height: 200)

    private func center(of target: StepCompassGrid.Target) -> CGPoint {
        let cell = target.cell
        let frame = StepCompassGrid.frame(column: cell.column, row: cell.row, in: size)
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    @Test func everyCellsMiddleReadsBackAsItself() {
        for target in [StepCompassGrid.Target.middle] + CompassPlace.all.map({ .place($0) }) {
            #expect(StepCompassGrid.target(at: center(of: target), in: size) == target)
        }
    }

    @Test func upIsAddingAndOutIsTheSecondChoice() {
        let top = CGPoint(x: size.width / 2, y: 1)
        #expect(StepCompassGrid.target(at: top, in: size) == .place(CompassPlace(.add, 2)))
        let right = CGPoint(x: size.width - 1, y: size.height / 2)
        #expect(StepCompassGrid.target(at: right, in: size) == .place(CompassPlace(.raise, 2)))
    }

    @Test func aCornerAndAGapAreNothing() {
        #expect(StepCompassGrid.target(at: CGPoint(x: 1, y: 1), in: size) == nil)
        let middle = StepCompassGrid.frame(column: 2, row: 2, in: size)
        let gap = CGPoint(x: middle.maxX + StepCompassGrid.spacing / 2, y: middle.midY)
        #expect(StepCompassGrid.target(at: gap, in: size) == nil)
        #expect(StepCompassGrid.target(at: CGPoint(x: -5, y: size.height / 2), in: size) == nil)
    }

    /// A corner is the two cells by two the cross leaves empty, so nothing
    /// in it is a place.
    @Test func aCornerIsTheFourCellsTheCrossLeaves() {
        let topLeading = StepCompassGrid.frame(of: .topLeading, in: size)
        #expect(topLeading == StepCompassGrid.frame(column: 0, row: 0, in: size)
            .union(StepCompassGrid.frame(column: 1, row: 1, in: size)))
        let bottomTrailing = StepCompassGrid.frame(of: .bottomTrailing, in: size)
        #expect(bottomTrailing.maxX == size.width)
        #expect(bottomTrailing.maxY == size.height)
        for corner in StepCompassGrid.Corner.allCases {
            let frame = StepCompassGrid.frame(of: corner, in: size)
            #expect(StepCompassGrid.target(at: CGPoint(x: frame.midX, y: frame.midY), in: size) == nil)
        }
    }
}
