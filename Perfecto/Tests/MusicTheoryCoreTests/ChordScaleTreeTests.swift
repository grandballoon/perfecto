import Testing
@testable import MusicTheoryCore

/// The chord–scale tree's theory, held to the values in
/// `docs/chord-scale-tree.md`, which were made by the prototype's own engine.
@Suite("ChordScaleTree")
struct ChordScaleTreeTests {

    // MARK: – Helpers

    /// The note written `name` ("F♯", "D𝄪").
    private func note(_ name: String) -> NoteName {
        let letter = Array("CDEFGAB").firstIndex(of: name.first!)!
        let accidental: Int
        switch name.dropFirst() {
        case "𝄫": accidental = -2
        case "♭": accidental = -1
        case "":  accidental = 0
        case "♯": accidental = 1
        case "𝄪": accidental = 2
        default:  preconditionFailure("no accidental \(name)")
        }
        return NoteName(letter: letter, accidental: accidental)
    }

    /// Notes written as a line, "C D E♭".
    private func names(_ notes: [NoteName]) -> String {
        notes.map(\.name).joined(separator: " ")
    }

    /// A scale's seven chords as the spec writes them: "C (I) · Dm (ii) · …".
    private func chords(of mode: HeptatonicMode, on root: String, _ size: ChordSize) -> String {
        let notes = mode.spelled(from: note(root))
        return (0..<7).map { degree in
            let chord = TreeChord(root: notes[degree], quality: mode.chord(onDegree: degree, size: size))
            return "\(chord.label) (\(mode.numeral(ofDegree: degree, size: size)))"
        }
        .joined(separator: " · ")
    }

    private func chord(_ root: String, _ quality: ChordQuality) -> TreeChord {
        TreeChord(root: note(root), quality: quality)
    }

    // MARK: – Hosts

    @Test func eachChordIsTheHomeChordOfTheModesThatStackToIt() {
        let hosts: [ChordQuality: [HeptatonicMode]] = [
            .major: [.ionian, .lydian, .mixolydian, .phrygianDominant, .lydianSharp2, .lydianDominant,
                     .mixolydianFlat6],
            .minor: [.dorian, .phrygian, .aeolian, .harmonicMinor, .dorianSharp4, .melodicMinor, .dorianFlat2],
            .diminished: [.locrian, .locrianNatural6, .ultralocrian, .locrianNatural2, .altered],
            .augmented: [.ionianSharp5, .lydianAugmented],
            .major7: [.ionian, .lydian, .lydianSharp2],
            .dominant7: [.mixolydian, .phrygianDominant, .lydianDominant, .mixolydianFlat6],
            .minor7: [.dorian, .phrygian, .aeolian, .dorianSharp4, .dorianFlat2],
            .minorMajor7: [.harmonicMinor, .melodicMinor],
            .halfDiminished7: [.locrian, .locrianNatural6, .locrianNatural2, .altered],
            .diminished7: [.ultralocrian],
            .augmentedMajor7: [.ionianSharp5, .lydianAugmented],
            .augmented7: [],
        ]
        for quality in ChordQuality.allCases {
            #expect(quality.hosts == hosts[quality], "\(quality)")
        }
    }

    @Test func everyModeHasOneHomeTriadAndOneHomeSeventh() {
        for size in ChordSize.allCases {
            #expect(ChordQuality.all(size).map(\.hosts.count).reduce(0, +) == 21)
        }
    }

    // MARK: – Modes

