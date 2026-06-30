@MainActor
final class RepeatMode: PerformanceMode {
    var name: String { "Repeat" }
    var requiresClock: Bool { true }

    private var heldDegree: Degree?
    private var retriggerTask: Task<Void, Never>?
    private var tickCount = 0   // MasterClock fires at 1/16th; retrigger every 4 ticks

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

    func onJoystickChange(direction: JoystickDirection, state: PerformanceState) {
        guard let degree = heldDegree else { return }
        state.startChord(degree: degree)
    }

    func onClockTick(state: PerformanceState) {
        tickCount += 1
        guard tickCount >= 4 else { return }
        tickCount = 0
        guard let degree = heldDegree else { return }
        cancelRetrigger()
        state.stopAudioOnly()       // silence without clearing OLED display
        retriggerTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 80_000_000)  // 80 ms silent gap
            guard let self, !Task.isCancelled, self.heldDegree != nil else { return }
            state.startChord(degree: degree)
        }
    }

    func deactivate(state: PerformanceState) {
        cancelRetrigger()
        heldDegree = nil
        state.endChord()
    }

    private func cancelRetrigger() {
        retriggerTask?.cancel()
        retriggerTask = nil
    }
}
