@MainActor
final class DroneMode: PerformanceMode {
    var name: String { "Drone" }
    var requiresClock: Bool { false }

    private var dronedDegree: Degree?

    func onButtonDown(degree: Degree, state: PerformanceState) {
        if dronedDegree == degree {
            dronedDegree = nil
            state.endChord()
        } else {
            dronedDegree = degree
            state.startChord(degree: degree)
        }
    }

    func onButtonUp(degree: Degree, state: PerformanceState) { }

    func onJoystickChange(direction: JoystickDirection, state: PerformanceState) {
        guard let degree = dronedDegree else { return }
        state.startChord(degree: degree)
    }

    func deactivate(state: PerformanceState) {
        dronedDegree = nil
        state.endChord()
    }
}
