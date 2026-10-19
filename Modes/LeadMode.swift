@MainActor
final class LeadMode: PerformanceMode {
    var kind: ModeKind { .lead }
    var requiresClock: Bool { false }

    func onButtonDown(key: ChordKey, state: PerformanceState) {
        state.leadNote(key)
    }

    func onButtonUp(key: ChordKey, state: PerformanceState) {
        state.endChord()
    }

    func onColorChange(state: PerformanceState) {
        guard let key = state.activeKey else { return }
        state.leadNote(key)
    }
}
