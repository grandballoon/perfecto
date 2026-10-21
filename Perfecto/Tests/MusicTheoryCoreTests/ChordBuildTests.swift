import Testing
@testable import MusicTheoryCore

@Suite("ChordBuild")
struct ChordBuildTests {

    private let cMajor = Key(root: .C, scale: .major)

    private func spec(_ type: ChordType?, _ extensions: Set<ChordExtension> = [],
                      degree: Degree = .I) -> ChordSpec {
        ChordSpec(degree: degree, color: .built(ChordBuild(type: type, extensions: extensions)))
    }

    private func notes(_ type: ChordType?, _ extensions: Set<ChordExtension> = [],
                       degree: Degree = .I, inversion: Inversion = .root) -> [Int] {
        computeVoicing(key: cMajor, spec: spec(type, extensions, degree: degree),
                       inversion: inversion, octave: 4, voiceLeading: false, previousVoicing: nil).notes
    }

    private func name(_ type: ChordType?, _ extensions: Set<ChordExtension> = [],
                      degree: Degree = .I) -> String {
        chordLabel(key: cMajor, spec: spec(type, extensions, degree: degree))
    }

    // MARK: – Types

    @Test func eachTypeIsItsTriadOnAnyDegree() {
        #expect(notes(.diminished) == [60, 63, 66])
        #expect(notes(.minor) == [60, 63, 67])
        #expect(notes(.major) == [60, 64, 67])
        #expect(notes(.suspended) == [60, 65, 67])
        // D is minor in C major, and a major button makes it major.
        #expect(notes(.major, degree: .ii) == [62, 66, 69])
        #expect(name(.major, degree: .ii) == "D maj")
    }

    @Test func noTypeIsTheDegreesOwnTriad() {
        #expect(notes(nil, degree: .ii) == [62, 65, 69])
        #expect(notes(nil, [.minorSeventh], degree: .ii) == [62, 65, 69, 72])
        #expect(name(nil, [.minorSeventh], degree: .ii) == "D min7")
        #expect(ChordColor.built(ChordBuild(type: nil)).isBase)
        #expect(!ChordColor.built(ChordBuild(type: .major)).isBase)
    }

    @Test func aNoteIsItsRootAloneAndKeepsNoExtensions() {
        #expect(notes(.note, [.ninth, .sixth]) == [60])
        #expect(name(.note, [.ninth]) == "C")
        #expect(ChordBuild(type: .note, extensions: [.ninth]).extensions.isEmpty)
    }

    // MARK: – Extensions

    @Test func theExtensionsAreAddedAboveTheTriad() {
        #expect(notes(.major, [.sixth]) == [60, 64, 67, 69])
        #expect(notes(.major, [.minorSeventh]) == [60, 64, 67, 70])
        #expect(notes(.major, [.majorSeventh]) == [60, 64, 67, 71])
        #expect(notes(.major, [.ninth]) == [60, 64, 67, 74])
        #expect(notes(.major, [.sixth, .ninth]) == [60, 64, 67, 69, 74])
    }

    @Test func aSixthOverASeventhIsAThirteenth() {
        #expect(notes(.major, [.minorSeventh, .sixth]) == [60, 64, 67, 70, 81])
        #expect(notes(.major, [.minorSeventh, .ninth, .sixth]) == [60, 64, 67, 70, 74, 81])
    }

    @Test func aDiminishedTriadsSixthIsADiminishedSeventh() {
        #expect(notes(.diminished, [.sixth]) == [60, 63, 66, 69])
        #expect(name(.diminished, [.sixth]) == "C dim7")
    }

    @Test func theTwoSeventhsTogetherAreTheMajorOne() {
        #expect(notes(.minor, [.minorSeventh, .majorSeventh]) == [60, 63, 67, 71])
    }

    @Test func theExtensionsStayOnTopAsTheChordIsInverted() {
        // C add9 in first inversion: E G C, with the D above them.
        #expect(notes(.major, [.ninth], inversion: .first) == [64, 67, 72, 74])
    }

    // MARK: – Names

    @Test func theChordIsNamedAsTheJoysticksAre() {
        #expect(name(.major) == "C maj")
        #expect(name(.suspended) == "C sus4")
        #expect(name(.major, [.minorSeventh]) == "C 7")
        #expect(name(.major, [.majorSeventh]) == "C maj7")
        #expect(name(.minor, [.minorSeventh]) == "C min7")
        #expect(name(.minor, [.majorSeventh]) == "C min(maj7)")
        #expect(name(.diminished, [.minorSeventh]) == "C min7♭5")
        #expect(name(.suspended, [.minorSeventh]) == "C 7sus4")
        #expect(name(.major, [.ninth]) == "C add9")
        #expect(name(.minor, [.ninth]) == "C min add9")
        #expect(name(.major, [.sixth]) == "C 6")
        #expect(name(.minor, [.sixth]) == "C min6")
        #expect(name(.major, [.sixth, .ninth]) == "C 6/9")
        #expect(name(.minor, [.sixth, .ninth]) == "C min6/9")
    }

    @Test func aNinthOverASeventhNamesTheChord() {
        #expect(name(.major, [.minorSeventh, .ninth]) == "C 9")
        #expect(name(.major, [.majorSeventh, .ninth]) == "C maj9")
        #expect(name(.minor, [.minorSeventh, .ninth]) == "C min9")
        #expect(name(.diminished, [.minorSeventh, .ninth]) == "C min9♭5")
        #expect(name(.suspended, [.minorSeventh, .ninth]) == "C 9sus4")
        #expect(name(.major, [.minorSeventh, .ninth, .sixth]) == "C 9(13)")
    }

    @Test func theLegendIsTheButtonsMarks() {
        #expect(ChordBuild(type: .minor, extensions: [.ninth, .minorSeventh]).legend == "Min · m7 9")
        #expect(ChordBuild(type: nil, extensions: [.sixth]).legend == "6")
        #expect(ChordBuild(type: nil).legend == "Base")
        #expect(colorActionLabel(.built(ChordBuild(type: .major))) == "Maj")
    }

    @Test func everyBuildHasItsNotesOnceAndItsRootLowest() {
        let types: [ChordType?] = [nil] + ChordType.allCases
        let subsets = (0..<16).map { bits in
            Set(ChordExtension.allCases.enumerated().filter { bits & (1 << $0.offset) != 0 }.map(\.element))
        }
        for type in types {
            for extensions in subsets {
                let played = notes(type, extensions)
                #expect(played.first == 60)
                #expect(Set(played).count == played.count)
                #expect(!name(type, extensions).isEmpty)
            }
        }
    }
}
