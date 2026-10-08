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
/// An engine that has opened the mic keeps an input on its hardware unit
/// for good, connected or not, and with one it cannot start in a session
/// that only plays. So the engine does not outlive its use of the mic: the
/// next start that is not for the mic is a new engine's, with the same
/// unit in it.
///
/// It knows nothing of the audio session: `AudioOutput` owns that, and
/// tests run the graph without one.
@MainActor
final class AudioGraph {

    /// What the unit can hear, beside silence.
    enum Source {
        /// The device's microphone, which needs a session that records.
        case microphone
        case node(AVAudioNode)
    }

    let unit: KernelAudioUnit
    /// The engine there is now: a start may replace it.
    private(set) var engine = AVAudioEngine()
    /// Called when the engine has stopped itself because the hardware's
    /// format changed, and is to be started again.
    var onConfigurationChange: (() -> Void)?

    private let node: AVAudioUnit
    private var input = AVAudioMixerNode()
    private var silence = AVAudioPlayerNode()
    /// Whether this engine has opened the mic.
    private var hasOpenedMicrophone = false
    private var cancelsEcho = false
    private var observer: (any NSObjectProtocol)?

    init() {
        let made = KernelAudioUnit.makeNode()
        node = made.node
        unit = made.unit
        assemble()
    }

    var isRunning: Bool { engine.isRunning }

    /// Connects everything at `sampleRate`, the hardware's (which a new
    /// route may have changed), and starts the engine. The unit hears
    /// `source` if one is given, in whatever format it has.
    func start(sampleRate: Double, listeningTo source: Source? = nil) throws {
        if hasOpenedMicrophone, source?.isMicrophone != true { replaceEngine() }
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)
        engine.disconnectNodeInput(input)
        engine.connect(silence, to: input, format: format)
        if let heard = source.map(node(for:)) {
            engine.connect(heard, to: input, format: heard.outputFormat(forBus: 0))
        }
        engine.connect(input, to: node, format: format)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        try engine.start()
    }

    func stop() {
        engine.stop()
    }

    /// Has the device take its own sound out of what the mic hears, so
    /// that what plays from the speaker is not heard again. It dulls
    /// everything played while it is on, so it is for when the speaker and
    /// the mic are both in use, and is switched off again after. Only
    /// while the engine is stopped, in a session that records.
    func setEchoCancelling(_ isOn: Bool) throws {
        guard isOn != cancelsEcho else { return }
        try microphone.setVoiceProcessingEnabled(isOn)
        cancelsEcho = isOn
    }

    /// The engine's own node for the mic. Asking for it is what opens the
    /// mic, so it is asked for nowhere else.
    private var microphone: AVAudioInputNode {
        hasOpenedMicrophone = true
        return engine.inputNode
    }

    private func node(for source: Source) -> AVAudioNode {
        switch source {
        case .microphone:
            return microphone
        case .node(let node):
            if node.engine !== engine {
                node.engine?.detach(node)
                engine.attach(node)
            }
            return node
        }
    }

    /// Puts the unit, and what feeds it, in the engine.
    private func assemble() {
        engine.attach(node)
        engine.attach(input)
        engine.attach(silence)
        observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.onConfigurationChange?() }
        }
    }

    /// Leaves the engine for a new one that has never opened the mic. Only
    /// the unit is taken along: it has the kernel, with its sounds and
    /// recordings.
    private func replaceEngine() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        engine.stop()
        engine.detach(node)
        engine = AVAudioEngine()
        input = AVAudioMixerNode()
        silence = AVAudioPlayerNode()
        hasOpenedMicrophone = false
        cancelsEcho = false
        assemble()
    }
}

private extension AudioGraph.Source {
    var isMicrophone: Bool {
        if case .microphone = self { true } else { false }
    }
}
