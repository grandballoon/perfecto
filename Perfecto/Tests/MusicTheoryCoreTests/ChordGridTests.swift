import Testing
@testable import MusicTheoryCore

@Suite("ChordGrid")
struct ChordGridTests {

    private let cMajor = Key(root: .C, scale: .major)

    @Test func rowsAreAWindowAroundTheDegreesOwnMode() {
        #expect(ChordGrid.rows(key: cMajor, degree: .I) == HeptatonicMode.rows(around: .ionian, count: 7))
        #expect(ChordGrid.rows(key: cMajor, degree: .ii).contains(.dorian))
    }

    @Test func ownRowIsDiatonicAndOtherRowsNameTheirMode() {
        let rows = ChordGrid.rows(key: cMajor, degree: .V)
        let own = rows.firstIndex(of: .mixolydian)!
        #expect(ChordGrid.color(at: GridPosition(height: .seventh, row: own), key: cMajor, degree: .V)
                == .grid(.seventh, nil))
        let other = own == 0 ? 1 : own - 1
        #expect(ChordGrid.color(at: GridPosition(height: .ninth, row: other), key: cMajor, degree: .V)
                == .grid(.ninth, rows[other]))
    }

    @Test func samePositionResolvesPerDegree() {
        // The middle row is each degree's own mode; the top row is three
        // modes brighter, which differs by degree.
        let middle = GridPosition(height: .seventh, row: 3)
        #expect(ChordGrid.color(at: middle, key: cMajor, degree: .vi) == .grid(.seventh, nil))
        let top = GridPosition(height: .seventh, row: 0)
        #expect(ChordGrid.color(at: top, key: cMajor, degree: .ii) == .grid(.seventh, .mixolydian))
        #expect(ChordGrid.color(at: top, key: cMajor, degree: .vi) == .grid(.seventh, .dorian))
    }

    @Test func positionIsTheInverseOfColor() {
        for scale in ScaleType.allCases where scale.isHeptatonic {
            let key = Key(root: .E, scale: scale)
            for degree in Degree.allCases {
                for height in StackHeight.allCases {
                    for row in 0..<ChordGrid.rowCount {
                        let position = GridPosition(height: height, row: row)
                        let color = ChordGrid.color(at: position, key: key, degree: degree)
                        #expect(ChordGrid.position(of: color, key: key, degree: degree) == position,
                                "\(scale) \(degree) \(height) row \(row)")
                    }
                }
            }
        }
    }

    @Test func colorsOffTheGridHaveNoPosition() {
        #expect(ChordGrid.position(of: .joystick(.default, .right), key: cMajor, degree: .I) == nil)
        #expect(ChordGrid.position(of: .grid(.triad, .ultralocrian), key: cMajor, degree: .I) == nil)
    }

    @Test func baseGridColorSoundsTheDiatonicTriad() {
        for degree in Degree.allCases {
            let grid = computeVoicing(key: cMajor, spec: ChordSpec(degree: degree, color: .grid(.triad, nil)),
                                      inversion: .root, octave: 4, voiceLeading: false, previousVoicing: nil)
            let joystick = computeVoicing(key: cMajor, spec: ChordSpec(degree: degree, color: .base),
                                          inversion: .root, octave: 4, voiceLeading: false, previousVoicing: nil)
            #expect(grid == joystick, "\(degree)")
        }
    }
}
