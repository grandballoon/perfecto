@testable import Perfecto

/// Recording double for ChordEventSink. Captures calls instead of driving audio/MIDI.
/// Use in mode tests to assert what was played or stopped.
@MainActor
final class RecordingSink: ChordEventSink {

    enum Call: Equatable {
        case play(ChordEvent)
        case stop
    }

    private(set) var calls: [Call] = []

    var playEvents: [ChordEvent] { calls.compactMap { if case let .play(e) = $0 { e } else { nil } } }
    var playCalls:  [Voicing]    { playEvents.map(\.voicing) }
    var stopCount:  Int          { calls.filter { $0 == .stop }.count }
    var lastPlay:   Voicing?     { playCalls.last }

    func playChord(_ event: ChordEvent) {
        calls.append(.play(event))
    }

    func stopChord() {
        calls.append(.stop)
    }

    func reset() { calls = [] }
}
