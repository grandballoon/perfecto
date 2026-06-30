@MainActor
final class LeadMode: PerformanceMode {
    var name: String { "Lead" }
    var requiresClock: Bool { false }

    func onButtonDown(degree: Degree, state: PerformanceState) {
        state.leadNote(degree: degree)
    }

    func onButtonUp(degree: Degree, state: PerformanceState) {
        state.endChord()
    }

    func onJoystickChange(direction: JoystickDirection, state: PerformanceState) {
        guard let degree = state.activeDegree else { return }
        state.leadNote(degree: degree)
    }
}
