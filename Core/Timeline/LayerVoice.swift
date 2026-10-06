/// One layer's voice: its chords go through an arpeggiator of its own to a
/// sink of its own, so a layer is arpeggiated as its notes say, whatever
/// the keys and the other layers are doing.
@MainActor
final class LayerVoice: TimelineVoice {

    private let arpeggiator: Arpeggiator
    private let onChord: (TimedChord?) -> Void

    /// - Parameter onChord: told each chord as it starts, and nil when the
    ///   voice falls silent.
    init(sink: any ChordEventSink, clock: any ClockTickable, onChord: @escaping (TimedChord?) -> Void = { _ in }) {
        arpeggiator = Arpeggiator(downstream: sink, clock: clock)
        self.onChord = onChord
    }

    func play(_ chord: TimedChord) {
        if arpeggiator.settings != chord.effects.arpeggiator {
            // New settings re-sound a held chord; the one being replaced
            // must not be heard again first.
            arpeggiator.stopChord()
            arpeggiator.settings = chord.effects.arpeggiator
        }
        arpeggiator.playChord(chord.event)
        onChord(chord)
    }

    func stop() {
        arpeggiator.stopChord()
        onChord(nil)
    }
}
