import Foundation

/// Protocol that both MasterClock (production) and ManualClock (tests) conform to.
/// Callers register a tick handler via onTick(_:) rather than conforming to a delegate.
@MainActor
protocol ClockTickable: AnyObject {
    var bpm: Double { get set }
    /// How many ticks the clock fires per quarter-note beat. This is the one
    /// place the clock's resolution is stated: MasterClock derives its timer
    /// interval from it, and tempo-aware modes divide by it to schedule musical
    /// durations. Without it, every mode hardcoded "4" and silently depended on
    /// a resolution the protocol never exposed.
    var ticksPerBeat: Int { get }
    func start()
    func stop()
    func onTick(_ handler: @escaping @MainActor () -> Void)
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
        let interval = 60.0 / bpm / Double(ticksPerBeat)  // one tick per 1/16th note
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
