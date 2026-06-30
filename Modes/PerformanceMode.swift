@MainActor
protocol PerformanceMode: AnyObject {
    var name: String { get }
    var requiresClock: Bool { get }
    func onButtonDown(degree: Degree, state: PerformanceState)
    func onButtonUp(degree: Degree, state: PerformanceState)
    func onJoystickChange(direction: JoystickDirection, state: PerformanceState)
    func onClockTick(state: PerformanceState)
    func deactivate(state: PerformanceState)
}

extension PerformanceMode {
    func onClockTick(state: PerformanceState) { }
    func deactivate(state: PerformanceState) { state.endChord() }
}
