@MainActor
final class StrumMode: PerformanceMode {
    var kind: ModeKind { .strum }
    var requiresClock: Bool { false }

    /// Seconds between successive notes of the strum, low to high.
    static let noteInterval = 0.06

    func onButtonDown(degree: Degree, state: PerformanceState) {
        state.strumChord(degree: degree, interval: Self.noteInterval)
    }

    func onButtonUp(degree: Degree, state: PerformanceState) { }

    func onColorChange(state: PerformanceState) { }
}
