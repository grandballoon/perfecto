@testable import Perfecto

/// Test double for ClockTickable. Exposes tick() so tests control timing precisely.
/// Does not use any Timemmr — ticks only when the test calls tick().
@MainActor
final class ManualClock: ClockTickable {
    var bpm: Double = 120

    /// Overridable so tests can prove tempo-aware modes read the clock's
    /// resolution rather than assuming the production default of 4.
    var ticksPerBeat: Int = 4

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
