import AVFoundation

/// What the app is heard through, and what it hears: the audio session
/// and the engine (`AudioGraph`) kept running together.
///
/// Everything about the sound is the kernel's; this starts the engine,
/// starts it again when the route changes, and opens the mic while the
/// sample is recorded or the vocoder is on.
@MainActor
final class AudioOutput {

    /// Where notes go to be heard.
    let sink: KernelSink
    /// Records the mic sample.
    let sampleRecorder: SampleRecorder

    private let graph = AudioGraph()
    private let session: AudioSession
    private let logger: (any Logger)?
    private var observer: (any NSObjectProtocol)?
    /// Whether the mic is open to the kernel for a recording.
    private var isRecording = false {
        didSet { if isListening != (oldValue || isVocoding) { restart() } }
    }
    /// Whether the kernel hears the mic: a session that records, and the
    /// mic connected.
    private var isListening: Bool { isRecording || isVocoding }

    init(logger: (any Logger)? = nil) {
        self.logger = logger
        session = AudioSession(logger: logger)
        // The sounds and the sample kept from last time are loaded before
        // the engine first renders.
        sink = KernelSink(unit: graph.unit)
        sampleRecorder = SampleRecorder(unit: graph.unit, capture: SynthPreset.micCapture,
                                        url: SampleRecorder.keptSampleURL, logger: logger)
        start()

        sampleRecorder.listen = { [weak self] listening in
            self?.isRecording = listening
        }
        session.onRouteChange = { [weak self] in self?.restart() }
        // The engine stops itself when the hardware's format changes.
        observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: graph.engine, queue: .main
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

    /// While on, the mic is open and the vocoder shapes the notes sent to
    /// it by what it hears.
    var isVocoding = false {
        didSet {
            guard isVocoding != oldValue else { return }
            graph.unit.setVocoder(isVocoding)
            if isListening != (oldValue || isRecording) { restart() }
        }
    }

    private func start() {
        do {
            // On the speaker the vocoder would hear itself. Echo cancelling
            // is switched while the session still records, or records again.
            let cancelsEcho = isVocoding && session.isOnSpeaker
            if !cancelsEcho { try graph.setEchoCancelling(false) }
            try session.activate(recording: isListening)
            if cancelsEcho { try graph.setEchoCancelling(true) }
            try graph.start(sampleRate: session.sampleRate, listeningTo: isListening ? graph.microphone : nil)
            logger?.log(.audio_engine_started)
            sampleRecorder.engineStarted()
        } catch {
            logger?.log(.audio_engine_failed(message: error.localizedDescription))
            assertionFailure("[AudioOutput] could not start: \(error)")
        }
    }

    private func stop() {
        graph.stop()
        logger?.log(.audio_engine_stopped)
    }

    private func restart() {
        guard !isExternalSynth else { return }
        stop()
        start()
    }
}
