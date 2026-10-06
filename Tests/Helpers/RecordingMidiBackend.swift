@testable import Perfecto

/// Recording double for MidiBackend. Captures the messages sent instead of
/// touching CoreMIDI. Use in MidiSink tests to assert exact note sequences.
@MainActor
final class RecordingMidiBackend: MidiBackend {

    struct Call: Equatable {
        enum Kind: Equatable { case noteOn, noteOff, controlChange }
        let kind: Kind
        /// The controller number, for a control change.
        let note: UInt8
        /// The controller's value, for a control change.
        let velocity: UInt8
        let channel: UInt8
    }

    private(set) var calls: [Call] = []

    var noteOnCalls:  [Call] { calls.filter { $0.kind == .noteOn  } }
    var noteOffCalls: [Call] { calls.filter { $0.kind == .noteOff } }
    var controlChangeCalls: [Call] { calls.filter { $0.kind == .controlChange } }

    func sendNoteOn(note: UInt8, velocity: UInt8, channel: UInt8) {
        calls.append(Call(kind: .noteOn,  note: note, velocity: velocity, channel: channel))
    }

    func sendNoteOff(note: UInt8, velocity: UInt8, channel: UInt8) {
        calls.append(Call(kind: .noteOff, note: note, velocity: velocity, channel: channel))
    }

    func sendControlChange(controller: UInt8, value: UInt8, channel: UInt8) {
        calls.append(Call(kind: .controlChange, note: controller, velocity: value, channel: channel))
    }

    func reset() { calls = [] }
}
