import AudioKit
import SoundpipeAudioKit

/// The one reverb everything shares: what is being played and every loop
/// track send into it (`EffectsChain.reverbSend`), each as much as its own
/// mix says, and it adds the room to the output.
///
/// One room costs the same however many sounds are in it, and it has one
/// size: the size set now, also for loops closed earlier.
///
/// It lets out everything that reaches it, so what is ringing dies away in
/// its own time whatever happens to the sends.
final class SharedReverb {

    /// The room's sound alone, none of what was sent: send it to the output.
    var output: Node { reverb }

    private let reverb: ZitaReverb

    /// Reverb tails, in seconds to fall 60 dB.
    private static let tails: ClosedRange<AUValue> = 1...8

    init(_ sends: [Node]) {
        reverb = ZitaReverb(Mixer(sends), dryWetMix: 1)
        apply(ReverbSettings())
    }

    /// Sets the room's size. How much of each sound reaches the room is its
    /// own `EffectsChain`'s to say.
    func apply(_ settings: ReverbSettings) {
        let tail = Self.tails.exponential(at: settings.size)
        reverb.midReleaseTime = tail
        reverb.lowReleaseTime = tail
    }
}
