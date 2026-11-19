import CoreGraphics
import Testing
@testable import Perfecto

/// The edge layout's other two color surfaces: the table's qualities are
/// fixed and read back where they are drawn, and the tree's nodes are the
/// compass's places, laid out each kind its way from the root.
@Suite("Color surfaces")
struct ColorSurfaceLayoutTests {

    private let size = CGSize(width: 480, height: 220)
    private let key = Key(root: .C, scale: .major)

    // MARK: – The table

    @Test func theTablesQualitiesAreNamedAsTheAppNamesThem() {
        #expect(ColorTable.rows.map { $0.map(\.name) } == [
            ["maj", "min", "sus2", "sus4", "dim", "aug", "5"],
            ["6", "min6", "add9", "min add9", "6/9", "min6/9"],
            ["maj7", "7", "min7", "min7♭5", "dim7", "min(maj7)", "7sus4"],
            ["maj9", "9", "min9", "7♭9", "7♯9", "add11", "min add11"],
        ])
        #expect(Set(ColorTable.rows.joined()).count == ColorTable.rows.joined().count)
    }

    @Test func everyCellReadsBackAsItself() {
        for target in [ColorTable.Target.plain] + ColorTable.rows.joined().map({ .quality($0) }) {
            let cell = ColorTable.cell(of: target)!
            let frame = ColorTable.frame(column: cell.column, row: cell.row, in: size)
            #expect(ColorTable.target(at: CGPoint(x: frame.midX, y: frame.midY), in: size) == target)
        }
        // The pin, a gap and an empty cell are nothing.
        let pin = ColorTable.frame(column: ColorTable.pinCell.column, row: ColorTable.pinCell.row, in: size)
        #expect(ColorTable.target(at: CGPoint(x: pin.midX, y: pin.midY), in: size) == nil)
        let empty = ColorTable.frame(column: 6, row: 1, in: size)
        #expect(ColorTable.target(at: CGPoint(x: empty.midX, y: empty.midY), in: size) == nil)
        #expect(ColorTable.frame(column: ColorTable.columns - 1, row: ColorTable.rows.count - 1, in: size).maxX
                == size.width)
    }

    @Test func aQualityIsInKeyOnADegreeWhoseScaleHasItsTones() {
        let maj7 = ChordTones([0, 4, 7, 11]), dominant = ChordTones([0, 4, 7, 10])
        #expect(KeyAssistance.isInKey(maj7, key: key, degree: .I))
        #expect(!KeyAssistance.isInKey(maj7, key: key, degree: .V))
        #expect(KeyAssistance.isInKey(dominant, key: key, degree: .V))
    }

    // MARK: – The tree

    @Test func aTriadsTreeHasABranchForEveryPlaceWithAChoice() {
        let triad = StepCompass.base(key: key, degree: .I)
        let nodes = ColorTree.nodes(from: triad, focus: nil, key: key, degree: .I, ranking: .theory)
        #expect(nodes == CompassPlace.all.map { [$0] })
    }

    /// The branch a finger is on fans out a step further, but not to a step
    /// that only undoes it: Csus4 lowered first is C again.
    @Test func theFocusedBranchHasItsChildrenButNotItsUndoing() {
        let triad = StepCompass.base(key: key, degree: .I)
        let raise = CompassPlace(.raise, 1)
        let nodes = ColorTree.nodes(from: triad, focus: raise, key: key, degree: .I, ranking: .theory)
        #expect(Array(nodes.prefix(8)) == CompassPlace.all.map { [$0] })
        let children = Array(nodes.dropFirst(8))
        #expect(children == [[raise, CompassPlace(.add, 1)], [raise, CompassPlace(.raise, 1)],
                             [raise, CompassPlace(.takeAway, 1)]])
        let steps = ColorTree.steps(of: [raise, CompassPlace(.lower, 1)], from: triad, key: key, degree: .I,
                                    ranking: .theory)!
        #expect(steps.map(\.editName) == ["3→4", "4→3"])
    }

    @Test func aBranchGoesItsKindsWayFromTheRoot() {
        let layout = ColorTreeLayout(size: size)
        let root = layout.frame(of: .root)
        let up = layout.frame(of: .node([CompassPlace(.add, 1)]))
        let right = layout.frame(of: .node([CompassPlace(.raise, 2)]))
        let down = layout.frame(of: .node([CompassPlace(.takeAway, 1)]))
        let left = layout.frame(of: .node([CompassPlace(.lower, 1)]))
        #expect(up.midY < root.midY)
        #expect(right.midX > root.midX)
        #expect(down.midY > root.midY)
        #expect(left.midX < root.midX)
        // A kind's first choice is turned back from its way, the second on.
        #expect(layout.frame(of: .node([CompassPlace(.add, 1)])).midX < layout.frame(of: .node([CompassPlace(.add, 2)])).midX)
        // A child is out on the edge, beyond its branch.
        let child = layout.frame(of: .node([CompassPlace(.add, 1), CompassPlace(.raise, 1)]))
        #expect(child.midY < up.midY)
        #expect(CGRect(origin: .zero, size: size).insetBy(dx: -0.001, dy: -0.001).contains(child))
    }

    @Test func aNodeReadsBackAsItselfAndTheLaterDrawnWins() {
        let layout = ColorTreeLayout(size: size)
        let triad = StepCompass.base(key: key, degree: .I)
        let shown = ColorTree.nodes(from: triad, focus: CompassPlace(.raise, 1), key: key, degree: .I,
                                    ranking: .theory)
        for path in shown {
            let frame = layout.frame(of: .node(path))
            let read = layout.target(at: CGPoint(x: frame.midX, y: frame.midY), among: shown)
            #expect(read == .node(path))
        }
        let root = layout.frame(of: .root)
        #expect(layout.target(at: CGPoint(x: root.midX, y: root.midY), among: shown) == .root)
        #expect(layout.target(at: CGPoint(x: 1, y: size.height - 1), among: []) == nil)
    }
}
