import Testing
@testable import MusicTheoryCore

@Suite("SoloScale")
struct SoloScaleTests {

    private let cMajor = Key(root: .C, scale: .major)

    private func intervals(_ degree: Degree, _ color: ChordColor = .base, in key: Key? = nil) -> [Int] {
        soloIntervals(key: key ?? cMajor, spec: ChordSpec(degree: degree, color: color))
    }

    // MARK: – The pentatonic a chord implies

    @Test func aMajorChordGetsTheMajorPentatonic() {
        #expect(intervals(.I) == [0, 2, 4, 7, 9])
        #expect(intervals(.IV) == [0, 2, 4, 7, 9])
    }

    @Test func aMinorChordGetsTheMinorPentatonic() {
        #expect(intervals(.ii) == [0, 3, 5, 7, 10])
        #expect(intervals(.iii) == [0, 3, 5, 7, 10])
        #expect(intervals(.vi) == [0, 3, 5, 7, 10])
    }

    /// Of the sixth and the flat seventh, a semitone apart, the upper stays.
    @Test func theDominantKeepsItsSeventh() {
        #expect(intervals(.V) == [0, 2, 4, 7, 10])
    }

    @Test func aChordThatLeavesLittleRoomGetsLittleMore() {
        #expect(intervals(.viiDim) == [0, 3, 6, 8, 10])
        // An augmented triad leaves the major scale one note clear of it.
        #expect(intervals(.I, .joystick(.default, .upLeft)) == [0, 2, 4, 8])
    }

    /// The seventh a color adds is not part of the triad, so it does not
    /// change the scale: G maj7 in G major is played over with G A B D E.
    @Test func aSeventhLeavesThePentatonicAsItWas() {
        let gMajor = Key(root: .G, scale: .major)
        #expect(intervals(.I, .joystick(.default, .right), in: gMajor) == [0, 2, 4, 7, 9])
        #expect(intervals(.I, .joystick(.default, .upRight), in: gMajor) == [0, 2, 4, 7, 9])
    }

    // MARK: – The chord that sounds, not the degree's own

    @Test func aFlippedThirdIsFollowed() {
        // C minor on the tonic of C major: the key's E and B would clash.
        #expect(intervals(.I, .joystick(.default, .up)) == [0, 3, 5, 7, 9])
    }

    @Test func aSuspendedChordKeepsItsFourth() {
        #expect(intervals(.I, .joystick(.default, .down)) == [0, 2, 5, 7, 9])
    }

    @Test func aGridColorIsPlayedThroughItsOwnMode() {
        // Phrygian on the tonic of C major: its seventh is flat, where the key's is not.
        #expect(intervals(.I, .grid(.triad, .phrygian)) == [0, 3, 5, 7, 10])
        // The degree's own mode is the key's scale.
        #expect(intervals(.ii, .grid(.seventh, nil)) == intervals(.ii))
    }

    // MARK: – Rules that hold for every chord

    private static let colors: [ChordColor] =
        JoystickMode.allCases.flatMap { mode in JoystickDirection.allCases.map { ChordColor.joystick(mode, $0) } }
        + StackHeight.allCases.flatMap { height in
            [ChordColor.grid(height, nil)] + HeptatonicMode.allCases.map { ChordColor.grid(height, $0) }
        }

    @Test func everyChordsSoloScaleHoldsItsTriadAndNoOtherSemitones() {
        for scale in ScaleType.allCases where scale.isHeptatonic {
            let key = Key(root: .E, scale: scale)
            for degree in Degree.allCases {
                for color in Self.colors {
                    let spec = ChordSpec(degree: degree, color: color)
                    let solo = soloIntervals(key: key, spec: spec)
                    let triad = Set(chordShape(key: key, spec: spec).intervals.prefix(3).map { $0 % 12 })

                    #expect(solo.first == 0)
                    #expect(solo == solo.sorted() && Set(solo).count == solo.count)
                    #expect(triad.isSubset(of: solo))
                    for note in solo where !triad.contains(note) {
                        #expect(!solo.contains((note + 1) % 12) && !solo.contains((note + 11) % 12),
                                "\(note) is a semitone from another note over \(spec) in \(scale)")
                    }
                }
            }
        }
    }

    // MARK: – As notes

    @Test func notesAscendFromTheLowestAtOrAboveTheStart() {
        let notes = soloNotes(key: cMajor, spec: ChordSpec(degree: .I, color: .base), from: 60, count: 7)
        #expect(notes.map(\.note) == [60, 62, 64, 67, 69, 72, 74])
        #expect(notes.map(\.role) == [.root, .passing, .chordTone, .chordTone, .passing, .root, .passing])
    }

    /// The strip starts at the key's tonic whatever the chord, so its notes
    /// stay about where they were when the chord changes.
    @Test func anotherChordStartsFromTheSamePlace() {
        let notes = soloNotes(key: cMajor, spec: ChordSpec(degree: .ii, color: .base), from: 60, count: 5)
        // D minor pentatonic (D F G A C) from middle C up.
        #expect(notes.map(\.note) == [60, 62, 65, 67, 69])
        #expect(notes.map(\.role) == [.passing, .root, .chordTone, .passing, .chordTone])
    }

    @Test func notesEndWhereMidiDoes() {
        let notes = soloNotes(key: cMajor, spec: ChordSpec(degree: .I, color: .base), from: 120, count: 12)
        #expect(notes.map(\.note) == [120, 122, 124, 127])
        #expect(soloNotes(key: cMajor, spec: ChordSpec(degree: .I, color: .base), from: -5, count: 1).map(\.note) == [0])
    }
}
