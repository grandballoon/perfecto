import AVFoundation
import CoreAudio
@testable import Perfecto

/// A sine for an engine to hear. It is read on the render thread, one
/// render at a time.
final class Tone: @unchecked Sendable {
    private let step: Double
    private var phase = 0.0

    init(hz: Double, rate: Double) {
        step = 2 * Double.pi * hz / rate
    }

    /// A node that plays it. The node's block is called on the render
    /// thread, so it is made here, where nothing is the main actor's.
    nonisolated func node(_ format: AVAudioFormat) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { [self] _, _, frames, buffers in
            fill(buffers, frames: Int(frames))
            return noErr
        }
    }

    func fill(_ buffers: UnsafeMutablePointer<AudioBufferList>, frames: Int) {
        let list = UnsafeMutableAudioBufferListPointer(buffers)
        let start = phase
        for buffer in list {
            guard let samples = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            for frame in 0..<frames { samples[frame] = Float(0.5 * sin(start + step * Double(frame))) }
        }
        phase = start + step * Double(frames)
    }
}

/// How strong the sine at `hz` is in `recording`: its amplitude.
func strength(of hz: Double, in recording: Recording) -> Double {
    var (sine, cosine) = (0.0, 0.0)
    for (frame, sample) in recording.samples.enumerated() {
        let angle = 2 * Double.pi * hz * Double(frame) / recording.sampleRate
        sine += Double(sample) * sin(angle)
        cosine += Double(sample) * cos(angle)
    }
    return 2 * (sine * sine + cosine * cosine).squareRoot() / Double(max(recording.samples.count, 1))
}

extension Recording {
    /// A second of a full-level sine at `hz`, to stand for a mic sample.
    static func tone(_ hz: Double = 261.63, rate: Double = 48_000) -> Recording {
        Recording(samples: (0..<Int(rate)).map { Float(sin(2 * Double.pi * hz * Double($0) / rate)) },
                  sampleRate: rate)
    }
}
