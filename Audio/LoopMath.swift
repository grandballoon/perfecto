import Darwin

/// Loop arithmetic on plain sample arrays (one `[Float]` per channel), with no
/// audio engine involved, so the rules that keep layers in time are testable
/// on their own.
enum LoopMath {

    /// Where `time` falls inside a loop of `period` frames whose cycles begin
    /// at `anchor`: always in `0..<period`, also for times before the anchor.
    static func phase(of time: Int64, anchor: Int64, period: Int) -> Int {
        let remainder = (time - anchor) % Int64(period)
        return Int(remainder < 0 ? remainder + Int64(period) : remainder)
    }

    /// Wraps a take onto a loop of `period` frames. The take's first frame
    /// lands at `offset`; whatever runs past the end of the loop continues
    /// from its start, adding to what is already there, so a take longer than
    /// the loop layers over itself the way overdubbing does.
    static func fold(_ take: [[Float]], offset: Int, period: Int) -> [[Float]] {
        take.map { channel in
            var loop = [Float](repeating: 0, count: period)
            var position = offset % period
            for sample in channel {
                loop[position] += sample
                position += 1
                if position == period { position = 0 }
            }
            return loop
        }
    }

    /// `channels` cut or zero-padded to exactly `frames`.
    static func fitted(_ channels: [[Float]], to frames: Int) -> [[Float]] {
        channels.map { channel in
            channel.count >= frames
                ? Array(channel.prefix(frames))
                : channel + [Float](repeating: 0, count: frames - channel.count)
        }
    }

    /// Raised-cosine fade-in over the first `frames` of each channel, so a
    /// take that starts mid-note doesn't click.
    static func fadeIn(_ channels: inout [[Float]], frames: Int) {
        for c in channels.indices {
            for i in 0..<min(frames, channels[c].count) {
                channels[c][i] *= fadeGain(i, of: frames)
            }
        }
    }

    /// The matching fade-out over the last `frames` of each channel.
    static func fadeOut(_ channels: inout [[Float]], frames: Int) {
        for c in channels.indices {
            let count = channels[c].count
            for i in 0..<min(frames, count) {
                channels[c][count - 1 - i] *= fadeGain(i, of: frames)
            }
        }
    }

    private static func fadeGain(_ index: Int, of frames: Int) -> Float {
        let t = Float(index) / Float(frames)
        return 0.5 * (1 - cosf(.pi * t))
    }
}
