import Testing
@testable import Perfecto

@Suite("MidiMessage")
struct MidiMessageTests {

    /// A MIDI 1.0 channel voice message as a Universal MIDI Packet word.
    private func word(_ status: UInt32, _ data1: UInt32, _ data2: UInt32 = 0) -> UInt32 {
        0x2000_0000 | status << 16 | data1 << 8 | data2
    }

    @Test func channelVoiceMessagesAreRead() {
        #expect(MidiMessage(status: 0x90, data1: 60, data2: 100) == .noteOn(channel: 0, note: 60, velocity: 100))
        #expect(MidiMessage(status: 0x89, data1: 36, data2: 64) == .noteOff(channel: 9, note: 36))
        #expect(MidiMessage(status: 0xB0, data1: 20, data2: 127)
                == .controlChange(channel: 0, controller: 20, value: 127))
        #expect(MidiMessage(status: 0xC3, data1: 5, data2: 0) == .programChange(channel: 3, program: 5))
        #expect(MidiMessage(status: 0xD0, data1: 70, data2: 0) == .channelPressure(channel: 0, pressure: 70))
        #expect(MidiMessage(status: 0xA0, data1: 60, data2: 30) == .polyPressure(channel: 0, note: 60, pressure: 30))
    }

    @Test func aNoteOnWithNoVelocityIsANoteOff() {
        #expect(MidiMessage(status: 0x92, data1: 60, data2: 0) == .noteOff(channel: 2, note: 60))
    }

    @Test func thePitchBendIsCenteredOnNothing() {
        #expect(MidiMessage(status: 0xE0, data1: 0x00, data2: 0x40) == .pitchBend(channel: 0, value: 0))
        #expect(MidiMessage(status: 0xE0, data1: 0x00, data2: 0x00) == .pitchBend(channel: 0, value: -8192))
        #expect(MidiMessage(status: 0xE0, data1: 0x7F, data2: 0x7F) == .pitchBend(channel: 0, value: 8191))
    }

    @Test func systemMessagesAreNotChannelVoiceMessages() {
        #expect(MidiMessage(status: 0xF8, data1: 0, data2: 0) == nil)
        #expect(MidiMessage(status: 0xF0, data1: 0x7E, data2: 0) == nil)
    }

    @Test func packetsOfOtherTypesArePassedOverByTheirLength() {
        let words: [UInt32] = [
            word(0x90, 60, 100),
            0x1000_F800,                 // a system message: one word
            0x3016_7E00, 0x0000_0000,    // a SysEx packet: two words
            word(0xB1, 21, 64),
        ]
        #expect(MidiMessage.messages(in: words) == [
            .noteOn(channel: 0, note: 60, velocity: 100),
            .controlChange(channel: 1, controller: 21, value: 64),
        ])
    }

    @Test func aPacketCutShortEndsTheMessages() {
        #expect(MidiMessage.messages(in: [word(0x90, 60, 1), 0x5000_0000, 0]) == [
            .noteOn(channel: 0, note: 60, velocity: 1),
        ])
    }

    @Test func anAddressOnAnyChannelHearsEveryChannel() {
        let knob = MidiAddress.controller(20)
        #expect(knob.matches(.controlChange(channel: 0, controller: 20, value: 1)))
        #expect(knob.matches(.controlChange(channel: 15, controller: 20, value: 1)))
        #expect(!knob.matches(.controlChange(channel: 0, controller: 21, value: 1)))
        #expect(!knob.matches(.noteOn(channel: 0, note: 20, velocity: 1)))
    }

    @Test func anAddressOnOneChannelHearsOnlyIt() {
        let pad = MidiAddress.note(36, channel: 9)
        #expect(pad.matches(.noteOn(channel: 9, note: 36, velocity: 90)))
        #expect(pad.matches(.noteOff(channel: 9, note: 36)))
        #expect(!pad.matches(.noteOn(channel: 0, note: 36, velocity: 90)))
    }

    @Test func aControlLearnsTheAddressOnItsOwnChannel() {
        #expect(MidiAddress(learning: .controlChange(channel: 2, controller: 74, value: 3))
                == .controller(74, channel: 2))
        #expect(MidiAddress(learning: .noteOn(channel: 9, note: 40, velocity: 3)) == .note(40, channel: 9))
        #expect(MidiAddress(learning: .pitchBend(channel: 0, value: 5)) == .pitchBend(channel: 0))
        // A release says nothing a note does not.
        #expect(MidiAddress(learning: .noteOff(channel: 0, note: 40)) == nil)
    }

    @Test func addressesAreNamedWithChannelsFromOne() {
        #expect(MidiAddress.controller(20).label == "CC 20")
        #expect(MidiAddress.note(36, channel: 9).label == "Note 36 · ch 10")
    }
}
