@MainActor
final class PlayMode: PerformanceMode {
    var kind: ModeKind { .play }
    var requiresClock: Bool { false }

    func onButtonDown(degree: Degree, state: PerformanceState) {
        state.startChord(degree: degree)
    }

    func onButtonUp(degree: Degree, state: PerformanceState) {
        state.endChord()
    }

    func onColorChange(state: PerformanceState) {
        guard let degree = state.activeDegree else { return }
        state.startChord(degree: degree)
    }
}
