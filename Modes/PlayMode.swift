@MainActor
final class PlayMode: PerformanceMode {
    var kind: ModeKind { .play }
    var requiresClock: Bool { false }

    func onButtonDown(key: ChordKey, state: PerformanceState) {
        state.startChord(key)
    }

    func onButtonUp(key: ChordKey, state: PerformanceState) {
        state.endChord()
    }

    func onColorChange(state: PerformanceState) {
        guard let key = state.activeKey else { return }
        state.startChord(key)
    }
}