    @Test func theModesAreTheirFamiliesRotated() {
        let table: [(HeptatonicMode, ScaleFamily, Int, [Int], ChordQuality, ChordQuality)] = [
            (.ionian, .major, 1, [0, 2, 4, 5, 7, 9, 11], .major, .major7),
            (.dorian, .major, 2, [0, 2, 3, 5, 7, 9, 10], .minor, .minor7),
            (.phrygian, .major, 3, [0, 1, 3, 5, 7, 8, 10], .minor, .minor7),
            (.lydian, .major, 4, [0, 2, 4, 6, 7, 9, 11], .major, .major7),
            (.mixolydian, .major, 5, [0, 2, 4, 5, 7, 9, 10], .major, .dominant7),
            (.aeolian, .major, 6, [0, 2, 3, 5, 7, 8, 10], .minor, .minor7),
            (.locrian, .major, 7, [0, 1, 3, 5, 6, 8, 10], .diminished, .halfDiminished7),
            (.harmonicMinor, .harmonicMinor, 1, [0, 2, 3, 5, 7, 8, 11], .minor, .minorMajor7),
            (.locrianNatural6, .harmonicMinor, 2, [0, 1, 3, 5, 6, 9, 10], .diminished, .halfDiminished7),
            (.ionianSharp5, .harmonicMinor, 3, [0, 2, 4, 5, 8, 9, 11], .augmented, .augmentedMajor7),
            (.dorianSharp4, .harmonicMinor, 4, [0, 2, 3, 6, 7, 9, 10], .minor, .minor7),
            (.phrygianDominant, .harmonicMinor, 5, [0, 1, 4, 5, 7, 8, 10], .major, .dominant7),
            (.lydianSharp2, .harmonicMinor, 6, [0, 3, 4, 6, 7, 9, 11], .major, .major7),
            (.ultralocrian, .harmonicMinor, 7, [0, 1, 3, 4, 6, 8, 9], .diminished, .diminished7),
            (.melodicMinor, .melodicMinor, 1, [0, 2, 3, 5, 7, 9, 11], .minor, .minorMajor7),
            (.dorianFlat2, .melodicMinor, 2, [0, 1, 3, 5, 7, 9, 10], .minor, .minor7),
            (.lydianAugmented, .melodicMinor, 3, [0, 2, 4, 6, 8, 9, 11], .augmented, .augmentedMajor7),
            (.lydianDominant, .melodicMinor, 4, [0, 2, 4, 6, 7, 9, 10], .major, .dominant7),
            (.mixolydianFlat6, .melodicMinor, 5, [0, 2, 4, 5, 7, 8, 10], .major, .dominant7),
            (.locrianNatural2, .melodicMinor, 6, [0, 2, 3, 5, 6, 8, 10], .diminished, .halfDiminished7),
            (.altered, .melodicMinor, 7, [0, 1, 3, 4, 6, 8, 10], .diminished, .halfDiminished7),
        ]
        #expect(ScaleFamily.allModes == table.map(\.0))
        for (mode, family, number, intervals, triad, seventh) in table {
            #expect(mode.family == family, "\(mode)")
            #expect(mode.number == number, "\(mode)")
            #expect(mode.intervals == intervals, "\(mode)")
            #expect(mode.chord(onDegree: 0, size: .triads) == triad, "\(mode)")
            #expect(mode.chord(onDegree: 0, size: .sevenths) == seventh, "\(mode)")
        }
    }

    // MARK: – Scales and their chords

    @Test func aScaleIsSpelledALetterToANote() {
        #expect(names(HeptatonicMode.ionian.spelled(from: note("C"))) == "C D E F G A B")
        #expect(names(HeptatonicMode.harmonicMinor.spelled(from: note("A"))) == "A B C D E F G♯")
        #expect(names(HeptatonicMode.melodicMinor.spelled(from: note("C"))) == "C D E♭ F G A B")
        #expect(names(HeptatonicMode.phrygian.spelled(from: note("E"))) == "E F G A B C D")
        #expect(names(HeptatonicMode.locrian.spelled(from: note("B"))) == "B C D E F G A")
        #expect(names(HeptatonicMode.ionian.spelled(from: note("F♯"))) == "F♯ G♯ A♯ B C♯ D♯ E♯")
        #expect(names(HeptatonicMode.phrygianDominant.spelled(from: note("E♭"))) == "E♭ F♭ G A♭ B♭ C♭ D♭")
        #expect(names(HeptatonicMode.altered.spelled(from: note("G"))) == "G A♭ B♭ C♭ D♭ E♭ F")
    }

