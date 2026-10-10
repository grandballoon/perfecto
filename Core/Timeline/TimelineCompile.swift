/// What is chosen now: the key, octave, sound and effects a note follows
/// wherever it has none of its own.
struct LiveSettings: Equatable, Sendable {
    var key: Key
    var octave: Int
    var preset: SynthPreset
    var effects: NoteEffects
}

/// One chord of a layer as it is played: when it starts and ends, the event
/// to send, and the sound to send it with.
struct TimedChord: Equatable {
    /// Ticks from the start of the timeline.
    var start: Int
    var end: Int
    var event: ChordEvent
    var preset: SynthPreset
    var effects: NoteEffects
    /// A slide played inside the note: the effects at ticks after `start`.
    var changes: [SoundChange]
}

extension Timeline {

    /// The layer `id` as it is played: its notes inside the stretch that
    /// repeats, in order, each with its key, octave, sound and effects
    /// settled (its own, or the live one). A note that runs past the end of
    /// that stretch is cut there.
    ///
    /// Playback and the MIDI export both read this, so what is exported is
    /// what is heard. A muted layer still compiles: muting is the player's.
    func compile(layer id: Layer.ID, live: LiveSettings) -> [TimedChord] {
        guard let layer = layer(id) else { return [] }
        let range = playedRange
        var previous: Voicing?
        return layer.notes.compactMap { note in
            guard range.contains(note.start) else { return nil }
            let context = performanceContext(key: note.playing.key ?? live.key,
                                             octave: note.playing.octave ?? live.octave,
                                             spec: note.chord)
            let chord = context.voicing(after: previous)
            previous = chord
            let voicing: Voicing
            switch note.pitch {
            case .chord: voicing = chord
            case .lead:  voicing = Voicing(notes: [leadPitch(key: context.key, octave: context.octave,
                                                              degree: note.chord.degree)])
            case .notes(let notes): voicing = Voicing(notes: notes)
            }
            let end = min(note.end, range.upperBound)
            return TimedChord(
                start: note.start,
                end: end,
                event: ChordEvent(voicing: voicing, articulation: note.articulation, context: context),
                preset: note.playing.preset ?? live.preset,
                effects: note.playing.effects ?? live.effects,
                changes: note.changes.filter { note.start + $0.offset < end })
        }
    }
}
