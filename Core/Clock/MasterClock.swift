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

/// A call a clock has been asked to make, once or over and over. It is made
/// until `cancel()`; cancelling one that has already been made, or cancelled,
/// does nothing.
@MainActor
final class ClockCall {
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
///
/// Everything a clock calls, it calls in the order it falls due (`ClockSchedule`
/// keeps that order for both clocks):
/// - A tick is made before the other calls due at the same moment, and so
///   is a call asked for as `first`. Whatever starts a chord (a tick, the
///   timeline) can then cancel a call before it acts on the chord that was
///   replaced: an arpeggio's next note is never heard after its chord ended.
/// - Inside a call, "now" is the moment the call was due, not the moment the
///   clock got round to it. A call that asks for another one a beat later
///   gets it exactly a beat after its own time, so nothing drifts.
@MainActor
protocol ClockTickable: AnyObject {
    var bpm: Double { get set }
    /// How many ticks the clock fires per quarter-note beat. This is the one
    /// place the clock's resolution is stated: MasterClock derives its tick
    /// interval from it, and tempo-aware modes divide by it to schedule musical
    /// durations. Without it, every mode hardcoded "4" and silently depended on
    /// a resolution the protocol never exposed. Must be a multiple of
    /// `MusicalTime.stepsPerBeat`, so every sequencer step starts on a tick.
    var ticksPerBeat: Int { get }
    func start()
    func stop()
    func onTick(_ handler: @escaping @MainActor () -> Void)
    /// Calls `handler` every `beats` beats at the current tempo, first one
    /// such length from now, until the returned call is cancelled. For
    /// timing finer than a tick, or not on the tick grid at all; it runs
    /// whether or not the clock is ticking.
    /// How far the music has got, in beats since the clock was made. It
    /// moves at the tempo, so it is where a playhead is: a timeline playing
    /// from beat `b` is `beats - b` beats into itself, whatever the tempo
    /// has done since.
    var beats: Double { get }
    func every(beats: Double, _ handler: @escaping @MainActor () -> Void) -> ClockCall
    /// Calls `handler` once, `beats` beats from now. A change of tempo before
    /// then moves it, so it stays that many beats away. `first` puts it
    /// ahead of the other calls due at the same moment.
    func after(beats: Double, first: Bool, _ handler: @escaping @MainActor () -> Void) -> ClockCall
    /// Calls `handler` once, `seconds` from now, whatever the tempo does.
    func after(seconds: Double, _ handler: @escaping @MainActor () -> Void) -> ClockCall
}

extension ClockTickable {
    func after(beats: Double, _ handler: @escaping @MainActor () -> Void) -> ClockCall {
        after(beats: beats, first: false, handler)
    }

    /// Default resolution: 1/16-note ticks, one per sequencer step. Shared by
    /// every clock so production and test doubles agree.
    var ticksPerBeat: Int { MusicalTime.stepsPerBeat }
}

/// The real clock: a `ClockSchedule` run against the time since the app
/// started, by one timer set for whatever is due next.
/// The interface is intentionally simple so alternative implementations
/// (e.g. `ManualClock` in tests) can drop in without changing callers.
@MainActor
final class MasterClock: ClockTickable {
    var bpm: Double {
        get { schedule.bpm }
        set {
            settle()
            schedule.bpm = newValue.clamped(to: MusicalTime.tempoRange)
        }
    }

    private let schedule = ClockSchedule(bpm: 120)
    private var timer: Timer?
    /// The moment the schedule's time is counted from.
    private let origin = ProcessInfo.processInfo.systemUptime

    init() {
        schedule.ticksPerBeat = ticksPerBeat
        schedule.onChange = { [weak self] in self?.arm() }
    }

    var isRunning: Bool { schedule.isTicking }

    var beats: Double {
        settle()
        return schedule.beats
    }

    func onTick(_ handler: @escaping @MainActor () -> Void) {
        schedule.onTick(handler)
    }

    func start() {
        settle()
        schedule.startTicks()
    }

    func stop() {
        schedule.stopTicks()
    }

    func every(beats: Double, _ handler: @escaping @MainActor () -> Void) -> ClockCall {
        settle()
        return schedule.every(beats: beats, handler)
    }

    func after(beats: Double, first: Bool, _ handler: @escaping @MainActor () -> Void) -> ClockCall {
        settle()
        return schedule.after(beats: beats, first: first, handler)
    }

    func after(seconds: Double, _ handler: @escaping @MainActor () -> Void) -> ClockCall {
        settle()
        return schedule.after(seconds: seconds, handler)
    }

    /// Seconds since the schedule's time began.
    private var elapsed: Double { ProcessInfo.processInfo.systemUptime - origin }

    /// Brings the schedule's "now" up to the real one, so a call asked for
    /// from outside the schedule (a finger, not another call) is timed from
    /// the moment it was asked for.
    private func settle() {
        schedule.settle(at: elapsed)
    }

    /// Sets the one timer for whatever is due next.
    private func arm() {
        timer?.invalidate()
        timer = nil
        guard let due = schedule.nextDue else { return }
        // .common mode keeps the timer firing during UIKit touch-tracking; .default pauses it,
        // which causes missed ticks (and a half-second gap at the loop boundary) when the user
        // is pressing chord buttons while the sequencer is running.
        // The timer is on the main run loop, so it fires on the main actor.
        // Calling right there, rather than in a task queued from it, means a
        // call can never arrive after it was cancelled or the clock stopped.
        let t = Timer(fire: Date(timeIntervalSinceNow: max(0, due - elapsed)), interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.fire() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func fire() {
        // The app may have been held up (or suspended) for many ticks'
        // worth of time; those are skipped, not played in a burst.
        schedule.run(until: elapsed, skippingMissed: true)
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