    @Test func aScaleLeadsToItsSevenChordsEachWithItsNumeral() {
        #expect(chords(of: .ionian, on: "C", .triads)
                == "C (I) · Dm (ii) · Em (iii) · F (IV) · G (V) · Am (vi) · B° (vii°)")
        #expect(chords(of: .ionian, on: "C", .sevenths)
                == "Cmaj7 (Imaj7) · Dm7 (ii7) · Em7 (iii7) · Fmaj7 (IVmaj7) · G7 (V7) · Am7 (vi7) · Bø7 (viiø7)")
        #expect(chords(of: .harmonicMinor, on: "A", .triads)
                == "Am (i) · B° (ii°) · C+ (♭III+) · Dm (iv) · E (V) · F (♭VI) · G♯° (vii°)")
        #expect(chords(of: .harmonicMinor, on: "A", .sevenths)
                == "Am(maj7) (i(maj7)) · Bø7 (iiø7) · C+maj7 (♭III+maj7) · Dm7 (iv7) · E7 (V7) · Fmaj7 (♭VImaj7) · G♯°7 (vii°7)")
        #expect(chords(of: .melodicMinor, on: "C", .sevenths)
                == "Cm(maj7) (i(maj7)) · Dm7 (ii7) · E♭+maj7 (♭III+maj7) · F7 (IV7) · G7 (V7) · Aø7 (viø7) · Bø7 (viiø7)")
        #expect(chords(of: .phrygian, on: "E", .triads)
                == "Em (i) · F (♭II) · G (♭III) · Am (iv) · B° (v°) · C (♭VI) · Dm (♭vii)")
        #expect(chords(of: .locrian, on: "B", .sevenths)
                == "Bø7 (iø7) · Cmaj7 (♭IImaj7) · Dm7 (♭iii7) · Em7 (iv7) · Fmaj7 (♭Vmaj7) · G7 (♭VI7) · Am7 (♭vii7)")
        #expect(chords(of: .ionian, on: "F♯", .triads)
                == "F♯ (I) · G♯m (ii) · A♯m (iii) · B (IV) · C♯ (V) · D♯m (vi) · E♯° (vii°)")
        #expect(chords(of: .phrygianDominant, on: "E♭", .sevenths)
                == "E♭7 (I7) · F♭maj7 (♭IImaj7) · G°7 (iii°7) · A♭m(maj7) (iv(maj7)) · B♭ø7 (vø7) · C♭+maj7 (♭VI+maj7) · D♭m7 (♭vii7)")
        #expect(chords(of: .altered, on: "G", .sevenths)
                == "Gø7 (iø7) · A♭m(maj7) (♭ii(maj7)) · B♭m7 (♭iii7) · C♭+maj7 (♭IV+maj7) · D♭7 (♭V7) · E♭7 (♭VI7) · Fø7 (♭viiø7)")
    }

    // MARK: – Spelling

    @Test func aChordIsSpelledEveryOtherLetter() {
        #expect(names(ChordQuality.dominant7.spelled(from: note("D♭"))) == "D♭ F A♭ C♭")
        #expect(names(ChordQuality.diminished7.spelled(from: note("B"))) == "B D F A♭")
        // Double sharps are written as they fall in a chord, not respelled.
        #expect(names(ChordQuality.augmentedMajor7.spelled(from: note("G♯"))) == "G♯ B♯ D𝄪 F𝄪")
    }

    @Test func theRootsAreWrittenAsTheyAreChosen() {
        #expect(names(NoteName.roots) == "C D♭ D E♭ E F F♯ G A♭ A B♭ B")
        #expect(NoteName.roots.map(\.pitchClass) == PitchClass.allCases)
    }

    @Test func onlyADoubleAccidentalIsRespelledToBeARoot() {
        #expect(note("D𝄪").asRoot == note("E"))
        #expect(note("B𝄫").asRoot == note("A"))
        #expect(note("F♭").asRoot == note("F♭"))
        #expect(note("E♯").asRoot == note("E♯"))
    }

    // MARK: – Properties

    @Test func everyScaleUsesEachLetterOnce() {
        for mode in HeptatonicMode.allCases {
            for root in NoteName.roots {
                #expect(Set(mode.spelled(from: root).map(\.letter)).count == 7, "\(root.name) \(mode)")
            }
        }
    }

    @Test func everyChordOfAScaleIsTheHomeChordOfTheModeOnItsDegree() {
        for size in ChordSize.allCases {
            for mode in HeptatonicMode.allCases {
                for degree in 0..<7 {
                    let rotated = (0..<7).map { (mode.intervals[(degree + $0) % 7] - mode.intervals[degree] + 12) % 12 }
                    let home = HeptatonicMode(intervals: rotated)!
                    #expect(mode.chord(onDegree: degree, size: size).hosts.contains(home), "\(mode) \(degree)")
                }
            }
        }
    }

    // MARK: – The way on

    @Test func aChordGoesOnToEveryChordOfItsScalesOnceEach() {
        let next = chord("C", .major).next
        #expect(next.map(\.count) == [5, 2, 3, 4, 2, 6])
        let all = next.joined().map(\.chord)
        #expect(Set(all).count == all.count)
        #expect(!all.contains(chord("C", .major)))
    }

    @Test func aBranchIsTheChordsOnOneLetterLowestRootFirst() {
        let second = chord("C", .major).next[0]
        #expect(second.map(\.chord.label) == ["D♭", "D", "Dm", "D°", "D♯°"])
        #expect(second.map(\.numeral) == ["♭II", "II", "ii", "ii°", "♯ii°"])
    }

    @Test func aStepSaysWhichScalesHaveIt() {
        let dm = chord("C", .major).next[0].first { $0.chord == chord("D", .minor) }!
        #expect(dm.scales == [.ionian, .mixolydian])
    }

    @Test func everyStepLeadsOnAgain() {
        for size in ChordSize.allCases {
            for quality in ChordQuality.all(size) where !quality.hosts.isEmpty {
                for root in NoteName.roots {
                    for step in TreeChord(root: root, quality: quality).next.joined() {
                        #expect(!step.chord.scales.isEmpty, "\(step.chord.label)")
                        #expect(!step.chord.next.joined().isEmpty, "\(step.chord.label)")
                    }
                }
            }
        }
    }

    @Test func aChordChangesSizeToTheFirstOfItsGroup() {
        #expect(chord("G", .major).resized(to: .sevenths) == chord("G", .major7))
        #expect(chord("G", .dominant7).resized(to: .triads) == chord("G", .major))
        #expect(chord("D", .minor).resized(to: .sevenths) == chord("D", .minor7))
        #expect(chord("B", .diminished).resized(to: .sevenths) == chord("B", .halfDiminished7))
        #expect(chord("C", .augmented).resized(to: .sevenths) == chord("C", .augmentedMajor7))
        #expect(chord("C", .major7).resized(to: .triads) == chord("C", .major))
        #expect(chord("C", .minorMajor7).resized(to: .triads) == chord("C", .minor))
    }

    @Test func theTreeStartsOnTheTonicChordOfTheKey() {
        #expect(TreeChord.home(of: Key(root: .C, scale: .major), size: .triads) == chord("C", .major))
        #expect(TreeChord.home(of: Key(root: .A, scale: .naturalMinor), size: .sevenths) == chord("A", .minor7))
        #expect(TreeChord.home(of: Key(root: .As, scale: .harmonicMinor), size: .sevenths)
                == chord("B♭", .minorMajor7))
    }
}
