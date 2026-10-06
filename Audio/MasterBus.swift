import AudioKit

/// The last thing every sound passes through on its way to the speaker: all
/// of them added together, then a limiter.
///
/// Voices, loop tracks and the reverb simply add, so a dense chord over a
/// few loops can ask for more than the output can carry, and what it cannot
/// carry it clips. The limiter turns the whole mix down for as long as it
/// would, and leaves everything quieter than that untouched.
///
/// To turn a peak down before it arrives the limiter has to see it coming,
/// so everything is heard later by its attack time.
final class MasterBus {

    /// The node to make the engine's output.
    var output: Node { limiter }

    private let limiter: PeakLimiter

    /// Seconds the limiter looks ahead, and so delays the sound: the
    /// shortest it offers.
    static let attack: AUValue = 0.001
    /// Seconds it takes to let go once the peak has passed: its longest,
    /// which is the least audible.
    private static let release: AUValue = 0.04

    init(_ inputs: [Node]) {
        limiter = PeakLimiter(Mixer(inputs), attackTime: Self.attack, decayTime: Self.release, preGain: 0)
    }
}
