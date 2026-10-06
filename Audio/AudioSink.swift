import AudioKit
import AVFoundation
import SoundpipeAudioKit

/// Drives a pool of `polyphony` SynthVoices from chord events.
/// Signal chain: SynthVoices → synthMixer → BrightnessFilter → liveMixer → EffectsChain → AudioEngine output
///               Looper players → each track's EffectsChain → looper.outputMixer ↗
/// The loopers record the filter's output (through one shared `LoopCapture`),
/// so a loop holds what was played, as bright as it was played, and never the
/// other loops. They record it
/// before the effects, and each loop then plays through effects of its own,
/// set as the live ones were set when it was closed (not as they were being
/// played): later changes to the
/// effects reach only what is played next, and a loop's reverb tail carries
/// on across its seam.
@MainActor
final class AudioSink: ChordEventSink, AudioEffects {

    /// Voices in the pool: the most notes one chord can sound. Notes past this
    /// are dropped and logged (`audio_notes_dropped`); MIDI still sends them.
    static let polyphony = 8

    /// Layers the play-mode looper can hold.
    static let quickLoopTrackCount = 6

    private let engine     = AudioEngine()
    private var voices:    [SynthVoice] = []
    private let synthMixer = Mixer()
    private var filter:    BrightnessFilter!
    private var effects:   EffectsChain!
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
            .playAndRecord, mode: .default, options: Self.sessionOptions)
        try? AVAudioSession.sharedInstance().setActive(true)
        Settings.sampleRate = AVAudioSession.sharedInstance().sampleRate

        for _ in 0..<Self.polyphony {
            let voice = SynthVoice(patch: SynthPreset.initial.patch)
            voices.append(voice)
            synthMixer.addInput(voice.node)
        }
        filter       = BrightnessFilter(synthMixer)
        let capture  = LoopCapture(source: filter.output)
        looper       = Looper(capture: capture, trackCount: 2, logger: logger)
        quickLooper  = Looper(capture: capture, trackCount: Self.quickLoopTrackCount, logger: logger)
        micSampler   = MicSampler(engine: engine)
        effects = EffectsChain(Mixer([filter.output, micSampler.outputMixer]))
        engine.output = Mixer([effects.output, looper.outputMixer, quickLooper.outputMixer])

        do {
            try configureSession()
            try engine.start()
            // AudioKit reconfigures AVAudioSession during start(), so re-apply our options
            // afterward to ensure .defaultToSpeaker takes effect when no headphones are present.
            try configureSession()
            // Sources are switched on once the engine runs.
            setPreset(.initial)
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
                loopersDidRestart()
            }
        }
    }

    // .playAndRecord blocks AirPlay and A2DP Bluetooth unless explicitly allowed.
    // Allowing them lets the user route output to a Mac (AirPlay Receiver) or a
    // Bluetooth speaker/headphones while the mic stays on the built-in input.
    private static let sessionOptions: AVAudioSession.CategoryOptions = [
        .mixWithOthers, .defaultToSpeaker, .allowAirPlay, .allowBluetoothA2DP,
    ]

    /// 256 frames at 48 kHz.
    private static let ioBufferDuration: TimeInterval = 256.0 / 48_000

    private func configureSession() throws {
        try AVAudioSession.sharedInstance().setCategory(
            .playAndRecord,
            mode: .default,
            options: Self.sessionOptions
        )
        // Small render cycles keep the delay from touch to sound, and from
        // closing a loop to hearing it come round, to a few milliseconds.
        try AVAudioSession.sharedInstance().setPreferredIOBufferDuration(Self.ioBufferDuration)
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
            loopersDidRestart()
        } catch {
            logger?.log(.audio_engine_failed(message: error.localizedDescription))
            print("[AudioSink] route-change restart error: \(error)")
        }
    }

    private func loopersDidRestart() {
        looper.engineDidRestart()
        quickLooper.engineDidRestart()
    }

    func playChord(_ event: ChordEvent) {
        stopChord()
        let notes = event.voicing.notes
        if notes.count > voices.count {
            logger?.log(.audio_notes_dropped(requested: notes.count, voices: voices.count))
        }
        filter.settle()
        strumTask = startNotes(Array(notes.prefix(voices.count)), event.articulation) { [weak self] i, note in
            self?.voices[i].noteOn(midiNote: note)
        }
    }

    func stopChord() {
        strumTask?.cancel()
        strumTask = nil
        for voice in voices { voice.noteOff() }
    }

    /// Switches every voice to `preset`. Notes that are sounding are released.
    func setPreset(_ preset: SynthPreset) {
        stopChord()
        for voice in voices { voice.apply(preset.patch) }
    }

    func setFilter(_ settings: FilterSettings) {
        filter.apply(settings)
    }

    func setChorus(_ settings: ChorusSettings) {
        effects.apply(settings)
    }

    func setReverb(_ settings: ReverbSettings) {
        effects.apply(settings)
    }

    func setLoopEffects(_ effects: SoundEffects) {
        looper.liveEffects = effects
        quickLooper.liveEffects = effects
    }
}
