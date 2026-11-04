import AVFoundation

/// What plays a piece's recording: stretches of it, one after another and
/// over again if asked, and the moment of it being heard.
@MainActor
protocol RecordingPlaying: AnyObject {
    /// The recording at `url` made the one played; its length in seconds.
    func load(_ url: URL) throws -> Double
    /// Plays `segments` in order, from the first, and again from the first
    /// after the last while `repeats`; anything playing stops first.
    func play(_ segments: [Segment], repeats: Bool)
    func stop()
    var isPlaying: Bool { get }
    /// The moment of the recording being heard, in its seconds.
    var currentTime: Double { get }
    /// Called when the segments have all played, if they do not repeat.
    var onFinish: (() -> Void)? { get set }
}

/// The recording played through an engine of its own, beside the app's,
/// so nothing of the instrument's sound is in its way: a player node that
/// is given each segment of the file as the last nears its end, so
/// segments follow one another, and repeat, with no gap.
///
/// The moment heard is the player's own count of the frames it has
/// played, set against the segments it was given, so the piano is lit by
/// the sound and never by a timer.
@MainActor
final class RecordingPlayer: RecordingPlaying {

    var onFinish: (() -> Void)?

    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private var file: AVAudioFile?

    /// A segment as given to the player: where in the player's own count
    /// of frames it begins, and where in the file.
    private struct Scheduled {
        let playerFrame: AVAudioFramePosition
        let fileFrame: AVAudioFramePosition
        let frames: AVAudioFrameCount
    }

    private var segments: [Segment] = []
    private var repeats = false
    private var nextSegment = 0
    private var scheduled: [Scheduled] = []
    private var scheduledFrames: AVAudioFramePosition = 0
    /// Which run of `play` the callbacks belong to, so a stopped run's
    /// last callbacks are not taken for the new one's.
    private var generation = 0
    private var stoppedAt = 0.0

    /// Segments given to the player ahead of the one playing.
    private static let ahead = 2

    init() {
        engine.attach(node)
    }

    func load(_ url: URL) throws -> Double {
        stop()
        let file = try AVAudioFile(forReading: url)
        self.file = file
        engine.disconnectNodeOutput(node)
        engine.connect(node, to: engine.mainMixerNode, format: file.processingFormat)
        return Double(file.length) / file.processingFormat.sampleRate
    }

    func play(_ segments: [Segment], repeats: Bool) {
        stop()
        guard let file else { return }
        let rate = file.processingFormat.sampleRate
        let length = Double(file.length) / rate
        self.segments = segments
            .map { Segment(start: $0.start.clamped(to: 0...length), end: $0.end.clamped(to: 0...length)) }
            .filter { $0.duration * rate >= 1 }
        guard !self.segments.isEmpty else { return }
        self.repeats = repeats
        do {
            if !engine.isRunning { try engine.start() }
        } catch {
            return
        }
        for _ in 0...Self.ahead { scheduleNext() }
        node.play()
    }

    func stop() {
        stoppedAt = currentTime
        generation += 1
        node.stop()
        segments = []
        scheduled = []
        scheduledFrames = 0
        nextSegment = 0
        engine.pause()
    }

    var isPlaying: Bool { node.isPlaying && !segments.isEmpty }

    var currentTime: Double {
        guard isPlaying, let file,
              let nodeTime = node.lastRenderTime,
              let playerTime = node.playerTime(forNodeTime: nodeTime) else { return stoppedAt }
        let rate = file.processingFormat.sampleRate
        let frame = playerTime.sampleTime
        guard let segment = scheduled.last(where: { $0.playerFrame <= frame }) ?? scheduled.first else {
            return stoppedAt
        }
        let into = min(max(frame - segment.playerFrame, 0), AVAudioFramePosition(segment.frames))
        return Double(segment.fileFrame + into) / rate
    }

    private func scheduleNext() {
        guard let file else { return }
        if nextSegment == segments.count {
            guard repeats else { return }
            nextSegment = 0
        }
        let rate = file.processingFormat.sampleRate
        let segment = segments[nextSegment]
        nextSegment += 1
        let start = AVAudioFramePosition(segment.start * rate)
        let frames = AVAudioFrameCount(min(segment.duration * rate, Double(file.length - start)))
        let isLast = !repeats && nextSegment == segments.count
        scheduled.append(Scheduled(playerFrame: scheduledFrames, fileFrame: start, frames: frames))
        // Only those still to come, and the one playing, are needed.
        if scheduled.count > Self.ahead + 2 { scheduled.removeFirst() }
        scheduledFrames += AVAudioFramePosition(frames)
        let generation = generation
        node.scheduleSegment(file, startingFrame: start, frameCount: frames, at: nil,
                             completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == generation else { return }
                if isLast {
                    self.stop()
                    self.onFinish?()
                } else {
                    self.scheduleNext()
                }
            }
        }
    }

    /// The loudness of the recording at `url`, `perSecond` peaks to each
    /// of its seconds. It reads the whole file, so it is called off the
    /// main thread.
    nonisolated static func peaks(of url: URL, perSecond: Int) -> [Float] {
        guard perSecond > 0, let reader = try? AVAudioFile(forReading: url) else { return [] }
        let format = reader.processingFormat
        let frames = max(1, Int(format.sampleRate) / perSecond)
        let chunk = AVAudioFrameCount(frames * 1024)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else { return [] }
        var peaks: [Float] = []
        while (try? reader.read(into: buffer, frameCount: chunk)) != nil, buffer.frameLength > 0 {
            guard let channels = buffer.floatChannelData else { break }
            let count = Int(buffer.frameLength)
            // The louder channel's outline.
            let louder = (0..<Int(format.channelCount)).map { channel in
                Waveform.peaks(Array(UnsafeBufferPointer(start: channels[channel], count: count)), frames: frames)
            }
            peaks += louder.dropFirst().reduce(louder[0]) { zip($0, $1).map(max) }
        }
        return peaks
    }
}
