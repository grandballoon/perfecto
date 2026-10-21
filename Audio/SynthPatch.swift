/// What one sound is made of, as plain data: the kernel realizes it
/// (`kernelPatch`), `SynthPreset` names the ones the app has. Every voice
/// has the same fixed signal path, and a patch only says which parts sound
/// and how:
///
///     oscillators ─┐
///     FM pair ─────┼─→ low-pass filter ─→ amplitude envelope
///     a recording ─┘
///
/// with noise beside the sources, and a drive after the filter;
///
/// and an LFO that moves the pitch, the pulses' width and the filter. The
/// oscillators or the FM pair can be several copies of themselves (`unison`)
/// and can wander from their pitch (`driftCents`).
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
        /// Whether the top falls away at 24 dB an octave, the rounder
        /// filter the presets were made on, or at 12, which is brighter.
        var isSteep = true
    }

    /// Several copies of the oscillators or the FM pair sounding at once,
    /// tuned evenly from `spreadCents` under the note to as far over it and
    /// together as loud as one: the wide, beating sound of many players on
    /// one note.
    struct Unison: Equatable, Sendable {
        /// How many copies, up to `SynthPatch.unisonLimit`.
        var voices: Int
        var spreadCents: Float
    }

    /// A slow sine that moves the sound for as long as a note sounds. It
    /// starts with each note, from nothing, and comes up to its full depth
    /// over `rise` seconds, so a vibrato can wait for a note to be held.
    /// Each depth is how far it moves one thing either way.
    struct LFO: Equatable, Sendable {
        /// Cycles a second.
        var rate: Float
        var rise: Float = 0
        /// Vibrato: the pitch of the oscillators or the FM pair.
        var pitchCents: Float = 0
        /// The width of every pulse wave, as a share of its cycle.
        var pulseWidth: Float = 0
        /// The filter's cutoff.
        var cutoffOctaves: Float = 0
    }

    struct Envelope: Equatable, Sendable {
        var attack: Float
        var decay: Float
        var sustain: Float
        var release: Float
    }

    /// A recording played as the sound, in place of oscillators: one of the
    /// kernel's captures, heard as it was recorded at the note `root` and
    /// faster or slower at every other.
    struct Sample: Equatable, Sendable {
        var capture: Int
        var root: Int = 60
    }

    /// The most oscillators a patch may use; a voice has this many.
    static let oscillatorCount = 2
    /// The most copies a unison may have.
    static let unisonLimit = 7

    var oscillators: [Oscillator] = []
    var fm: FM? = nil
    /// A recording to play. With one, the oscillators and the FM pair are
    /// not heard.
    var sample: Sample? = nil
    /// Sine partials at whole multiples of the note's pitch, the
    /// fundamental first, each as strong as given (times `level`), in place
    /// of the oscillators and the FM pair: a sound whose partials can each
    /// be set apart while a note sounds (`PartialSink`). Unlike a wave of
    /// harmonics it is not scaled to peak at the level.
    var partials: [Float]? = nil
    /// Noise beside the sources, as loud as this share of `level`: swept
    /// down it is the breath at the start of a blown note, and steady it is
    /// air in the sound. nil is none.
    var noise: Sweep? = nil
    /// nil is the sources once each.
    var unison: Unison? = nil
    /// How far each oscillator wanders either side of its pitch, slowly
    /// and differently for every note, as an analog synth's do: no two
    /// notes are tuned quite alike, and two oscillators beat unevenly. An
    /// FM pair wanders as one.
    var driftCents: Float = 0
    /// Seconds a note takes over most of the way to its pitch from the
    /// pitch of the note before, when it follows that note with no gap
    /// (each note of a chord from the nearest note of the last chord).
    /// 0 is every note at its own pitch from the start.
    var glide: Float = 0
    /// nil leaves the sources unfiltered.
    var filter: Filter? = nil
    /// How hard the sound is pushed into a soft limit after the filter,
    /// from 0 (not at all) to 1: it flattens and grows partials, and stays
    /// about as loud.
    var drive: Float = 0
    /// nil leaves a held note as it is.
    var lfo: LFO? = nil
    var envelope: Envelope
    /// One note's output level. Notes add, and the kernel's limiter holds the sum under full scale.
    var level: Float
}
