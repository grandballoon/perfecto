import Testing
@testable import MusicTheoryCore

@Suite("ComputeVoicing")
struct ComputeVoicingTests {

    // MARK: – Spec example

    @Test func specExample_CmajI_defaultRight_octave4() {
        // From spec §4.4: C-E-G-B = Cmaj7
        let result = computeVoicing(
            key: Key(root: .C, scale: .major),
            spec: ChordSpec(degree: .I, color: .joystick(.default, .right)),
            inversion: .root,
            octave: 4,
            voiceLeading: false,
            previousVoicing: nil
        )
        #expect(result.notes == [60, 64, 67, 71])
    }

    // MARK: – MIDI root placement

    @Test func octave3ShiftsAllNotesDown12() {
        let oct4 = computeVoicing(
            key: Key(root: .C, scale: .major), spec: ChordSpec(degree: .I, color: .joystick(.default, .center)),
            inversion: .root, octave: 4, voiceLeading: false, previousVoicing: nil
        )
        let oct3 = computeVoicing(
            key: Key(root: .C, scale: .major), spec: ChordSpec(degree: .I, color: .joystick(.default, .center)),
            inversion: .root, octave: 3, voiceLeading: false, previousVoicing: nil
        )
        #expect(oct3.notes == oct4.notes.map { $0 - 12 })
    }

    @Test func degreeVRootIsCorrectForGMajorKey() {
        // G major, degree V = D chord.
        // G.rawValue=7, octave=4, degreeOffset=7 (G major V).
        // chordRoot = 7 + (4+1)*12 + 7 = 74 (D5)
        let result = computeVoicing(
            key: Key(root: .G, scale: .major), spec: ChordSpec(degree: .V, color: .joystick(.default, .center)),
            inversion: .root, octave: 4, voiceLeading: false, previousVoicing: nil
        )
        #expect(result.notes.first == 74)  // D5 is the chord root
    }

    // MARK: – Inversions

    @Test func firstInversion() {
        // C major [60,64,67] → first inversion: C moves up → [64,67,72]
        let result = computeVoicing(
            key: Key(root: .C, scale: .major), spec: ChordSpec(degree: .I, color: .joystick(.default, .center)),
            inversion: .first, octave: 4, voiceLeading: false, previousVoicing: nil
        )
        #expect(result.notes == [64, 67, 72])
    }

    @Test func secondInversion() {
        // C major [60,64,67] → second inversion: C and E move up → [67,72,76]
        let result = computeVoicing(
            key: Key(root: .C, scale: .major), spec: ChordSpec(degree: .I, color: .joystick(.default, .center)),
            inversion: .second, octave: 4, voiceLeading: false, previousVoicing: nil
        )
        #expect(result.notes == [67, 72, 76])
    }

    private func cMajor(_ inversion: Inversion, color: ChordColor = .joystick(.default, .center)) -> [Int] {
        computeVoicing(key: Key(root: .C, scale: .major), spec: ChordSpec(degree: .I, color: color),
                       inversion: inversion, octave: 4, voiceLeading: false, previousVoicing: nil).notes
    }

    /// Each step up takes the lowest note up an octave, so a triad is an
    /// octave higher after three.
    @Test func anInversionGoesOnUpPastTheSecond() {
        #expect(cMajor(Inversion(steps: 3)) == [72, 76, 79])
        #expect(cMajor(Inversion(steps: 4)) == [76, 79, 84])
        #expect(cMajor(Inversion.second.rolled(by: 2)) == cMajor(Inversion(steps: 4)))
    }

    /// Each step down takes the highest note down an octave.
    @Test func anInversionBelowRootPositionRollsTheChordDown() {
        #expect(cMajor(Inversion(steps: -1)) == [55, 60, 64])
        #expect(cMajor(Inversion(steps: -2)) == [52, 55, 60])
        #expect(cMajor(Inversion(steps: -3)) == [48, 52, 55])
    }

    /// A four-note chord takes four steps to the octave, and has a third
    /// inversion on the way.
    @Test func aFourNoteChordHasAThirdInversion() {
        let maj7 = ChordColor.joystick(.default, .right)
        #expect(cMajor(Inversion(steps: 3), color: maj7) == [71, 72, 76, 79])
        #expect(cMajor(Inversion(steps: 4), color: maj7) == [72, 76, 79, 83])
    }

    /// However far a chord is rolled, it is the same notes in other octaves.
    @Test func rollingKeepsTheChordsPitchClasses() {
        let ninth = ChordColor.grid(.ninth, nil)
        let root = Set(cMajor(.root, color: ninth).map { $0 % 12 })
        for steps in -8...8 {
            let rolled = cMajor(Inversion(steps: steps), color: ninth)
            #expect(Set(rolled.map { $0 % 12 }) == root)
            #expect(rolled == rolled.sorted())
        }
    }

    // MARK: – Chords wider than an octave

    private let ninth = ChordColor.joystick(.extended, .upRight)   // C9: C E G B♭ D

    /// The notes above the octave are not inverted: the 9th stays on top
    /// while the four notes under it take turns in the bass.
    @Test func aNinthStaysOnTopWhileTheNotesUnderItAreInverted() {
        #expect(cMajor(.root, color: ninth) == [60, 64, 67, 70, 74])
        #expect(cMajor(.first, color: ninth) == [64, 67, 70, 72, 74])
        // The E rolled up would pass the 9th, which goes up an octave.
        #expect(cMajor(.second, color: ninth) == [67, 70, 72, 76, 86])
        #expect(cMajor(Inversion(steps: 3), color: ninth) == [70, 72, 76, 79, 86])
    }

