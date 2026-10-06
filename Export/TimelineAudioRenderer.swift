import AVFoundation

/// Renders a timeline to an audio file, as it plays: the same player, the
/// same voices and the same kernel as the app's own sound, run with no
/// real time passing, so what is exported is what was heard, to the frame.
///
/// It plays the timeline through once and lets the last notes ring out.
/// The vocoder needs a voice, and there is none here: notes sent to it are
/// heard whole.
@MainActor
enum TimelineAudioRenderer {

    static let sampleRate = 48_000.0
    /// The longest the sound is followed after the last note has ended.
    static let longestTail = 10.0
    /// A stretch quieter than this, 66 dB under full scale, is the end.
    private static let silence: Float = 0.0005
    private static let blockFrames: AVAudioFrameCount = 512

    /// Writes `timeline` to `url` as a 24-bit stereo WAV file, played at
    /// `bpm` with `live` for whatever its notes do not set themselves, and
    /// `sample` as the mic sample. Returns the file's length in seconds.
    @discardableResult
    static func render(_ timeline: Timeline, live: LiveSettings, bpm: Double, sample: Recording? = nil,
                       to url: URL) async throws -> TimeInterval {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let engine = AVAudioEngine()
        let made = KernelAudioUnit.makeNode()
        let sink = KernelSink(unit: made.unit) { UInt64(max(0, ($0 * sampleRate).rounded())) }
        if let sample, !sample.samples.isEmpty { made.unit.load(sample, into: SynthPreset.micCapture) }
        engine.attach(made.node)
        engine.connect(made.node, to: engine.outputNode, format: format)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: blockFrames)
        try engine.start()
        defer { engine.stop() }

        let clock = SteppedClock()
        clock.bpm = bpm
        let player = TimelinePlayer(timeline: timeline, live: live, clock: clock) { _ in
            let notes = NotePlayer([sink], clock: clock)
            return LayerVoice(sink: notes, sound: notes, clock: clock)
        }

        let file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 24,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ], commonFormat: .pcmFormatFloat32, interleaved: false)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: blockFrames) else {
            throw CocoaError(.fileWriteUnknown)
        }

        let beats = Double(timeline.playedRange.count) / Double(TimelineTime.ticksPerBeat)
        let length = beats * 60 / bpm
        // The kernel's limiter makes everything a moment late: that much
        // at the start belongs to no note, and is left out.
        var skipped = made.unit.latencyFrames
        var written = 0

        /// Renders the next block and writes it. Returns its loudest sample.
        func renderBlock() throws -> Float {
            let status = try engine.renderOffline(blockFrames, to: buffer)
            guard status == .success, let channels = buffer.floatChannelData else {
                throw CocoaError(.fileWriteUnknown)
            }
            let frames = Int(buffer.frameLength)
            var loudest: Float = 0
            for channel in 0..<Int(buffer.format.channelCount) {
                for frame in 0..<frames { loudest = max(loudest, abs(channels[channel][frame])) }
            }
            if skipped > 0 {
                // Only the first block is cut into, and it is longer than the delay.
                let kept = frames - skipped
                for channel in 0..<Int(buffer.format.channelCount) {
                    channels[channel].update(from: channels[channel] + skipped, count: kept)
                }
                buffer.frameLength = AVAudioFrameCount(kept)
                skipped = 0
            }
            try file.write(from: buffer)
            written += Int(buffer.frameLength)
            return loudest
        }

        // The notes: each block's are sent before it is rendered, stamped
        // with their own moments, so each sounds on its exact frame.
        player.start()
        var rendered = 0.0
        while rendered < length {
            rendered += Double(blockFrames) / sampleRate
            // Short of the very end, where the timeline would start again.
            clock.advance(seconds: min(rendered, length - 1e-6) - clock.time)
            _ = try renderBlock()
            if Int(rendered * 10) != Int((rendered - Double(blockFrames) / sampleRate) * 10) { await Task.yield() }
        }
        player.stop()

        // The tail: until what is left of the last notes has died away.
        var tail = 0.0
        while tail < longestTail {
            tail += Double(blockFrames) / sampleRate
            if try renderBlock() < silence { break }
        }
        return Double(written) / sampleRate
    }
}
