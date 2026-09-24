import Testing
@testable import MusicTheoryCore

@Suite("Voicing")
struct VoicingTests {

    @Test func notesAreSortedAndUnique() {
        #expect(Voicing(notes: [67, 60, 64, 60]).notes == [60, 64, 67])
    }

    @Test func notesAboveTheMidiRangeFoldDownByOctaves() {
        // B major vii add9 at octave 7: A♯ C♯ E♯ and B♯ an octave above the top.
        #expect(Voicing(notes: [118, 122, 125, 132]).notes == [118, 120, 122, 125])
    }

    @Test func notesBelowTheMidiRangeFoldUpByOctaves() {
        #expect(Voicing(notes: [-3, 0, 4]).notes == [0, 4, 9])
    }

    @Test func foldingKeepsPitchClasses() {
        let raw = [100, 115, 129, 140, 151]
        let folded = Voicing(notes: raw).notes
        #expect(folded.allSatisfy(Voicing.midiRange.contains))
        #expect(Set(folded.map { $0 % 12 }) == Set(raw.map { $0 % 12 }))
    }

    @Test func bassNoteIsFoldedToo() {
        #expect(Voicing(notes: [60], bassNote: 130).bassNote == 118)
    }

    @Test func everyComputedVoicingIsInRange() {
        for scale in ScaleType.allCases where scale.isHeptatonic {
            for degree in Degree.allCases {
                for octave in [0, 7, 9] {
                    let v = computeVoicing(key: Key(root: .B, scale: scale),
                                           spec: ChordSpec(degree: degree, color: .joystick(.chromatic, .down)),
                                           inversion: .second, octave: octave,
                                           voiceLeading: false, previousVoicing: nil)
                    #expect(v.notes.allSatisfy(Voicing.midiRange.contains), "\(scale) \(degree) oct \(octave)")
                }
            }
        }
    }
}
