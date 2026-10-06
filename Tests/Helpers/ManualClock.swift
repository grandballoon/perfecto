@testable import Perfecto

/// Test double for ClockTickable. Time moves only when the test says so:
/// `tick()` steps to the next tick, `advance(beats:)` and `advance(seconds:)`
/// move any distance. Everything falling due inside a move is called in time
/// order, by the same `ClockSchedule` the real clock uses.
@MainActor
final class ManualClock: ClockTickable {
    var bpm: Double = 120 {
        didSet { schedule.bpm = bpm }
    }

    /// Overridable so tests can prove tempo-aware modes read the clock's
    /// resolution rather than assuming the production default of 4.
    var ticksPerBeat: Int = MusicalTime.stepsPerBeat {
        didSet {
            schedule.ticksPerBeat = ticksPerBeat
            schedule.stopTicks()
            schedule.startTicks()
        }
    }

    private(set) var isRunning = false

    var beats: Double { schedule.beats }

    /// Calls waiting to be made (repeats not cancelled, one-off calls not
    /// yet made), ticks apart.
    var pendingCount: Int { schedule.pendingCount }

    private let schedule = ClockSchedule(bpm: 120)

    init() {
        // It ticks whether or not it was started.
        schedule.startTicks()
    }

    func start()  { isRunning = true  }
    func stop()   { isRunning = false }

    func onTick(_ handler: @escaping @MainActor () -> Void) {
        schedule.onTick(handler)
    }

    func every(beats: Double, _ handler: @escaping @MainActor () -> Void) -> ClockCall {
        schedule.every(beats: beats, handler)
    }

    func after(beats: Double, first: Bool, _ handler: @escaping @MainActor () -> Void) -> ClockCall {
        schedule.after(beats: beats, first: first, handler)
    }

    func after(seconds: Double, _ handler: @escaping @MainActor () -> Void) -> ClockCall {
        schedule.after(seconds: seconds, handler)
    }

    /// Advance the clock to its next tick.
    func tick() {
        schedule.run(until: schedule.nextTick ?? schedule.now)
    }

    func advance(beats: Double) {
        advance(seconds: beats * 60 / bpm)
    }

    func advance(seconds: Double) {
        schedule.run(until: schedule.now + seconds)
    }
}
