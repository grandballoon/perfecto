import Foundation
import PerfectoKernel
import Testing

/// Sounds made beforehand and given to the kernel (a drum kit), played as a
/// capture is.
struct LoadedSampleTests {

    private static let rate = KernelRig.sampleRate

    /// A sine at `hz` as if made at `rate`.
    private static func tone(of hz: Double, seconds: Double = 1, rate: Double = rate) -> [Float] {
        (0..<Int(seconds * rate)).map { Float(sin(2 * Double.pi * hz * Double($0) / rate)) }
    }

    @Test func thereAreRoomForManySamplesAndSounds() {
        #expect(perfecto_kernel_sample_count() == 128)
        #expect(perfecto_kernel_sound_count() == 128)
    }

    @Test func aSampleIsAsLongAsWhatWasLoaded() {
        let rig = KernelRig()
        #expect(rig.sampleLength(5) == 0)
        rig.loadSample(Self.tone(of: 440, seconds: 0.25), into: 5)
        #expect(rig.sampleLength(5) == 12_000)
    }

    @Test(arguments: [(69, 440.0), (81, 880.0), (76, 440 * pow(2, 7.0 / 12))])
    func aNotePlaysTheSampleAtItsPitch(note: Int, hz: Double) {
        let rig = KernelRig()
        rig.loadSample(Self.tone(of: 440), into: 100)
        rig.setSound(127, .loaded(100))
        rig.noteOn(1, note: note, sound: 127)
        rig.render(14_400)
        #expect(abs(rig.strength(of: hz, in: 4800..<14_400) - 0.5) < 0.01)
    }

    @Test func aSampleMadeAtAnotherRateKeepsItsPitch() {
        let rig = KernelRig()
        rig.loadSample(Self.tone(of: 440, rate: 24_000), rate: 24_000)
        rig.setSound(0, .loaded())
        rig.noteOn(1, note: 69)
        rig.render(14_400)
        #expect(abs(rig.strength(of: 440, in: 4800..<14_400) - 0.5) < 0.01)
    }

    @Test func aNoteEndsWhenItsSampleDoes() {
        let rig = KernelRig()
        rig.loadSample(Self.tone(of: 440, seconds: 0.1))
        rig.setSound(0, .loaded())
        rig.noteOn(1)
        rig.render(9600)
        #expect(rig.loudest(0..<4000) > 0.4)
        #expect(rig.loudest(4800..<9600) == 0)
    }

    @Test func aSampleAndACaptureOfTheSameNumberAreApart() {
        let rig = KernelRig()
        rig.loadSample(Self.tone(of: 440))
        rig.load(Self.tone(of: 660))
        rig.setSound(0, .loaded())
        rig.setSound(1, .sampled())
        rig.noteOn(1, note: 69, sound: 0)
        rig.render(9600)
        #expect(rig.strength(of: 440, in: 2400..<9600) > 0.4)
        #expect(rig.strength(of: 660, in: 2400..<9600) < 0.001)
    }

    @Test func recordingOverACaptureLeavesSamplesPlaying() {
        let rig = KernelRig()
        rig.loadSample(Self.tone(of: 440))
        rig.setSound(0, .loaded())
        rig.noteOn(1, note: 69)
        rig.input = { _ in 0 }
        rig.captureStart(at: 4800)
        rig.render(9600)
        #expect(rig.strength(of: 440, in: 4800..<9600) > 0.4)
    }

    @Test func loadingASampleAgainEndsTheNotesPlayingIt() {
        let rig = KernelRig()
        rig.loadSample(Self.tone(of: 440), into: 0)
        rig.loadSample(Self.tone(of: 440), into: 1)
        rig.setSound(0, .loaded(0))
        rig.setSound(1, .loaded(1, root: 57))
        rig.noteOn(1, note: 69, sound: 0)
        rig.noteOn(2, note: 69, sound: 1)
        rig.render(4800)
        rig.loadSample(Self.tone(of: 440, seconds: 0.5), into: 0)
        rig.render(9600)
        // The note on the sample loaded again is gone; the other plays on, an octave up.
        #expect(rig.strength(of: 440, in: 7200..<14_400) < 0.001)
        #expect(rig.strength(of: 880, in: 7200..<14_400) > 0.4)
    }

    @Test func readyingTheKernelAgainKeepsTheSamples() {
        let rig = KernelRig()
        rig.loadSample(Self.tone(of: 440, seconds: 0.25), into: 3)
        rig.prepareAgain()
        #expect(rig.sampleLength(3) == 12_000)
    }
}
