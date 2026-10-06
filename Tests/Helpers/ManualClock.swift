@testable import Perfecto

/// Test double for ClockTickable. Time moves only when the test says so:
/// `tick()` steps to the next tick, `advance(beats:)` moves any distance.
/// Ticks and repeats falling inside a move are called in time order.
@MainActor
final class ManualClock: ClockTickable {
    var bpm: Double = 120

    /// Overridable so tests can prove tempo-aware modes read the clock's
    /// resolution rather than assuming the production default of 4.
    var ticksPerBeat: Int = 4

    private(set) var isRunning = false

    /// Repeats that have not been cancelled.
    var repeatCount: Int { repeats.count }

    private struct Repeat {
        let beats: Double
        var due: Double
        let handler: @MainActor () -> Void
    }

    private var tickHandler: (@MainActor () -> Void)?
    private var repeats: [Int: Repeat] = [:]
    private var nextRepeatID = 0
    /// Now, in beats since the clock was made.
    private var position = 0.0
    private var ticksFired = 0

    /// Two times closer than this are the same moment.
    private static let sameMoment = 1e-9

    func start()  { isRunning = true  }
    func stop()   { isRunning = false }

    func onTick(_ handler: @escaping @MainActor () -> Void) {
        tickHandler = handler
    }

    func every(beats: Double, _ handler: @escaping @MainActor () -> Void) -> ClockRepeat {
        let id = nextRepeatID
        nextRepeatID += 1
        repeats[id] = Repeat(beats: beats, due: position + beats, handler: handler)
        return ClockRepeat { [weak self] in self?.repeats[id] = nil }
    }

    /// Advance the clock to its next tick. It ticks whether or not it was started.
    func tick() {
        advance(to: nextTick)
    }

    func advance(beats: Double) {
        advance(to: position + beats)
    }

    private var nextTick: Double { Double(ticksFired + 1) / Double(ticksPerBeat) }

    private func advance(to target: Double) {
        while true {
            let nextRepeat = repeats.min { $0.value.due < $1.value.due }
            // A tick comes before a repeat due at the same moment.
            if nextTick <= target + Self.sameMoment,
               nextTick <= (nextRepeat?.value.due ?? .infinity) + Self.sameMoment {
                position = nextTick
                ticksFired += 1
                tickHandler?()
            } else if let (id, next) = nextRepeat, next.due <= target + Self.sameMoment {
                position = next.due
                repeats[id]?.due += next.beats
                next.handler()
            } else {
                break
            }
        }
        position = max(position, target)
    }
}
