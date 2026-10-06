import AudioKit
import SoundpipeAudioKit

/// The low-pass filter every synth voice passes through on the way to the
/// speaker.
///
/// Off, it is bypassed and the sound passes through untouched.
final class BrightnessFilter {

    /// The node to send on.
    var output: Node { filter }

    private let filter: LowPassButterworthFilter
    private var cutoff: AUValue

    /// Cutoffs from dark to fully open, in Hz.
    private static let cutoffs: ClosedRange<AUValue> = 300...20_000
    /// Seconds a change of brightness takes: long enough that a sliding
    /// finger is heard as a sweep and not as steps.
    private static let glide: Float = 0.03

    init(_ input: Node) {
        cutoff = Self.cutoffs.upperBound
        filter = LowPassButterworthFilter(input, cutoffFrequency: cutoff)
        apply(FilterSettings())
    }

    /// Glides to `settings`' brightness.
    func apply(_ settings: FilterSettings) {
        cutoff = Self.cutoffs.exponential(at: settings.brightness)
        filter.$cutoffFrequency.ramp(to: cutoff, duration: Self.glide)
        if settings.isOn { filter.start() } else { filter.bypass() }
    }

    /// Ends any glide at once. Called as a note starts, so the note begins
    /// at the brightness asked for and not on the way to it.
    func settle() {
        filter.cutoffFrequency = cutoff
    }
}
