import Testing
@testable import Perfecto

/// A loop recorded from the keys, turned into notes for the timeline.
@Suite("LoopTake")
struct LoopTakeTests {

    private let cMajor = Key(root: .C, scale: .major)

    private func event(_ degree: Degree) -> ChordEvent {
        let context = performanceContext(key: cMajor, octave: 4, spec: ChordSpec(degree: degree, color: .base))
        return ChordEvent(voicing: context.voicing(after: nil), articulation: .block, context: context)
    }

    private var asPlayed: NotePlaying {
        NotePlaying(key: cMajor, octave: 4, preset: .bell, effects: NoteEffects())
    }

    // MARK: – The take

    @Test func chordsBecomeNotesTimedFromTheStartOfTheTake() {
        var take = LoopTake(start: 10)
        take.chordStarted(event(.I), pitch: .chord, playing: asPlayed, at: 10.5)
        take.chordEnded(at: 11.5)
        take.chordStarted(event(.V), pitch: .lead, playing: asPlayed, at: 12)
        take.chordEnded(at: 12.25)

        let notes = take.notes(closedAt: 14, ticksPerBeat: 480)
        #expect(notes.map(\.start) == [240, 960])
        #expect(notes.map(\.length) == [480, 120])
        #expect(notes.map(\.chord.degree) == [.I, .V])
        #expect(notes.map(\.pitch) == [.chord, .lead])
        // What it was played with is the note's own: the loop keeps its sound.
        #expect(notes.allSatisfy { $0.playing == asPlayed })
    }

    @Test func aChordReplacesTheOneBeforeAndOneStillHeldEndsAtTheClose() {
        var take = LoopTake(start: 0)
        take.chordStarted(event(.I), pitch: .chord, playing: asPlayed, at: 0)
        take.chordStarted(event(.IV), pitch: .chord, playing: asPlayed, at: 1)
        let notes = take.notes(closedAt: 3, ticksPerBeat: 480)
        #expect(notes.map(\.start) == [0, 480])
        #expect(notes.map(\.length) == [480, 960])
    }

    @Test func aTakeWithNothingPlayedIsEmpty() {
        var take = LoopTake(start: 0)
        take.chordEnded(at: 1)
        #expect(take.isEmpty)
        #expect(take.notes(closedAt: 4, ticksPerBeat: 480).isEmpty)
    }

    /// A slide played while the chord was held is kept, as the points it
    /// passed through.
    @Test func aSlideInsideAHeldChordIsRecorded() {
        var bright = NoteEffects()
        bright.filter = FilterSettings(isOn: true, brightness: 0.9)
        var take = LoopTake(start: 0)
        take.effectsChanged(to: bright, at: 0)                      // nothing held: ignored
        take.chordStarted(event(.I), pitch: .chord, playing: asPlayed, at: 0)
        take.effectsChanged(to: NoteEffects(), at: 0.2)             // no change: ignored
        take.effectsChanged(to: bright, at: 0.5)
        take.effectsChanged(to: bright, at: 0.6)                    // the same again: ignored
        take.chordEnded(at: 1)
        take.effectsChanged(to: NoteEffects(), at: 1.5)             // nothing held: ignored

        let note = take.notes(closedAt: 2, ticksPerBeat: 480)[0]
        #expect(note.changes == [SoundChange(offset: 240, effects: bright)])
    }

    // MARK: – Fitting the first loop

    /// Played at about the tempo that was set: the tempo moves a little to
    /// make it whole bars, and the bar count is the natural one.
    @Test func aLoopNearWholeBarsIsReadAsThoseBars() {
        let fit = Timeline.fit(loopOf: 7.8, at: 120, signature: .common)
        #expect(fit.bars == 2)
        #expect(abs(fit.bpm - 120 * 8 / 7.8) < 1e-9)                // a touch faster: 123.08
    }

    @Test func aShortLoopIsOneBar() {
        let fit = Timeline.fit(loopOf: 3, at: 120, signature: .common)
        #expect(fit.bars == 1)
        #expect(abs(fit.bpm - 160) < 1e-9)
    }

    @Test func theBarLengthFollowsTheSignature() {
        let waltz = TimeSignature(beats: 3, unit: .quarter)
        #expect(Timeline.fit(loopOf: 6.1, at: 100, signature: waltz).bars == 2)
        #expect(Timeline.fit(loopOf: 6.1, at: 100, signature: .common).bars == 2)   // 8 beats is nearer than 4
        #expect(Timeline.fit(loopOf: 5.9, at: 100, signature: .common).bars == 1)
    }

    /// The tempo that fits must be one the app has.
    @Test func theBarCountGivesWhenTheTempoWouldBeOutOfRange() {
        // Eight bars would need 309 BPM; seven need 271.
        let fast = Timeline.fit(loopOf: 30, at: 290, signature: .common)
        #expect(fast.bars == 7)
        #expect(abs(fast.bpm - 290 * 28 / 30) < 1e-9)
        // Two bars would need 17.8 BPM; three need 26.7.
        let slow = Timeline.fit(loopOf: 9, at: 20, signature: .common)
        #expect(slow.bars == 3)
        // One bar is the fewest there is: the tempo stops at the fastest.
        let tiny = Timeline.fit(loopOf: 1, at: 120, signature: .common)
        #expect(tiny.bars == 1 && tiny.bpm == MusicalTime.tempoRange.upperBound)
    }

    // MARK: – Folding a later take onto the loop

    private func note(_ start: Int, _ length: Int) -> TimelineNote {
        TimelineNote(start: start, length: length, chord: ChordSpec(degree: .I, color: .base))
    }

    @Test func aTakeIsPlacedWhereInTheLoopItWasPlayed() {
        let timeline = Timeline(barCount: 1)                                    // 1,920 ticks
        let rounds = timeline.folded([note(0, 100), note(400, 100)], from: 1000)
        #expect(rounds.count == 1)
        #expect(rounds[0].map(\.start) == [1000, 1400])
    }

    /// A take that runs past the end comes round to the start, as one more
    /// time round; a chord held over the seam carries on across it.
    @Test func aTakeLongerThanTheLoopIsOneLayerForEachTimeRound() {
        let timeline = Timeline(barCount: 1)
        let rounds = timeline.folded([note(0, 300), note(800, 400), note(2100, 100)], from: 1000)
        #expect(rounds.count == 2)
        #expect(rounds[0].map(\.start) == [1000, 1800])
        #expect(rounds[0].map(\.length) == [300, 120])                          // cut at the seam
        #expect(rounds[1].map(\.start) == [0, 1180])
        #expect(rounds[1].map(\.length) == [280, 100])                          // and carried on
    }

    @Test func aSlideHeldOverTheSeamGoesWithEachPart() {
        var held = note(0, 400)
        held.changes = [SoundChange(offset: 50, effects: NoteEffects()), SoundChange(offset: 300, effects: NoteEffects())]
        let rounds = Timeline(barCount: 1).folded([held], from: 1720)           // 200 before the seam
        #expect(rounds[0][0].changes.map(\.offset) == [50])
        #expect(rounds[1][0].changes.map(\.offset) == [100])
    }
}
