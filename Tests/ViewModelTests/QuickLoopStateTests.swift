import Foundation
import Testing
@testable import Perfecto

/// Play mode's loop, through the keys and the clock as in the app: what is
/// played becomes a layer of the timeline, and plays back as notes.
@Suite("QuickLoopState")
@MainActor
struct QuickLoopStateTests {

    /// The keys, the clock and the loop button, with a sequencer that saves
    /// nowhere the next test can see.
    @MainActor
    private final class Rig {
        let sink = RecordingSink()
        let clock = ManualClock()
        let logger = RecordingLogger()
        let sequencer = SequencerState(defaults: isolatedDefaults())
        let state: PerformanceState

        init(layerLead: Double = 0) {
            state = PerformanceState(sink: sink, layerLead: layerLead, sequencer: sequencer, clock: clock,
                                     logger: logger)
        }

        var loops: QuickLoopState { state.quickLoopState }
        var timeline: Timeline { sequencer.timeline }

        /// Holds `degree` for `beats`, then lets go.
        func play(_ degree: Degree, beats: Double) {
            state.press(degree: degree)
            clock.advance(beats: beats)
            state.release(degree: degree)
        }

        /// Records a first loop: I for two beats, V for two.
        func recordFirstLoop() {
            loops.triggerTapped()
            play(.I, beats: 2)
            play(.V, beats: 2)
            loops.triggerTapped()
        }

        var discards: [String] {
            logger.events.compactMap { if case let .loop_take_discarded(_, reason) = $0 { reason } else { nil } }
        }
    }

    // MARK: – Before anything is recorded

    @Test func itStartsIdleWithNoLoops() {
        let rig = Rig()
        #expect(rig.loops.phase == .idle)
        #expect(rig.loops.loops.isEmpty)
        #expect(rig.loops.canStartNew)
        #expect(!rig.loops.isRunning)
    }

    @Test func theFirstTapStartsATakeAndAddsNothingYet() {
        let rig = Rig()
        rig.loops.triggerTapped()
        #expect(rig.loops.phase == .recording)
        #expect(rig.loops.loops.isEmpty)
    }

    // MARK: – The first loop

    /// Played to the tempo that was set: four beats is one bar, and the
    /// chords are where they were played.
    @Test func theFirstLoopBecomesTheTimeline() {
        let rig = Rig()
        rig.recordFirstLoop()

        #expect(rig.loops.phase == .idle)
        #expect(rig.loops.loops.count == 1)
        #expect(rig.timeline.barCount == 1)
        #expect(rig.state.bpm == 120)
        let notes = rig.timeline.layers[0].notes
        #expect(notes.map(\.chord.degree) == [.I, .V])
        #expect(notes.map(\.start) == [0, 960])
        #expect(notes.map(\.length) == [960, 960])
    }

    /// Played a little short of a bar, with no metronome: it is still one
    /// bar, the tempo moves to make it so, and nothing played is moved.
    @Test func aLooselyTimedLoopSetsTheTempo() {
        let rig = Rig()
        rig.loops.triggerTapped()
        rig.play(.I, beats: 2)
        rig.play(.V, beats: 1.8)
        rig.loops.triggerTapped()

        #expect(rig.timeline.barCount == 1)
        #expect(abs(rig.state.bpm - 120 * 4 / 3.8) < 1e-6)
        let notes = rig.timeline.layers[0].notes
        #expect(notes.map(\.start) == [0, 1011])                     // 2 of 3.8 beats through the bar
        #expect(notes[1].end == 1920)
    }

    /// It loops from the moment it is closed, as notes through its own voice.
    @Test func theLoopPlaysFromTheMomentItIsClosed() {
        let rig = Rig()
        rig.loops.triggerTapped()
        rig.play(.I, beats: 2)
        rig.play(.V, beats: 2)
        rig.sink.reset()
        rig.loops.triggerTapped()

        #expect(rig.loops.isRunning)
        #expect(rig.sink.lastPlay?.notes == [60, 64, 67])
        rig.clock.advance(beats: 2.01)
        #expect(rig.sink.lastPlay?.notes == [67, 71, 74])
        rig.clock.advance(beats: 2)
        #expect(rig.sink.playCalls.map(\.notes) == [[60, 64, 67], [67, 71, 74], [60, 64, 67]])
    }

