import AudioKit
import AVFoundation
@testable import Perfecto

/// A short tone, then silence, rendered through real AudioKit nodes in an
/// engine that renders offline, so what comes out can be measured.
@MainActor
struct OfflineTone {

    static let toneSeconds = 0.5
    static let totalSeconds = 1.5

    var frequency = 440.0

    private final class Source: Node {
        let playerNode = AVAudioPlayerNode()
        var connections: [Node] { [] }
        var avAudioNode: AVAudioNode { playerNode }
    }

    /// Renders the tone through the node `build` makes from the source,
    /// returning the first channel and the sample rate. `afterTone` runs
    /// once the tone has ended, before the silence that follows is rendered.
    func render(through build: (Node) -> Node,
                afterTone: () -> Void = {}) -> (output: [Float], rate: Double) {
        let engine = AudioEngine()
        let source = Source()
        engine.output = build(source)
        _ = engine.startTest(totalDuration: Self.totalSeconds)
        defer { engine.stop() }
        let rate = engine.avEngine.manualRenderingFormat.sampleRate

        let format = source.playerNode.outputFormat(forBus: 0)
        let frames = Int(Self.toneSeconds * rate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        for channel in 0..<Int(format.channelCount) {
            for frame in 0..<frames { buffer.floatChannelData![channel][frame] = sample(frame, rate: rate) }
        }
        source.playerNode.scheduleBuffer(buffer, at: nil)
        source.playerNode.play()

        var output: [Float] = []
        func render(_ seconds: Double) {
            let rendered = engine.render(duration: seconds)
            output += UnsafeBufferPointer(start: rendered.floatChannelData![0],
                                          count: Int(rendered.frameLength))
        }
        render(Self.toneSeconds)
        afterTone()
        render(Self.totalSeconds - Self.toneSeconds)
        return (output, rate)
    }

    /// The tone's value at `frame`.
    func sample(_ frame: Int, rate: Double) -> Float {
        0.5 * Float(sin(2 * Double.pi * frequency * Double(frame) / rate))
    }

    /// The furthest `output` strays from the tone while the tone plays,
    /// from `settleSeconds` in.
    func distance(from output: [Float], rate: Double, after settleSeconds: Double = 0) -> Float {
        var worst: Float = 0
        for frame in Int(settleSeconds * rate)..<Int(Self.toneSeconds * rate) {
            worst = max(worst, abs(output[frame] - sample(frame, rate: rate)))
        }
        return worst
    }
}

/// The loudest sample in `samples`.
func loudest(_ samples: ArraySlice<Float>) -> Float {
    samples.map(abs).max() ?? 0
}
