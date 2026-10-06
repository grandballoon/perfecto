@testable import Perfecto

/// Recording double for NoteSink. Captures the notes started and ended
/// instead of sounding them.
@MainActor
final class RecordingNoteSink: NoteSink {

    enum Call: Equatable {
        case on(NoteID, note: Int)
        case off(NoteID)
    }

    private(set) var calls: [Call] = []
    /// The sound each note was started with, and the changes to notes held.
    private(set) var sounds: [NoteSound] = []
    private(set) var changes: [NoteSound] = []

    /// The pitches started, in order.
    var started: [Int] { calls.compactMap { if case let .on(_, note) = $0 { note } else { nil } } }

    /// The pitches sounding now, in the order they started.
    var sounding: [Int] {
        var notes: [(id: NoteID, note: Int)] = []
        for call in calls {
            switch call {
            case let .on(id, note): notes.append((id, note))
            case let .off(id):      notes.removeAll { $0.id == id }
            }
        }
        return notes.map(\.note)
    }

    func noteOn(_ id: NoteID, note: Int, sound: NoteSound) {
        calls.append(.on(id, note: note))
        sounds.append(sound)
    }

    func noteChange(_ id: NoteID, sound: NoteSound) {
        changes.append(sound)
    }

    func noteOff(_ id: NoteID) {
        calls.append(.off(id))
    }

    func reset() {
        calls = []
        sounds = []
        changes = []
    }
}
