import Foundation
import PerfectoKernel
import Testing

/// Recording the input, and playing what was recorded as a sound.
struct CaptureTests {

    private static let rate = KernelRig.sampleRate

    /// A sine at `hz`, `level` high, by frame.
    private static func tone(_ hz: Double, level: Float = 0.5) -> (Int) -> Float {
        { level * Float(sin(2 * Double.pi * hz * Double($0) / rate)) }
    }

    /// One second of a sine at `hz` as if recorded at `rate`.
    private static func recording(of hz: Double, seconds: Double = 1, rate: Double = rate) -> [Float] {
        (0..<Int(seconds * rate)).map { Float(sin(2 * Double.pi * hz * Double($0) / rate)) }
    }

    // MARK: Recording

    @Test(arguments: [[256], [7, 300, 64, 1], [4096]])
    func aCaptureHoldsExactlyTheFramesBetweenItsStartAndItsStop(chunks: [Int]) {
        let rig = KernelRig()
        let input = Self.tone(4000)
        rig.input = input
        rig.captureStart(at: 1000)
        rig.captureStop(at: 5000)
        var rendered = 0
        while rendered < 8000 {
            rig.render(chunks: chunks)
            rendered += chunks.reduce(0, +)
        }

        let captured = rig.captured()
        #expect(captured.count == 4000)
        // It is brought up to full level: the tone was at half.
        let furthest = captured.enumerated().map { abs($1 - 2 * input(1000 + $0)) }.max() ?? 1
        #expect(furthest < 0.02)
    }

    @Test func nothingIsPlayableWhileItIsRecorded() {
        let rig = KernelRig()
        rig.input = Self.tone(1000)
        rig.captureStart(at: 0)
        rig.render(4800)
        #expect(rig.capturing == 0)
        #expect(rig.captureLength() == 0)
        rig.captureStop()
        rig.render(256)
        #expect(rig.capturing == nil)
        #expect(rig.captureLength() > 4800)
    }

    @Test func aRecordingIsCutToItsSound() {
        let rig = KernelRig()
        let tone = Self.tone(1000)
        rig.input = { (10_000..<20_000).contains($0) ? tone($0) : 0 }
        rig.captureStart(at: 0)
        rig.captureStop(at: 40_000)
        rig.render(41_000)

        // A moment before the sound and a little after it are kept.
        let captured = rig.captured()
        #expect((10_000 + 7000...10_000 + 7700).contains(captured.count))
        let quiet = captured.firstIndex { abs($0) > 0.1 } ?? 0
        #expect((200...260).contains(quiet))
    }

    @Test func aQuietRecordingIsBroughtUpToFullLevel() {
        let rig = KernelRig()
        rig.input = Self.tone(1000, level: 0.05)
        rig.captureStart(at: 0)
        rig.captureStop(at: 9600)
        rig.render(10_000)
        let peak = rig.captured().map(abs).max() ?? 0
        #expect(abs(peak - 1) < 0.02)
    }

    @Test func aRecordingOfSilenceHasNothingToPlay() {
        let rig = KernelRig()
        rig.input = { _ in 0.001 }
        rig.captureStart(at: 0)
        rig.captureStop(at: 9600)
        rig.render(10_000)
        #expect(rig.captureLength() == 0)

        rig.setSound(0, .sampled())
        rig.noteOn(1)
        rig.render(4800)
        #expect(rig.loudest(10_000..<14_800) == 0)
    }

    @Test func aSteadyOffsetIsTakenOut() {
        let rig = KernelRig()
        let tone = Self.tone(1000, level: 0.2)
        rig.input = { 0.3 + tone($0) }
        rig.captureStart(at: 0)
        rig.captureStop(at: 48_000)
        rig.render(48_256)
        // Past the moment it takes to settle, the recording is centred.
        let late = rig.captured().suffix(9600)
        let mean = late.reduce(0, +) / Float(late.count)
        #expect(abs(mean) < 0.01)
    }

    @Test func aCaptureStopsItselfWhenItIsFull() {
        let rig = KernelRig()
        rig.input = Self.tone(1000)
        rig.captureStart(at: 0)
        rig.render(KernelRig.captureCapacity + 4096, chunk: 4096)
        #expect(rig.capturing == nil)
        #expect(rig.captureLength() == KernelRig.captureCapacity)
    }

    @Test func oneCaptureIsRecordedAtATime() {
        let rig = KernelRig()
        rig.input = Self.tone(1000)
        rig.captureStart(0, at: 0)
        rig.captureStart(1, at: 4800)
        rig.captureStop(at: 9600)
        // A stop with nothing being recorded ends nothing.
        rig.captureStop(at: 9700)
        rig.render(10_000)
        #expect(rig.capturesEnded == 2)
        #expect(rig.captureLength(0) == 4800)
        #expect(rig.captureLength(1) == 4800)
    }

