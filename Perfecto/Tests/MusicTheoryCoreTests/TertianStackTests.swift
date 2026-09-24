import Testing
@testable import MusicTheoryCore

@Suite("TertianStack")
struct TertianStackTests {

    private let cMajor = Key(root: .C, scale: .major)
    private let dorian     = [0, 2, 3, 5, 7, 9, 10]
    private let ionian     = [0, 2, 4, 5, 7, 9, 11]
    private let mixolydian = [0, 2, 4, 5, 7, 9, 10]
    private let lydian     = [0, 2, 4, 6, 7, 9, 11]

    // MARK: – Diatonic modes

    @Test func degreeModesOfCMajor() {
        #expect(diatonicMode(key: cMajor, degree: .I) == ionian)
        #expect(diatonicMode(key: cMajor, degree: .ii) == dorian)
        #expect(diatonicMode(key: cMajor, degree: .V) == mixolydian)
        #expect(diatonicMode(key: cMajor, degree: .IV) == lydian)
    }

    @Test func noModeForScalesWithoutSevenNotes() {
        #expect(diatonicMode(key: Key(root: .C, scale: .blues), degree: .I) == nil)
    }

    // MARK: – Heights

    @Test func eachHeightAddsAThird() {
        #expect(stackThirds(mixolydian, height: .triad)      == [0, 4, 7])
        #expect(stackThirds(mixolydian, height: .seventh)    == [0, 4, 7, 10])
        #expect(stackThirds(mixolydian, height: .ninth)      == [0, 4, 7, 10, 14])
        #expect(stackThirds(dorian,     height: .eleventh)   == [0, 3, 7, 10, 14, 17])
        #expect(stackThirds(dorian,     height: .thirteenth) == [0, 3, 7, 10, 14, 17, 21])
    }

    @Test func diatonicSeventhsOfCMajor() {
        let sevenths = Degree.allCases.map {
            stackThirds(diatonicMode(key: cMajor, degree: $0)!, height: .seventh)
        }
        #expect(sevenths == [
            [0, 4, 7, 11],   // I    maj7
            [0, 3, 7, 10],   // ii   min7
            [0, 3, 7, 10],   // iii  min7
            [0, 4, 7, 11],   // IV   maj7
            [0, 4, 7, 10],   // V    7
            [0, 3, 7, 10],   // vi   min7
            [0, 3, 6, 10],   // vii  min7♭5
        ])
    }

    // MARK: – The eleventh over a major third

    @Test func dominantElevenDropsTheThird() {
        #expect(stackThirds(mixolydian, height: .eleventh) == [0, 7, 10, 14, 17])
    }

    @Test func thirteenthsDropTheElevenOverAMajorThird() {
        #expect(stackThirds(mixolydian, height: .thirteenth) == [0, 4, 7, 10, 14, 21])   // 13
        #expect(stackThirds(ionian,     height: .thirteenth) == [0, 4, 7, 11, 14, 21])   // maj13
    }

    @Test func raisedElevenIsKept() {
        #expect(stackThirds(lydian, height: .eleventh) == [0, 4, 7, 11, 14, 18])         // maj9♯11
    }

    // MARK: – Chords the joystick table gets wrong or can't reach

    @Test func harmonicMinorThirdIsAugmented() {
        // JoystickMap plays E♭–G–B♭ here; B♭ is not in C harmonic minor.
        let mode = diatonicMode(key: Key(root: .C, scale: .harmonicMinor), degree: .iii)!
        #expect(stackThirds(mode, height: .triad) == [0, 4, 8])
    }

    @Test func harmonicMinorSeventhDegreeIsFullyDiminished() {
        let mode = diatonicMode(key: Key(root: .C, scale: .harmonicMinor), degree: .viiDim)!
        #expect(stackThirds(mode, height: .seventh) == [0, 3, 6, 9])
    }

    // MARK: – Structural rules, every heptatonic scale, degree and height

    @Test func stacksAscendAndStayInTheirMode() {
        for scale in ScaleType.allCases where scale.isHeptatonic {
            for degree in Degree.allCases {
                let mode = diatonicMode(key: Key(root: .C, scale: scale), degree: degree)!
                for height in StackHeight.allCases {
                    let chord = stackThirds(mode, height: height)
                    let label = "\(scale) \(degree) \(height)"
                    #expect(chord.first == 0, "\(label)")
                    #expect(zip(chord, chord.dropFirst()).allSatisfy { $0 < $1 }, "\(label)")
                    #expect(chord.allSatisfy { mode.contains($0 % 12) }, "\(label)")
                    #expect(height.rawValue - chord.count <= 1, "\(label) dropped more than one tone")
                }
            }
        }
    }

    @Test func everyColumnDiffersFromItsNeighbour() {
        for scale in ScaleType.allCases where scale.isHeptatonic {
            for degree in Degree.allCases {
                let mode = diatonicMode(key: Key(root: .C, scale: scale), degree: degree)!
                let column = StackHeight.allCases.map { stackThirds(mode, height: $0) }
                #expect(zip(column, column.dropFirst()).allSatisfy { $0 != $1 }, "\(scale) \(degree)")
            }
        }
    }
}
