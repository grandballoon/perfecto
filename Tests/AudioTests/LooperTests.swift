import AudioKit
import AVFoundation
import Testing
@testable import Perfecto

/// Runs the real `Looper` and `LoopCapture` in an engine that renders offline,
/// so every frame it plays can be checked against what it was given: a ramp
/// that never repeats, which makes a loop even one frame out of place show up.
@Suite("Looper", .serialized)
@MainActor
struct LooperTests {

    /// Plays a known signal into the looper's capture point.
    private final class Source: Node {
        let playerNode = AVAudioPlayerNode()
        var connections: [Node] { [] }
        var avAudioNode: AVAudioNode { playerNode }
    }

    /// An offline engine: the source feeds a mixer (the capture point), and
    /// the output is that mixer plus the looper.
    @MainActor
    private final class Rig {
        static let lead = 0.05
        static let seconds = 8.0
        /// How far a rendered frame may be from the expected one. A track's
        /// effects, switched off, pass its loop on to within a few parts in
        /// a million of this; a loop one frame out of place is further off
        /// than this wherever it fades in or out.
        static let tolerance: Float = 1e-5

        let engine = AudioEngine()
        let source = Source()
        let looper: Looper
        let logger = RecordingLogger()
        let rate: Double
        /// Everything rendered so far, first channel.
        private(set) var output: [Float] = []
        private let capture: LoopCapture

        init() {
            let captureMixer = Mixer(source)
            capture = LoopCapture(source: captureMixer)
            looper = Looper(capture: capture, trackCount: 2, logger: logger,
                            scheduleLead: { Rig.lead })
            engine.output = Mixer(captureMixer, looper.outputMixer)
            _ = engine.startTest(totalDuration: Rig.seconds)
            rate = engine.avEngine.manualRenderingFormat.sampleRate

            let format = source.playerNode.outputFormat(forBus: 0)
            let frames = Int(Rig.seconds * rate)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
            buffer.frameLength = AVAudioFrameCount(frames)
            for channel in 0..<Int(format.channelCount) {
                for frame in 0..<frames { buffer.floatChannelData![channel][frame] = Rig.signal(frame) }
            }
            source.playerNode.scheduleBuffer(buffer, at: nil)
            source.playerNode.play()
        }

        /// The source's value at `frame`.
        static func signal(_ frame: Int) -> Float { Float(frame) / 1_000_000 }

        /// The capture clock's latest reading, as the looper sees it.
        var now: Int { Int(capture.now!.sampleTime) }

        /// Frames rendered so far.
        var position: Int { output.count }