    @Test func readyingTheKernelAgainKeepsWhatWasRecorded() {
        let rig = KernelRig()
        rig.input = Self.tone(1000)
        rig.captureStart(at: 0)
        rig.render(4800)
        // The engine stops mid-recording: what there is of it is kept.
        rig.prepareAgain()
        #expect(rig.capturesEnded == 1)
        #expect(rig.capturing == nil)
        #expect(rig.captureLength() > 4800)
    }

    @Test func aLoadedRecordingIsReadBackAsItWas() {
        let rig = KernelRig()
        let samples = Self.recording(of: 440, seconds: 0.1)
        rig.load(samples, into: 2)
        #expect(rig.captured(2) == samples)
    }

    // MARK: Playing

    @Test(arguments: [(69, 440.0), (81, 880.0), (57, 220.0), (76, 440 * pow(2, 7.0 / 12))])
    func aNotePlaysTheRecordingAtItsPitch(note: Int, hz: Double) {
        let rig = KernelRig()
        rig.load(Self.recording(of: 440))
        rig.setSound(0, .sampled(root: 69, level: 0.5))
        rig.noteOn(1, note: note)
        rig.render(14_400)
        #expect(abs(rig.strength(of: hz, in: 4800..<14_400) - 0.5) < 0.01)
    }

    @Test func aRecordingMadeAtAnotherRateKeepsItsPitch() {
        let rig = KernelRig()
        rig.load(Self.recording(of: 440, rate: 24_000), rate: 24_000)
        rig.setSound(0, .sampled(root: 69, level: 0.5))
        rig.noteOn(1, note: 69)
        rig.render(14_400)
        #expect(abs(rig.strength(of: 440, in: 4800..<14_400) - 0.5) < 0.01)
    }

    @Test func aRecordingBetweenItsFramesIsStillATone() {
        // Played a fifth up, nearly every frame read falls between two
        // recorded: what is not the tone is the error of reading between.
        let rig = KernelRig()
        rig.load(Self.recording(of: 440))
        rig.setSound(0, .sampled(root: 69, level: 0.5))
        rig.noteOn(1, note: 76)
        rig.render(14_400)
        let rest = rig.remainder(without: [440 * pow(2, 7.0 / 12)], in: 4800..<14_400)
        #expect(rest < 0.5 * 0.001)
    }

    @Test func aNoteEndsWhenItsRecordingDoes() {
        let rig = KernelRig()
        rig.load(Self.recording(of: 440, seconds: 0.1))
        rig.setSound(0, .sampled())
        rig.noteOn(1)
        rig.render(9600)
        #expect(rig.loudest(0..<4000) > 0.4)
        #expect(rig.loudest(4800..<9600) == 0)
        // It ends faded out, not cut: no step bigger than the tone's own.
        #expect(rig.biggestStep(4000..<5000) < 0.04)
    }

    @Test func aNoteEndedSoonerDiesAwayAsAnyOtherDoes() {
        let rig = KernelRig()
        rig.load(Self.recording(of: 440))
        rig.setSound(0, .sampled(release: 0.01))
        rig.noteOn(1)
        rig.noteOff(1, at: 4800)
        rig.render(14_400)
        #expect(rig.loudest(0..<4800) > 0.4)
        #expect(rig.loudest(9600..<14_400) == 0)
    }

    @Test func recordingOverACaptureEndsTheNotesPlayingIt() {
        let rig = KernelRig()
        rig.load(Self.recording(of: 440))
        rig.setSound(0, .sampled())
        rig.setSound(1, .wave(PerfectoWaveSine))
        rig.noteOn(1, note: 69, sound: 0)
        rig.noteOn(2, note: 81, sound: 1)
        rig.input = { _ in 0 }
        rig.captureStart(at: 4800)
        rig.render(9600)
        #expect(rig.strength(of: 440, in: 2400..<4800) > 0.4)
        #expect(rig.strength(of: 440, in: 4800..<9600) < 0.001)
        // Notes of other sounds play on.
        #expect(rig.strength(of: 880, in: 4800..<9600) > 0.4)
    }

    @Test func whatIsRecordedCanBePlayed() {
        let rig = KernelRig()
        rig.input = Self.tone(440, level: 0.25)
        rig.captureStart(at: 0)
        rig.captureStop(at: 24_000)
        rig.setSound(0, .sampled(root: 60, level: 0.5))
        rig.noteOn(1, note: 72, at: 28_800)
        rig.render(48_000)
        #expect(rig.strength(of: 880, in: 33_600..<38_400) > 0.45)
    }
}
