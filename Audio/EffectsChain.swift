import AudioKit
import Darwin
import DunneAudioKit

/// The effects one sound has to itself, on its way to the speaker:
///
///     input ─→ chorus ─┬─→ dry          (to the output)
///                      └─→ reverbSend   (to the shared `SharedReverb`)
///
/// What is being played has one, and so has every loop track, so a loop
/// keeps its own chorus, and its own share of the reverb, whatever is played
/// over it. The reverb itself is shared: there is one room, and each chain
/// says how much of its sound goes into it.
///
/// The path is fixed. An effect that is off still runs, with none of the
/// sound reaching it, so switching one on or off never rewires the graph
/// while the engine runs.
///
/// The reverb's mix is how much of the sound is sent into it, not how much
/// of it is let out: what is already ringing always dies away in its own
/// time, so a mix that is being played, or a reverb switched off, never cuts
/// a tail short.
final class EffectsChain {

    /// The sound that goes straight on: send it to the output.
    var dry: Node { dryMixer }
    /// The sound that goes into the reverb: send it to the shared `SharedReverb`.
    var reverbSend: Node { sendMixer }

    private let chorus: Chorus
    private let dryMixer: Mixer
    private let sendMixer: Mixer

    /// A chorus at full amount is equal parts dry and wavering sound; past
    /// that the dry sound thins out and it turns into vibrato.
    private static let chorusFullMix: AUValue = 0.5
    private static let chorusDepth: AUValue = 0.3
    /// Modulation speeds from a slow drift to a fast shimmer, in Hz.
    private static let chorusRates: ClosedRange<AUValue> = 0.2...5

    init(_ input: Node) {
        chorus = Chorus(input, depth: Self.chorusDepth, feedback: 0)
        dryMixer = Mixer(chorus)
        sendMixer = Mixer(chorus)
        apply(ChorusSettings())
        apply(ReverbSettings())
    }

    func apply(_ effects: SoundEffects) {
        apply(effects.chorus)
        apply(effects.reverb)
    }

    func apply(_ settings: ChorusSettings) {
        chorus.frequency = Self.chorusRates.exponential(at: settings.rate)
        chorus.dryWetMix = settings.isOn ? settings.amount.clamped(to: 0...1) * Self.chorusFullMix : 0
    }

    /// Sets how much of the sound goes to the reverb. The room's size is
    /// the shared `SharedReverb`'s, not this chain's.
    func apply(_ settings: ReverbSettings) {
        let mix = settings.isOn ? settings.mix.clamped(to: 0...1) : 0
        sendMixer.volume = mix
        dryMixer.volume = 1 - mix
    }
}

extension ClosedRange where Bound == AUValue {
    /// The value `amount` (0...1) of the way through the range, placed so
    /// equal steps multiply it by equal amounts, the way speeds, lengths and
    /// pitches are heard.
    func exponential(at amount: Float) -> AUValue {
        lowerBound * pow(upperBound / lowerBound, amount.clamped(to: 0...1))
    }
}
