@MainActor
final class StrumMode: PerformanceMode {
    var name: String { "Strum" }
    var requiresClock: Bool { false }

    func onButtonDown(degree: Degree, state: PerformanceState) {
        state.strumChord(degree: degree)
    }

    func onButtonUp(degree: Degree, state: PerformanceState) { }

    func onJoystickChange(direction: JoystickDirection, state: PerformanceState) { }
}
