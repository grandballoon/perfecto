import Testing
@testable import MusicTheoryCore

@Suite("ColorRing")
struct ColorRingTests {

    private let cMajor = Key(root: .C, scale: .major)
    private let aMinor = Key(root: .A, scale: .naturalMinor)

    @Test func theSectorsGoFromDarkestToBrightest() {
        #expect(ColorRing.modes == [.locrian, .phrygian, .aeolian, .dorian, .mixolydian, .ionian, .lydian])
        #expect(ColorRing.modes[ColorRing.topSector] == .dorian)
    }

    @Test func eachSectorIsOneNoteFromTheNext() {
        for (a, b) in zip(ColorRing.modes, ColorRing.modes.dropFirst()) {
            #expect(zip(a.intervals, b.intervals).filter { $0 != $1 }.count == 1)
        }
    }

    @Test func aFixedRingIsNeverTurned() {
        for degree in Degree.allCases {
            #expect(ColorRing.turn(.fixed, key: cMajor, degree: degree) == 0)
        }
    }

    @Test func aHomeRingHasTheOwnModeAtTheTop() {
        for key in [cMajor, aMinor] {
            for degree in Degree.allCases {
                let own = ChordGrid.ownMode(key: key, degree: degree)
                let sector = ColorRing.modes.firstIndex(of: own)!
                #expect(sector + ColorRing.turn(.home, key: key, degree: degree) == ColorRing.topSector)
            }
        }
    }

    @Test func aHomeRingIsNotTurnedForAModeOffTheRing() {
        let harmonic = Key(root: .A, scale: .harmonicMinor)
        #expect(ColorRing.turn(.home, key: harmonic, degree: .I) == 0)
    }

    @Test func positionsAndSectorsInvertEachOther() {
        for arrangement in ColorRingArrangement.allCases {
            for key in [cMajor, aMinor] {
                for degree in Degree.allCases {
                    for sector in ColorRing.modes.indices {
                        let position = ColorRing.position(height: .ninth, sector: sector, arrangement: arrangement,
                                                          key: key, degree: degree)
                        #expect(ColorRing.sector(of: position, key: key, degree: degree) == sector)
                    }
                }
            }
        }
    }

    /// The own mode's cell on a home ring follows the degree; on a fixed
    /// ring a sector stays its mode.
    @Test func theHomeRingsOwnCellFollowsTheDegree() {
        let home = ColorRing.position(height: .seventh, sector: 5, arrangement: .home, key: cMajor, degree: .I)
        #expect(home.mode == nil)
        #expect(ColorRing.mode(of: home, key: cMajor, degree: .ii) == .dorian)
        let fixed = ColorRing.position(height: .seventh, sector: 5, arrangement: .fixed, key: cMajor, degree: .I)
        #expect(ColorRing.mode(of: fixed, key: cMajor, degree: .ii) == .ionian)
    }

    @Test func theOwnModesCellPlaysTheGridsOwnColor() {
        let fixed = ColorRingPosition(height: .seventh, mode: .ionian)
        #expect(ColorRing.color(at: fixed, marks: .none, key: cMajor, degree: .I) == .grid(.seventh, nil))
        #expect(ColorRing.color(at: fixed, marks: .none, key: cMajor, degree: .V) == .grid(.seventh, .ionian))
    }
}
