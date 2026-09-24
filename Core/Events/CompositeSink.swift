/// Broadcasts ChordEvents to multiple sinks simultaneously.
/// AudioSink and MidiSink operate independently — neither knows about the other.
@MainActor
final class CompositeSink: ChordEventSink {
    private let sinks: [any ChordEventSink]

    init(_ sinks: [any ChordEventSink]) {
        self.sinks = sinks
    }

    func playChord(_ event: ChordEvent) {
        for sink in sinks { sink.playChord(event) }
    }

    func stopChord() {
        for sink in sinks { sink.stopChord() }
    }
}
