import AVFoundation

/// Recorded sound: one channel of samples, and the rate they were taken at.
struct Recording: Equatable, Sendable {
    var samples: [Float]
    var sampleRate: Double

    var duration: TimeInterval { sampleRate > 0 ? Double(samples.count) / sampleRate : 0 }
}

extension Recording {

    /// Reads the recording kept at `url`.
    init(contentsOf url: URL) throws {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let frames = AVAudioFrameCount(file.length)
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames) else {
            self.init(samples: [], sampleRate: file.processingFormat.sampleRate)
            return
        }
        try file.read(into: buffer)
        let channel = UnsafeBufferPointer(start: buffer.floatChannelData?[0], count: Int(buffer.frameLength))
        self.init(samples: Array(channel), sampleRate: file.processingFormat.sampleRate)
    }

    /// Keeps the recording at `url`, in place of what was there.
    func write(to url: URL) throws {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                                         channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(max(samples.count, 1)))
        else { throw CocoaError(.fileWriteUnknown) }
        samples.withUnsafeBufferPointer { from in
            buffer.floatChannelData?[0].update(from: from.baseAddress!, count: from.count)
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        try? FileManager.default.removeItem(at: url)
        let file = try AVAudioFile(forWriting: url, settings: format.settings,
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buffer)
    }
}
