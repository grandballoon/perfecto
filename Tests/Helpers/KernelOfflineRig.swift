import AVFoundation
import Testing
@testable import Perfecto

/// An offline engine whose only source is the kernel's unit: what the app
/// hears from it, rendered into memory.
@MainActor
final class KernelOfflineRig {
    static let rate = 48_000.0

    let engine = AVAudioEngine()
    let unit: KernelAudioUnit
    /// Everything the engine has rendered, the unit's delay included.
    private var rendered: [Float] = []
    /// What has been heard, by the frame it belongs to: `output[f]` is
    /// what an event on frame `f` makes.
    var output: [Float] { Array(rendered.dropFirst(unit.latencyFrames)) }
    private let buffer: AVAudioPCMBuffer

    /// `sounds` are loaded before the engine starts, numbered from 0, and
    /// `configure` is run then too, for whatever else must be done before
    /// the unit renders.
    init(bufferSize: AVAudioFrameCount = 256, sounds: [SynthPatch] = [],
         configure: (KernelAudioUnit) -> Void = { _ in }) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: Self.rate, channels: 2)!
        let made = KernelAudioUnit.makeNode()
        unit = made.unit
        for (number, patch) in sounds.enumerated() { unit.setSound(number, to: patch) }
        configure(unit)
        engine.attach(made.node)
        engine.connect(made.node, to: engine.outputNode, format: format)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: bufferSize)
        try engine.start()
        buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: bufferSize)!
    }

    /// Renders until `frames` frames have been heard: the unit's
    /// delay (its limiter looks ahead) is rendered past.
    func render(_ frames: Int) throws {
        while rendered.count < frames + unit.latencyFrames {
            let wanted = min(buffer.frameCapacity,
                             AVAudioFrameCount(frames + unit.latencyFrames - rendered.count))
            let status = try engine.renderOffline(wanted, to: buffer)
            #expect(status == .success)
            rendered += UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength))
        }
    }
}

/// The loudest sample of `samples`.
func loudest(_ samples: some Sequence<Float>) -> Float {
    samples.map(abs).max() ?? 0
}
