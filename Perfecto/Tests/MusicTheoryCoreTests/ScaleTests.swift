import Testing
@testable import MusicTheoryCore

@Suite("Scale")
struct ScaleTests {

    // MARK: – Scale intervals

    @Test func majorIntervals() {
        #expect(ScaleType.major.intervals == [0, 2, 4, 5, 7, 9, 11])
    }

    @Test func naturalMinorIntervals() {
        #expect(ScaleType.naturalMinor.intervals == [0, 2, 3, 5, 7, 8, 10])
    }

    @Test func harmonicMinorIntervals() {
        #expect(ScaleType.harmonicMinor.intervals == [0, 2, 3, 5, 7, 8, 11])
    }

    @Test func melodicMinorIntervals() {
        #expect(ScaleType.melodicMinor.intervals == [0, 2, 3, 5, 7, 9, 11])
    }

    @Test func majorPentatonicIntervals() {
        #expect(ScaleType.majorPentatonic.intervals == [0, 2, 4, 7, 9])
    }

    @Test func minorPentatonicIntervals() {
        #expect(ScaleType.minorPentatonic.intervals == [0, 3, 5, 7, 10])
    }

    @Test func bluesIntervals() {
        #expect(ScaleType.blues.intervals == [0, 3, 5, 6, 7, 10])
    }

    @Test func dorianIntervals() {
        #expect(ScaleType.dorian.intervals == [0, 2, 3, 5, 7, 9, 10])
    }

    @Test func mixolydianIntervals() {
        #expect(ScaleType.mixolydian.intervals == [0, 2, 4, 5, 7, 9, 10])
    }

    @Test func lydianIntervals() {
        #expect(ScaleType.lydian.intervals == [0, 2, 4, 6, 7, 9, 11])
    }

    // Every scale must start at 0, be strictly ascending, and end below 12
    @Test func allScalesAreAscendingAndInRange() {
        for scale in ScaleType.allCases {
            let ivls = scale.intervals
            #expect(!ivls.isEmpty, "\(scale) has empty intervals")
            #expect(ivls.first == 0, "\(scale) must start at 0")
            for i in 0..<ivls.count - 1 {
                #expect(ivls[i] < ivls[i + 1],
                    "\(scale) intervals not strictly ascending at index \(i)")
            }
            #expect((ivls.last ?? 12) < 12, "\(scale) last interval must be < 12")
        }
    }

    // MARK: – Base triads for all degrees of C major

    // C major: I=C, ii=Dm, iii=Em, IV=F, V=G, vi=Am, vii°=Bdim
    @Test func cMajorBaseTriads() {
        let key = Key(root: .C, scale: .major)
        let cases: [(Degree, [Int])] = [
            (.I,      [60, 64, 67]),  // C-E-G
            (.ii,     [62, 65, 69]),  // D-F-A
            (.iii,    [64, 67, 71]),  // E-G-B
            (.IV,     [65, 69, 72]),  // F-A-C
            (.V,      [67, 71, 74]),  // G-B-D
            (.vi,     [69, 72, 76]),  // A-C-E
            (.viiDim, [71, 74, 77]),  // B-D-F
        ]
        for (degree, expected) in cases {
            let result = computeVoicing(
                key: key, degree: degree,
                joystickMode: .default, joystickDirection: .center,
                inversion: .root, octave: 4, voiceLeading: false, previousVoicing: nil
            )
            #expect(result.notes == expected, "C major \(degree) base triad mismatch")
        }
    }

    // A natural minor: I=Am, ii°=Bdim, III=C, iv=Dm, v=Em, VI=F, VII=G
    @Test func aNaturalMinorBaseTriads() {
        let key = Key(root: .A, scale: .naturalMinor)
        let cases: [(Degree, [Int])] = [
            (.I,      [69, 72, 76]),  // A-C-E  (Am)
            (.ii,     [71, 74, 77]),  // B-D-F  (Bdim)
            (.iii,    [72, 76, 79]),  // C-E-G  (C)
            (.IV,     [74, 77, 81]),  // D-F-A  (Dm)
            (.V,      [76, 79, 83]),  // E-G-B  (Em)
            (.vi,     [77, 81, 84]),  // F-A-C  (F)
            (.viiDim, [79, 83, 86]),  // G-B-D  (G)
        ]
        for (degree, expected) in cases {
            let result = computeVoicing(
                key: key, degree: degree,
                joystickMode: .default, joystickDirection: .center,
                inversion: .root, octave: 4, voiceLeading: false, previousVoicing: nil
            )
            #expect(result.notes == expected, "A natural minor \(degree) mismatch")
        }
    }
}
