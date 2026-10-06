import AudioKit
import Testing
@testable import Perfecto

/// Runs the real `EffectsChain`, sending into a real `SharedReverb`, in an engine
/// that renders offline: a short tone goes in, then silence, and what comes
/// out is measured.
@Suite("EffectsChain", .serialized)
@MainActor
struct EffectsChainTests {

    private let tone = OfflineTone()

    /// The reverb fades its output in over its first moments after being
    /// made, so comparisons with the tone start once that has passed.
    private static let settleSeconds = 0.3

    /// A chain and the reverb it sends into, as they are wired to the output.
    private func wire(_ source: Node) -> (chain: EffectsChain, reverb: SharedReverb, output: Node) {
        let chain = EffectsChain(Mixer(source))
        let reverb = SharedReverb([chain.reverbSend])
        return (chain, reverb, Mixer(chain.dry, reverb.output))
    }

    /// Renders the tone through a chain and reverb set up by `configure`,
    /// returning the first channel and the sample rate.
    private func render(_ configure: (EffectsChain, SharedReverb) -> Void) -> (output: [Float], rate: Double) {
        tone.render { source in
            let wired = wire(source)
            configure(wired.chain, wired.reverb)
            return wired.output
        }
    }

    /// The furthest `output` strays from the tone while the tone plays.
    private func distanceFromTone(_ output: [Float], rate: Double) -> Float {
        tone.distance(from: output, rate: rate, after: Self.settleSeconds)
    }

    /// The part of the render well after the tone has ended.
    private func tail(_ output: [Float], rate: Double) -> ArraySlice<Float> {
        output[Int((OfflineTone.toneSeconds + 0.2) * rate)...]
    }

    @Test func withEverythingOffTheSoundPassesThroughUnchanged() {
        let (output, rate) = render { _, _ in }
        #expect(distanceFromTone(output, rate: rate) < 1e-3)
        #expect(loudest(tail(output, rate: rate)) < 1e-4)
    }

    @Test func reverbRingsOnAfterTheSoundEnds() {
        let (output, rate) = render { chain, _ in chain.apply(ReverbSettings(isOn: true, mix: 0.5, size: 0.5)) }
        #expect(loudest(tail(output, rate: rate)) > 0.01)
    }

    /// The mix is what goes into the reverb, so taking it away (a finger
    /// lifting from a played mix, or the reverb being switched off) leaves
    /// what is already ringing to die away.
    @Test func aTailRingsOnAfterTheMixIsTakenAway() {
        let wet = ReverbSettings(isOn: true, mix: 0.5, size: 0.5)
        for after in [ReverbSettings(isOn: true, mix: 0, size: 0.5), ReverbSettings(isOn: false)] {
            var chain: EffectsChain?
            let (output, rate) = tone.render(through: { source in
                let wired = wire(source)
                wired.chain.apply(wet)
                chain = wired.chain
                return wired.output
            }, afterTone: { chain?.apply(after) })
            #expect(loudest(tail(output, rate: rate)) > 0.01, "\(after)")
        }
    }

    @Test func chorusChangesTheSoundWhileItPlays() {
        let (output, rate) = render { chain, _ in chain.apply(ChorusSettings(isOn: true, amount: 1, rate: 0.5)) }
        #expect(distanceFromTone(output, rate: rate) > 0.05)
        #expect(loudest(tail(output, rate: rate)) < 1e-4)
    }

    /// Switching an effect off takes all of it out, whatever its amount.
    @Test func anEffectSwitchedOffIsSilentWhateverItsAmount() {
        let (output, rate) = render { chain, _ in
            chain.apply(ChorusSettings(isOn: false, amount: 1, rate: 1))
            chain.apply(ReverbSettings(isOn: false, mix: 1, size: 1))
        }
        #expect(distanceFromTone(output, rate: rate) < 1e-3)
        #expect(loudest(tail(output, rate: rate)) < 1e-4)
    }

    /// The room's size is the reverb's, whatever each sound sends into it.
    @Test func aBiggerRoomRingsForLonger() {
        func tailLevel(size: Float) -> Float {
            let settings = ReverbSettings(isOn: true, mix: 0.5, size: size)
            let (output, rate) = render { chain, reverb in
                chain.apply(settings)
                reverb.apply(settings)
            }
            return loudest(output[Int((OfflineTone.toneSeconds + 0.7) * rate)...])
        }
        #expect(tailLevel(size: 1) > 2 * tailLevel(size: 0))
    }
}
