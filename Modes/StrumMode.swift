@MainActor
final class StrumMode: PerformanceMode {
    var kind: ModeKind { .strum }
    var requiresClock: Bool { false }

    /// Seconds between successive notes of the strum, low to high.
    static let noteInterval = 0.06

    func onButtonDown(key: ChordKey, state: PerformanceState) {
        state.strumChord(key, interval: Self.noteInterval)
    }

    func onButtonUp(key: ChordKey, state: PerformanceState) { }

    func onColorChange(state: PerformanceState) { }
}
