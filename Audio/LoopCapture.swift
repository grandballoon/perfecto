import AudioKit
import AVFoundation

/// Audio recorded from the capture point, stamped with where it sits on the
/// engine's sample clock.
struct LoopTake: Sendable {
    /// The sample time of the first frame.
    let start: AVAudioFramePosition
    /// One array per channel, all the same length.
    var channels: [[Float]]
    let sampleRate: Double

    var frameCount: Int { channels.first?.count ?? 0 }
}

/// Records what one node plays into memory, for the loopers.
///
/// A node can carry only one tap, so this is the single owner of the tap on
/// the capture point: every looper records through the same `LoopCapture`,
/// and a second recording while one is running is refused instead of silently
/// stealing the first one's audio.
///
/// Each buffer arrives stamped with its sample time, so a take knows exactly
/// when it started, and it is ended at an exact sample rather than at
/// whichever buffer happened to arrive last.
final class LoopCapture: @unchecked Sendable {

    enum Failure: Error {
        /// Another take is being recorded.
        case busy
        /// The capture point isn't rendering, so there is nothing to record.
        case engineNotRunning
    }

    /// The longest take kept; frames past it are dropped.
    static let maxSeconds: Double = 120

    /// How long `end` waits for the audio up to its stop time before
    /// delivering what has arrived.
    private static let endTimeoutSeconds = 0.5

    private let node: AVAudioNode

    private typealias Delivery = @MainActor @Sendable (LoopTake) -> Void

    private enum State {
        case idle
        /// The tap is filling `take` (nil until its first buffer arrives);
        /// `ending` is set once the take has been asked to stop.
        case recording(take: LoopTake?, ending: (stop: AVAudioFramePosition, deliver: Delivery)?)
        /// The take is complete and the tap is about to be removed.
        case closing
    }

    // Written by the tap's thread and the main actor; guarded by `lock`.
    private let lock = NSLock()
    private var state = State.idle
    /// Counts takes, so a late timeout can't end a newer take.
    private var generation = 0

    init(source: Node) {
        node = source.avAudioNode
    }

    /// The capture point's clock right now; nil while the engine is stopped.
    var now: AVAudioTime? {
        guard let time = node.lastRenderTime, time.isSampleTimeValid else { return nil }
        return time
    }

    /// The node whose clock stamps the takes.
    var clockNode: AVAudioNode { node }

    /// Whether a take is being recorded or is still being handed over.
    var isBusy: Bool {
        lock.withLock {
            if case .idle = state { return false }
            return true
        }
    }

    /// Starts a take.
    @MainActor
    func begin() throws {
        guard node.engine?.isRunning == true else { throw Failure.engineNotRunning }
        try lock.withLock {
            guard case .idle = state else { throw Failure.busy }
            state = .recording(take: nil, ending: nil)
            generation += 1
        }
        installTap()
    }

    /// The tap's block runs on an audio thread. It is made here, outside the
    /// main actor, so it isn't taken to be main-actor code and stopped by the
    /// runtime's isolation check the first time it is called.
    private nonisolated func installTap() {
        node.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, time in
            self?.append(buffer, at: time)
        }
    }

    /// The take so far (nil until its first buffer arrives). Recording continues.
    func snapshot() -> LoopTake? {
        lock.withLock {
            if case let .recording(take, _) = state { return take }
            return nil
        }
    }

    /// Ends the take at sample time `stop`. The audio up to `stop` is usually
    /// still on its way, so the finished take is handed to `deliver` a moment
    /// later, cut to end exactly there.
    @MainActor
    func end(at stop: AVAudioFramePosition, deliver: @escaping @MainActor @Sendable (LoopTake) -> Void) {
        let token: Int? = lock.withLock {
            guard case let .recording(take, nil) = state else { return nil }
            state = .recording(take: take, ending: (stop, deliver))
            return generation
        }
        guard let token else { return }
        finishIfComplete()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.endTimeoutSeconds))
            self.finish(onlyGeneration: token)
        }
    }

    /// Drops the take in progress, if any.
    @MainActor
    func cancel() {
        let wasRecording: Bool = lock.withLock {
            guard case .recording = state else { return false }
            state = .idle
            return true
        }
        if wasRecording { node.removeTap(onBus: 0) }
    }

    // MARK: – Private

    private func append(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime) {
        guard let data = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        let rate = buffer.format.sampleRate
        lock.withLock {
            guard case let .recording(take, ending) = state else { return }
            var current = take ?? LoopTake(
                start: time.sampleTime,
                channels: Array(repeating: [], count: Int(buffer.format.channelCount)),
                sampleRate: rate)
            // Buffers normally follow one another exactly. Keep the take
            // aligned to the clock if one doesn't: silence for a gap, and no
            // second copy of frames that overlap.
            let position = Int(time.sampleTime - current.start)
            let skipped = max(0, current.frameCount - position)
            let gap = max(0, position - current.frameCount)
            let room = Int(Self.maxSeconds * rate) - current.frameCount - gap
            let kept = min(frames - skipped, room)
            if kept > 0 {
                for c in current.channels.indices {
                    if gap > 0 { current.channels[c] += [Float](repeating: 0, count: gap) }
                    current.channels[c] += UnsafeBufferPointer(start: data[c] + skipped, count: kept)
                }
            }
            state = .recording(take: current, ending: ending)
        }
        finishIfComplete()
    }

    /// Delivers the take once it reaches the requested stop time.
    private func finishIfComplete() {
        let reached: Bool = lock.withLock {
            guard case let .recording(take?, ending?) = state else { return false }
            return take.start + AVAudioFramePosition(take.frameCount) >= ending.stop
        }
        if reached { finish(onlyGeneration: nil) }
    }

    /// Ends the take being ended, delivering what has arrived cut to the stop
    /// time. With `onlyGeneration`, does nothing unless that take is still the
    /// one being ended.
    private func finish(onlyGeneration token: Int?) {
        let finished: (LoopTake, Delivery)? = lock.withLock {
            guard case let .recording(take, ending?) = state,
                  token == nil || token == generation else { return nil }
            var result = take ?? LoopTake(start: ending.stop, channels: [], sampleRate: 0)
            let length = max(0, Int(ending.stop - result.start))
            result.channels = result.channels.map { Array($0.prefix(length)) }
            state = .closing
            return (result, ending.deliver)
        }
        guard let (result, deliver) = finished else { return }
        // The tap can't be removed from inside its own callback, and the
        // capture stays busy until it is gone.
        Task { @MainActor in
            self.node.removeTap(onBus: 0)
            self.lock.withLock { self.state = .idle }
            deliver(result)
        }
    }
}
