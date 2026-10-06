import AudioKit
import Testing
@testable import Perfecto

/// Runs the real `BrightnessFilter` in an engine that renders offline: a
/// tone high in the range the filter sweeps goes in, and what comes out is
/// measured.
@Suite("BrightnessFilter", .serialized)
@MainActor
struct BrightnessFilterTests {

    private let tone = OfflineTone(frequency: 3000)

    /// How loud the tone comes out with the filter at `settings`, once the
    /// filter has settled.
    private func level(_ settings: FilterSettings) -> Float {
        let (output, rate) = tone.render { source in
            let filter = BrightnessFilter(Mixer(source))
            filter.apply(settings)
            filter.settle()
            return filter.output
        }
        return loudest(output[Int(0.2 * rate)..<Int(OfflineTone.toneSeconds * rate)])
    }

    @Test func offTheSoundPassesThroughUnchanged() {
        let (output, rate) = tone.render { BrightnessFilter(Mixer($0)).output }
        #expect(tone.distance(from: output, rate: rate) < 1e-3)
    }

    /// Switching the filter off takes all of it out, however dark it is set.
    @Test func switchedOffItIsSilentWhateverItsBrightness() {
        #expect(level(FilterSettings(isOn: false, brightness: 0)) > 0.49)
    }

    @Test func fullyBrightLetsTheTopEndThrough() {
        #expect(level(FilterSettings(isOn: true, brightness: 1)) > 0.45)
    }

    @Test func darkTakesTheTopEndOut() {
        #expect(level(FilterSettings(isOn: true, brightness: 0)) < 0.02)
    }

    @Test func brightnessOpensTheFilterStepByStep() {
        let levels = [0, 0.5, 1].map { level(FilterSettings(isOn: true, brightness: $0)) }
        #expect(levels == levels.sorted())
        #expect(levels[1] > levels[0] * 4 && levels[2] > levels[1] * 1.05)
    }
}
