import Testing
@testable import MusicTheoryCore

@Suite("ToneMarks")
struct ToneMarksTests {

    private let cMajor = Key(root: .C, scale: .major)
    private let dorian     = HeptatonicMode.dorian.intervals
    private let ionian     = HeptatonicMode.ionian.intervals
    private let mixolydian = HeptatonicMode.mixolydian.intervals
    private let lydian     = HeptatonicMode.lydian.intervals

    private func marks(_ moves: [(ChordTone, Int)] = [], skips: [ChordTone] = []) -> ToneMarks {
        var marks = ToneMarks()
        moves.forEach { marks.toggleMove($0.0, by: $0.1) }
        skips.forEach { marks.toggleSkip($0) }
        return marks
    }

    // MARK: – No marks

    @Test func noMarksIsTheStackItself() {
        for mode in HeptatonicMode.allCases {
            for height in StackHeight.allCases {
                #expect(markedStack(mode.intervals, height: height, marks: .none) == stackThirds(mode.intervals, height: height))
                #expect(markedChordName(mode, height: height, marks: .none) == tertianChordName(mode, height: height))
            }
        }
    }

    @Test func noMarksIsTheGridColor() {
        #expect(ChordColor.tertian(.seventh, .mixolydian, .none) == .grid(.seventh, .mixolydian))
        #expect(ChordColor.tertian(.seventh, .mixolydian, marks([(.fifth, 1)])) == .marked(.seventh, .mixolydian, marks([(.fifth, 1)])))
    }

    // MARK: – The joystick's colors, by marks

    @Test func susChordsMoveTheThird() {
        #expect(markedStack(ionian, height: .triad, marks: marks([(.third, 1)])) == [0, 5, 7])     // sus4
        #expect(markedStack(dorian, height: .triad, marks: marks([(.third, -1)])) == [0, 2, 7])    // sus2
        #expect(markedStack(mixolydian, height: .seventh, marks: marks([(.third, 1)])) == [0, 5, 7, 10]) // 7sus4
    }

    @Test func addChordsLeaveOutTheSeventh() {
        #expect(markedStack(ionian, height: .ninth, marks: marks(skips: [.seventh])) == [0, 4, 7, 14])  // add9
        #expect(markedStack(ionian, height: .ninth, marks: marks([(.seventh, -1)])) == [0, 4, 7, 10, 14])       // maj9 with ♭7: 9
    }

    @Test func alteredDominants() {
        #expect(markedStack(mixolydian, height: .ninth, marks: marks([(.ninth, -1)])) == [0, 4, 7, 10, 13])          // 7♭9
        #expect(markedStack(mixolydian, height: .ninth, marks: marks([(.ninth, 1)])) == [0, 4, 7, 10, 15])           // 7♯9
        #expect(markedStack(mixolydian, height: .ninth, marks: marks([(.fifth, 1), (.ninth, 1)])) == [0, 4, 8, 10, 15]) // 7alt
        #expect(markedStack(ionian, height: .triad, marks: marks([(.fifth, 1)])) == [0, 4, 8])                       // aug
        #expect(markedStack(dorian, height: .seventh, marks: marks([(.seventh, 1)])) == [0, 3, 7, 11])               // m(maj7)
    }

    @Test func sixthsLowerTheSeventh() {
        #expect(markedStack(mixolydian, height: .seventh, marks: marks([(.seventh, -1)])) == [0, 4, 7, 9])       // 6
        #expect(markedStack(mixolydian, height: .ninth, marks: marks([(.seventh, -1)])) == [0, 4, 7, 9, 14])     // 6/9
    }

    @Test func aDroppedToneIsBroughtBack() {
        #expect(droppedTones(ionian, height: .eleventh) == [.third])
        #expect(droppedTones(ionian, height: .thirteenth) == [.eleventh])
        #expect(droppedTones(dorian, height: .eleventh).isEmpty)
        let add11 = marks(skips: [.third, .seventh, .ninth])
        #expect(markedStack(ionian, height: .eleventh, marks: add11) == [0, 4, 7, 17])
        #expect(markNames(ionian, height: .eleventh, marks: add11) == ["add 3", "no 7", "no 9"])
        #expect(markedStack(lydian, height: .eleventh, marks: marks(skips: [.ninth])) == [0, 4, 7, 11, 18])       // maj7♯11
    }