    /// A finished loop keeps its key, octave and sound whatever is chosen later.
    @Test func aLoopKeepsWhatItWasPlayedWith() {
        let rig = Rig()
        rig.recordFirstLoop()
        rig.state.key = Key(root: .D, scale: .major)
        rig.state.octave = 5
        rig.sink.reset()
        rig.clock.advance(beats: 4.01)

        #expect(rig.sink.playCalls.map(\.notes) == [[67, 71, 74], [60, 64, 67]])
        let note = rig.timeline.layers[0].notes[0]
        #expect(note.playing.key == Key(root: .C, scale: .major))
        #expect(note.playing.octave == 4)
        #expect(note.playing.preset == .initial)
        #expect(note.playing.effects == NoteEffects())
    }

    @Test func aKeyStillHeldWhenTheTakeClosesEndsThere() {
        let rig = Rig()
        rig.loops.triggerTapped()
        rig.state.press(degree: .I)
        rig.clock.advance(beats: 4)
        rig.loops.triggerTapped()

        #expect(rig.state.activeDegree == nil)
        #expect(rig.timeline.layers[0].notes.map(\.length) == [1920])
        #expect(rig.loops.loops.count == 1)
    }

    // MARK: – Takes that are not loops

    @Test func aTakeWithNothingPlayedIsDropped() {
        let rig = Rig()
        rig.loops.triggerTapped()
        rig.clock.advance(beats: 4)
        rig.loops.triggerTapped()
        #expect(rig.loops.loops.isEmpty)
        #expect(rig.loops.phase == .idle)
        #expect(rig.discards == ["nothing played"])
    }

    /// An accidental double tap.
    @Test func aTakeShorterThanHalfASecondIsDropped() {
        let rig = Rig()
        rig.loops.triggerTapped()
        rig.play(.I, beats: 0.5)                                     // a quarter of a second
        rig.loops.triggerTapped()
        #expect(rig.loops.loops.isEmpty)
        #expect(rig.discards == ["too short"])
        #expect(rig.state.bpm == 120)
    }

    // MARK: – Later takes

    /// A second take is layered at the point in the loop where it was
    /// played, and the tempo stays.
    @Test func aSecondTakeIsLayeredWhereItWasPlayed() {
        let rig = Rig()
        rig.recordFirstLoop()
        rig.clock.advance(beats: 1)
        rig.loops.triggerTapped()
        rig.play(.IV, beats: 1)
        rig.clock.advance(beats: 0.5)
        rig.loops.triggerTapped()

        #expect(rig.loops.loops.count == 2)
        #expect(rig.state.bpm == 120)
        #expect(rig.timeline.barCount == 1)
        let second = rig.timeline.layers[1].notes
        #expect(second.map(\.chord.degree) == [.IV])
        #expect(second.map(\.start) == [480])
        #expect(second.map(\.length) == [480])
    }

    /// Both layers play together, each on a voice of its own.
    /// Layers are heard a moment after their time on the clock. A chord
    /// played to what is heard goes where it was heard, not that moment
    /// later, so it is in time with the layer when both play back.
    @Test func aTakePlayedToWhatIsHeardLandsWhereItWasHeard() throws {
        let rig = Rig(layerLead: 0.125)                // a quarter of a beat at 120
        rig.recordFirstLoop()                          // one bar; playing from its top
        // The loop's second beat is heard a quarter of a beat late, and
        // the key is pressed with it.
        rig.clock.advance(beats: 1)
        rig.loops.triggerTapped()
        rig.clock.advance(beats: 0.25)
        rig.play(.IV, beats: 1)
        rig.loops.triggerTapped()
        #expect(rig.timeline.layers.count == 2)
        #expect(rig.timeline.layers.last?.notes.map(\.start) == [TimelineTime.ticksPerBeat])
    }

