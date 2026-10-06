import AVFoundation

/// What the app is heard through: an engine whose one source is the audio
/// kernel, hosted as an Audio Unit.
///
///     notes ─→ KernelSink ─→ KernelAudioUnit (voices, chorus, reverb, limiter) ─→ output
///
/// Everything about the sound is the kernel's; this only keeps it running:
/// it starts the engine, and starts it again when the route changes.
@MainActor
final class AudioOutput {

    /// Where notes go to be heard.
    let sink: KernelSink

    private let engine = AVAudioEngine()
    private let node: AVAudioUnit
    private let session: AudioSession
    private let logger: (any Logger)?
    private var observer: (any NSObjectProtocol)?

    init(logger: (any Logger)? = nil) {
        self.logger = logger
        session = AudioSession(logger: logger)
        let made = KernelAudioUnit.makeNode()
        node = made.node
        // The sounds are loaded before the engine first renders.
        sink = KernelSink(unit: made.unit)
        engine.attach(node)
        start()

        session.onRouteChange = { [weak self] in self?.restart() }
        // The engine stops itself when the hardware's format changes.
        observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.restart() }
        }
    }

    /// While on, the engine is stopped and the audio session given up, so
    /// another app (GarageBand, say) can own the audio while Perfecto plays
    /// it over MIDI.
    var isExternalSynth = false {
        didSet {
            guard isExternalSynth != oldValue else { return }
            if isExternalSynth {
                stop()
                session.deactivate()
            } else {
                start()
            }
        }
    }

    private func start() {
        do {
            try session.activate()
            // Connected at the hardware's rate, which a new route may have changed.
            let format = AVAudioFormat(standardFormatWithSampleRate: session.sampleRate, channels: 2)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            try engine.start()
            logger?.log(.audio_engine_started)
        } catch {
            logger?.log(.audio_engine_failed(message: error.localizedDescription))
            assertionFailure("[AudioOutput] could not start: \(error)")
        }
    }

    private func stop() {
        engine.stop()
        logger?.log(.audio_engine_stopped)
    }

    private func restart() {
        guard !isExternalSynth else { return }
        stop()
        start()
    }
}
