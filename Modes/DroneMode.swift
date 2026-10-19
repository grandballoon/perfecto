@MainActor
final class DroneMode: PerformanceMode {
    var kind: ModeKind { .drone }
    var requiresClock: Bool { false }

    private var droned: ChordKey?

    func onButtonDown(key: ChordKey, state: PerformanceState) {
        if droned == key {
            droned = nil
            state.endChord()
        } else {
            droned = key
            state.startChord(key)
        }
    }

    func onButtonUp(key: ChordKey, state: PerformanceState) { }

    func onColorChange(state: PerformanceState) {
        guard let droned else { return }
        state.startChord(droned)
    }

    func deactivate(state: PerformanceState) {
        droned = nil
        state.endChord()
    }
}
