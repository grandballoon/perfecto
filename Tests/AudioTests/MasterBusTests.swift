import AudioKit
import Testing
@testable import Perfecto

/// Runs the real `MasterBus` in an engine that renders offline: a tone goes
/// in, quiet or far too loud, and what comes out is measured.
@Suite("MasterBus", .serialized)
@MainActor
struct MasterBusTests {

    private let tone = OfflineTone()

    /// `source` added to itself `times` over, as loops add to what is played.
    private func layered(_ source: Node, times: Int) -> [Node] {
        (0..<times).map { _ in Mixer(source) }
    }

    /// Renders `layers` of the tone through a master bus.
    private func render(layers: Int) -> (output: [Float], rate: Double) {
        tone.render { MasterBus(layered($0, times: layers)).output }
    }

    /// The frame the tone first comes out at. The tone starts from zero, so
    /// this is its second frame.
    private func arrival(_ output: [Float]) -> Int {
        output.firstIndex { abs($0) > 1e-4 } ?? output.count
    }

    /// The tone is half of full scale: well inside what the output carries.
    @Test func aSoundTheOutputCanCarryPassesThroughUnchanged() {
        let (output, rate) = render(layers: 1)
        let arrived = arrival(output)
        var worst: Float = 0
        for frame in 1..<Int(OfflineTone.toneSeconds * rate) - arrived {
            worst = max(worst, abs(output[arrived + frame - 1] - tone.sample(frame, rate: rate)))
        }
        #expect(worst < 1e-3)
    }

    /// The limiter looks ahead by its attack time and no further: that is
    /// all the delay the master bus adds between a touch and its sound.
    @Test func itDelaysTheSoundByNoMoreThanItsAttack() {
        let (output, rate) = render(layers: 1)
        let attackFrames = Double(MasterBus.attack) * rate
        #expect(Double(arrival(output)) <= attackFrames + 2)
    }

    /// Four layers of the tone are twice full scale, as several loops under
    /// a dense chord can be.
    @Test func aSoundTooLoudForTheOutputIsHeldUnderFullScale() {
        let (output, _) = render(layers: 4)
        #expect(loudest(output[...]) <= 1)
        // Held under, not turned right down.
        #expect(loudest(output[...]) > 0.8)
    }

    /// Without the master bus the same sound is twice what the output carries.
    @Test func theSameSoundWouldOtherwiseClip() {
        let (output, _) = tone.render { Mixer(layered($0, times: 4)) }
        #expect(loudest(output[...]) > 1.9)
    }
}
