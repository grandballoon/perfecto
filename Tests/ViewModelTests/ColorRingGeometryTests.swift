import CoreGraphics
import Testing
@testable import Perfecto

/// The ring is drawn and read by the same geometry: a point in a cell is
/// read back as that cell, and the hub and the gap are no cell.
@Suite("ColorRingGeometry")
struct ColorRingGeometryTests {

    private let size = CGSize(width: 240, height: 240)

    @Test func everyCellsMiddleReadsBackAsItself() {
        for turn in [0, 2, -3] {
            let geometry = ColorRingGeometry(size: size, turn: turn)
            for sector in ColorRing.modes.indices {
                for height in StackHeight.allCases {
                    let cell = geometry.cell(at: geometry.middle(height: height, sector: sector))
                    #expect(cell?.height == height && cell?.sector == sector)
                }
            }
        }
    }

    @Test func theHubIsNoCell() {
        let geometry = ColorRingGeometry(size: size, turn: 0)
        #expect(geometry.cell(at: geometry.center) == nil)
    }

    @Test func theGapIsAtTheBottomOfARingNotTurned() {
        let geometry = ColorRingGeometry(size: size, turn: 0)
        #expect(geometry.cell(at: geometry.point(radius: geometry.outer - 4, angle: 180)) == nil)
        #expect(geometry.cell(at: geometry.point(radius: geometry.outer - 4, angle: 0))?.sector == ColorRing.topSector)
    }

    @Test func aTurnedRingHasTheTurnedSectorAtTheTop() {
        // The home ring for I in C major puts Ionian (sector 5) at the top.
        let geometry = ColorRingGeometry(size: size, turn: ColorRing.topSector - 5)
        #expect(geometry.cell(at: geometry.point(radius: geometry.outer - 4, angle: 0))?.sector == 5)
    }

    @Test func outsideTheRingIsNoCell() {
        let geometry = ColorRingGeometry(size: size, turn: 0)
        #expect(geometry.cell(at: CGPoint(x: 0, y: 0)) == nil)
    }
}

/// A ring that is not turned is fitted to what it draws: its lowest cells,
/// beside the gap, are on the bottom edge, and its top mode's name is in.
@Suite("ColorRingGeometry fitted")
struct ColorRingGeometryFittedTests {

    @Test func theLowestCellsAreOnTheBottomEdge() {
        let size = CGSize(width: 390, height: 283)
        let geometry = ColorRingGeometry(size: size, turn: 0, fitsGap: true)
        let lowest = geometry.point(radius: geometry.outer, angle: ColorRingGeometry.start)
        #expect(abs(lowest.y - size.height) < 0.5)
        #expect(geometry.center.y - geometry.outer - ColorRingGeometry.labelMargin >= -0.5)
    }

    @Test func aFittedRingIsLargerThanAWholeCircle() {
        let size = CGSize(width: 390, height: 283)
        #expect(ColorRingGeometry(size: size, turn: 0, fitsGap: true).outer
                > ColorRingGeometry(size: size, turn: 0).outer)
    }

    @Test func aWideFrameFitsByHeightAndANarrowOneByWidth() {
        let narrow = ColorRingGeometry(size: CGSize(width: 200, height: 400), turn: 0, fitsGap: true)
        #expect(abs(narrow.outer - (100 - ColorRingGeometry.sideMargin)) < 0.01)
    }

    @Test func everyCellReadsBackOnAFittedRing() {
        let geometry = ColorRingGeometry(size: CGSize(width: 390, height: 283), turn: 0, fitsGap: true)
        for sector in ColorRing.modes.indices {
            for height in StackHeight.allCases {
                let cell = geometry.cell(at: geometry.middle(height: height, sector: sector))
                #expect(cell?.height == height && cell?.sector == sector)
            }
        }
    }
}