        func render(_ seconds: Double) {
            let buffer = engine.render(duration: seconds)
            output += UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength))
        }

        /// Lets a finished take reach the looper, as it would while the
        /// engine keeps running. The tap hands audio over in blocks of its
        /// own size, so a take's last frames only arrive once rendering has
        /// carried on past them; then the handover happens on the tap's
        /// thread and the main actor, in their own time.
        func settle() async throws {
            render(0.25)
            let delivered = try await waitUntil { !capture.isBusy }
            #expect(delivered)
        }

        func stop() { engine.stop() }
    }

    /// The loop a take from `start` to `stop` becomes: faded at both ends.
    private func firstLoop(from start: Int, to stop: Int) -> [Float] {
        var loop = [(start..<stop).map(Rig.signal)]
        LoopMath.fadeIn(&loop, frames: 256)
        LoopMath.fadeOut(&loop, frames: 256)
        return loop[0]
    }

    @Test func theFirstTakeLoopsFromTheMomentItIsClosed() async throws {
        let rig = Rig()
        defer { rig.stop() }

        rig.render(0.25)
        let start = rig.position
        try rig.looper.startRecording(0)
        rig.render(1.0)
        let stop = rig.now
        #expect(rig.looper.stopRecording(0))
        try await rig.settle()
        rig.render(3.0)

        let period = stop - start
        let anchor = stop + Int(Rig.lead * rig.rate)
        let loop = firstLoop(from: start, to: stop)
        #expect(rig.position > anchor + 2 * period)
        var worst: Float = 0
        for frame in anchor..<rig.position {
            let expected = Rig.signal(frame) + loop[(frame - anchor) % period]
            worst = max(worst, abs(rig.output[frame] - expected))
        }
        #expect(worst < Rig.tolerance)
    }

    @Test func aSecondTakeIsLayeredAtThePointInTheLoopWhereItWasPlayed() async throws {
        let rig = Rig()
        defer { rig.stop() }

        rig.render(0.25)
        let start = rig.position
        try rig.looper.startRecording(0)
        rig.render(1.0)
        let stop = rig.now
        rig.looper.stopRecording(0)
        try await rig.settle()
        rig.render(0.7)

        let overdubStart = rig.position
        try rig.looper.startRecording(1)
        rig.render(0.4)
        let overdubStop = rig.now
        #expect(rig.looper.stopRecording(1))
        try await rig.settle()
        let joined = rig.now + Int(Rig.lead * rig.rate)
        rig.render(3.0)

        let period = stop - start
        let anchor = stop + Int(Rig.lead * rig.rate)
        let first = firstLoop(from: start, to: stop)
        var take = [(overdubStart..<overdubStop).map(Rig.signal)]
        LoopMath.fadeIn(&take, frames: 256)
        LoopMath.fadeOut(&take, frames: 256)
        let second = LoopMath.fold(take, offset: (overdubStart - anchor) % period, period: period)[0]

        #expect(rig.position > joined + 2 * period)
        var worst: Float = 0
        for frame in joined..<rig.position {
            let phase = (frame - anchor) % period
            let expected = Rig.signal(frame) + first[phase] + second[phase]
            worst = max(worst, abs(rig.output[frame] - expected))
        }
        #expect(worst < Rig.tolerance)
    }

    @Test func aPausedLayerComesBackInTime() async throws {
        let rig = Rig()
        defer { rig.stop() }

        rig.render(0.25)
        let start = rig.position
        try rig.looper.startRecording(0)
        rig.render(1.0)
        let stop = rig.now
        rig.looper.stopRecording(0)
        try await rig.settle()
        rig.render(0.6)

        rig.looper.stopPlayback(0)
        rig.render(0.33)
        let silentFrom = rig.position - Int(0.1 * rig.rate)
        for frame in silentFrom..<rig.position {
            #expect(rig.output[frame] == Rig.signal(frame))
        }

        let resumed = rig.now + Int(Rig.lead * rig.rate)
        rig.looper.startPlayback(0)
        rig.render(2.0)

        let period = stop - start
        let anchor = stop + Int(Rig.lead * rig.rate)
        let loop = firstLoop(from: start, to: stop)
        var worst: Float = 0
        for frame in resumed..<rig.position {
            let expected = Rig.signal(frame) + loop[(frame - anchor) % period]
            worst = max(worst, abs(rig.output[frame] - expected))
        }
        #expect(worst < Rig.tolerance)
    }

    /// Effects chosen after a loop is closed are for what is played next:
    /// the loop plays on unchanged, and comes back unchanged after a pause.
    @Test func laterEffectsLeaveAFinishedLoopAsItWas() async throws {
        let rig = Rig()
        defer { rig.stop() }

        rig.render(0.25)
        let start = rig.position
        try rig.looper.startRecording(0)
        rig.render(1.0)
        let stop = rig.now
        rig.looper.stopRecording(0)
        try await rig.settle()

        let changed = rig.position
        rig.looper.liveEffects = Self.wet
        rig.render(1.5)
        rig.looper.stopPlayback(0)
        rig.render(0.3)
        let resumed = rig.now + Int(Rig.lead * rig.rate)
        rig.looper.startPlayback(0)
        rig.render(1.5)

        let period = stop - start
        let anchor = stop + Int(Rig.lead * rig.rate)
        let loop = firstLoop(from: start, to: stop)
        let paused = resumed - Int(0.3 * rig.rate) - Int(Rig.lead * rig.rate)
        var worst: Float = 0
        for frame in Array(changed..<paused) + Array(resumed..<rig.position) {
            let expected = Rig.signal(frame) + loop[(frame - anchor) % period]
            worst = max(worst, abs(rig.output[frame] - expected))
        }
        #expect(worst < Rig.tolerance)
    }

    /// A loop closed with reverb on keeps it after the reverb is switched
    /// off: paused, it still rings on.
    @Test func aLoopKeepsTheEffectsItWasClosedWith() async throws {
        let rig = Rig()
        defer { rig.stop() }

        rig.looper.liveEffects = Self.wet
        rig.render(0.25)
        try rig.looper.startRecording(0)
        rig.render(1.0)
        rig.looper.stopRecording(0)
        try await rig.settle()

        rig.looper.liveEffects = SoundEffects()
        rig.render(1.5)
        rig.looper.stopPlayback(0)
        rig.render(0.1)
        let from = rig.position
        rig.render(0.3)

        var loudest: Float = 0
        for frame in from..<rig.position {
            loudest = max(loudest, abs(rig.output[frame] - Rig.signal(frame)))
        }
        #expect(loudest > 1e-3)
    }

    private static let wet = SoundEffects(
        chorus: ChorusSettings(isOn: true, amount: 1, rate: 0.5),
        reverb: ReverbSettings(isOn: true, mix: 0.5, size: 0.5))

    @Test func aTakeTooShortToLoopIsDropped() async throws {
        let rig = Rig()
        defer { rig.stop() }

        rig.render(0.25)
        try rig.looper.startRecording(0)
        rig.render(0.1)
        #expect(!rig.looper.stopRecording(0))
        try await rig.settle()
        let from = rig.position
        rig.render(1.0)

        for frame in from..<rig.position {
            #expect(rig.output[frame] == Rig.signal(frame))
        }
        #expect(rig.logger.events.contains {
            if case .loop_take_discarded = $0 { true } else { false }
        })
    }

    @Test func clearingEveryTrackLetsTheNextTakeSetANewLength() async throws {
        let rig = Rig()
        defer { rig.stop() }

        rig.render(0.25)
        try rig.looper.startRecording(0)
        rig.render(1.0)
        rig.looper.stopRecording(0)
        try await rig.settle()
        rig.render(0.3)
        rig.looper.clearTrack(0)

        rig.render(0.2)
        let start = rig.position
        try rig.looper.startRecording(0)
        rig.render(0.75)
        let stop = rig.now
        rig.looper.stopRecording(0)
        try await rig.settle()
        rig.render(2.0)

        let period = stop - start
        let anchor = stop + Int(Rig.lead * rig.rate)
        let loop = firstLoop(from: start, to: stop)
        var worst: Float = 0
        for frame in anchor..<rig.position {
            let expected = Rig.signal(frame) + loop[(frame - anchor) % period]
            worst = max(worst, abs(rig.output[frame] - expected))
        }
        #expect(worst < Rig.tolerance)
    }

    @Test func onlyOneTakeIsRecordedAtATime() async throws {
        let rig = Rig()
        defer { rig.stop() }

        rig.render(0.25)
        let capture = LoopCapture(source: rig.looper.outputMixer)
        try capture.begin()
        #expect(throws: LoopCapture.Failure.busy) { try capture.begin() }
        capture.cancel()
        try capture.begin()
        capture.cancel()
    }
}
