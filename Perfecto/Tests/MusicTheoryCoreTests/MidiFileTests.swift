import Testing
@testable import MusicTheoryCore

@Suite("MidiFile")
struct MidiFileTests {

    @Test func variableLengthQuantityMatchesTheSpecExamples() {
        // Examples from the Standard MIDI File 1.0 spec.
        #expect(variableLengthQuantity(0x00) == [0x00])
        #expect(variableLengthQuantity(0x40) == [0x40])
        #expect(variableLengthQuantity(0x7F) == [0x7F])
        #expect(variableLengthQuantity(0x80) == [0x81, 0x00])
        #expect(variableLengthQuantity(0x2000) == [0xC0, 0x00])
        #expect(variableLengthQuantity(0x3FFF) == [0xFF, 0x7F])
        #expect(variableLengthQuantity(0x4000) == [0x81, 0x80, 0x00])
        #expect(variableLengthQuantity(0x0FFF_FFFF) == [0xFF, 0xFF, 0xFF, 0x7F])
    }

    @Test func singleTrackFileIsFormatZeroWithExactBytes() {
        let file = MidiFile(ticksPerQuarter: 480, tracks: [
            MidiTrack(events: [
                MidiEvent(tick: 0,   .noteOn(channel: 0, note: 60, velocity: 100)),
                MidiEvent(tick: 120, .noteOff(channel: 0, note: 60)),
            ], length: 480),
        ])
        #expect(file.encoded() == [
            0x4D, 0x54, 0x68, 0x64,  0, 0, 0, 6,  0, 0,  0, 1,  0x01, 0xE0,  // MThd
            0x4D, 0x54, 0x72, 0x6B,  0, 0, 0, 13,                            // MTrk
            0x00, 0x90, 60, 100,
            0x78, 0x80, 60, 0,
            0x82, 0x68, 0xFF, 0x2F, 0x00,   // end of track 360 ticks later
        ])
    }

    @Test func severalTracksAreFormatOne() {
        let track = MidiTrack(events: [])
        let bytes = MidiFile(ticksPerQuarter: 96, tracks: [track, track]).encoded()
        #expect(Array(bytes[8..<12]) == [0, 1, 0, 2])
    }

    @Test func eventsAreSortedMetaThenNoteOffThenNoteOnWithinATick() {
        // Deliberately shuffled input: a retrigger of the same pitch at tick 0
        // must release before re-striking, and tempo must precede both.
        let track = MidiTrack(events: [
            MidiEvent(tick: 0, .noteOn(channel: 0, note: 64, velocity: 100)),
            MidiEvent(tick: 0, .noteOff(channel: 0, note: 64)),
            MidiEvent(tick: 0, .tempo(bpm: 120)),
        ])
        #expect(track.encodedBody() == [
            0x00, 0xFF, 0x51, 0x03, 0x07, 0xA1, 0x20,   // 500 000 µs per quarter
            0x00, 0x80, 64, 0,
            0x00, 0x90, 64, 100,
            0x00, 0xFF, 0x2F, 0x00,
        ])
    }

    @Test func metaEventsEncodeTheirPayloads() {
        #expect(MidiEvent.Kind.timeSignature(numerator: 4, denominator: 4).encoded()
                == [0xFF, 0x58, 0x04, 4, 2, 24, 8])
        #expect(MidiEvent.Kind.timeSignature(numerator: 6, denominator: 8).encoded()
                == [0xFF, 0x58, 0x04, 6, 3, 24, 8])
        #expect(MidiEvent.Kind.keySignature(MidiKeySignature(sharps: -3, isMinor: true)).encoded()
                == [0xFF, 0x59, 0x02, 0xFD, 1])
        #expect(MidiEvent.Kind.trackName("Perfecto").encoded()
                == [0xFF, 0x03, 8] + Array("Perfecto".utf8))
        #expect(MidiEvent.Kind.marker("C#m7").encoded()
                == [0xFF, 0x06, 4] + Array("C#m7".utf8))
    }

    @Test func noteDataIsClampedToSevenBits() {
        #expect(MidiEvent.Kind.noteOn(channel: 0, note: 200, velocity: 300).encoded()
                == [0x90, 127, 127])
        #expect(MidiEvent.Kind.noteOff(channel: 0, note: -5).encoded() == [0x80, 0, 0])
    }

    @Test func trackLengthNeverCutsOffALaterEvent() {
        let track = MidiTrack(events: [MidiEvent(tick: 10, .marker(""))], length: 5)
        #expect(track.encodedBody().suffix(4) == [0x00, 0xFF, 0x2F, 0x00])
    }

    @Test(arguments: [
        (PitchClass.C,  ScaleType.major,         0,  false),
        (PitchClass.G,  ScaleType.major,         1,  false),
        (PitchClass.F,  ScaleType.major,         -1, false),
        (PitchClass.Fs, ScaleType.major,         6,  false),
        (PitchClass.Cs, ScaleType.major,         -5, false),  // spelled D♭
        (PitchClass.As, ScaleType.major,         -2, false),  // spelled B♭
        (PitchClass.A,  ScaleType.naturalMinor,  0,  true),
        (PitchClass.E,  ScaleType.harmonicMinor, 1,  true),
        (PitchClass.C,  ScaleType.minorPentatonic, -3, true),
        (PitchClass.D,  ScaleType.dorian,        -1, true),   // D minor
        (PitchClass.G,  ScaleType.mixolydian,    1,  false),  // G major
        (PitchClass.F,  ScaleType.lydian,        -1, false),  // F major
        (PitchClass.A,  ScaleType.blues,         0,  true),
    ])
    func keySignatureUsesTheMajorOrMinorKeyOnTheSameTonic(
        root: PitchClass, scale: ScaleType, sharps: Int, isMinor: Bool
    ) {
        #expect(Key(root: root, scale: scale).midiKeySignature
                == MidiKeySignature(sharps: sharps, isMinor: isMinor))
    }
}
