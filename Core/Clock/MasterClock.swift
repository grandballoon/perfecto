import Foundation

/// Musical time shared by every clock-driven feature, so none of them
/// restates "16" or "4" on its own.
enum MusicalTime {
    /// Sequencer steps are sixteenth notes.
    static let stepsPerBeat = 4
    static let beatsPerBar = 4
    static let stepsPerBar = stepsPerBeat * beatsPerBar
    /// The tempos the app supports, in BPM.
    static let tempoRange = 20.0...300.0
}

/// A call a clock makes over and over until `cancel()`.
@MainActor
final class ClockRepeat {
    private var onCancel: (() -> Void)?

    init(onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
    }

    func cancel() {
        onCancel?()
        onCancel = nil
    }
}

/// Protocol that both MasterClock (production) and ManualClock (tests) conform to.
/// Callers register a tick handler via onTick(_:) rather than conforming to a delegate.
@MainActor
protocol ClockTickable: AnyObject {
    var bpm: Double { get set }
    /// How many ticks the clock fires per quarter-note beat. This is the one
    /// place the clock's resolution is stated: MasterClock derives its timer
    /// interval from it, and tempo-aware modes divide by it to schedule musical
    /// durations. Without it, every mode hardcoded "4" and silently depended on
    /// a resolution the protocol never exposed. Must be a multiple of
    /// `MusicalTime.stepsPerBeat`, so every sequencer step starts on a tick.
    var ticksPerBeat: Int { get }
    func start()
    func stop()
    func onTick(_ handler: @escaping @MainActor () -> Void)
    /// Calls `handler` every `beats` beats at the current tempo, first one
    /// such length from now, until the returned repeat is cancelled. For
    /// timing finer than a tick, or not on the tick grid at all; it runs
    /// whether or not the clock is ticking.
    ///
    /// A call that falls due at the same moment as a tick is made after the
    /// tick's handler, so whatever the tick starts (a sequencer step) can
    /// cancel a repeat before it acts on what the tick replaced.
    func every(beats: Double, _ handler: @escaping @MainActor () -> Void) -> ClockRepeat
}

extension ClockTickable {
    /// Default resolution: 1/16-note ticks (four per beat). Shared by every
    /// clock so production and test doubles agree.
    var ticksPerBeat: Int { 4 }
}

/// Fires at 1/16th-note resolution. iOS implementation using Timer.
/// The interface (bpm/start/stop/onTick) is intentionally simple so alternative
/// implementations (e.g. `ManualClock` in tests) can drop in without changing callers.
@MainActor
final class MasterClock: ClockTickable {
    var bpm: Double = 120 {
        didSet {
            bpm = bpm.clamped(to: MusicalTime.tempoRange)
            if isRunning { schedule() }
            for id in repeats.keys { scheduleRepeat(id) }
        }
    }

    private struct Repeat {
        let beats: Double
        let handler: @MainActor () -> Void
        var timer: Timer?
    }

    private var timer: Timer?
    private var tickHandler: (@MainActor () -> Void)?
    private var repeats: [Int: Repeat] = [:]
    private var nextRepeatID = 0
    /// Repeats that fell due with a tick about to fire; called after it.
    private var repeatsAfterTick: [Int] = []

    /// How close to a tick a repeat's call counts as the same moment. Two
    /// timers set for one instant fire within a few milliseconds of each
    /// other, in either order.
    private static let sameMoment: TimeInterval = 0.005

    var isRunning: Bool { timer != nil }

    func onTick(_ handler: @escaping @MainActor () -> Void) {
        tickHandler = handler
    }

    func start() {
        schedule()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func every(beats: Double, _ handler: @escaping @MainActor () -> Void) -> ClockRepeat {
        let id = nextRepeatID
        nextRepeatID += 1
        repeats[id] = Repeat(beats: beats, handler: handler)
        scheduleRepeat(id)
        return ClockRepeat { [weak self] in
            self?.repeats.removeValue(forKey: id)?.timer?.invalidate()
        }
    }

    private func schedule() {
        timer?.invalidate()
        let interval = 60.0 / bpm / Double(ticksPerBeat)  // one tick per 1/16th note
        // .common mode keeps the timer firing during UIKit touch-tracking; .default pauses it,
        // which causes missed ticks (and a half-second gap at the loop boundary) when the user
        // is pressing chord buttons while the sequencer is running.
        // The timer is on the main run loop, so it fires on the main actor.
        // Ticking right there, rather than in a task queued from it, means a
        // tick can never arrive after the clock was stopped or restarted.
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        tickHandler?()
        let due = repeatsAfterTick
        repeatsAfterTick = []
        for id in due { repeats[id]?.handler() }
    }

    private func scheduleRepeat(_ id: Int) {
        guard let beats = repeats[id]?.beats else { return }
        repeats[id]?.timer?.invalidate()
        let t = Timer(timeInterval: 60.0 / bpm * beats, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.repeatFired(id) }
        }
        RunLoop.main.add(t, forMode: .common)
        repeats[id]?.timer = t
    }

    private func repeatFired(_ id: Int) {
        if let nextTick = timer?.fireDate, nextTick.timeIntervalSinceNow < Self.sameMoment {
            repeatsAfterTick.append(id)
        } else {
            repeats[id]?.handler()
        }
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
