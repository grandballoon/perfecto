/// Decouples chord-event producers (performance modes) from consumers (audio, MIDI).
/// Both AudioSink and MidiSink implement this protocol and receive the same events.
@MainActor
protocol ChordEventSink: AnyObject {
    func playChord(_ voicing: Voicing)
    func stopChord()
}
