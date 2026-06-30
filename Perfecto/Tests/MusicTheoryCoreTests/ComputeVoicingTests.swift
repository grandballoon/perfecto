import Testing
@testable import MusicTheoryCore

@Suite("ComputeVoicing")
struct ComputeVoicingTests {

    // MARK: – Spec example

    @Test func specExample_CmajI_defaultRight_octave4() {
        // From spec §4.4: C-E-G-B = Cmaj7
        let result = computeVoicing(
            key: Key(root: .C, scale: .major),
            degree: .I,
            joystickMode: .default,
            joystickDirection: .right,
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
            key: Key(root: .C, scale: .major), degree: .I,
            joystickMode: .default, joystickDirection: .center,
            inversion: .root, octave: 4, voiceLeading: false, previousVoicing: nil
        )
        let oct3 = computeVoicing(
            key: Key(root: .C, scale: .major), degree: .I,
            joystickMode: .default, joystickDirection: .center,
            inversion: .root, octave: 3, voiceLeading: false, previousVoicing: nil
        )
        #expect(oct3.notes == oct4.notes.map { $0 - 12 })
    }

    @Test func degreeVRootIsCorrectForGMajorKey() {
        // G major, degree V = D chord.
        // G.rawValue=7, octave=4, degreeOffset=7 (G major V).
        // chordRoot = 7 + (4+1)*12 + 7 = 74 (D5)
        let result = computeVoicing(
            key: Key(root: .G, scale: .major), degree: .V,
            joystickMode: .default, joystickDirection: .center,
            inversion: .root, octave: 4, voiceLeading: false, previousVoicing: nil
        )
        #expect(result.notes.first == 74)  // D5 is the chord root
    }

    // MARK: – Inversions

    @Test func firstInversion() {
        // C major [60,64,67] → first inversion: C moves up → [64,67,72]
        let result = computeVoicing(
            key: Key(root: .C, scale: .major), degree: .I,
            joystickMode: .default, joystickDirection: .center,
            inversion: .first, octave: 4, voiceLeading: false, previousVoicing: nil
        )
        #expect(result.notes == [64, 67, 72])
    }

    @Test func secondInversion() {
        // C major [60,64,67] → second inversion: C and E move up → [67,72,76]
        let result = computeVoicing(
            key: Key(root: .C, scale: .major), degree: .I,
            joystickMode: .default, joystickDirection: .center,
            inversion: .second, octave: 4, voiceLeading: false, previousVoicing: nil
        )
        #expect(result.notes == [67, 72, 76])
    }

    @Test func secondInversionOnFourNoteChord() {
        // Cmaj7 [60,64,67,71] → second inversion → [67,71,72,76]
        let result = computeVoicing(
            key: Key(root: .C, scale: .major), degree: .I,
            joystickMode: .default, joystickDirection: .right,
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
            key: Key(root: .C, scale: .major), degree: .IV,
            joystickMode: .default, joystickDirection: .center,
            inversion: .root, octave: 4, voiceLeading: true, previousVoicing: prev
        )
        #expect(result.notes == [60, 65, 69])
    }

    @Test func voiceLeadingWithNilPreviousMatchesNoVoiceLeading() {
        let a = computeVoicing(
            key: Key(root: .C, scale: .major), degree: .I,
            joystickMode: .default, joystickDirection: .center,
            inversion: .root, octave: 4, voiceLeading: true, previousVoicing: nil
        )
        let b = computeVoicing(
            key: Key(root: .C, scale: .major), degree: .I,
            joystickMode: .default, joystickDirection: .center,
            inversion: .root, octave: 4, voiceLeading: false, previousVoicing: nil
        )
        #expect(a.notes == b.notes)
    }

    // MARK: – Cross-scale quality detection

    @Test func harmonicMinorVIIisDim() {
        // C harmonic minor vii = B dim triad = B-D-F
        let result = computeVoicing(
            key: Key(root: .C, scale: .harmonicMinor), degree: .viiDim,
            joystickMode: .default, joystickDirection: .center,
            inversion: .root, octave: 4, voiceLeading: false, previousVoicing: nil
        )
        #expect(result.notes == [71, 74, 77])
    }

    @Test func mixolydianIisMajorAndGetsMaj7() {
        // G Mixolydian I = G major; joystick right → Gmaj7 = G-B-D-F#
        // G=67, B=71, D=74, F#=78
        let result = computeVoicing(
            key: Key(root: .G, scale: .mixolydian), degree: .I,
            joystickMode: .default, joystickDirection: .right,
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
                        key: Key(root: .C, scale: scale), degree: degree,
                        joystickMode: .default, joystickDirection: dir,
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
                    key: Key(root: .C, scale: scale), degree: degree,
                    joystickMode: .default, joystickDirection: .center,
                    inversion: .root, octave: 4, voiceLeading: false, previousVoicing: nil
                )
                #expect(result.notes.count >= 2, "\(scale) \(degree) has too few notes")
            }
        }
    }
}
