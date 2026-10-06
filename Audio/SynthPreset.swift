/// The built-in synth sounds, in the order the Sound panel lists them.
enum SynthPreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case electricPiano, glassKeys, organ, clav
    case sinePad, warmPad, strings
    case pluck, bell, kalimba
    case sawLead, squareLead, brass, synthBass
    /// What was last recorded from the mic, played at each note's pitch.
    case micSample

    /// The kernel's capture the mic sample is recorded into and played from.
    static let micCapture = 0

    enum Category: String, CaseIterable, Identifiable, Sendable {
        case keys, pads, plucked, synth, recorded

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .keys:    return "Keys"
            case .pads:    return "Pads"
            case .plucked: return "Plucked"
            case .synth:   return "Synth"
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
        case .pluck:         return "Pluck"
        case .bell:          return "Bell"
        case .kalimba:       return "Kalimba"
        case .sawLead:       return "Saw Lead"
        case .squareLead:    return "Square Lead"
        case .brass:         return "Brass"
        case .synthBass:     return "Synth Bass"
        case .micSample:     return "Mic Sample"
        }
    }

    var category: Category {
        switch self {
        case .electricPiano, .glassKeys, .organ, .clav:  return .keys
        case .sinePad, .warmPad, .strings:               return .pads
        case .pluck, .bell, .kalimba:                    return .plucked
        case .sawLead, .squareLead, .brass, .synthBass:  return .synth
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
        case .brass:
            // The filter opens as the note speaks, like a brass attack.
            return SynthPatch(
                oscillators: [Osc(wave: .sawtooth),
                              Osc(wave: .sawtooth, detuneCents: 5)],
                filter: .init(cutoff: Sweep(from: 1.5, to: 7, time: 0.09), resonance: 0.2),
                envelope: .init(attack: 0.04, decay: 0.15, sustain: 0.85, release: 0.18),
                level: 0.2)
        case .synthBass:
            return SynthPatch(
                oscillators: [Osc(wave: .sawtooth),
                              Osc(wave: .square, level: 0.7, octave: -1)],
                filter: .init(cutoff: Sweep(from: 10, to: 3, time: 0.2), resonance: 0.4),
                envelope: .init(attack: 0.005, decay: 0.2, sustain: 0.7, release: 0.15),
                level: 0.22)

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
