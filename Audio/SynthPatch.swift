/// What one synth sound is made of, as plain data: `SynthVoice` realizes it,
/// `SynthPreset` names the ones the app ships. Every voice has the same fixed
/// signal path, and a patch only says which parts sound and how:
///
///     oscillators ─┐
///                  ├─→ low-pass filter ─→ amplitude envelope
///     FM pair ─────┘
struct SynthPatch: Equatable, Sendable {

    enum Wave: Equatable, Sendable {
        case sine, triangle, square, sawtooth
        /// A pulse that is high for `width` (0...1) of each cycle.
        case pulse(width: Float)
        /// Sine partials, the fundamental first, each at the given strength.
        case harmonics([Float])
    }

    /// A value that moves from `from` to `to` over `time` seconds after each
    /// note starts, then stays there.
    struct Sweep: Equatable, Sendable {
        var from: Float
        var to: Float
        var time: Float

        static func steady(_ value: Float) -> Sweep {
            Sweep(from: value, to: value, time: 0)
        }
    }

    struct Oscillator: Equatable, Sendable {
        var wave: Wave
        /// Strength relative to the patch's other sources.
        var level: Float = 1
        /// Tuning away from the played note.
        var octave: Int = 0
        var detuneCents: Float = 0
    }

    /// A sine carrier whose frequency a sine modulator bends. `index` is the
    /// modulation depth: sweeping it down gives the bright attack and mellow
    /// tail of struck and plucked sounds.
    struct FM: Equatable, Sendable {
        /// Carrier and modulator frequencies, as multiples of the played note.
        var carrier: Float = 1
        var modulator: Float
        var index: Sweep
        var level: Float = 1
    }

    struct Filter: Equatable, Sendable {
        /// Cutoff as a multiple of the played note's frequency, so a patch is
        /// equally bright in every octave.
        var cutoff: Sweep
        /// 0 (none) up to 1 (ringing).
        var resonance: Float = 0
    }

    struct Envelope: Equatable, Sendable {
        var attack: Float
        var decay: Float
        var sustain: Float
        var release: Float
    }

    /// The most oscillators a patch may use; a voice has this many.
    static let oscillatorCount = 2

    var oscillators: [Oscillator] = []
    var fm: FM? = nil
    /// nil leaves the sources unfiltered.
    var filter: Filter? = nil
    var envelope: Envelope
    /// One note's output level. Notes add, and the `MasterBus` holds the sum under full scale.
    var level: Float
}
