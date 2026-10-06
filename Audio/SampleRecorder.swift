import Foundation

/// Records the mic into one of the kernel's captures, to be played as a
/// sound, and keeps the recording on disk for the next launch.
///
/// The kernel does the recording, frame for frame on the render thread;
/// this asks for it and watches for its end. A recording ends when it is
/// stopped or when its capture is full, and either way the kernel says so
/// only once it has rendered that far, so the end is watched for
/// (`check`), not assumed.
@MainActor
final class SampleRecorder {

    enum Phase: Equatable {
        case idle
        /// Asked for; the kernel has not rendered its first frame of it.
        case starting
        case recording
        /// Asked to end; the kernel has not rendered that far.
        case stopping
    }

    private(set) var phase = Phase.idle
    /// Opens the mic to the kernel, or closes it, and returns with the
    /// engine running again.
    var listen: (Bool) -> Void = { _ in }
    /// Called when a recording has ended and can be played (or was of
    /// nothing audible, and there is nothing to play).
    var onEnd: () -> Void = {}

    private let unit: KernelAudioUnit
    private let capture: Int
    private let url: URL?
    private let logger: (any Logger)?
    private var watch: Task<Void, Never>?
    /// The kernel's count of recordings ended, when this one was asked for.
    private var endedBefore = 0
    private var stopAsked = ContinuousClock.now
    /// How long a stop is waited on before the recording is taken as over.
    private static let patience = Duration.seconds(1)

    /// Where the app keeps the mic sample between launches.
    static var keptSampleURL: URL {
        URL.applicationSupportDirectory.appending(path: "mic-sample.caf")
    }

    /// Loads the recording kept at `url`, if there is one, into `unit`,
    /// which must not be rendering yet.
    init(unit: KernelAudioUnit, capture: Int, url: URL? = nil, logger: (any Logger)? = nil) {
        self.unit = unit
        self.capture = capture
        self.url = url
        self.logger = logger
        if let url, let kept = try? Recording(contentsOf: url), !kept.samples.isEmpty {
            unit.load(kept, into: capture)
        }
    }

    /// Seconds of sound there are to play.
    var duration: TimeInterval { unit.captureDuration(capture) }

    /// Starts recording, in place of what was recorded before.
    func start() {
        guard phase == .idle else { return }
        logger?.log(.sample_record_started)
        // Opening the mic starts the engine again; the recording is asked
        // for once it is running.
        listen(true)
        begin()
        watch = Task { [weak self] in
            while let self, self.phase != .idle {
                try? await Task.sleep(for: .milliseconds(30))
                self.check()
            }
        }
    }

    /// Ends the recording. It is playable a moment later (`onEnd`).
    func stop() {
        guard phase == .starting || phase == .recording else { return }
        phase = .stopping
        stopAsked = .now
        unit.stopCapture()
    }

    /// The engine has been started again, which ended whatever the kernel
    /// was recording: a recording still wanted starts over.
    func engineStarted() {
        guard phase == .starting || phase == .recording else { return }
        begin()
    }

    /// Follows the kernel: notices that the recording has begun, and that
    /// it has ended.
    func check() {
        switch phase {
        case .idle:
            break
        case .starting, .recording:
            if unit.capturesEnded != endedBefore {
                end()
            } else if unit.capturing == capture {
                phase = .recording
            }
        case .stopping:
            // An engine that is not rendering never answers.
            if unit.capturesEnded != endedBefore || ContinuousClock.now - stopAsked > Self.patience { end() }
        }
    }

    private func begin() {
        phase = .starting
        endedBefore = unit.capturesEnded
        unit.startCapture(capture)
    }

    private func end() {
        phase = .idle
        watch?.cancel()
        watch = nil
        listen(false)
        let recording = unit.captured(capture)
        if let url {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            if recording.samples.isEmpty {
                try? FileManager.default.removeItem(at: url)
            } else {
                try? recording.write(to: url)
            }
        }
        logger?.log(.sample_recorded(seconds: recording.duration))
        onEnd()
    }
}
