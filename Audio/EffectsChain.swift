import AudioKit
import Darwin
import DunneAudioKit
import SoundpipeAudioKit

/// The effects one sound passes through on its way to the speaker:
///
///     input ─→ chorus ─┬─────────────→ dry ─┬─→ output
///                      └─→ send ─→ reverb ──┘
///
/// What is being played has one, and so has every loop track, so a loop
/// keeps its own effects whatever is played over it.
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

    /// The node to send on to the engine's output.
    let output: Node

    private let chorus: Chorus
    private let dry: Mixer
    private let send: Mixer
    private let reverb: ZitaReverb

    /// A chorus at full amount is equal parts dry and wavering sound; past
    /// that the dry sound thins out and it turns into vibrato.
    private static let chorusFullMix: AUValue = 0.5
    private static let chorusDepth: AUValue = 0.3
    /// Modulation speeds from a slow drift to a fast shimmer, in Hz.
    private static let chorusRates: ClosedRange<AUValue> = 0.2...5
    /// Reverb tails, in seconds to fall 60 dB.
    private static let reverbTails: ClosedRange<AUValue> = 1...8

    init(_ input: Node) {
        chorus = Chorus(input, depth: Self.chorusDepth, feedback: 0)
        dry = Mixer(chorus)
        send = Mixer(chorus)
        reverb = ZitaReverb(send, dryWetMix: 1)
        output = Mixer([dry, reverb])
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

    func apply(_ settings: ReverbSettings) {
        let tail = Self.reverbTails.exponential(at: settings.size)
        reverb.midReleaseTime = tail
        reverb.lowReleaseTime = tail
        let mix = settings.isOn ? settings.mix.clamped(to: 0...1) : 0
        send.volume = mix
        dry.volume = 1 - mix
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
