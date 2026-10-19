import Testing
@testable import MusicTheoryCore

@Suite("ChordWire")
struct ChordWireTests {

    private let announcement = ChordAnnouncement(
        key: Key(root: .C, scale: .major),
        degree: .I,
        joystickMode: .default,
        joystickDirection: .right,
        inversion: .root,
        octave: 4,
        voiceLeading: false,
        voicing: Voicing(notes: [60, 64, 67, 71])
    )

    // MARK: – Golden frames (shared with Harmonicland's chordwire.test.ts —
    // if these bytes change, the protocol version must bump)

    @Test func goldenChordFrame_CmajI_maj7() {
        #expect(ChordWire.encodeChord(announcement) == [
            0xF0, 0x7D, 0x50, 0x46, 0x01,   // header: SysEx, non-commercial, 'P', 'F', v1
            0x01,                           // type: chord
            0, 0, 1, 0, 3, 0, 4, 0,         // C, major, I, default, right, root, octave 4, no VL
            0, 0,                           // no bass note
            4, 60, 64, 67, 71,              // Cmaj7 voicing
            0xF7,
        ])
    }

    @Test func goldenReleaseFrame() {
        #expect(ChordWire.encodeRelease() == [0xF0, 0x7D, 0x50, 0x46, 0x01, 0x02, 0xF7])
    }

    // MARK: – Round-trips

    @Test func chordRoundTrip() {
        #expect(ChordWire.decode(ChordWire.encodeChord(announcement)) == .chord(announcement))
    }

    @Test func releaseRoundTrip() {
        #expect(ChordWire.decode(ChordWire.encodeRelease()) == .release)
    }

    @Test func roundTripCoversEveryScaleModeDirectionAndInversion() {
        for scale in ScaleType.allCases {
            for mode in ChordWire.modeOrder {
                for direction in ChordWire.directionOrder {
                    for inversion in ChordWire.inversionOrder {
                        let a = ChordAnnouncement(
                            key: Key(root: .Fs, scale: scale),
                            degree: .V,
                            joystickMode: mode,
                            joystickDirection: direction,
                            inversion: inversion,
                            octave: 3,
                            voiceLeading: true,
                            voicing: Voicing(notes: [54, 58, 61], bassNote: 42)
                        )
                        #expect(ChordWire.decode(ChordWire.encodeChord(a)) == .chord(a))
                    }
                }
            }
        }
    }

    @Test func bassNoteSurvivesRoundTrip() {
        let a = ChordAnnouncement(
            key: Key(root: .A, scale: .naturalMinor),
            degree: .iii,
            joystickMode: .extended,
            joystickDirection: .downLeft,
            inversion: .second,
            octave: 5,
            voiceLeading: true,
            voicing: Voicing(notes: [72, 76, 79], bassNote: 45)
        )
        #expect(ChordWire.decode(ChordWire.encodeChord(a)) == .chord(a))
    }

    // MARK: – Inversions a frame cannot state

    private static let cMajor = Key(root: .C, scale: .major)
    private static let triad = ChordSpec(degree: .I, color: .joystick(.default, .center))

    @Test func anInversionAFrameHasIsStatedAsItIs() {
        for inversion in ChordWire.inversionOrder {
            let stated = ChordWire.stated(inversion, octave: 4, key: Self.cMajor, spec: Self.triad)
            #expect(stated?.inversion == inversion)
            #expect(stated?.octave == 4)
        }
    }

    /// A chord rolled past the second inversion, or down, is stated as the
    /// inversion and octave that have the same notes.
    @Test func aChordRolledFurtherIsStatedByTheSameNotesInAnotherOctave() {
        for steps in [-4, -1, 3, 5, 8] {
            let rolled = Inversion(steps: steps)
            guard let stated = ChordWire.stated(rolled, octave: 4, key: Self.cMajor, spec: Self.triad) else {
                Issue.record("\(steps) steps was not stated")
                continue
            }
            #expect(ChordWire.inversionOrder.contains(stated.inversion))
            func notes(_ inversion: Inversion, _ octave: Int) -> [Int] {
                computeVoicing(key: Self.cMajor, spec: Self.triad, inversion: inversion, octave: octave,
                               voiceLeading: false, previousVoicing: nil).notes
            }
            #expect(notes(stated.inversion, stated.octave) == notes(rolled, 4))
        }
        let down = ChordWire.stated(Inversion(steps: -1), octave: 4, key: Self.cMajor, spec: Self.triad)
        #expect(down?.inversion == .second)
        #expect(down?.octave == 3)
    }

    /// A four-note chord's third inversion is none of the three a frame has.
    @Test func aThirdInversionCannotBeStated() {
        let maj7 = ChordSpec(degree: .I, color: .joystick(.default, .right))
        #expect(ChordWire.stated(Inversion(steps: 3), octave: 4, key: Self.cMajor, spec: maj7) == nil)
    }

    // MARK: – 7-bit safety

    @Test func outOfRangeNotesAreClampedBelowSysExStatusRange() {
        let a = ChordAnnouncement(
            key: Key(root: .C, scale: .major),
            degree: .I,
            joystickMode: .default,
            joystickDirection: .center,
            inversion: .root,
            octave: 4,
            voiceLeading: false,
            voicing: Voicing(notes: [-3, 200])
        )
        let bytes = ChordWire.encodeChord(a)
        // Every byte between the F0/F7 frame markers must stay below 0x80.
        #expect(bytes.dropFirst().dropLast().allSatisfy { $0 < 0x80 })
    }

    // MARK: – Rejection of malformed input

    @Test func rejectsForeignAndMalformedFrames() {
        let good = ChordWire.encodeChord(announcement)
        #expect(ChordWire.decode([]) == nil)
        #expect(ChordWire.decode([0xF0, 0x7D, 0xF7]) == nil)                    // too short
        #expect(ChordWire.decode([0xF0, 0x43, 0x50, 0x46, 0x01, 0x02, 0xF7]) == nil) // foreign mfr
        #expect(ChordWire.decode([0xF0, 0x7D, 0x50, 0x46, 0x02, 0x02, 0xF7]) == nil) // future version
        #expect(ChordWire.decode(Array(good.dropLast())) == nil)                // truncated
        #expect(ChordWire.decode(Array(good.dropLast(2)) + [0xF7]) == nil)      // note count mismatch
        var badDegree = good
        badDegree[8] = 9                                                        // degree out of range
        #expect(ChordWire.decode(badDegree) == nil)
        var badOctave = good
        badOctave[12] = 9                                                       // octave out of range
        #expect(ChordWire.decode(badOctave) == nil)
        var unsorted = good
        unsorted.swapAt(17, 18)                                                 // notes not ascending
        #expect(ChordWire.decode(unsorted) == nil)
    }

    // MARK: – Wire tables stay exhaustive

    @Test func wireTablesCoverEveryCase() {
        // Each table lists every case exactly once, so encoding never traps
        // and no two cases share a wire number.
        func coversEveryCase<T: CaseIterable & Hashable>(_ table: [T]) -> Bool {
            table.count == Set(table).count && Set(table) == Set(T.allCases)
        }
        #expect(coversEveryCase(ChordWire.scaleOrder))
        #expect(coversEveryCase(ChordWire.degreeOrder))
        #expect(coversEveryCase(ChordWire.modeOrder))
        #expect(coversEveryCase(ChordWire.directionOrder))
    }
}
