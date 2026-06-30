import AudioKit
import AVFoundation
import SoundpipeAudioKit

/// Drives six polyphonic SynthVoices from chord voicings.
/// Signal chain: SynthVoices → synthMixer → finalMixer → AudioEngine output
///               Looper players        → looper.outputMixer ↗
@MainActor
final class AudioSink: ChordEventSink {

    private let engine     = AudioEngine()
    private var voices:    [SynthVoice] = []
    private let synthMixer = Mixer()
    private var strumTask: Task<Void, Never>?
    private let logger: (any Logger)?

    private(set) var looper:       Looper!
    private(set) var quickLooper:  Looper!
    private(set) var micSampler:   MicSampler!

    init(logger: (any Logger)? = nil) {
        self.logger = logger
        // Activate the session and sync Settings.sampleRate to the hardware rate
        // BEFORE creating any AudioKit nodes. AudioPlayer graph connections inherit
        // their output format from Settings.sampleRate at creation time; if it stays
        // at AudioKit's default (44100 Hz) while the hardware runs at 48000 Hz, loops
        // play back ~1.5 semitones flat. configureSession() below keeps this in sync
        // across engine restarts as well.
        try? AVAudioSession.sharedInstance().setCategory(
            .playAndRecord, mode: .default, options: [.mixWithOthers, .defaultToSpeaker])
        try? AVAudioSession.sharedInstance().setActive(true)
        Settings.sampleRate = AVAudioSession.sharedInstance().sampleRate

        for _ in 0..<6 {
            let voice = SynthVoice()
            voices.append(voice)
            synthMixer.addInput(voice.node)
        }
        looper       = Looper(synthSource: synthMixer, trackCount: 2)
        quickLooper  = Looper(synthSource: synthMixer, trackCount: 6)
        micSampler   = MicSampler(engine: engine)
        let finalMixer = Mixer([synthMixer, looper.outputMixer, quickLooper.outputMixer, micSampler.outputMixer])
        engine.output = finalMixer

        do {
            try configureSession()
            try engine.start()
            // AudioKit reconfigures AVAudioSession during start(), so re-apply our options
            // afterward to ensure .defaultToSpeaker takes effect when no headphones are present.
            try configureSession()
            for voice in voices { voice.prepare() }
            logger?.log(.audio_engine_started)
        } catch {
            logger?.log(.audio_engine_failed(message: error.localizedDescription))
            print("[AudioSink] startup error: \(error)")
            assertionFailure("[AudioSink] startup error: \(error)")
        }

        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason) else { return }
            switch reason {
            case .newDeviceAvailable, .oldDeviceUnavailable:
                Task { @MainActor in
                    let portName = AVAudioSession.sharedInstance().currentRoute
                        .outputs.first?.portName ?? "unknown"
                    self.logger?.log(.audio_route_changed(to: portName, reason: String(describing: reason)))
                    self.restartEngine()
                }
            default:
                break
            }
        }
    }

    // When true, the AudioKit engine is stopped and the audio session is released so an
    // external app (e.g. GarageBand) can own audio while Perfecto drives it via MIDI.
    var isExternalSynth: Bool = false {
        didSet {
            if isExternalSynth {
                engine.stop()
                logger?.log(.audio_engine_stopped)
                try? AVAudioSession.sharedInstance().setActive(
                    false, options: .notifyOthersOnDeactivation)
            } else {
                try? configureSession()
                try? engine.start()
                logger?.log(.audio_engine_started)
            }
        }
    }

    private func configureSession() throws {
        try AVAudioSession.sharedInstance().setCategory(
            .playAndRecord,
            mode: .default,
            options: [.mixWithOthers, .defaultToSpeaker]
        )
        try AVAudioSession.sharedInstance().setActive(true)
        // Re-sync Settings.sampleRate in case engine.start() reset it.
        // The primary sync happens before node creation in init(); this keeps
        // NodeRecorder and AudioPlayer aligned across engine restarts too.
        Settings.sampleRate = AVAudioSession.sharedInstance().sampleRate
        logger?.log(.audio_session_activated(
            category: "playAndRecord",
            mode: "default",
            sampleRate: AVAudioSession.sharedInstance().sampleRate
        ))
    }

    private func restartEngine() {
        engine.stop()
        logger?.log(.audio_engine_stopped)
        do {
            try configureSession()
            try engine.start()
            try configureSession()
            logger?.log(.audio_engine_started)
        } catch {
            logger?.log(.audio_engine_failed(message: error.localizedDescription))
            print("[AudioSink] route-change restart error: \(error)")
        }
    }

    func playChord(_ voicing: Voicing) {
        stopChord()
        for (voice, note) in zip(voices, voicing.notes.prefix(voices.count)) {
            voice.noteOn(midiNote: note)
        }
    }

    func strumChord(_ voicing: Voicing, interval: TimeInterval = 0.06) {
        strumTask?.cancel()
        for voice in voices { voice.noteOff() }
        let notes = Array(voicing.notes.prefix(voices.count))
        strumTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for (i, note) in notes.enumerated() {
                guard !Task.isCancelled else { return }
                voices[i].noteOn(midiNote: note)
                try? await Task.sleep(nanoseconds: 60_000_000)
            }
            strumTask = nil
        }
    }

    func stopChord() {
        strumTask?.cancel()
        strumTask = nil
        for voice in voices { voice.noteOff() }
    }

    func setPreset(_ preset: SynthPreset) {
        stopChord()
        for voice in voices { synthMixer.removeInput(voice.node) }
        voices = (0..<6).map { _ in
            let voice = SynthVoice(waveform: preset.table)
            synthMixer.addInput(voice.node)
            voice.prepare()
            voice.applyEnvelope(from: preset)
            return voice
        }
    }
}
