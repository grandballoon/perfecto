import CoreGraphics
import Testing
@testable import Perfecto

/// The edge layout's keys are two columns at the sides, the root in a
/// bottom corner and the degrees going round from it; the left hand's is
/// the right hand's in a mirror, and the middle is what the columns leave.
@Suite("EdgeKeyLayout")
struct EdgeKeyLayoutTests {

    /// About a phone on its side, under the top band.
    private let size = CGSize(width: 760, height: 300)

    @Test func theRootIsInTheBottomLeadingCornerForTheRightHand() {
        let layout = EdgeKeyLayout(size: size, handedness: .right)
        let root = layout.keys[.I]!
        #expect(root.minX == 0)
        #expect(root.maxY == size.height)
        // vii° ends the round in the other bottom corner.
        let last = layout.keys[.viiDim]!
        #expect(last.maxX == size.width)
        #expect(last.maxY == size.height)
    }

    @Test func theDegreesGoUpOneSideAndDownTheOther() {
        let layout = EdgeKeyLayout(size: size, handedness: .right)
        let up = EdgeKeyLayout.rootColumn.map { layout.keys[$0]!.minY }
        #expect(up == up.sorted(by: >))
        let down = EdgeKeyLayout.otherColumn.map { layout.keys[$0]!.minY }
        #expect(down == down.sorted())
        #expect(layout.keys[.IV]!.minY == 0)
        #expect(layout.keys[.V]!.minY == 0)
        #expect(Set(layout.keys.keys) == Set(Degree.allCases))
    }

    @Test func eachColumnSharesItsHeight() {
        let layout = EdgeKeyLayout(size: size, handedness: .right)
        let gap = EdgeKeyLayout.keyGap
        #expect(layout.keys[.I]!.height == (size.height - 3 * gap) / 4)
        #expect(layout.keys[.V]!.height == (size.height - 2 * gap) / 3)
        // A column is 15% of the width.
        #expect(abs(layout.keys[.I]!.width - size.width * EdgeKeyLayout.columnShare) < 0.001)
    }

    @Test func theLeftHandsIsTheRightHandsInAMirror() {
        let right = EdgeKeyLayout(size: size, handedness: .right)
        let left = EdgeKeyLayout(size: size, handedness: .left)
        for degree in Degree.allCases {
            let frame = right.keys[degree]!
            #expect(left.keys[degree]! == CGRect(x: size.width - frame.maxX, y: frame.minY,
                                                 width: frame.width, height: frame.height))
        }
        #expect(left.center == right.center)
    }

    @Test func theMiddleIsBetweenTheColumns() {
        let layout = EdgeKeyLayout(size: size, handedness: .right)
        #expect(layout.center.minX == layout.keys[.I]!.maxX + EdgeKeyLayout.centerGap)
        #expect(layout.center.maxX == layout.keys[.V]!.minX - EdgeKeyLayout.centerGap)
        #expect(layout.center.height == size.height)
        for frame in layout.keys.values { #expect(!frame.intersects(layout.center)) }
    }

    /// A column is never narrower than a finger, nor wider than a key needs.
    @Test func aColumnsWidthIsBounded() {
        let wide = EdgeKeyLayout(size: CGSize(width: 2000, height: 900), handedness: .right)
        #expect(wide.keys[.I]!.width == EdgeKeyLayout.columnWidths.upperBound)
        let narrow = EdgeKeyLayout(size: CGSize(width: 500, height: 300), handedness: .right)
        #expect(narrow.keys[.I]!.width == EdgeKeyLayout.columnWidths.lowerBound)
        let tiny = EdgeKeyLayout(size: CGSize(width: 150, height: 20), handedness: .right)
        #expect(tiny.keys[.I]!.width == 50)
        #expect(tiny.center.width == 26)
        #expect(tiny.keys.values.allSatisfy { $0.height >= 0 })
    }
}
