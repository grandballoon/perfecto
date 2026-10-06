import AVFoundation

/// The engine and what is connected in it:
///
///     silence ─┐
///              ├─→ KernelAudioUnit (voices, chorus, reverb, limiter) ─→ output
///     the mic ─┘      (while something is listened to)
///
/// The kernel's unit has an input, and an engine running in real time
/// renders such a unit only while something is connected to it, so a
/// source of silence always is. The silence is a player that never plays,
/// so nothing of ours runs on the render thread for it.
///
/// It knows nothing of the audio session: `AudioOutput` owns that, and
/// tests run the graph without one.
@MainActor
final class AudioGraph {

    let unit: KernelAudioUnit
    /// For observing the engine's own notifications.
    let engine = AVAudioEngine()

    private let node: AVAudioUnit
    private let input = AVAudioMixerNode()
    private let silence = AVAudioPlayerNode()

    init() {
        let made = KernelAudioUnit.makeNode()
        node = made.node
        unit = made.unit
        engine.attach(node)
        engine.attach(input)
        engine.attach(silence)
    }

    /// The device's microphone. Asking for it needs a session that records.
    var microphone: AVAudioNode { engine.inputNode }

    var isRunning: Bool { engine.isRunning }

    /// Connects everything at `sampleRate`, the hardware's (which a new
    /// route may have changed), and starts the engine. The unit hears
    /// `source` (the mic, say) if one is given, in whatever format it has.
    func start(sampleRate: Double, listeningTo source: AVAudioNode? = nil) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)
        engine.disconnectNodeInput(input)
        engine.connect(silence, to: input, format: format)
        if let source {
            if source.engine == nil { engine.attach(source) }
            engine.connect(source, to: input, format: source.outputFormat(forBus: 0))
        }
        engine.connect(input, to: node, format: format)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        try engine.start()
    }

    func stop() {
        engine.stop()
    }
}
