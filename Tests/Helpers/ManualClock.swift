@testable import Perfecto

/// Test double for ClockTickable. Exposes tick() so tests control timing precisely.
/// Does not use any Timemmr — ticks only when the test calls tick().
@MainActor
final class ManualClock: ClockTickable {
    var bpm: Double = 120

    private var tickHandler: (@MainActor () -> Void)?
    private(set) var started = false

    func start()  { started = true  }
    func stop()   { started = false }

    func onTick(_ handler: @escaping @MainActor () -> Void) {
        tickHandler = handler
    }

    /// Advance the clock by one tick. Call from tests to simulate a clock event.
    func tick() {
        tickHandler?()
    }
}
