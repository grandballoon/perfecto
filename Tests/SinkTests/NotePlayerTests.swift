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

    // MARK: – Sound

    /// Every note a player starts takes the player's sound as it is then.
    @Test func notesTakeThePlayersSound() {
        let sink = RecordingNoteSink()
        let player = NotePlayer([sink], clock: clock)
        player.sound.preset = .bell
        player.setReverb(ReverbSettings(isOn: true, mix: 0.7))
        player.playChord(.block([60, 64]))
        #expect(sink.sounds.count == 2)
        #expect(sink.sounds.allSatisfy { $0.preset == .bell && $0.reverb.mix == 0.7 && $0.reverb.isOn })
        #expect(sink.changes.isEmpty)
    }

    /// A change of sound reaches the notes being held, and only when it is
    /// a change.
    @Test func aChangeOfSoundReachesTheNotesHeld() {
        let sink = RecordingNoteSink()
        let player = NotePlayer([sink], clock: clock)
        player.playChord(.block([60, 64, 67]))
        player.setFilter(FilterSettings(isOn: true, brightness: 0.3))
        #expect(sink.changes.count == 3)
        #expect(sink.changes.allSatisfy { $0.filter.brightness == 0.3 })
        player.setFilter(FilterSettings(isOn: true, brightness: 0.3))     // the same again
        #expect(sink.changes.count == 3)

        player.stopChord()
        player.setChorus(ChorusSettings(isOn: true))                      // nothing held: nothing to change
        #expect(sink.changes.count == 3)
    }

    /// A new chord's sound is its own: the chord still sounding keeps the
    /// one it was started with.
    @Test func startingAfreshLeavesTheNotesHeldAsTheyWere() {
        let sink = RecordingNoteSink()
        let player = NotePlayer([sink], clock: clock)
        player.playChord(.block([60]))
        player.startNotes(in: NoteSound(preset: .bell))
        #expect(sink.changes.isEmpty)
        player.playChord(.block([62]))
        #expect(sink.sounds.map(\.preset) == [.initial, .bell])
    }

    /// Two players on one sink each have their own sound: a layer keeps
    /// its sound while the keys play another over it.
    @Test func eachPlayerHasItsOwnSound() {
        let sink = RecordingNoteSink()
        let keys = NotePlayer([sink], clock: clock)
        let layer = NotePlayer([sink], clock: clock)
        keys.sound.preset = .sawLead
        layer.sound.preset = .warmPad
        layer.playChord(.block([48]))
        keys.playChord(.block([72]))
        keys.setFilter(FilterSettings(isOn: true, brightness: 0.1))
        #expect(sink.sounds.map(\.preset) == [.warmPad, .sawLead])
        #expect(sink.changes.map(\.preset) == [.sawLead])                 // the layer's note is left as it was
    }

    // MARK: – Time

    /// A strum's notes are stamped with the moments they are due, exactly
    /// the interval apart, however late the clock gets round to them.
    @Test func aStrumsNotesAreStampedExactlyTheIntervalApart() {
        let sink = RecordingNoteSink()
        let player = NotePlayer([sink], clock: clock)
        clock.advance(seconds: 1)
        player.playChord(strummed([60, 64, 67, 72], interval: 0.03))
        clock.advance(seconds: 0.5)                                       // all three later notes in one late step
        #expect(sink.startTimes.count == 4)
        for (index, time) in sink.startTimes.enumerated() {
            #expect(abs(time - (1 + 0.03 * Double(index))) < 1e-9)
        }
    }

    /// What the clock plays is sounded its player's lead after the
    /// clock's time, starts and ends alike.
    @Test func aLeadPutsEveryNoteThatMuchLater() {
        let sink = RecordingNoteSink()
        let player = NotePlayer([sink], clock: clock, lead: 0.05)
        clock.advance(seconds: 2)
        player.playChord(.block([60, 64]))
        clock.advance(seconds: 0.25)
        player.setFilter(FilterSettings(isOn: true, brightness: 0.5))
        clock.advance(seconds: 0.25)
        player.stopChord()
        #expect(sink.startTimes == [2.05, 2.05])
        #expect(sink.changeTimes == [2.3, 2.3])
        #expect(sink.endTimes == [2.55, 2.55])
    }
}
