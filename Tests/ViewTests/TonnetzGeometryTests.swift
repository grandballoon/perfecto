import CoreGraphics
import Testing
@testable import Perfecto

/// Where the Tonnetz's triangles are drawn, and which one a point is in.
@Suite("Tonnetz geometry")
struct TonnetzGeometryTests {

    private let size = CGSize(width: 1040, height: 820)

    private func net(center: TonnetzCell = .home, edge: CGFloat = 104) -> TonnetzNet {
        TonnetzNet(size: size, center: center, edge: edge)
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
    }

    private static let centers = [
        TonnetzCell.home,
        TonnetzCell(corner: TonnetzPoint(fifths: 5, thirds: -3), pointsUp: false),
        TonnetzCell(corner: TonnetzPoint(fifths: -2, thirds: 4), pointsUp: true),
    ]

    @Test(arguments: centers)
    func theCentreTriangleIsInTheMiddle(_ center: TonnetzCell) {
        let middle = net(center: center).middle(of: center)
        #expect(abs(middle.x - size.width / 2) < 0.001)
        #expect(abs(middle.y - size.height / 2) < 0.001)
    }

    @Test func everySideOfATriangleIsAsLongAsTheNetsEdge() {
        let net = net()
        for cell in net.cells {
            let corners = net.corners(of: cell)
            for (a, b) in [(0, 1), (1, 2), (2, 0)] {
                #expect(abs(distance(corners[a], corners[b]) - 104) < 0.001)
            }
        }
    }

    @Test func aMajorTrianglePointsUpAndAMinorOneDown() {
        let net = net()
        let major = net.corners(of: .home)                       // C, E, G
        #expect(major[1].y < major[0].y && major[0].y == major[2].y)
        #expect(major[0].x < major[2].x)                         // the fifth to the right
        let minor = net.corners(of: TonnetzCell.home.flipped(.parallel))   // C, E♭, G
        #expect(minor[1].y > minor[0].y && minor[0].y == minor[2].y)
    }

    /// Drawing and touch agree: the point in the middle of a triangle is in it.
    @Test(arguments: centers, [56, 104, 168] as [CGFloat])
    func aPointInsideATriangleIsReadAsIt(_ center: TonnetzCell, edge: CGFloat) {
        let net = net(center: center, edge: edge)
        for cell in net.cells {
            #expect(net.cell(at: net.middle(of: cell)) == cell)
            // And just inside each corner.
            let middle = net.middle(of: cell)
            for corner in net.corners(of: cell) {
                let inside = CGPoint(x: corner.x + (middle.x - corner.x) * 0.05,
                                     y: corner.y + (middle.y - corner.y) * 0.05)
                #expect(net.cell(at: inside) == cell)
            }
        }
    }

    @Test(arguments: centers, [56, 104, 168] as [CGFloat])
    func theTrianglesDrawnCoverTheWholeView(_ center: TonnetzCell, edge: CGFloat) {
        let net = net(center: center, edge: edge)
        let cells = Set(net.cells)
        #expect(cells.count == net.cells.count)
        for x in stride(from: 0, through: size.width, by: 13) {
            for y in stride(from: 0, through: size.height, by: 13) {
                #expect(cells.contains(net.cell(at: CGPoint(x: x, y: y))))
            }
        }
        #expect(Set(net.points) == Set(cells.flatMap(\.points)))
    }

    /// A pointer on a note's disc is on the note, and anywhere else in a
    /// triangle on the triangle.
    @Test(arguments: [56, 104, 168] as [CGFloat])
    func aNotesDiscIsTheNoteAndTheRestOfATriangleIsTheTriangle(_ edge: CGFloat) {
        let net = net(edge: edge)
        let radius = net.noteDiameter / 2
        for cell in net.cells {
            let middle = net.middle(of: cell)
            #expect(net.target(at: middle, noteDiameter: net.noteDiameter) == .cell(cell))
            for (point, corner) in zip(cell.points, net.corners(of: cell)) {
                let toMiddle = distance(corner, middle)
                func along(_ points: CGFloat) -> CGPoint {
                    CGPoint(x: corner.x + (middle.x - corner.x) * points / toMiddle,
                            y: corner.y + (middle.y - corner.y) * points / toMiddle)
                }
                #expect(net.target(at: along(radius - 1), noteDiameter: net.noteDiameter) == .note(point.pitchClass))
                #expect(net.target(at: along(radius + 1), noteDiameter: net.noteDiameter) == .cell(cell))
            }
        }
    }

    @Test func aNetWithNoRoomHasNoTriangles() {
        #expect(TonnetzNet(size: .zero, center: .home, edge: 104).cells.isEmpty)
    }

    /// The triad view: a triangle and the three it can be flipped into, all
    /// in view whichever way the triangle points.
    @Test(arguments: [CGSize(width: 1040, height: 820), CGSize(width: 600, height: 900)],
          [TonnetzCell.home, TonnetzCell.home.flipped(.parallel)])
    func oneTriadAndItsMovesFitTheView(_ size: CGSize, cell: TonnetzCell) {
        let net = TonnetzNet.around(cell, in: size)
        let bounds = CGRect(origin: .zero, size: size)
        #expect(net.edge > 100)
        for shown in [cell] + TonnetzMove.allCases.map(cell.flipped) {
            for corner in net.corners(of: shown) {
                // With room left for the note drawn on the corner.
                #expect(bounds.insetBy(dx: net.triadNoteDiameter / 2, dy: net.triadNoteDiameter / 2)
                    .contains(corner))
            }
        }
        let middle = net.middle(of: cell)
        #expect(abs(middle.x - size.width / 2) < 0.001 && abs(middle.y - size.height / 2) < 0.001)
    }
}
