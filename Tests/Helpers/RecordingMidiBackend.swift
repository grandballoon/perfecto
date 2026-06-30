@testable import Perfecto

/// Recording double for MidiBackend. Captures sendNoteOn/sendNoteOff calls instead of
/// touching CoreMIDI. Use in MidiSink tests to assert exact note sequences.
@MainActor
final class RecordingMidiBackend: MidiBackend {

    struct Call: Equatable {
        enum Kind: Equatable { case noteOn, noteOff }
        let kind: Kind
        let note: UInt8
        let velocity: UInt8
        let channel: UInt8
    }

    private(set) var calls: [Call] = []

    var noteOnCalls:  [Call] { calls.filter { $0.kind == .noteOn  } }
    var noteOffCalls: [Call] { calls.filter { $0.kind == .noteOff } }

    func sendNoteOn(note: UInt8, velocity: UInt8, channel: UInt8) {
        calls.append(Call(kind: .noteOn,  note: note, velocity: velocity, channel: channel))
    }

    func sendNoteOff(note: UInt8, velocity: UInt8, channel: UInt8) {
        calls.append(Call(kind: .noteOff, note: note, velocity: velocity, channel: channel))
    }

    func reset() { calls = [] }
}
