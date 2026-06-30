/// Broadcasts ChordEvents to multiple sinks simultaneously.
/// AudioSink and MidiSink operate independently — neither knows about the other.
@MainActor
final class CompositeSink: ChordEventSink {
    private let sinks: [any ChordEventSink]

    init(_ sinks: [any ChordEventSink]) {
        self.sinks = sinks
    }

    func playChord(_ voicing: Voicing) {
        for sink in sinks { sink.playChord(voicing) }
    }

    func stopChord() {
        for sink in sinks { sink.stopChord() }
    }
}
