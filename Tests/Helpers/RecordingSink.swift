@testable import Perfecto

/// Recording double for ChordEventSink. Captures calls instead of driving audio/MIDI.
/// Use in mode tests to assert what voicings were played or stopped.
@MainActor
final class RecordingSink: ChordEventSink {

    struct Call: Equatable {
        enum Kind: Equatable { case play, stop }
        let kind: Kind
        let voicing: Voicing
    }

    private(set) var calls: [Call] = []

    var playCalls: [Voicing] { calls.compactMap { $0.kind == .play  ? $0.voicing : nil } }
    var stopCalls: [Voicing] { calls.compactMap { $0.kind == .stop  ? $0.voicing : nil } }
    var lastPlay:  Voicing?  { playCalls.last }

    func playChord(_ voicing: Voicing) {
        calls.append(Call(kind: .play, voicing: voicing))
    }

    func stopChord() {
        // stopChord has no voicing on the protocol; record a sentinel with empty notes
        calls.append(Call(kind: .stop, voicing: Voicing(notes: [])))
    }

    func reset() { calls = [] }
}
