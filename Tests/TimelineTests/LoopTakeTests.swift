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
        var voiced = NoteEffects()
        voiced.vocoder = VocoderSettings(isOn: true, amount: 0.9)
        var take = LoopTake(start: 0)
        take.effectsChanged(to: voiced, at: 0)                      // nothing held: ignored
        take.chordStarted(event(.I), pitch: .chord, playing: asPlayed, at: 0)
        take.effectsChanged(to: NoteEffects(), at: 0.2)             // no change: ignored
        take.effectsChanged(to: voiced, at: 0.5)
        take.effectsChanged(to: voiced, at: 0.6)                    // the same again: ignored
        take.chordEnded(at: 1)
        take.effectsChanged(to: NoteEffects(), at: 1.5)             // nothing held: ignored

        let note = take.notes(closedAt: 2, ticksPerBeat: 480)[0]
        #expect(note.changes == [SoundChange(offset: 240, effects: voiced)])
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

    // MARK: – Laying a take on the timeline

    @Test func aFirstTakeMakesTheTimelineItsLength() {
        let laid = Timeline().layering([[note(0, 100), note(2000, 100)]], bars: 2, from: 700)
        #expect(laid.barCount == 2)
        #expect(laid.layers.count == 1)
        #expect(laid.layers[0].notes.map(\.start) == [0, 2000])               // from its top, whatever the offset
    }

    /// A take as long as the timeline is placed where in it it was played.
    @Test func aTakeIsLaidWhereInTheTimelineItWasPlayed() {
        let timeline = Timeline(barCount: 1, layers: [Layer(notes: [note(0, 1920)])])
        let laid = timeline.layering([[note(0, 100), note(1200, 100)]], bars: 1, from: 1000)
        #expect(laid.barCount == 1)
        #expect(laid.layers[1].notes.map(\.start) == [280, 1000])              // what passed the end came round
    }

    /// A take shorter than the timeline is played again every time it
    /// comes round within it.
    @Test func aShorterTakeIsRepeatedRoundTheTimeline() {
        let timeline = Timeline(barCount: 4, layers: [Layer(notes: [note(0, 1920)])])
        let laid = timeline.layering([[note(0, 100)]], bars: 1, from: 500)
        #expect(laid.barCount == 4)
        #expect(laid.layers[1].notes.map(\.start) == [500, 2420, 4340, 6260])
    }

    /// A take longer than the timeline lengthens it, and what was there
    /// plays again each time round, so nothing falls out of time.
    @Test func aLongerTakeRepeatsTheTimelineUnderIt() {
        let timeline = Timeline(barCount: 1, layers: [Layer(notes: [note(0, 960), note(960, 960)])])
        let laid = timeline.layering([[note(0, 100), note(1920, 100)]], bars: 2, from: 960)
        #expect(laid.barCount == 2)
        #expect(laid.layers[0].notes.map(\.start) == [0, 960, 1920, 2880])
        #expect(laid.layers[1].notes.map(\.start) == [960, 2880])
    }

    /// Lengths where neither is a whole number of the other meet at the
    /// least they both go into.
    @Test func lengthsThatDoNotDivideMeetWhereTheyComeRoundTogether() {
        let timeline = Timeline(barCount: 3, layers: [Layer(notes: [note(0, 100)])])
        let laid = timeline.layering([[note(0, 100)]], bars: 2, from: 0)
        #expect(laid.barCount == 6)
        #expect(laid.layers[0].notes.map(\.start) == [0, 5760])
        #expect(laid.layers[1].notes.map(\.start) == [0, 3840, 7680])
    }

    /// A take is a layer of its own, or fills one that is empty.
    @Test func aTakeFillsAnEmptyLayerFirst() {
        let timeline = Timeline(barCount: 1, layers: [Layer(notes: [note(0, 100)]), Layer()])
        let laid = timeline.layering([[note(0, 100)]], bars: 1, from: 0)
        #expect(laid.layers.count == 2)
        #expect(laid.layers[1].notes.count == 1)
    }

    @Test func aChordHeldOverTheEndOfTheTimelineCarriesOnFromItsStart() {
        let timeline = Timeline(barCount: 1, layers: [Layer(notes: [note(0, 100)])])
        let laid = timeline.laidRound([note(0, 600)], every: 1920, from: 1720)
        #expect(laid.map(\.start) == [0, 1720])
        #expect(laid.map(\.length) == [400, 200])
    }
}
