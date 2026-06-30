enum ArpeggioPattern: String, CaseIterable, Identifiable, Sendable {
    case up, down, upDown, random
    var id: Self { self }
    var label: String {
        switch self {
        case .up:     return "Up"
        case .down:   return "Down"
        case .upDown: return "Up/Down"
        case .random: return "Random"
        }
    }
}

@MainActor
final class ArpeggioMode: PerformanceMode {
    var name: String { "Arpeggio" }
    var requiresClock: Bool { true }

    var pattern: ArpeggioPattern = .up

    private var cursor     = 0
    private var direction  = 1   // +1 ascending, -1 descending (upDown only)
    private var tickCount  = 0   // MasterClock fires at 1/16th; fire arpeggio every 4 ticks

    func onButtonDown(degree: Degree, state: PerformanceState) {
        state.armChord(degree: degree)
        resetCursor(noteCount: state.currentVoicing?.notes.count ?? 1)
    }

    func onButtonUp(degree: Degree, state: PerformanceState) {
        state.endChord()
    }

    func onJoystickChange(direction: JoystickDirection, state: PerformanceState) {
        guard let degree = state.activeDegree else { return }
        state.armChord(degree: degree)
        resetCursor(noteCount: state.currentVoicing?.notes.count ?? 1)
    }

    func onClockTick(state: PerformanceState) {
        tickCount += 1
        guard tickCount >= 4 else { return }
        tickCount = 0
        guard let degree = state.activeDegree,
              let voicing = state.currentVoicing,
              !voicing.notes.isEmpty else { return }
        _ = degree  // keep activeDegree reference live
        let notes = voicing.notes
        let safeIdx = cursor.clamped(to: 0...(notes.count - 1))
        state.playNote(notes[safeIdx])
        advanceCursor(noteCount: notes.count)
    }

    func deactivate(state: PerformanceState) {
        cursor = 0
        direction = 1
        state.endChord()
    }

    // MARK: – Private

    private func resetCursor(noteCount: Int) {
        direction = 1
        switch pattern {
        case .up, .upDown, .random: cursor = 0
        case .down:                  cursor = max(0, noteCount - 1)
        }
    }

    private func advanceCursor(noteCount: Int) {
        guard noteCount > 1 else { cursor = 0; return }
        switch pattern {
        case .up:
            cursor = (cursor + 1) % noteCount
        case .down:
            cursor = cursor == 0 ? noteCount - 1 : cursor - 1
        case .upDown:
            cursor += direction
            if cursor >= noteCount - 1 { cursor = noteCount - 1; direction = -1 }
            if cursor <= 0             { cursor = 0;             direction =  1 }
        case .random:
            cursor = Int.random(in: 0..<noteCount)
        }
    }
}

