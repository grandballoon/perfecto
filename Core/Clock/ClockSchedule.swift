/// The calls a clock has been asked to make (ticks, repeats, one-off calls)
/// and the order they are made in. It has no timer of its own: whoever owns
/// it says how far time has got (`run(until:)`), the real clock from a
/// timer, the test clock from the test. So both clocks order and time their
/// calls by the same rules.
///
/// Time is in seconds since the schedule was made. Inside a call, `now` is
/// the moment that call was due, so a call asking for another one is timed
/// from its own due time and lateness never accumulates.
@MainActor
final class ClockSchedule {

    private enum Kind {
        case tick
        case once
        /// Repeats at this spacing, in beats.
        case every(beats: Double)
    }

    private struct Call {
        var due: Double
        let kind: Kind
        /// Whether `due` is a number of beats away, and so moves with the tempo.
        let followsTempo: Bool
        /// Whether it is made before the other calls due at the same moment.
        let isFirst: Bool
        /// The order calls were asked for in: the order they are made in
        /// when they fall due together.
        let order: Int
        let handler: @MainActor () -> Void
    }

    /// The moment time has got to, or the due time of the call being made.
    private(set) var now = 0.0

    var bpm: Double {
        didSet {
            guard bpm != oldValue else { return }
            beatsAtTempoChange += (now - tempoChanged) * oldValue / 60
            tempoChanged = now
            // A call so many beats away stays that many beats away.
            for id in calls.keys where calls[id]!.followsTempo {
                calls[id]!.due = now + (calls[id]!.due - now) * oldValue / bpm
            }
            changed()
        }
    }

    /// How far the music has got, in beats since the schedule was made: time
    /// as the tempo has counted it, so a slower tempo covers fewer beats.
    var beats: Double { beatsAtTempoChange + (now - tempoChanged) * bpm / 60 }

    /// Ticks per beat: one per sequencer step unless its owner says
    /// otherwise. A change takes effect from the tick after next.
    var ticksPerBeat = MusicalTime.stepsPerBeat

    /// Called when what is due next may have changed, other than by `run`
    /// itself getting through its calls.
    var onChange: (() -> Void)?

    /// The moment of the last tempo change, and the beats counted by then.
    private var tempoChanged = 0.0
    private var beatsAtTempoChange = 0.0

    private var calls: [Int: Call] = [:]
    private var nextOrder = 0
    private var tickHandler: (@MainActor () -> Void)?
    private var tickID: Int?
    private var isRunning = false

    /// Two times closer than this are the same moment.
    private static let sameMoment = 1e-9

    init(bpm: Double) {
        self.bpm = bpm
    }

    // MARK: – Asking for calls

    var isTicking: Bool { tickID != nil }

    func onTick(_ handler: @escaping @MainActor () -> Void) {
        tickHandler = handler
    }

    /// Starts ticking, the first tick one tick's length from now. Does
    /// nothing if already ticking.
    func startTicks() {
        guard tickID == nil else { return }
        tickID = add(.tick, due: now + seconds(forBeats: tickBeats), followsTempo: true, isFirst: true) { [weak self] in
            self?.tickHandler?()
        }
    }

    func stopTicks() {
        guard let tickID else { return }
        self.tickID = nil
        remove(tickID)
    }

    func every(beats: Double, _ handler: @escaping @MainActor () -> Void) -> ClockCall {
        precondition(beats > 0, "a repeat needs a length")
        return cancellable(add(.every(beats: beats), due: now + seconds(forBeats: beats), followsTempo: true,
                               isFirst: false, handler))
    }

    /// `first` puts the call ahead of the others due at the same moment, as
    /// a tick is.
    func after(beats: Double, first: Bool, _ handler: @escaping @MainActor () -> Void) -> ClockCall {
        cancellable(add(.once, due: now + seconds(forBeats: max(0, beats)), followsTempo: true,
                        isFirst: first, handler))
    }

    func after(seconds: Double, _ handler: @escaping @MainActor () -> Void) -> ClockCall {
        cancellable(add(.once, due: now + max(0, seconds), followsTempo: false, isFirst: false, handler))
    }

    /// Calls waiting to be made, ticks apart.
    var pendingCount: Int { calls.count - (tickID == nil ? 0 : 1) }

    // MARK: – Running

    /// When the next tick is due; nil when not ticking.
    var nextTick: Double? { tickID.map { calls[$0]!.due } }

    /// When the next call is due; nil when there is none.
    var nextDue: Double? { next.map { calls[$0]!.due } }

    /// Says that time has got to `time` without making any calls, so calls
    /// asked for next are timed from it. Calls already overdue stay due.
    /// Ignored inside a call, where "now" is the call's own time.
    func settle(at time: Double) {
        guard !isRunning else { return }
        now = max(now, time)
    }

    /// Makes every call due up to `target`, in order, and moves time there.
    /// With `skippingMissed`, a repeating call that has fallen more than a
    /// whole length behind is made once and then picks up from `target`,
    /// instead of being made once for every length missed.
    func run(until target: Double, skippingMissed: Bool = false) {
        guard !isRunning else { return }
        isRunning = true
        while let id = next, var call = calls[id], call.due <= target + Self.sameMoment {
            now = max(now, call.due)
            if let spacing = spacing(of: call.kind) {
                call.due += spacing
                if skippingMissed, call.due <= target { call.due = target + spacing }
                calls[id] = call
            } else {
                calls[id] = nil
            }
            call.handler()
        }
        now = max(now, target)
        isRunning = false
        onChange?()
    }

    // MARK: – Private

    private var tickBeats: Double { 1 / Double(ticksPerBeat) }

    private func seconds(forBeats beats: Double) -> Double {
        beats * 60 / bpm
    }

    /// Seconds from one call of `kind` to the next; nil if it is made once.
    private func spacing(of kind: Kind) -> Double? {
        switch kind {
        case .tick:              return seconds(forBeats: tickBeats)
        case .once:              return nil
        case let .every(beats):  return seconds(forBeats: beats)
        }
    }

    /// The call to make next: the earliest due and, of those due at the
    /// same moment, the ones that go first (a tick, whatever starts a
    /// chord) and then the one asked for first.
    private var next: Int? {
        guard let earliest = calls.values.map(\.due).min() else { return nil }
        return calls
            .filter { $0.value.due <= earliest + Self.sameMoment }
            .min { a, b in
                if a.value.isFirst != b.value.isFirst { return a.value.isFirst }
                return a.value.order < b.value.order
            }?.key
    }

    private func add(_ kind: Kind, due: Double, followsTempo: Bool, isFirst: Bool,
                     _ handler: @escaping @MainActor () -> Void) -> Int {
        let id = nextOrder
        nextOrder += 1
        calls[id] = Call(due: due, kind: kind, followsTempo: followsTempo, isFirst: isFirst, order: id, handler: handler)
        changed()
        return id
    }

    private func remove(_ id: Int) {
        guard calls.removeValue(forKey: id) != nil else { return }
        changed()
    }

    private func cancellable(_ id: Int) -> ClockCall {
        ClockCall { [weak self] in self?.remove(id) }
    }

    /// `run` tells its owner once, when it is through.
    private func changed() {
        if !isRunning { onChange?() }
    }
}
