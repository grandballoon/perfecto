import Foundation

/// Protocol that both MasterClock (production) and ManualClock (tests) conform to.
/// Callers register a tick handler via onTick(_:) rather than conforming to a delegate.
@MainActor
protocol ClockTickable: AnyObject {
    var bpm: Double { get set }
    func start()
    func stop()
    func onTick(_ handler: @escaping @MainActor () -> Void)
}

/// Fires at 1/16th-note resolution. iOS implementation using Timer.
/// The interface (bpm/start/stop/onTick) is intentionally simple so alternative
/// implementations (e.g. `ManualClock` in tests) can drop in without changing callers.
@MainActor
final class MasterClock: ClockTickable {
    var bpm: Double = 120 {
        didSet {
            bpm = bpm.clamped(to: 20...300)
            if isRunning { schedule() }
        }
    }

    private var timer: Timer?
    private var tickHandler: (@MainActor () -> Void)?

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

    private func schedule() {
        timer?.invalidate()
        let interval = 60.0 / bpm / 4.0  // one tick per 1/16th note
        // .common mode keeps the timer firing during UIKit touch-tracking; .default pauses it,
        // which causes missed ticks (and a half-second gap at the loop boundary) when the user
        // is pressing chord buttons while the sequencer is running.
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tickHandler?()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
