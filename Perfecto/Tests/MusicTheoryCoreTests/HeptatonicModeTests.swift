import Testing
@testable import MusicTheoryCore

@Suite("HeptatonicMode")
struct HeptatonicModeTests {

    @Test func intervalsReadTheParentScaleFromTheModesStep() {
        #expect(HeptatonicMode.lydian.intervals           == [0, 2, 4, 6, 7, 9, 11])
        #expect(HeptatonicMode.lydianDominant.intervals   == [0, 2, 4, 6, 7, 9, 10])
        #expect(HeptatonicMode.altered.intervals          == [0, 1, 3, 4, 6, 8, 10])
        #expect(HeptatonicMode.phrygianDominant.intervals == [0, 1, 4, 5, 7, 8, 10])
        #expect(HeptatonicMode.ultralocrian.intervals     == [0, 1, 3, 4, 6, 8, 9])
    }

    @Test func everyModeIsDistinct() {
        #expect(Set(HeptatonicMode.allCases.map(\.intervals)).count == 21)
    }

    @Test func everyDegreeOfEveryOfferedScaleHasItsMode() {
        for scale in ScaleType.allCases where scale.isHeptatonic {
            for degree in Degree.allCases {
                #expect(HeptatonicMode(key: Key(root: .D, scale: scale), degree: degree) != nil,
                        "\(scale) \(degree)")
            }
        }
        #expect(HeptatonicMode(key: Key(root: .C, scale: .major), degree: .V) == .mixolydian)
        #expect(HeptatonicMode(key: Key(root: .C, scale: .harmonicMinor), degree: .V) == .phrygianDominant)
        #expect(HeptatonicMode(key: Key(root: .C, scale: .blues), degree: .I) == nil)
    }

    // MARK: – Brightness

    @Test func brightnessOrder() {
        #expect(HeptatonicMode.byBrightness == [
            .lydianSharp2, .lydianAugmented, .lydian, .ionianSharp5, .ionian,
            .lydianDominant, .mixolydian, .dorianSharp4, .melodicMinor, .dorian,
            .mixolydianFlat6, .harmonicMinor, .aeolian, .phrygianDominant, .dorianFlat2,
            .phrygian, .locrianNatural2, .locrianNatural6, .locrian, .altered, .ultralocrian,
        ])
    }

    @Test func majorModesKeepTheirFamiliarOrder() {
        let major: [HeptatonicMode] = [.lydian, .ionian, .mixolydian, .dorian, .aeolian, .phrygian, .locrian]
        #expect(HeptatonicMode.byBrightness.filter(major.contains) == major)
    }

    @Test func neighbouringRowsDifferByAtMostTwoNotes() {
        let rows = HeptatonicMode.byBrightness
        for (upper, lower) in zip(rows, rows.dropFirst()) {
            let changed = zip(upper.intervals, lower.intervals).filter { $0 != $1 }.count
            #expect((1...2).contains(changed), "\(upper) → \(lower)")
        }
    }

    @Test func brightnessNeverIncreasesDownTheRows() {
        let sums = HeptatonicMode.byBrightness.map { $0.intervals.reduce(0, +) }
        #expect(sums == sums.sorted(by: >))
    }

    @Test func rowsCentreOnTheModeAndStayInRange() {
        #expect(HeptatonicMode.rows(around: .ionian, count: 7) == [
            .lydianAugmented, .lydian, .ionianSharp5, .ionian, .lydianDominant, .mixolydian, .dorianSharp4,
        ])
        #expect(HeptatonicMode.rows(around: .lydianSharp2, count: 7) == Array(HeptatonicMode.byBrightness.prefix(7)))
        #expect(HeptatonicMode.rows(around: .altered, count: 7) == Array(HeptatonicMode.byBrightness.suffix(7)))
        for mode in HeptatonicMode.allCases {
            let rows = HeptatonicMode.rows(around: mode, count: 7)
            #expect(rows.count == 7 && rows.contains(mode), "\(mode)")
        }
    }
}
