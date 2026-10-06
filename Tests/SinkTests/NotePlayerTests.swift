import Testing
@testable import Perfecto

@Suite("NotePlayer")
@MainActor
struct NotePlayerTests {

    private let clock = ManualClock()

    private func strummed(_ notes: [Int], interval: Double = 0.05) -> ChordEvent {
        ChordEvent(voicing: Voicing(notes: notes), articulation: .strum(interval: interval), context: .cMajorI)
    }

    @Test func aBlockChordStartsEveryNoteAtOnce() {
        let sink = RecordingNoteSink()
        let player = NotePlayer([sink], clock: clock)
        player.playChord(.block([60, 64, 67]))
        #expect(sink.sounding == [60, 64, 67])
    }

    /// The chord-level contract: a chord replaces the one before it.
    @Test func aNewChordEndsTheOldNotesBeforeStartingItsOwn() {
        let sink = RecordingNoteSink()
        let player = NotePlayer([sink], clock: clock)
        player.playChord(.block([60, 64, 67]))
        sink.reset()
        player.playChord(.block([62, 65, 69]))

        let kinds = sink.calls.map { if case .on = $0 { "on" } else { "off" } }
        #expect(kinds == ["off", "off", "off", "on", "on", "on"])
        #expect(sink.started == [62, 65, 69])
    }

    @Test func stoppingEndsEveryNoteAndASecondStopDoesNothing() {
        let sink = RecordingNoteSink()
        let player = NotePlayer([sink], clock: clock)
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
        let player = NotePlayer([sink], clock: clock)
        player.playChord(.block([60, 64, 67]))
        player.playChord(.block([60, 65, 69]))

        let ids = sink.calls.compactMap { if case let .on(id, _) = $0 { id } else { nil } }
        #expect(Set(ids).count == 6)
        #expect(sink.sounding == [60, 65, 69])
    }

    @Test func everySinkHearsTheSameNotesUnderTheSameIds() {
        let first = RecordingNoteSink(), second = RecordingNoteSink()
        let player = NotePlayer([first, second], clock: clock)
        player.playChord(.block([60, 64, 67]))
        player.stopChord()
        #expect(first.calls == second.calls)
        #expect(first.calls.count == 6)
    }

    /// Players are independent lines: one stopping, or changing chord,
    /// leaves the other's notes alone, even on the same pitches.
    @Test func twoPlayersSoundAtOnceThroughOneSink() {
        let sink = RecordingNoteSink()
        let loop = NotePlayer([sink], clock: clock), live = NotePlayer([sink], clock: clock)
        loop.playChord(.block([60, 64, 67]))
        live.playChord(.block([60, 64, 67]))
        #expect(sink.sounding.count == 6)

        live.stopChord()
        #expect(sink.sounding == [60, 64, 67])
        live.playChord(.block([62]))
        #expect(sink.sounding == [60, 64, 67, 62])
    }

    // MARK: – Strum

    @Test func aStrumStartsItsNotesLowToHighEachAtItsOwnTime() {
        let sink = RecordingNoteSink()
        let player = NotePlayer([sink], clock: clock)
        player.playChord(strummed([60, 64, 67], interval: 0.05))
        #expect(sink.started == [60])

        clock.advance(seconds: 0.049)
        #expect(sink.started == [60])
        clock.advance(seconds: 0.002)
        #expect(sink.started == [60, 64])
        clock.advance(seconds: 0.05)
        #expect(sink.started == [60, 64, 67])
        #expect(clock.pendingCount == 0)
    }

    /// The notes are timed from the chord, not from one another, and not by
    /// the tempo: a strum is a gesture, the same at any speed.
    @Test func aStrumIsTheSameAtAnyTempo() {
        let sink = RecordingNoteSink()
        let player = NotePlayer([sink], clock: clock)
        player.playChord(strummed([60, 64, 67], interval: 0.05))
        clock.bpm = 30
        clock.advance(seconds: 0.101)
        #expect(sink.started == [60, 64, 67])
    }

    @Test func stoppingMidStrumCancelsTheNotesStillToCome() {
        let sink = RecordingNoteSink()
        let player = NotePlayer([sink], clock: clock)
        player.playChord(strummed([60, 64, 67]))
        clock.advance(seconds: 0.06)
        player.stopChord()
        #expect(sink.started == [60, 64])
        #expect(clock.pendingCount == 0)

        clock.advance(seconds: 1)
        #expect(sink.started == [60, 64])
        #expect(sink.sounding.isEmpty)
    }

    @Test func aChordReplacingAStrumCancelsTheRestOfIt() {
        let sink = RecordingNoteSink()
        let player = NotePlayer([sink], clock: clock)
        player.playChord(strummed([60, 64, 67]))
        player.playChord(.block([72]))

        clock.advance(seconds: 1)
        #expect(sink.sounding == [72])
    }
}
