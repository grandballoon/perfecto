/// The built-in synth sounds, in the order the Sound panel lists them.
enum SynthPreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case electricPiano, glassKeys, organ, clav
    case sinePad, warmPad, strings, pulsePad, sweepPad
    case pluck, bell, kalimba, marimba
    case sawLead, squareLead, soloLead, driveLead, flute, superSaw, polySynth, brass, stab, crunch
    case synthBass, subBass, fmBass, reeseBass, wobbleBass, acidBass
    /// What was last recorded from the mic, played at each note's pitch.
    case micSample

    /// The kernel's capture the mic sample is recorded into and played from.
    static let micCapture = 0

    enum Category: String, CaseIterable, Identifiable, Sendable {
        case keys, pads, plucked, synth, bass, recorded

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .keys:    return "Keys"
            case .pads:    return "Pads"
            case .plucked: return "Plucked"
            case .synth:   return "Synth"
            case .bass:    return "Bass"
            case .recorded: return "Recorded"
            }
        }

        var presets: [SynthPreset] { SynthPreset.allCases.filter { $0.category == self } }
    }

    /// The sound the app starts with.
    static let initial = SynthPreset.sinePad

    var id: String { rawValue }

    var name: String {
        switch self {
        case .electricPiano: return "Electric Piano"
        case .glassKeys:     return "Glass Keys"
        case .organ:         return "Organ"
        case .clav:          return "Clav"
        case .sinePad:       return "Sine Pad"
        case .warmPad:       return "Warm Pad"
        case .strings:       return "Strings"
        case .pulsePad:      return "Pulse Pad"
        case .sweepPad:      return "Sweep Pad"
        case .pluck:         return "Pluck"
        case .bell:          return "Bell"
        case .kalimba:       return "Kalimba"
        case .marimba:       return "Marimba"
        case .sawLead:       return "Saw Lead"
        case .squareLead:    return "Square Lead"
        case .soloLead:      return "Solo Lead"
        case .driveLead:     return "Drive Lead"
        case .flute:         return "Flute"
        case .superSaw:      return "Supersaw"
        case .polySynth:     return "Poly Synth"
        case .brass:         return "Brass"
        case .stab:          return "Stab"
        case .crunch:        return "Crunch"
        case .synthBass:     return "Synth Bass"
        case .subBass:       return "Sub Bass"
        case .fmBass:        return "FM Bass"
        case .reeseBass:     return "Reese Bass"
        case .wobbleBass:    return "Wobble Bass"
        case .acidBass:      return "Acid Bass"
        case .micSample:     return "Mic Sample"
        }
    }

    var category: Category {
        switch self {
        case .electricPiano, .glassKeys, .organ, .clav:  return .keys
        case .sinePad, .warmPad, .strings, .pulsePad, .sweepPad:
                                                         return .pads
        case .pluck, .bell, .kalimba, .marimba:          return .plucked
        case .sawLead, .squareLead, .soloLead, .driveLead, .flute, .superSaw, .polySynth, .brass, .stab,
             .crunch:
                                                         return .synth
        case .synthBass, .subBass, .fmBass, .reeseBass, .wobbleBass, .acidBass:
                                                         return .bass
        case .micSample:                                 return .recorded
        }
    }

    var patch: SynthPatch {
        typealias Osc = SynthPatch.Oscillator
        typealias Sweep = SynthPatch.Sweep
        switch self {

        // Keys

        case .electricPiano:
            // The modulator's bite fades into a near-sine tail, like a tine.
            return SynthPatch(
                fm: .init(modulator: 1, index: Sweep(from: 2.2, to: 0.5, time: 0.35)),
                envelope: .init(attack: 0.004, decay: 1.2, sustain: 0.25, release: 0.35),
                level: 0.28)
        case .glassKeys:
            return SynthPatch(
                fm: .init(modulator: 4, index: Sweep(from: 1.5, to: 0.3, time: 0.5)),
                envelope: .init(attack: 0.004, decay: 0.9, sustain: 0.2, release: 0.6),
                level: 0.22)
        case .organ:
            // Drawbar-style partials; no decay, like a held organ key.
            return SynthPatch(
                oscillators: [Osc(wave: .harmonics([1, 0.8, 0.5, 0.35, 0, 0.25, 0, 0.2]))],
                envelope: .init(attack: 0.008, decay: 0.05, sustain: 1, release: 0.08),
                level: 0.16)
        case .clav:
            return SynthPatch(
                oscillators: [Osc(wave: .pulse(width: 0.2))],
                filter: .init(cutoff: Sweep(from: 16, to: 5, time: 0.12), resonance: 0.5),
                envelope: .init(attack: 0.003, decay: 0.5, sustain: 0.1, release: 0.12),
                level: 0.25)

        // Pads

        case .sinePad:
            return SynthPatch(
                oscillators: [Osc(wave: .sine)],
                envelope: .init(attack: 0.08, decay: 0.08, sustain: 0.75, release: 0.35),
                level: 0.25)
        case .warmPad:
            return SynthPatch(
                oscillators: [Osc(wave: .sawtooth, detuneCents: -5),
                              Osc(wave: .sawtooth, detuneCents: 5)],
                filter: .init(cutoff: Sweep(from: 3, to: 6, time: 0.6), resonance: 0.2),
                envelope: .init(attack: 0.35, decay: 0.3, sustain: 0.8, release: 0.9),
                level: 0.2)
        case .strings:
            return SynthPatch(
                oscillators: [Osc(wave: .sawtooth, detuneCents: -7),
                              Osc(wave: .sawtooth, detuneCents: 7)],
                filter: .init(cutoff: .steady(8), resonance: 0.1),
                envelope: .init(attack: 0.18, decay: 0.2, sustain: 0.85, release: 0.5),
                level: 0.18)
        case .pulsePad:
            // A pulse whose width never rests, so one oscillator is heard
            // as several drifting against each other, over a steady square
            // an octave down.
            return SynthPatch(
                oscillators: [Osc(wave: .pulse(width: 0.5)),
                              Osc(wave: .square, level: 0.4, octave: -1)],
                driftCents: 4,
                filter: .init(cutoff: .steady(7), resonance: 0.15),
                lfo: .init(rate: 0.45, pulseWidth: 0.38),
                envelope: .init(attack: 0.25, decay: 0.3, sustain: 0.85, release: 0.8),
                level: 0.18)
        case .sweepPad:
            // The filter opens slowly over the held chord, ringing at its
            // cutoff, so each partial is heard in turn as it passes.
            return SynthPatch(
                oscillators: [Osc(wave: .sawtooth, detuneCents: -6),
                              Osc(wave: .sawtooth, detuneCents: 6)],
                driftCents: 4,
                filter: .init(cutoff: Sweep(from: 1.5, to: 10, time: 2.5), resonance: 0.6),
                envelope: .init(attack: 0.4, decay: 0.3, sustain: 0.85, release: 1.2),
                level: 0.16)

        // Plucked

        case .pluck:
            return SynthPatch(
                oscillators: [Osc(wave: .sawtooth)],
                filter: .init(cutoff: Sweep(from: 12, to: 2, time: 0.18), resonance: 0.25),
                envelope: .init(attack: 0.003, decay: 0.35, sustain: 0, release: 0.35),
                level: 0.3)
        case .bell:
            // A non-integer modulator gives the clangorous, inharmonic partials.
            return SynthPatch(
                fm: .init(modulator: 3.5, index: Sweep(from: 4, to: 1, time: 1)),
                envelope: .init(attack: 0.003, decay: 1.8, sustain: 0, release: 1.8),
                level: 0.22)
        case .kalimba:
            return SynthPatch(
                fm: .init(modulator: 5, index: Sweep(from: 1.6, to: 0, time: 0.15)),
                envelope: .init(attack: 0.002, decay: 0.7, sustain: 0, release: 0.7),
                level: 0.3)
        case .marimba:
            // A knock that is gone at once, and a plain, short tone under it.
            return SynthPatch(
                fm: .init(modulator: 4, index: Sweep(from: 1.8, to: 0, time: 0.06)),
                envelope: .init(attack: 0.002, decay: 0.4, sustain: 0, release: 0.4),
                level: 0.3)

        // Synth

        case .sawLead:
            return SynthPatch(
                oscillators: [Osc(wave: .sawtooth)],
                filter: .init(cutoff: .steady(10), resonance: 0.3),
                envelope: .init(attack: 0.01, decay: 0.1, sustain: 0.8, release: 0.3),
                level: 0.2)
        case .squareLead:
            return SynthPatch(
                oscillators: [Osc(wave: .square)],
                filter: .init(cutoff: .steady(8)),
                envelope: .init(attack: 0.01, decay: 0.1, sustain: 0.8, release: 0.2),
                level: 0.18)
        case .soloLead:
            // A vibrato that waits for the note to be held, as a player's
            // does: a run is in tune and a long note sings.
            return SynthPatch(
                oscillators: [Osc(wave: .sawtooth),
                              Osc(wave: .pulse(width: 0.3), level: 0.6)],
                glide: 0.04,
                filter: .init(cutoff: .steady(9), resonance: 0.3),
                lfo: .init(rate: 5.5, rise: 0.45, pitchCents: 16),
                envelope: .init(attack: 0.01, decay: 0.15, sustain: 0.8, release: 0.25),
                level: 0.2)
        case .driveLead:
            // Pushed hard after its filter, so it is flattened and sings
            // on: an overdriven amplifier's sound, gliding between notes.
            return SynthPatch(
                oscillators: [Osc(wave: .sawtooth),
                              Osc(wave: .square, level: 0.6, detuneCents: 6)],
                glide: 0.05,
                filter: .init(cutoff: .steady(6), resonance: 0.35),
                drive: 0.7,
                lfo: .init(rate: 5.5, rise: 0.5, pitchCents: 12),
                envelope: .init(attack: 0.008, decay: 0.2, sustain: 0.9, release: 0.25),
                level: 0.16)
        case .flute:
            // A breath at the start of each note and a little air after
            // it, over a tone with little but its fundamental; the vibrato
            // comes once the note is held.
            return SynthPatch(
                oscillators: [Osc(wave: .triangle),
                              Osc(wave: .sine, level: 0.5)],
                noise: Sweep(from: 0.3, to: 0.04, time: 0.12),
                filter: .init(cutoff: Sweep(from: 3, to: 6, time: 0.08), resonance: 0.1),
                lfo: .init(rate: 5, rise: 0.6, pitchCents: 9),
                envelope: .init(attack: 0.05, decay: 0.2, sustain: 0.85, release: 0.15),
                level: 0.26)
        case .superSaw:
            // Seven saws spread a fifth of a semitone either side of the
            // note: one key is a whole section, wide and always moving.
            return SynthPatch(
                oscillators: [Osc(wave: .sawtooth)],
                unison: .init(voices: 7, spreadCents: 20),
                filter: .init(cutoff: .steady(12), resonance: 0.1, isSteep: false),
                envelope: .init(attack: 0.01, decay: 0.2, sustain: 0.85, release: 0.35),
                level: 0.2)
        case .polySynth:
            // A saw and a pulse that each wander a little, so no two notes
            // of a chord are tuned quite alike and the chord is never
            // still, under a filter that closes a little after each attack.
            return SynthPatch(
                oscillators: [Osc(wave: .sawtooth),
                              Osc(wave: .pulse(width: 0.4), level: 0.8)],
                driftCents: 7,
                filter: .init(cutoff: Sweep(from: 9, to: 5, time: 0.4), resonance: 0.25),
                envelope: .init(attack: 0.008, decay: 0.4, sustain: 0.75, release: 0.4),
                level: 0.2)
        case .brass:
            // The filter opens as the note speaks, like a brass attack.
            return SynthPatch(
                oscillators: [Osc(wave: .sawtooth),
                              Osc(wave: .sawtooth, detuneCents: 5)],
                filter: .init(cutoff: Sweep(from: 1.5, to: 7, time: 0.09), resonance: 0.2),
                envelope: .init(attack: 0.04, decay: 0.15, sustain: 0.85, release: 0.18),
                level: 0.2)
        case .stab:
            // Two saws a fifth apart, so one key is already a chord, shut
            // off quickly by the filter.
            return SynthPatch(
                oscillators: [Osc(wave: .sawtooth),
                              Osc(wave: .sawtooth, level: 0.8, detuneCents: 700)],
                filter: .init(cutoff: Sweep(from: 14, to: 3, time: 0.12), resonance: 0.3),
                envelope: .init(attack: 0.003, decay: 0.25, sustain: 0, release: 0.2),
                level: 0.22)
        case .crunch:
            // A saw an octave down and well out of tune with the one above:
            // low enough that each cycle is heard, which is the grain, and
            // the two beat. The filter is the brighter one, left wide open.
            return SynthPatch(
                oscillators: [Osc(wave: .sawtooth),
                              Osc(wave: .sawtooth, octave: -1, detuneCents: 18)],
                filter: .init(cutoff: .steady(16), resonance: 0.1, isSteep: false),
                envelope: .init(attack: 0.005, decay: 0.3, sustain: 0.85, release: 0.12),
                level: 0.2)

        // Bass

        case .synthBass:
            return SynthPatch(
                oscillators: [Osc(wave: .sawtooth),
                              Osc(wave: .square, level: 0.7, octave: -1)],
                filter: .init(cutoff: Sweep(from: 10, to: 3, time: 0.2), resonance: 0.4),
                envelope: .init(attack: 0.005, decay: 0.2, sustain: 0.7, release: 0.15),
                level: 0.22)
        case .subBass:
            // Nearly a sine, an octave down: felt more than heard.
            return SynthPatch(
                oscillators: [Osc(wave: .sine, octave: -1),
                              Osc(wave: .triangle, level: 0.3)],
                envelope: .init(attack: 0.008, decay: 0.2, sustain: 0.9, release: 0.12),
                level: 0.28)
        case .fmBass:
            // A short, hard burst from the modulator, an octave over the
            // carrier, and a hollow tone after it.
            return SynthPatch(
                fm: .init(carrier: 0.5, modulator: 1, index: Sweep(from: 3, to: 0.4, time: 0.1)),
                envelope: .init(attack: 0.003, decay: 0.35, sustain: 0.5, release: 0.1),
                level: 0.28)
        case .reeseBass:
            // Two low saws far enough apart to beat slowly against each
            // other, under a dark filter.
            return SynthPatch(
                oscillators: [Osc(wave: .sawtooth, octave: -1, detuneCents: -14),
                              Osc(wave: .sawtooth, octave: -1, detuneCents: 14)],
                filter: .init(cutoff: .steady(5), resonance: 0.15),
                envelope: .init(attack: 0.01, decay: 0.2, sustain: 1, release: 0.15),
                level: 0.22)
        case .wobbleBass:
            // The filter opens and closes three times a second, ringing
            // at its cutoff as it goes.
            return SynthPatch(
                oscillators: [Osc(wave: .sawtooth),
                              Osc(wave: .square, level: 0.7, octave: -1)],
                filter: .init(cutoff: .steady(5), resonance: 0.55),
                lfo: .init(rate: 3, cutoffOctaves: 1.8),
                envelope: .init(attack: 0.005, decay: 0.2, sustain: 0.85, release: 0.15),
                level: 0.2)
        case .acidBass:
            // A saw under a filter that rings hard and snaps shut after
            // each note, pushed a little, sliding from note to note.
            return SynthPatch(
                oscillators: [Osc(wave: .sawtooth, octave: -1)],
                glide: 0.06,
                filter: .init(cutoff: Sweep(from: 16, to: 3, time: 0.18), resonance: 0.85),
                drive: 0.4,
                envelope: .init(attack: 0.003, decay: 0.3, sustain: 0.6, release: 0.1),
                level: 0.18)

        // Recorded

        case .micSample:
            // Held, it plays to its end; let go, it dies away quickly.
            return SynthPatch(
                sample: .init(capture: Self.micCapture),
                envelope: .init(attack: 0.002, decay: 0.1, sustain: 1, release: 0.12),
                level: 0.25)
        }
    }
}
