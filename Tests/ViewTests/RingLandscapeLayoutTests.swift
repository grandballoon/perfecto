import CoreGraphics
import Testing
@testable import Perfecto

/// The circle layout on its side: a compass a third smaller in the bottom
/// leading corner, and the column with the ring against the trailing edge.
@Suite("RingLandscapeLayout")
struct RingLandscapeLayoutTests {

    /// About a phone on its side.
    private let size = CGSize(width: 760, height: 390)

    @Test func theCompassHasAThirdLessArea() {
        let compass = RingLandscapeLayout(size: size).compass
        let full = (size.width / 2 - 2 * RingLandscapeLayout.margin)
            * (size.height - 2 * RingLandscapeLayout.margin)
        #expect(abs(compass.width * compass.height - full * 2 / 3) < 0.001)
    }

    @Test func theCompassIsInTheBottomLeadingCorner() {
        let compass = RingLandscapeLayout(size: size).compass
        #expect(compass.minX == RingLandscapeLayout.edgeMargin)
        #expect(abs(compass.maxY - (size.height - RingLandscapeLayout.edgeMargin)) < 0.001)
    }

    @Test func theCompassIsClearOfTheMenuButton() {
        let compass = RingLandscapeLayout(size: size).compass
        #expect(compass.minY > SidePanelLayout.buttonTop + SidePanelLayout.buttonSize)
    }

    @Test func theColumnIsAgainstTheTrailingEdge() {
        let column = RingLandscapeLayout(size: size).column
        #expect(column.maxX == size.width - RingLandscapeLayout.edgeMargin)
        #expect(column.maxY == size.height - RingLandscapeLayout.edgeMargin)
        #expect(column.minX > RingLandscapeLayout(size: size).compass.maxX)
    }

    @Test func noSizeLeavesNoNegativeFrames() {
        let layout = RingLandscapeLayout(size: .zero)
        #expect(layout.compass.width == 0 && layout.compass.height == 0)
        #expect(layout.column.width == 0 && layout.column.height == 0)
    }
}