    /// A turn of the notes within the octave is an octave, whatever the
    /// chord has above them, up and down.
    @Test func aTurnOfTheInvertedNotesIsAnOctaveForEveryColor() {
        for mode in JoystickMode.allCases {
            for direction in JoystickDirection.allCases {
                let color = ChordColor.joystick(mode, direction)
                let shape = chordShape(key: Key(root: .C, scale: .major),
                                       spec: ChordSpec(degree: .I, color: color)).intervals
                let turn = shape.filter { $0 < 12 }.count
                let root = cMajor(.root, color: color)
                #expect(cMajor(Inversion(steps: turn), color: color) == root.map { $0 + 12 })
                #expect(cMajor(Inversion(steps: -2 * turn), color: color) == root.map { $0 - 24 })
            }
        }
    }

    /// No note above the octave is ever in the bass or among the inverted
    /// notes, so a chord is never rolled into a cluster of its extensions.
    @Test func theNotesAboveTheOctaveAreAlwaysOnTop() {
        for mode in JoystickMode.allCases {
            for direction in JoystickDirection.allCases {
                let color = ChordColor.joystick(mode, direction)
                let shape = chordShape(key: Key(root: .C, scale: .major),
                                       spec: ChordSpec(degree: .I, color: color)).intervals
                let above = Set(shape.filter { $0 >= 12 }.map { $0 % 12 })
                let below = shape.filter { $0 < 12 }.count
                for steps in -8...8 {
                    let rolled = cMajor(Inversion(steps: steps), color: color)
                    #expect(rolled.count == shape.count)
                    #expect(Set(rolled.suffix(shape.count - below).map { $0 % 12 }) == above)
                }
            }
        }
    }

    /// Going down, the 9th comes down with the chord it is over.
    @Test func aNinthRolledDownKeepsItsNinthOnTop() {
        #expect(cMajor(Inversion(steps: -1), color: ninth) == [58, 60, 64, 67, 74])
        #expect(cMajor(Inversion(steps: -4), color: ninth) == [48, 52, 55, 58, 62])
    }

    @Test func secondInversionOnFourNoteChord() {
        // Cmaj7 [60,64,67,71] → second inversion → [67,71,72,76]
        let result = computeVoicing(
            key: Key(root: .C, scale: .major), spec: ChordSpec(degree: .I, color: .joystick(.default, .right)),
            inversion: .second, octave: 4, voiceLeading: false, previousVoicing: nil
        )
        #expect(result.notes == [67, 71, 72, 76])
    }

    // MARK: – Voice leading

    @Test func voiceLeadingMinimizesMovementFromPreviousChord() {
        // C major (60,64,67) → IV = F major.
        // Best voice leading is F in 2nd inversion [60,65,69] = C-F-A (cost 3),
        // which retains the common tone C. Root position [65,69,72] costs 8.
        let prev = Voicing(notes: [60, 64, 67])
        let result = computeVoicing(
            key: Key(root: .C, scale: .major), spec: ChordSpec(degree: .IV, color: .joystick(.default, .center)),
            inversion: .root, octave: 4, voiceLeading: true, previousVoicing: prev
        )
        #expect(result.notes == [60, 65, 69])
    }

    @Test func voiceLeadingWithNilPreviousMatchesNoVoiceLeading() {
        let a = computeVoicing(
            key: Key(root: .C, scale: .major), spec: ChordSpec(degree: .I, color: .joystick(.default, .center)),
            inversion: .root, octave: 4, voiceLeading: true, previousVoicing: nil
        )
        let b = computeVoicing(
            key: Key(root: .C, scale: .major), spec: ChordSpec(degree: .I, color: .joystick(.default, .center)),
            inversion: .root, octave: 4, voiceLeading: false, previousVoicing: nil
        )
        #expect(a.notes == b.notes)
    }

    // MARK: – Cross-scale quality detection

    @Test func harmonicMinorVIIisDim() {
        // C harmonic minor vii = B dim triad = B-D-F
        let result = computeVoicing(
            key: Key(root: .C, scale: .harmonicMinor), spec: ChordSpec(degree: .viiDim, color: .joystick(.default, .center)),
            inversion: .root, octave: 4, voiceLeading: false, previousVoicing: nil
        )
        #expect(result.notes == [71, 74, 77])
    }

    @Test func mixolydianIisMajorAndGetsMaj7() {
        // G Mixolydian I = G major; joystick right → Gmaj7 = G-B-D-F#
        // G=67, B=71, D=74, F#=78
        let result = computeVoicing(
            key: Key(root: .G, scale: .mixolydian), spec: ChordSpec(degree: .I, color: .joystick(.default, .right)),
            inversion: .root, octave: 4, voiceLeading: false, previousVoicing: nil
        )
        #expect(result.notes == [67, 71, 74, 78])
    }

    // MARK: – Invariants

    @Test func outputIsAlwaysSortedAscending() {
        for scale in ScaleType.allCases {
            for degree in Degree.allCases {
                for dir in [JoystickDirection.center, .up, .right, .down, .upLeft] {
                    let result = computeVoicing(
                        key: Key(root: .C, scale: scale), spec: ChordSpec(degree: degree, color: .joystick(.default, dir)),
                        inversion: .root, octave: 4, voiceLeading: false, previousVoicing: nil
                    )
                    #expect(result.notes == result.notes.sorted(),
                        "\(scale) \(degree) \(dir) output not sorted")
                }
            }
        }
    }

    @Test func outputHasAtLeastTwoNotes() {
        for scale in ScaleType.allCases {
            for degree in Degree.allCases {
                let result = computeVoicing(
                    key: Key(root: .C, scale: scale), spec: ChordSpec(degree: degree, color: .joystick(.default, .center)),
                    inversion: .root, octave: 4, voiceLeading: false, previousVoicing: nil
                )
                #expect(result.notes.count >= 2, "\(scale) \(degree) has too few notes")
            }
        }
    }
}
