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
    }

    // MARK: – Wire tables stay exhaustive

    @Test func wireTablesCoverEveryCase() {
        #expect(ChordWire.scaleOrder.count == ScaleType.allCases.count)
        #expect(Set(ChordWire.scaleOrder).count == ChordWire.scaleOrder.count)
        #expect(ChordWire.modeOrder.count == 3)
        #expect(ChordWire.directionOrder.count == 9)
        #expect(ChordWire.inversionOrder.count == 3)
    }
}
