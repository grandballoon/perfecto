@MainActor
final class RepeatMode: PerformanceMode {
    var kind: ModeKind { .repeat }
    var requiresClock: Bool { true }

    private var heldDegree: Degree?
    /// The clock's call to strike the chord again, after the gap.
    private var retrigger: ClockCall?

    /// Seconds of silence before each repeat, so it is heard as a new strike.
    static let gap = 0.08
    private var tickCount = 0   // retrigger once per beat (ticksPerBeat ticks)

    func onButtonDown(degree: Degree, state: PerformanceState) {
        cancelRetrigger()           // cancel any in-flight gap from previous key
        heldDegree = degree
        state.startChord(degree: degree)
    }

    func onButtonUp(degree: Degree, state: PerformanceState) {
        guard degree == heldDegree else { return }  // ignore stale release from prior key
        cancelRetrigger()
        heldDegree = nil
        state.endChord()
    }

    func onColorChange(state: PerformanceState) {
        guard let degree = heldDegree else { return }
        state.startChord(degree: degree)
    }

    func onClockTick(state: PerformanceState) {
        tickCount += 1
        guard tickCount >= state.ticksPerBeat else { return }
        tickCount = 0
        guard let degree = heldDegree else { return }
        cancelRetrigger()
        state.stopSounding()        // silence without clearing OLED display
        retrigger = state.after(seconds: Self.gap) { [weak self, weak state] in
            guard self?.heldDegree != nil else { return }
            state?.startChord(degree: degree)
        }
    }

    func deactivate(state: PerformanceState) {
        cancelRetrigger()
        heldDegree = nil
        state.endChord()
    }

    private func cancelRetrigger() {
        retrigger?.cancel()
        retrigger = nil
    }
}
