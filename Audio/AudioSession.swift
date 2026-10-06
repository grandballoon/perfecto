import AVFoundation

/// The app's audio session: the one place its category, buffer size and
/// route are decided.
///
/// The app only plays for now, and mixes with other apps so it can sit
/// beside a DAW. Recording (the mic sample, the vocoder) will ask for the
/// input when it arrives.
@MainActor
final class AudioSession {

    /// 256 frames at 48 kHz: small render cycles keep the delay from touch
    /// to sound to a few milliseconds.
    private static let ioBufferDuration: TimeInterval = 256.0 / 48_000

    /// Called when headphones, a speaker or a display is connected or
    /// taken away, after which the hardware may run at another rate.
    var onRouteChange: (() -> Void)?

    private let session = AVAudioSession.sharedInstance()
    private let logger: (any Logger)?
    private var observer: (any NSObjectProtocol)?

    init(logger: (any Logger)? = nil) {
        self.logger = logger
        observer = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: raw),
                  reason == .newDeviceAvailable || reason == .oldDeviceUnavailable else { return }
            Task { @MainActor in
                guard let self else { return }
                let port = self.session.currentRoute.outputs.first?.portName ?? "unknown"
                self.logger?.log(.audio_route_changed(to: port, reason: String(describing: reason)))
                self.onRouteChange?()
            }
        }
    }

    /// The rate the hardware runs at.
    var sampleRate: Double { session.sampleRate }

    /// Takes the session for playing.
    func activate() throws {
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setPreferredIOBufferDuration(Self.ioBufferDuration)
        try session.setActive(true)
        logger?.log(.audio_session_activated(category: "playback", mode: "default", sampleRate: session.sampleRate))
    }

    /// Gives the session up, so another app can have the audio to itself.
    func deactivate() {
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }
}
