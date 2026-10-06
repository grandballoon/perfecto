/// Everything needed to render a sequence offline: the timeline, the
/// settings its notes follow where they have none of their own, and the tempo.
struct SequencerPattern: Sendable {
    var timeline: Timeline
    var live: LiveSettings
    var bpm: Double

    /// The steps playback runs through before starting again.
    var stepCount: Int { timeline.playedRange.count / TimelineTime.ticksPerStep }
}

/// Renders a sequence to a Standard MIDI File. It reads the same compiled
/// chords playback does (`Timeline.compile`), so the file holds exactly what
/// is heard: the stretch that repeats, once through, each chord from its
/// start to its end.
///
/// Every layer that is not muted is a track. Chord names are written as
/// markers at each change of chord in the first of them. No program change
/// is written, so the importing DAW assigns (and lets you swap) the instrument.
enum SequencerMidiRenderer {
    static let ticksPerQuarter = TimelineTime.ticksPerBeat
    /// Matches `MidiSink`: channel 1, fixed velocity.
    static let channel = 0
    static let velocity = 100

    static func render(_ pattern: SequencerPattern) -> MidiFile {
        let timeline = pattern.timeline
        let range = timeline.playedRange
        let header = [
            MidiEvent(tick: 0, .trackName("Perfecto")),
            MidiEvent(tick: 0, .tempo(bpm: pattern.bpm)),
            MidiEvent(tick: 0, .timeSignature(numerator: timeline.signature.beats,
                                              denominator: timeline.signature.unit.rawValue)),
            MidiEvent(tick: 0, .keySignature(pattern.live.key.midiKeySignature)),
        ]

        let layers = timeline.layers.filter { !$0.isMuted }
        var tracks: [MidiTrack] = []
        for (index, layer) in layers.enumerated() {
            var events = index == 0 ? header : [MidiEvent(tick: 0, .trackName("Perfecto \(index + 1)"))]
            var lastMarker: String?
            for chord in timeline.compile(layer: layer.id, live: pattern.live) {
                let start = chord.start - range.lowerBound
                for note in chord.event.voicing.notes {
                    events.append(MidiEvent(tick: start, .noteOn(channel: channel, note: note, velocity: velocity)))
                    events.append(MidiEvent(tick: chord.end - range.lowerBound, .noteOff(channel: channel, note: note)))
                }
                let label = chordLabel(key: chord.event.context.key, spec: chord.event.context.spec)
                if index == 0, label != lastMarker {
                    events.append(MidiEvent(tick: start, .marker(label)))
                    lastMarker = label
                }
            }
            tracks.append(MidiTrack(events: events, length: range.count))
        }
        if tracks.isEmpty { tracks = [MidiTrack(events: header, length: range.count)] }
        return MidiFile(ticksPerQuarter: ticksPerQuarter, tracks: tracks)
    }
}