    // MARK: – Moves that cannot be made

    @Test func aMoveOntoAnotherToneIsNotMade() {
        // Ionian's 7th raised would be the root; Lydian's 11th raised its 5th.
        #expect(markedStack(ionian, height: .seventh, marks: marks([(.seventh, 1)])) == [0, 4, 7, 11])
        #expect(markedStack(lydian, height: .eleventh, marks: marks([(.eleventh, 1)])) == [0, 4, 7, 11, 14, 18])
        // Dorian's 3rd raised frees its pitch class for the 9th raised: tones
        // move from the 3rd up, so both moves are made.
        let both = marks([(.third, 1), (.ninth, 1)])
        #expect(markedStack(dorian, height: .ninth, marks: both) == [0, 4, 7, 10, 15])
    }

    @Test func aMarkTwiceTakesItOff() {
        var marks = ToneMarks()
        marks.toggleMove(.fifth, by: 1)
        marks.toggleMove(.fifth, by: 1)
        #expect(marks.isEmpty)
        marks.toggleMove(.fifth, by: 1)
        marks.toggleMove(.fifth, by: -1)
        #expect(marks.move(of: .fifth) == -1)
        marks.toggleSkip(.ninth)
        marks.toggleSkip(.ninth)
        #expect(marks.move(of: .fifth) == -1 && !marks.skips(.ninth))
    }

    @Test func aMarkSetIsWhateverItIsSetTo() {
        var marks = ToneMarks()
        marks.setMove(.ninth, to: 1)
        marks.setMove(.ninth, to: -1)
        #expect(marks.move(of: .ninth) == -1)
        marks.setMove(.ninth, to: 0)
        marks.setSkip(.seventh, true)
        marks.setSkip(.seventh, true)
        #expect(marks.skips(.seventh))
        marks.setSkip(.seventh, false)
        #expect(marks.isEmpty)
    }

    // MARK: – Names

    @Test func namesAddTheMarksInBrackets() {
        #expect(markedChordName(.mixolydian, height: .ninth, marks: marks([(.fifth, 1), (.ninth, 1)])) == "9(♯5, ♯9)")
        #expect(markedChordName(.ionian, height: .triad, marks: marks([(.third, 1)])) == "maj(sus4)")
        #expect(markedChordName(.mixolydian, height: .seventh, marks: marks([(.seventh, -1)])) == "7(6)")
        #expect(chordLabel(key: cMajor, spec: ChordSpec(degree: .V, color: .marked(.ninth, nil, marks([(.ninth, -1)])))) == "G 9(♭9)")
    }

    @Test func theMarkedColorPlaysItsNotes() {
        let spec = ChordSpec(degree: .V, color: .marked(.ninth, nil, marks([(.fifth, 1), (.ninth, 1)])))
        #expect(computeVoicing(key: cMajor, spec: spec, inversion: .root, octave: 4,
                               voiceLeading: false, previousVoicing: nil).notes == [67, 71, 75, 77, 82])
    }

    // MARK: – Options

    @Test func optionsSayWhatEachToneCanDo() {
        let options = toneMarkOptions(ionian, height: .seventh, marks: .none)
        let third = options.first { $0.tone == .third }!
        #expect(third.up == "sus4" && third.down == "♭3")
        let seventh = options.first { $0.tone == .seventh }!
        #expect(seventh.up == nil && seventh.down == "♭7")
        let ninth = options.first { $0.tone == .ninth }!
        #expect(!ninth.isInStack && ninth.up == nil)

        let eleventh = toneMarkOptions(ionian, height: .eleventh, marks: .none).first { $0.tone == .third }!
        #expect(eleventh.isDroppedByStack && eleventh.isLeftOut && eleventh.up == nil)
    }
}
