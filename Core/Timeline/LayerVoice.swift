/// One layer's voice: its chords go through an arpeggiator of its own to a
/// sink of its own, so a layer is arpeggiated as its notes say, and heard in
/// the sound and effects they say, whatever the keys and the other layers
/// are doing. A slide recorded inside a chord is played back as it was
/// made: the effects change at the same moments after the chord starts.
@MainActor
final class LayerVoice: TimelineVoice {

    private let arpeggiator: Arpeggiator
    private let sound: (any SoundControl)?
    private let clock: any ClockTickable
    private let onChord: (TimedChord?) -> Void
    /// The changes of a slide still to come in the chord sounding.
    private var slide: [ClockCall] = []

    /// - Parameter sound: sets the sound of the notes `sink` starts; nil
    ///   for a sink with no sound to set.
    /// - Parameter onChord: told each chord as it starts, and nil when the
    ///   voice falls silent.
    init(sink: any ChordEventSink, sound: (any SoundControl)? = nil, clock: any ClockTickable,
         onChord: @escaping (TimedChord?) -> Void = { _ in }) {
        arpeggiator = Arpeggiator(downstream: sink, clock: clock)
        self.sound = sound
        self.clock = clock
        self.onChord = onChord
    }

    func play(_ chord: TimedChord) {
        endSlide()
        // The chord before keeps its sound to its end; this one's is its own.
        sound?.startNotes(in: NoteSound(preset: chord.preset, effects: chord.effects))
        for change in chord.changes {
            let beats = Double(change.offset) / Double(TimelineTime.ticksPerBeat)
            slide.append(clock.after(beats: beats) { [weak self] in
                self?.sound?.sound = NoteSound(preset: chord.preset, effects: change.effects)
            })
        }
        if arpeggiator.settings != chord.effects.arpeggiator {
            // New settings re-sound a held chord; the one being replaced
            // must not be heard again first.
            arpeggiator.stopChord()
            arpeggiator.settings = chord.effects.arpeggiator
        }
        arpeggiator.playChord(chord.event)
        onChord(chord)
    }

    /// The effects were edited under the chord sounding: its notes glide to
    /// them. What was left of a slide recorded in it is not played this
    /// time round, since it would undo the edit.
    func change(to chord: TimedChord) {
        endSlide()
        sound?.sound = NoteSound(preset: chord.preset, effects: chord.effects)
        arpeggiator.settings = chord.effects.arpeggiator
    }

    func stop() {
        endSlide()
        arpeggiator.stopChord()
        onChord(nil)
    }

    private func endSlide() {
        for call in slide { call.cancel() }
        slide = []
    }
}