    @Test func layersPlayTogether() {
        let rig = Rig()
        rig.recordFirstLoop()
        rig.clock.advance(beats: 1)
        rig.loops.triggerTapped()
        rig.play(.IV, beats: 1)
        rig.loops.triggerTapped()
        rig.clock.advance(beats: 2.5)                                // to half a beat into the next round
        rig.sink.reset()
        rig.clock.advance(beats: 4)

        let played = Set(rig.sink.playCalls.map(\.notes))
        #expect(played == [[60, 64, 67], [65, 69, 72], [67, 71, 74]])
    }

    /// A take longer than the loop becomes a layer for each time round.
    @Test func aTakeLongerThanTheLoopLayersOverItself() {
        let rig = Rig()
        rig.recordFirstLoop()
        rig.loops.triggerTapped()
        rig.play(.IV, beats: 1)
        rig.clock.advance(beats: 4)
        rig.play(.vi, beats: 1)
        rig.loops.triggerTapped()

        #expect(rig.loops.loops.count == 3)
        #expect(rig.timeline.layers[1].notes.map(\.chord.degree) == [.IV])
        #expect(rig.timeline.layers[2].notes.map(\.chord.degree) == [.vi])
        #expect(rig.timeline.layers[2].notes.map(\.start) == [480])
    }

    /// The loop playing underneath is not recorded into the take over it.
    @Test func whatTheLoopPlaysIsNotRecordedAgain() {
        let rig = Rig()
        rig.recordFirstLoop()
        rig.loops.triggerTapped()
        rig.clock.advance(beats: 4)
        rig.loops.triggerTapped()
        #expect(rig.loops.loops.count == 1)
        #expect(rig.discards == ["nothing played"])
    }

    @Test func thereAreAtMostSixLayers() {
        let rig = Rig()
        rig.recordFirstLoop()
        for _ in 1..<QuickLoopState.maxLoops {
            rig.loops.triggerTapped()
            rig.play(.IV, beats: 1)
            rig.loops.triggerTapped()
        }
        #expect(rig.loops.loops.count == QuickLoopState.maxLoops)
        #expect(!rig.loops.canStartNew)
        rig.loops.triggerTapped()
        #expect(rig.loops.phase == .idle)
    }

    // MARK: – How it was played

    @Test func aLeadNoteIsRecordedAsOne() {
        let rig = Rig()
        rig.state.setMode(LeadMode())
        rig.loops.triggerTapped()
        rig.play(.V, beats: 4)
        rig.loops.triggerTapped()
        #expect(rig.timeline.layers[0].notes.map(\.pitch) == [.lead])
        #expect(rig.sink.lastPlay?.notes == [67])
    }

    /// A slide played while a chord was held is kept with the note.
    @Test func aSlideInsideAHeldChordIsRecorded() {
        let rig = Rig()
        rig.state.effects.filter.isOn = true
        rig.loops.triggerTapped()
        rig.state.slide(on: .I, to: 0.2)
        rig.state.press(degree: .I)
        rig.clock.advance(beats: 2)
        rig.state.slide(on: .I, to: 0.8)
        rig.clock.advance(beats: 2)
        rig.state.release(degree: .I)
        rig.loops.triggerTapped()

        let note = rig.timeline.layers[0].notes[0]
        #expect(note.playing.effects?.filter.brightness == 0.2)
        #expect(note.changes.map(\.offset) == [960])
        #expect(note.changes.first?.effects.filter.brightness == 0.8)
    }

    /// A chord that was arpeggiated is recorded as the chord, with the
    /// arpeggiator among its effects: it is arpeggiated again when it plays.
    @Test func anArpeggiatedChordIsRecordedAsItsChord() {
        let rig = Rig()
        rig.state.effects.arpeggiator.isOn = true
        rig.loops.triggerTapped()
        rig.play(.I, beats: 4)
        rig.state.effects.arpeggiator.isOn = false
        rig.sink.reset()
        rig.loops.triggerTapped()

        let note = rig.timeline.layers[0].notes[0]
        #expect(note.pitch == .chord)
        #expect(note.playing.effects?.arpeggiator.isOn == true)
        rig.clock.advance(beats: 0.7)
        #expect(rig.sink.playCalls.map(\.notes) == [[60], [64], [67]])
    }

