import Foundation
import PerfectoKernel
import Testing

/// The vocoder: notes shaped by the voice at the input.
struct VocoderTests {

    private static let rate = KernelRig.sampleRate
    private let settled = 24_000..<48_000

    private static func tone(_ hz: Double, level: Float = 0.3) -> (Int) -> Float {
        { level * Float(sin(2 * Double.pi * hz * Double($0) / rate)) }
    }

    /// Noise with something in every band, as a voice has, the same every run.
    private static func hiss(level: Float = 0.3) -> (Int) -> Float {
        { frame in
            var x = UInt64(truncatingIfNeeded: frame) &* 0x9E37_79B9_7F4A_7C15
            x ^= x >> 31
            x = x &* 0xBF58_476D_1CE4_E5B9
            x ^= x >> 29
            return level * (Float(x >> 40) / Float(1 << 23) - 1)
        }
    }

    /// Something like a voice held on one pitch: partials of 150 Hz up to
    /// 4 kHz, each quieter than the one below, peaking near `level`.
    private static func voice(level: Float = 0.3) -> (Int) -> Float {
        { frame in
            var sample = 0.0
            for partial in 1...26 {
                sample += sin(2 * Double.pi * 150 * Double(partial) * Double(frame) / rate) / Double(partial)
            }
            return level * Float(sample / 1.85)
        }
    }

    /// A low sawtooth held: a carrier with a partial in every band.
    private func rig(vocoder: Float, on: Bool, input: ((Int) -> Float)?) -> KernelRig {
        let rig = KernelRig()
        rig.setSound(0, .wave(PerfectoWaveSawtooth, level: 0.3))
        rig.setVocoder(on)
        rig.input = input
        rig.noteOn(1, note: 45, vocoder: vocoder)
        return rig
    }

    @Test func whileItIsOffANoteSentToItIsHeardWhole() {
        let sent = rig(vocoder: 1, on: false, input: Self.hiss())
        let plain = rig(vocoder: 0, on: false, input: Self.hiss())
        sent.render(48_000)
        plain.render(48_000)
        #expect(sent.output == plain.output)
    }

    @Test func withNothingToHearANoteSentToItIsHeardWhole() {
        let sent = rig(vocoder: 1, on: true, input: nil)
        let plain = rig(vocoder: 0, on: true, input: nil)
        sent.render(48_000)
        plain.render(48_000)
        #expect(sent.output == plain.output)
    }

    @Test func underASilentVoiceWhatIsSentToItIsNotHeard() {
        let all = rig(vocoder: 1, on: true, input: { _ in 0 })
        let half = rig(vocoder: 0.5, on: true, input: { _ in 0 })
        let none = rig(vocoder: 0, on: true, input: { _ in 0 })
        for rig in [all, half, none] { rig.render(48_000) }
        #expect(all.loudest(settled) == 0)
        #expect(abs(half.power(settled) / none.power(settled) - 0.5) < 0.01)
    }

    @Test(arguments: [(1000.0, 990.0, 2970.0), (3000.0, 2970.0, 990.0)])
    func theNotesAreHeardWhereTheVoiceIs(voice: Double, near: Double, far: Double) {
        // Partials of the note (110 Hz) near the voice's pitch come
        // through; those far from it are held back, far more than they are
        // in the note itself.
        let plain = rig(vocoder: 0, on: true, input: Self.tone(voice))
        let shaped = rig(vocoder: 1, on: true, input: Self.tone(voice))
        plain.render(48_000)
        shaped.render(48_000)
        let before = plain.strength(of: near, in: settled) / plain.strength(of: far, in: settled)
        let after = shaped.strength(of: near, in: settled) / shaped.strength(of: far, in: settled)
        #expect(after > before * 30)
        #expect(shaped.strength(of: near, in: settled) > 0.2 * plain.strength(of: near, in: settled))
    }

    @Test func underAVoiceCloseToTheMicTheNotesAreAboutAsLoudAsTheyWere() {
        let plain = rig(vocoder: 0, on: true, input: Self.voice())
        let shaped = rig(vocoder: 1, on: true, input: Self.voice())
        plain.render(48_000)
        shaped.render(48_000)
        let ratio = shaped.power(settled) / plain.power(settled)
        #expect((0.5...2).contains(ratio), "\(ratio)")
    }

    @Test func theNotesStopWhenTheVoiceDoes() {
        let hiss = Self.hiss()
        let rig = rig(vocoder: 1, on: true, input: { $0 < 24_000 ? hiss($0) : 0 })
        rig.render(48_000)
        let during = rig.power(12_000..<24_000)
        #expect(during > 0.01)
        #expect(rig.power(28_800..<33_600) < during * 0.01)
        // And they come back with it at once: 10 ms in, they are there.
        let again = self.rig(vocoder: 1, on: true, input: { $0 >= 24_000 ? hiss($0) : 0 })
        again.render(48_000)
        #expect(again.power(24_480..<28_800) > during * 0.5)
    }

    @Test func aNoteCanBeMovedIntoTheVocoderWhileItSounds() {
        let rig = rig(vocoder: 0, on: true, input: { _ in 0 })
        rig.noteChange(1, vocoder: 1, at: 24_000)
        rig.render(48_000)
        #expect(rig.loudest(12_000..<24_000) > 0.2)
        #expect(rig.loudest(36_000..<48_000) < 0.001)
        // Glided there, not cut.
        #expect(rig.biggestStep(23_900..<26_000) <= rig.biggestStep(12_000..<23_900))
    }

    @Test func whatTheVocoderPutsOutCanBeRecorded() {
        let rig = rig(vocoder: 1, on: true, input: Self.tone(1000))
        rig.captureStart(1, of: PerfectoCaptureVocoder, at: 9600)
        rig.captureStop(at: 33_600)
        rig.render(48_000)
        let captured = rig.captured(1)
        #expect(captured.count == 24_000)
        // What was recorded is what was heard: the note's partial under the voice.
        var (sine, cosine) = (0.0, 0.0)
        for (frame, sample) in captured.enumerated() {
            let angle = 2 * Double.pi * 990 * Double(frame) / Self.rate
            sine += Double(sample) * sin(angle)
            cosine += Double(sample) * cos(angle)
        }
        let strength = 2 * (sine * sine + cosine * cosine).squareRoot() / Double(captured.count)
        #expect(strength > 0.2)
    }

    @Test func aFullKernelWithTheVocoderOnRendersFasterThanItIsHeard() {
        let rig = KernelRig()
        rig.setSound(0, .wave(PerfectoWaveSawtooth, level: 0.01))
        rig.setVocoder(true)
        rig.input = Self.tone(1000)
        for voice in 0..<Int(perfecto_kernel_voice_count()) {
            rig.noteOn(UInt64(voice + 1), note: 36 + voice, vocoder: 0.5)
        }
        let started = Date()
        rig.render(48_000)
        #expect(Date().timeIntervalSince(started) < 1)
    }
}
