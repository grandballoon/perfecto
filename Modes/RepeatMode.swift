@MainActor
final class RepeatMode: PerformanceMode {
    var kind: ModeKind { .repeat }
    var requiresClock: Bool { true }

    private var held: ChordKey?
    /// The clock's call to strike the chord again, after the gap.
    private var retrigger: ClockCall?

    /// Seconds of silence before each repeat, so it is heard as a new strike.
    static let gap = 0.08
    private var tickCount = 0   // retrigger once per beat (ticksPerBeat ticks)

    func onButtonDown(key: ChordKey, state: PerformanceState) {
        cancelRetrigger()           // cancel any in-flight gap from previous key
        held = key
        state.startChord(key)
    }

    func onButtonUp(key: ChordKey, state: PerformanceState) {
        guard key == held else { return }  // ignore stale release from prior key
        cancelRetrigger()
        held = nil
        state.endChord()
    }

    func onColorChange(state: PerformanceState) {
        guard let held else { return }
        state.startChord(held)
    }

    func onClockTick(state: PerformanceState) {
        tickCount += 1
        guard tickCount >= state.ticksPerBeat else { return }
        tickCount = 0
        guard let held else { return }
        cancelRetrigger()
        state.stopSounding()        // silence without clearing OLED display
        retrigger = state.after(seconds: Self.gap) { [weak self, weak state] in
            guard self?.held != nil else { return }
            state?.startChord(held)
        }
    }

    func deactivate(state: PerformanceState) {
        cancelRetrigger()
        held = nil
        state.endChord()
    }

    private func cancelRetrigger() {
        retrigger?.cancel()
        retrigger = nil
    }
}
