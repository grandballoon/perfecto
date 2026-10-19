/// A message a MIDI controller sends: one of MIDI 1.0's channel voice
/// messages. Channels are numbered from 0, as they are sent; people count
/// them from 1 (`MidiAddress.label`).
///
/// A note-on with no velocity is a note-off, as the standard says, so
/// nothing past the parser has to know that.
enum MidiMessage: Equatable, Sendable {
    case noteOn(channel: Int, note: Int, velocity: Int)
    case noteOff(channel: Int, note: Int)
    case polyPressure(channel: Int, note: Int, pressure: Int)
    case controlChange(channel: Int, controller: Int, value: Int)
    case programChange(channel: Int, program: Int)
    case channelPressure(channel: Int, pressure: Int)
    /// From -8192 to 8191, 0 at rest.
    case pitchBend(channel: Int, value: Int)

    var channel: Int {
        switch self {
        case let .noteOn(channel, _, _), let .noteOff(channel, _),
             let .polyPressure(channel, _, _), let .controlChange(channel, _, _),
             let .programChange(channel, _), let .channelPressure(channel, _),
             let .pitchBend(channel, _):
            return channel
        }
    }

    /// The message of a status byte and its data, or nil for anything that
    /// is not a channel voice message (clock, SysEx and the like).
    init?(status: UInt8, data1: UInt8, data2: UInt8) {
        let channel = Int(status & 0x0F)
        let data1 = Int(data1 & 0x7F), data2 = Int(data2 & 0x7F)
        switch status & 0xF0 {
        case 0x80: self = .noteOff(channel: channel, note: data1)
        case 0x90: self = data2 == 0 ? .noteOff(channel: channel, note: data1)
                                     : .noteOn(channel: channel, note: data1, velocity: data2)
        case 0xA0: self = .polyPressure(channel: channel, note: data1, pressure: data2)
        case 0xB0: self = .controlChange(channel: channel, controller: data1, value: data2)
        case 0xC0: self = .programChange(channel: channel, program: data1)
        case 0xD0: self = .channelPressure(channel: channel, pressure: data1)
        case 0xE0: self = .pitchBend(channel: channel, value: (data2 << 7 | data1) - 8192)
        default:   return nil
        }
    }

    /// The channel voice messages among Universal MIDI Packet `words`, as
    /// CoreMIDI hands them over when a port is opened for MIDI 1.0. Any
    /// other packet is passed over by its length.
    static func messages(in words: some Collection<UInt32>) -> [MidiMessage] {
        var messages: [MidiMessage] = []
        var index = words.startIndex
        while index != words.endIndex {
            let word = words[index]
            let type = Int(word >> 28)
            if type == 0x2, let message = MidiMessage(status: UInt8(truncatingIfNeeded: word >> 16),
                                                      data1: UInt8(truncatingIfNeeded: word >> 8),
                                                      data2: UInt8(truncatingIfNeeded: word)) {
                messages.append(message)
            }
            index = words.index(index, offsetBy: wordsInPacket[type],
                                limitedBy: words.endIndex) ?? words.endIndex
        }
        return messages
    }

    /// How many words a Universal MIDI Packet of each message type has.
    private static let wordsInPacket = [1, 1, 1, 2, 2, 4, 1, 1, 2, 2, 2, 3, 3, 4, 4, 4]
}

/// The messages a control on a MIDI controller sends: a note, a controller
/// number, a program, the pitch bend or the channel's pressure, on one
/// channel or on any.
struct MidiAddress: Hashable, Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        case note, controller, program, pitchBend, channelPressure
    }

    let kind: Kind
    /// The note or controller number; 0 for the kinds that have none. A
    /// program address is any program: a button set to send one is heard
    /// by its channel.
    let number: Int
    /// nil: any channel.
    let channel: Int?

    static func note(_ note: Int, channel: Int? = nil) -> MidiAddress {
        MidiAddress(kind: .note, number: note, channel: channel)
    }

    static func controller(_ number: Int, channel: Int? = nil) -> MidiAddress {
        MidiAddress(kind: .controller, number: number, channel: channel)
    }

    static func pitchBend(channel: Int? = nil) -> MidiAddress {
        MidiAddress(kind: .pitchBend, number: 0, channel: channel)
    }

    /// The address that sent `message`, on its own channel, which is what a
    /// control learns. A note's release and its pressure say nothing a note
    /// does not, so they are not learned.
    init?(learning message: MidiMessage) {
        switch message {
        case let .noteOn(channel, note, _):
            self.init(kind: .note, number: note, channel: channel)
        case let .controlChange(channel, controller, _):
            self.init(kind: .controller, number: controller, channel: channel)
        case let .programChange(channel, _):
            self.init(kind: .program, number: 0, channel: channel)
        case let .pitchBend(channel, _):
            self.init(kind: .pitchBend, number: 0, channel: channel)
        case let .channelPressure(channel, _):
            self.init(kind: .channelPressure, number: 0, channel: channel)
        case .noteOff, .polyPressure:
            return nil
        }
    }

    private init(kind: Kind, number: Int, channel: Int?) {
        self.kind = kind
        self.number = number
        self.channel = channel
    }

    /// Whether `message` is one this address sends.
    func matches(_ message: MidiMessage) -> Bool {
        guard channel == nil || channel == message.channel else { return false }
        switch (kind, message) {
        case let (.note, .noteOn(_, note, _)), let (.note, .noteOff(_, note)),
             let (.note, .polyPressure(_, note, _)):
            return note == number
        case let (.controller, .controlChange(_, controller, _)):
            return controller == number
        case (.program, .programChange), (.pitchBend, .pitchBend),
             (.channelPressure, .channelPressure):
            return true
        default:
            return false
        }
    }

    /// "CC 20", "Note 36 · ch 10": channels counted from 1.
    var label: String {
        let name: String
        switch kind {
        case .note:            name = "Note \(number)"
        case .controller:      name = "CC \(number)"
        case .program:         name = "Program"
        case .pitchBend:       name = "Pitch bend"
        case .channelPressure: name = "Pressure"
        }
        return channel.map { "\(name) · ch \($0 + 1)" } ?? name
    }
}

extension MidiMessage {
    /// What was heard, as a person reads it: "CC 21 · ch 1 = 64".
    var label: String {
        switch self {
        case let .noteOn(channel, note, velocity):
            return "\(MidiAddress.note(note, channel: channel).label) on, velocity \(velocity)"
        case let .noteOff(channel, note):
            return "\(MidiAddress.note(note, channel: channel).label) off"
        case let .polyPressure(channel, note, pressure):
            return "\(MidiAddress.note(note, channel: channel).label) pressure \(pressure)"
        case let .controlChange(channel, controller, value):
            return "\(MidiAddress.controller(controller, channel: channel).label) = \(value)"
        case let .programChange(channel, program):
            return "Program \(program + 1) · ch \(channel + 1)"
        case let .channelPressure(channel, pressure):
            return "Pressure \(pressure) · ch \(channel + 1)"
        case let .pitchBend(channel, value):
            return "\(MidiAddress.pitchBend(channel: channel).label) = \(value)"
        }
    }
}
