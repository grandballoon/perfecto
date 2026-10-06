@testable import Perfecto

/// The test double for `ClockTickable`: time moves only when the test says
/// so. It is the app's own `SteppedClock`.
typealias ManualClock = SteppedClock
