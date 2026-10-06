import Testing
@testable import Perfecto

@Suite("NotePlayer")
@MainActor
struct NotePlayerTests {

    private func strummed(_ notes: [Int], interval: Double = 0.05) -> ChordEvent {
        ChordEvent(voicing: Voicing(notes: notes), articulation: .strum(interval: interval), context: .cMajorI)
    }

    @Test func aBlockChordStartsEveryNoteAtOnce() {
        let sink = RecordingNoteSink()
        let player = NotePlayer([sink])
        player.playChord(.block([60, 64, 67]))
        #expect(sink.sounding == [60, 64, 67])
    }

    /// The chord-level contract: a chord replaces the one before it.
    @Test func aNewChordEndsTheOldNotesBeforeStartingItsOwn() {
        let sink = RecordingNoteSink()
        let player = NotePlayer([sink])
        player.playChord(.block([60, 64, 67]))
        sink.reset()
        player.playChord(.block([62, 65, 69]))

        let kinds = sink.calls.map { if case .on = $0 { "on" } else { "off" } }
        #expect(kinds == ["off", "off", "off", "on", "on", "on"])
        #expect(sink.started == [62, 65, 69])
    }

    @Test func stoppingEndsEveryNoteAndASecondStopDoesNothing() {
        let sink = RecordingNoteSink()
        let player = NotePlayer([sink])
        player.playChord(.block([60, 64, 67]))
        player.stopChord()
        #expect(sink.sounding.isEmpty)
        sink.reset()
        player.stopChord()
        #expect(sink.calls.isEmpty)
    }

    /// A chord that shares a pitch with the one before starts it as a new
    /// note, so the sink is never asked to start a note it is still holding.
    @Test func everyNoteHasAnIdOfItsOwn() {
        let sink = RecordingNoteSink()
        let player = NotePlayer([sink])
        player.playChord(.block([60, 64, 67]))
        player.playChord(.block([60, 65, 69]))

        let ids = sink.calls.compactMap { if case let .on(id, _) = $0 { id } else { nil } }
        #expect(Set(ids).count == 6)
        #expect(sink.sounding == [60, 65, 69])
    }

    @Test func everySinkHearsTheSameNotesUnderTheSameIds() {
        let first = RecordingNoteSink(), second = RecordingNoteSink()
        let player = NotePlayer([first, second])
        player.playChord(.block([60, 64, 67]))
        player.stopChord()
        #expect(first.calls == second.calls)
        #expect(first.calls.count == 6)
    }

    /// Players are independent lines: one stopping, or changing chord,
    /// leaves the other's notes alone, even on the same pitches.
    @Test func twoPlayersSoundAtOnceThroughOneSink() {
        let sink = RecordingNoteSink()
        let loop = NotePlayer([sink]), live = NotePlayer([sink])
        loop.playChord(.block([60, 64, 67]))
        live.playChord(.block([60, 64, 67]))
        #expect(sink.sounding.count == 6)

        live.stopChord()
        #expect(sink.sounding == [60, 64, 67])
        live.playChord(.block([62]))
        #expect(sink.sounding == [60, 64, 67, 62])
    }

    // MARK: – Strum

    @Test func aStrumStartsItsNotesLowToHighOneAtATime() async throws {
        let sink = RecordingNoteSink()
        let player = NotePlayer([sink])
        player.playChord(strummed([60, 64, 67]))
        #expect(sink.started.count < 3)

        _ = try await waitUntil { sink.started.count == 3 }
        #expect(sink.started == [60, 64, 67])
    }

    @Test func stoppingMidStrumCancelsTheNotesStillToCome() async throws {
        let sink = RecordingNoteSink()
        let player = NotePlayer([sink])
        player.playChord(strummed([60, 64, 67]))
        try await Task.sleep(for: .milliseconds(20))
        player.stopChord()
        let startedAtStop = sink.started.count

        try await Task.sleep(for: .milliseconds(200))
        #expect(sink.started.count == startedAtStop)
        #expect(sink.sounding.isEmpty)
    }

    @Test func aChordReplacingAStrumCancelsTheRestOfIt() async throws {
        let sink = RecordingNoteSink()
        let player = NotePlayer([sink])
        player.playChord(strummed([60, 64, 67]))
        player.playChord(.block([72]))

        try await Task.sleep(for: .milliseconds(200))
        #expect(sink.sounding == [72])
    }
}
