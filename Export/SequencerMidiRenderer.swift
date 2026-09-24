/// Everything needed to render a sequencer pattern offline: the steps as
/// playback runs through them plus the key, octave and tempo they sound in.
struct SequencerPattern: Sendable {
    var steps: [SequencerStep]
    var key: Key
    var octave: Int
    var bpm: Double
    /// Sequencer steps per quarter note (the clock's resolution).
    var stepsPerBeat: Int
}

/// Renders a sequencer pattern to a Standard MIDI File — the offline twin of
/// `SequencerMode`, following the same timing rules so the file matches what
/// playback sounds like:
///
///  • each step lasts one clock tick (a 1/16 note at the default resolution);
///  • a chord sounds for `gate` × the step, and a tied step rings until the
///    next step begins;
///  • a tied step followed by the same chord becomes one long note rather than
///    a retrigger — the natural reading of a tie in a DAW's piano roll.
///
/// Chord names are written as markers at each chord change. No program change
/// is written, so the importing DAW assigns (and lets you swap) the instrument.
enum SequencerMidiRenderer {
    static let ticksPerQuarter = 480
    /// Matches `MidiSink`: channel 1, fixed velocity.
    static let channel = 0
    static let velocity = 100

    static func render(_ pattern: SequencerPattern) -> MidiFile {
        let stepTicks = ticksPerQuarter / max(pattern.stepsPerBeat, 1)
        var events: [MidiEvent] = [
            MidiEvent(tick: 0, .trackName("Perfecto")),
            MidiEvent(tick: 0, .tempo(bpm: pattern.bpm)),
            MidiEvent(tick: 0, .timeSignature(numerator: 4, denominator: 4)),
            MidiEvent(tick: 0, .keySignature(pattern.key.midiKeySignature)),
        ]

        /// The chord currently sounding: its notes and whether its step tied.
        var sounding: (notes: [Int], tied: Bool)?
        var previousVoicing: Voicing?
        var lastMarker: String?

        func release(at tick: Int) {
            guard let chord = sounding else { return }
            for note in chord.notes {
                events.append(MidiEvent(tick: tick, .noteOff(channel: channel, note: note)))
            }
            sounding = nil
        }

        for (index, step) in pattern.steps.enumerated() {
            let start = index * stepTicks
            guard !step.isRest else {
                release(at: start)
                continue
            }

            let voicing = performanceVoicing(key: pattern.key,
                                             octave: pattern.octave,
                                             degree: step.degree,
                                             joystickMode: step.joystickMode,
                                             joystickDirection: step.joystickDirection,
                                             previousVoicing: previousVoicing)
            previousVoicing = voicing

            if let chord = sounding, chord.tied, chord.notes == voicing.notes {
                sounding?.tied = step.isTied          // tie continues the held chord
            } else {
                release(at: start)
                for note in voicing.notes {
                    events.append(MidiEvent(tick: start, .noteOn(channel: channel,
                                                                 note: note,
                                                                 velocity: velocity)))
                }
                sounding = (voicing.notes, step.isTied)

                let label = chordLabel(key: pattern.key,
                                       degree: step.degree,
                                       joystickMode: step.joystickMode,
                                       joystickDirection: step.joystickDirection)
                if label != lastMarker {
                    events.append(MidiEvent(tick: start, .marker(label)))
                    lastMarker = label
                }
            }

            if !step.isTied {
                let held = Int((step.gate * Double(stepTicks)).rounded())
                release(at: start + min(max(held, 1), stepTicks))
            }
        }

        let length = pattern.steps.count * stepTicks
        release(at: length)
        return MidiFile(ticksPerQuarter: ticksPerQuarter,
                        tracks: [MidiTrack(events: events, length: length)])
    }
}
