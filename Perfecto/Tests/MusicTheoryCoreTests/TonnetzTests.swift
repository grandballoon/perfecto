import Testing
@testable import MusicTheoryCore

@Suite("Tonnetz")
struct TonnetzTests {

    private func major(_ root: PitchClass) -> Triad { Triad(root: root, quality: .major) }
    private func minor(_ root: PitchClass) -> Triad { Triad(root: root, quality: .minor) }

    private static let triads: [Triad] = PitchClass.allCases.flatMap {
        [Triad(root: $0, quality: .major), Triad(root: $0, quality: .minor)]
    }

    /// Triangles around the origin, far enough out to cross the net's seams.
    private static let cells: [TonnetzCell] = (-7...7).flatMap { fifths in
        (-4...4).flatMap { thirds in
            [true, false].map {
                TonnetzCell(corner: TonnetzPoint(fifths: fifths, thirds: thirds), pointsUp: $0)
            }
        }
    }

    // MARK: – Notes played from the net

    @Test(arguments: triads)
    func threeNotesThatMakeATriadAreReadAsIt(_ triad: Triad) {
        #expect(Triad(Set(triad.pitchClasses)) == triad)
    }

    @Test func notesThatMakeNoTriadAreNone() {
        #expect(Triad([.C, .G, .D]) == nil)
        #expect(Triad([.C, .E]) == nil)
        #expect(Triad([.C, .E, .G, .B]) == nil)
        #expect(Triad([.C, .E, .Gs]) == nil)
    }

    @Test func notesFromTheNetAreNamedAsTheirTriadOrThemselves() {
        #expect(netLabel(of: [60, 64, 67]) == "C")
        // However it is voiced.
        #expect(netLabel(of: [60, 64, 69]) == "Am")
        #expect(netLabel(of: [59, 64, 67]) == "Em")
        #expect(netLabel(of: [71]) == "B")
        #expect(netLabel(of: [67, 60, 62]) == "C D G")
        #expect(netLabel(of: [60, 72, 67]) == "C G")
        #expect(netLabel(of: []) == "")
    }

    // MARK: – Triads

    @Test func aTriadIsItsRootThirdAndFifth() {
        #expect(major(.C).pitchClasses == [.C, .E, .G])
        #expect(minor(.A).pitchClasses == [.A, .C, .E])
        #expect(major(.B).pitchClasses == [.B, .Ds, .Fs])
        #expect(major(.C).name == "C")
        #expect(minor(.Fs).name == "F#m")
    }

    @Test func theMovesAreTheNeoRiemannianOnes() {
        #expect(major(.C).applying(.parallel) == minor(.C))
        #expect(major(.C).applying(.relative) == minor(.A))
        #expect(major(.C).applying(.leading) == minor(.E))
        #expect(minor(.A).applying(.parallel) == major(.A))
        #expect(minor(.A).applying(.relative) == major(.C))
        #expect(minor(.A).applying(.leading) == major(.F))
    }

    @Test func everyMoveKeepsTwoNotesAndIsItsOwnInverse() {
        for triad in Self.triads {
            for move in TonnetzMove.allCases {
                let next = triad.applying(move)
                #expect(next.quality != triad.quality)
                #expect(Set(next.pitchClasses).intersection(triad.pitchClasses).count == 2)
                #expect(next.applying(move) == triad)
            }
        }
    }

    // MARK: – The net

    @Test func aStepAlongALineIsAFifthOrAMajorThird() {
        let origin = TonnetzPoint(fifths: 0, thirds: 0)
        #expect(origin.pitchClass == .C)
        #expect(TonnetzPoint(fifths: 1, thirds: 0).pitchClass == .G)
        #expect(TonnetzPoint(fifths: 0, thirds: 1).pitchClass == .E)
        #expect(TonnetzPoint(fifths: -1, thirds: 0).pitchClass == .F)
        // The third line, a fifth along and a major third back: a minor third.
        #expect(TonnetzPoint(fifths: 1, thirds: -1).pitchClass == .Ds)
    }

    @Test func theTrianglesAtTheOriginAreCMajorAndEMinor() {
        #expect(TonnetzCell.home.triad == major(.C))
        #expect(TonnetzCell(corner: TonnetzCell.home.corner, pointsUp: false).triad == minor(.E))
    }

    @Test func aTrianglesCornersAreItsTriadsNotes() {
        for cell in Self.cells {
            #expect(cell.points.map(\.pitchClass) == cell.triad.pitchClasses)
            #expect(Set(cell.points).count == 3)
        }
    }

    /// The rule the two views rest on: flipping a triangle over a side is
    /// the move on its triad, wherever on the net the triangle is.
    @Test func flippingATriangleIsTheMoveOnItsTriad() {
        for cell in Self.cells {
            for move in TonnetzMove.allCases {
                let flipped = cell.flipped(move)
                #expect(flipped.triad == cell.triad.applying(move))
                #expect(flipped.pointsUp != cell.pointsUp)
                // The side flipped over is the two notes kept, in place.
                let kept = cell.kept(by: move)
                #expect(kept.count == 2)
                #expect(Set(flipped.points).intersection(cell.points) == Set(kept))
                #expect(flipped.kept(by: move).sorted(by: Self.inOrder) == kept.sorted(by: Self.inOrder))
                #expect(flipped.flipped(move) == cell)
            }
        }
    }

    @Test func theThreeMovesFlipOverTheThreeSides() {
        for cell in Self.cells {
            let sides = TonnetzMove.allCases.map { Set(cell.kept(by: $0)) }
            #expect(Set(sides).count == 3)
            #expect(Set(TonnetzMove.allCases.map { cell.flipped($0) }).count == 3)
        }
    }

    private static func inOrder(_ a: TonnetzPoint, _ b: TonnetzPoint) -> Bool {
        (a.fifths, a.thirds) < (b.fifths, b.thirds)
    }
}