    // MARK: – Layers

    @Test func aLayerCanBeSilencedAndBroughtBackInTime() {
        let rig = Rig()
        rig.recordFirstLoop()
        let id = rig.loops.loops[0].id
        rig.loops.togglePlayback(id: id)
        #expect(rig.loops.loops[0].isPlaying == false)
        rig.sink.reset()
        rig.clock.advance(beats: 1)
        #expect(rig.sink.playCalls.isEmpty)

        rig.loops.togglePlayback(id: id)
        #expect(rig.loops.loops[0].isPlaying)
        rig.clock.advance(beats: 1.01)
        #expect(rig.sink.lastPlay?.notes == [67, 71, 74])            // the V, in its place
    }

    /// Deleting every layer frees the length, so the next take sets a new one.
    @Test func deletingEveryLayerFreesTheLengthAndTempo() {
        let rig = Rig()
        rig.recordFirstLoop()
        rig.loops.removeLoop(id: rig.loops.loops[0].id)
        #expect(rig.loops.loops.isEmpty)
        #expect(!rig.loops.isRunning)
        #expect(rig.clock.pendingCount == 0)

        rig.loops.triggerTapped()
        rig.play(.I, beats: 8)
        rig.loops.triggerTapped()
        #expect(rig.timeline.barCount == 2)
    }

    @Test func clearingEverythingAlsoDropsTheTakeBeingRecorded() {
        let rig = Rig()
        rig.recordFirstLoop()
        rig.loops.triggerTapped()
        rig.loops.clearAll()
        #expect(rig.loops.phase == .idle)
        #expect(rig.loops.loops.isEmpty)
        #expect(rig.timeline.barCount == 1)
        #expect(!rig.loops.isRunning)
    }

    // MARK: – Stop and start

    @Test func theLoopsCanBeStoppedAndStartedAgainFromTheTop() {
        let rig = Rig()
        rig.recordFirstLoop()
        rig.clock.advance(beats: 2.5)
        rig.loops.toggleRunning()
        #expect(!rig.loops.isRunning)
        rig.sink.reset()
        rig.clock.advance(beats: 8)
        #expect(rig.sink.playCalls.isEmpty)

        rig.loops.toggleRunning()
        #expect(rig.loops.isRunning)
        #expect(rig.sink.lastPlay?.notes == [60, 64, 67])
    }

    // MARK: – With the sequencer

    /// A sequence entered in the sequencer is a layer like any other: a
    /// take is layered over it, at its length and tempo.
    @Test func aTakeIsLayeredOverASequenceEnteredByHand() {
        let rig = Rig()
        rig.sequencer.steps[0] = SequencerStep(degree: .vi)
        #expect(rig.loops.loops.count == 1)

        rig.loops.triggerTapped()                                    // starts the sequence, to play along to
        #expect(rig.loops.isRunning)
        rig.clock.advance(beats: 1)
        rig.play(.IV, beats: 1)
        rig.loops.triggerTapped()

        #expect(rig.loops.loops.count == 2)
        #expect(rig.state.bpm == 120)
        #expect(rig.timeline.layers[1].notes.map(\.start) == [480])
    }

    /// A recorded loop can be opened and edited in the sequencer.
    @Test func aRecordedLoopIsWhatTheSequencerShows() {
        let rig = Rig()
        rig.recordFirstLoop()
        #expect(rig.sequencer.steps[0].degree == .I)
        #expect(rig.sequencer.steps[8].degree == .V)
        #expect(rig.sequencer.steps[7].isTied)                       // held, not struck again

        rig.sequencer.undo()
        #expect(rig.loops.loops.isEmpty)
    }
}
