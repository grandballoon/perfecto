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
            state.press(.degree(degree))
            clock.advance(beats: beats)
            state.release(.degree(degree))
        }

        /// Chooses a take of `bars` bars and counts in: it is recording.
        func startTake(bars: Int = 1) {
            loops.triggerTapped()
            loops.choose(bars: bars)
            clock.advance(seconds: Double(QuickLoopState.countIn))
        }

        /// Records a first loop of one bar: I for two beats, V for two.
        /// The take ends by itself as V is let go.
        func recordFirstLoop() {
            startTake()
            play(.I, beats: 2)
            play(.V, beats: 2)
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

    @Test func theFirstTapOffersTheLengthsAndTheNextPutsThemAway() {
        let rig = Rig()
        rig.loops.triggerTapped()
        #expect(rig.loops.phase == .choosing)
        rig.loops.triggerTapped()
        #expect(rig.loops.phase == .idle)
        #expect(rig.loops.loops.isEmpty)
    }

    // MARK: – The count-in

    /// A length chosen counts in for three seconds, felt at each, and then
    /// records for that many bars.
    @Test func aLengthChosenCountsInThenRecords() {
        let rig = Rig()
        rig.loops.triggerTapped()
        rig.loops.choose(bars: 2)
        #expect(rig.loops.bars == 2)
        #expect(rig.loops.phase == .countingIn(remaining: 3))
        #expect(rig.loops.cue == .count(3))
        rig.clock.advance(seconds: 1)
        #expect(rig.loops.phase == .countingIn(remaining: 2))
        #expect(rig.loops.cue == .count(2))
        rig.clock.advance(seconds: 1)
        #expect(rig.loops.cue == .count(1))
        rig.clock.advance(seconds: 1)
        #expect(rig.loops.cue == .go)
        let start = rig.clock.beats
        #expect(rig.loops.phase == .recording(start: start, end: start + 8))
        #expect(rig.logger.events.contains {
            if case .loop_count_in_started(track: 0, bars: 2) = $0 { true } else { false }
        })
    }

    /// The take runs out as the clock moves: half way through two bars at
    /// 120, half of it is left, two seconds.
    @Test func theTakeShowsHowMuchOfItIsLeft() throws {
        let rig = Rig()
        rig.startTake(bars: 2)
        rig.clock.advance(beats: 4)
        let progress = try #require(rig.loops.recordingProgress)
        #expect(abs(progress.share - 0.5) < 1e-9)
        #expect(abs(progress.secondsLeft - 2) < 1e-9)
    }

    /// A chord struck on the last count, or a moment before it, or held
    /// through the count-in, starts the take.
    @Test func aChordSoundingAsTheTakeBeginsIsItsFirst() {
        let rig = Rig()
        rig.loops.triggerTapped()
        rig.loops.choose(bars: 1)
        rig.clock.advance(seconds: 2.95)
        rig.state.press(.degree(.IV))
        rig.clock.advance(seconds: 0.05)
        rig.clock.advance(beats: 1)
        rig.state.release(.degree(.IV))
        rig.clock.advance(beats: 3)

        let notes = rig.timeline.layers[0].notes
        #expect(notes.map(\.chord.degree) == [.IV])
        #expect(notes.map(\.start) == [0])
        #expect(notes.map(\.length) == [480])
    }

    /// A chord let go before the count-in ends is not in the take.
    @Test func aChordEndedDuringTheCountInIsNotRecorded() {
        let rig = Rig()
        rig.loops.triggerTapped()
        rig.loops.choose(bars: 1)
        rig.state.press(.degree(.IV))
        rig.clock.advance(seconds: 1)
        rig.state.release(.degree(.IV))
        rig.clock.advance(seconds: 2)
        rig.play(.I, beats: 4)
        #expect(rig.timeline.layers[0].notes.map(\.chord.degree) == [.I])
    }

    @Test func loopCallsOffTheCountIn() {
        let rig = Rig()
        rig.loops.triggerTapped()
        rig.loops.choose(bars: 1)
        rig.clock.advance(seconds: 1)
        rig.loops.triggerTapped()
        #expect(rig.loops.phase == .idle)
        #expect(rig.loops.cue == nil)
        rig.clock.advance(seconds: 5)
        #expect(rig.loops.phase == .idle)
        #expect(rig.discards == ["called off"])
    }

    @Test func loopCallsOffTheTakeBeingRecorded() {
        let rig = Rig()
        rig.startTake()
        rig.play(.I, beats: 2)
        rig.loops.triggerTapped()
        rig.clock.advance(beats: 4)
        #expect(rig.loops.phase == .idle)
        #expect(rig.loops.loops.isEmpty)
        #expect(rig.discards == ["called off"])
    }

    /// The keyboard's loop key has nothing to point with: it counts in to
    /// the length chosen last, and calls off what is counting in.
    @Test func theLoopKeyCountsInToTheLengthChosenLast() {
        let rig = Rig()
        rig.startTake(bars: 4)
        rig.clock.advance(beats: 16)
        rig.state.tap(.loop)
        #expect(rig.loops.phase == .countingIn(remaining: 3))
        #expect(rig.loops.bars == 4)
        rig.state.tap(.loop)
        #expect(rig.loops.phase == .idle)
    }

    // MARK: – The first loop

    /// Played to the tempo that was set: the bar chosen is the loop, and the
    /// chords are where they were played. The cues are felt in order.
    @Test func theFirstLoopBecomesTheTimeline() {
        let rig = Rig()
        rig.recordFirstLoop()

        #expect(rig.loops.phase == .idle)
        #expect(rig.loops.cue == .done)
        #expect(rig.loops.loops.count == 1)
        #expect(rig.timeline.barCount == 1)
        #expect(rig.state.bpm == 120)
        let notes = rig.timeline.layers[0].notes
        #expect(notes.map(\.chord.degree) == [.I, .V])
        #expect(notes.map(\.start) == [0, 960])
        #expect(notes.map(\.length) == [960, 960])
    }

    /// The take lasts the bars chosen however little is played in it, and
    /// the tempo stays as it was set.
    @Test func theTakeLastsTheBarsChosen() {
        let rig = Rig()
        rig.state.setBPM(90)
        rig.startTake(bars: 4)
        rig.play(.I, beats: 1)
        rig.clock.advance(beats: 14.9)
        #expect(rig.loops.isTaking)
        rig.clock.advance(beats: 0.1)
        #expect(rig.loops.phase == .idle)
        #expect(rig.timeline.barCount == 4)
        #expect(rig.state.bpm == 90)
        #expect(rig.timeline.layers[0].notes.map(\.length) == [480])
    }

    /// It loops from the moment it ends, as notes through its own voice.
    @Test func theLoopPlaysFromTheMomentItEnds() {
        let rig = Rig()
        rig.startTake()
        rig.play(.I, beats: 2)
        rig.state.press(.degree(.V))
        rig.clock.advance(beats: 1.9)
        rig.sink.reset()
        rig.clock.advance(beats: 0.1)
        rig.state.release(.degree(.V))

        #expect(rig.loops.isRunning)
        #expect(rig.sink.lastPlay?.notes == [60, 64, 67])
        rig.clock.advance(beats: 2.01)
        #expect(rig.sink.lastPlay?.notes == [67, 71, 74])
        rig.clock.advance(beats: 2)
        #expect(rig.sink.playCalls.map(\.notes) == [[60, 64, 67], [67, 71, 74], [60, 64, 67]])
    }

    /// A finished loop keeps the inversion its chords were played in.
    @Test func aLoopKeepsTheInversionItWasPlayedIn() {
        let rig = Rig()
        rig.state.inversion = .first
        rig.recordFirstLoop()
        rig.state.inversion = .root
        rig.sink.reset()
        rig.clock.advance(beats: 4.01)

        #expect(rig.timeline.layers[0].notes.allSatisfy { $0.playing.inversion == .first })
        #expect(rig.sink.playCalls.map(\.notes) == [[71, 74, 79], [64, 67, 72]])
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

    /// A chord from the octave's key for a note outside the key is kept
    /// in the key it was borrowed from, so it plays back as it was heard.
    @Test func aBorrowedChordIsRecordedInItsOwnKey() {
        let rig = Rig()
        rig.startTake()
        rig.state.press(.root(.As))
        rig.clock.advance(beats: 4)
        rig.state.release(.root(.As))

        let note = rig.timeline.layers[0].notes[0]
        #expect(note.chord.degree == .viiDim)
        #expect(note.playing.key == Key(root: .C, scale: .mixolydian))
        rig.sink.reset()
        rig.clock.advance(beats: 4.01)
        #expect(rig.sink.playCalls.map(\.notes) == [[70, 74, 77]])
    }

    @Test func aKeyStillHeldWhenTheTakeEndsEndsThere() {
        let rig = Rig()
        rig.startTake()
        rig.state.press(.degree(.I))
        rig.clock.advance(beats: 4)

        #expect(rig.state.activeDegree == nil)
        #expect(rig.timeline.layers[0].notes.map(\.length) == [1920])
        #expect(rig.loops.loops.count == 1)
    }

    // MARK: – Takes that are not loops

    @Test func aTakeWithNothingPlayedIsDropped() {
        let rig = Rig()
        rig.startTake()
        rig.clock.advance(beats: 4)
        #expect(rig.loops.loops.isEmpty)
        #expect(rig.loops.phase == .idle)
        #expect(rig.loops.cue == .dropped)
        #expect(rig.discards == ["nothing played"])
    }

    // MARK: – Later takes

    /// A second take is laid at the point in the loop where it was played,
    /// and the tempo stays. The loop plays through the count-in.
    @Test func aSecondTakeIsLayeredWhereItWasPlayed() {
        let rig = Rig()
        rig.recordFirstLoop()
        rig.clock.advance(beats: 1)
        rig.startTake()                                              // six beats on: the loop's fourth beat
        rig.play(.IV, beats: 1)
        rig.clock.advance(beats: 3)

        #expect(rig.loops.loops.count == 2)
        #expect(rig.state.bpm == 120)
        #expect(rig.timeline.barCount == 1)
        let second = rig.timeline.layers[1].notes
        #expect(second.map(\.chord.degree) == [.IV])
        #expect(second.map(\.start) == [1440])
        #expect(second.map(\.length) == [480])
    }

    /// Layers are heard a moment after their time on the clock. A chord
    /// played to what is heard goes where it was heard, not that moment
    /// later, so it is in time with the layer when both play back.
    @Test func aTakePlayedToWhatIsHeardLandsWhereItWasHeard() {
        let rig = Rig(layerLead: 0.125)                // a quarter of a beat at 120
        rig.recordFirstLoop()                          // one bar; playing from its top
        // The take begins on the loop's third beat, heard a quarter of a
        // beat late, and the key is pressed with it.
        rig.startTake()
        rig.clock.advance(beats: 0.25)
        rig.play(.IV, beats: 1)
        rig.clock.advance(beats: 2.75)
        #expect(rig.timeline.layers.count == 2)
        #expect(rig.timeline.layers.last?.notes.map(\.start) == [2 * TimelineTime.ticksPerBeat])
    }

    @Test func layersPlayTogether() {
        let rig = Rig()
        rig.recordFirstLoop()
        rig.startTake()
        rig.play(.IV, beats: 1)
        rig.clock.advance(beats: 3)
        rig.sink.reset()
        rig.clock.advance(beats: 4.01)

        let played = Set(rig.sink.playCalls.map(\.notes))
        #expect(played == [[60, 64, 67], [65, 69, 72], [67, 71, 74]])
    }

    /// A take longer than the loop lengthens it, and the loop plays twice
    /// under it.
    @Test func aLongerTakeRepeatsTheLoopUnderIt() {
        let rig = Rig()
        rig.recordFirstLoop()
        rig.startTake(bars: 2)                                       // on the loop's third beat
        rig.play(.IV, beats: 1)
        rig.clock.advance(beats: 3)
        rig.play(.vi, beats: 1)
        rig.clock.advance(beats: 3)

        #expect(rig.loops.loops.count == 2)
        #expect(rig.timeline.barCount == 2)
        #expect(rig.timeline.layers[0].notes.map(\.chord.degree) == [.I, .V, .I, .V])
        #expect(rig.timeline.layers[1].notes.map(\.chord.degree) == [.IV, .vi])
        #expect(rig.timeline.layers[1].notes.map(\.start) == [960, 2880])
    }

    /// A take shorter than the loop plays every time it comes round in it.
    @Test func aShorterTakeIsRepeatedRoundTheLoop() {
        let rig = Rig()
        rig.startTake(bars: 2)
        rig.play(.I, beats: 8)
        rig.startTake(bars: 1)                                       // six beats into the loop
        rig.play(.IV, beats: 1)
        rig.clock.advance(beats: 3)

        #expect(rig.timeline.barCount == 2)
        #expect(rig.timeline.layers[1].notes.map(\.start) == [960, 2880])
    }

    /// The loop playing underneath is not recorded into the take over it.
    @Test func whatTheLoopPlaysIsNotRecordedAgain() {
        let rig = Rig()
        rig.recordFirstLoop()
        rig.startTake()
        rig.clock.advance(beats: 4)
        #expect(rig.loops.loops.count == 1)
        #expect(rig.discards == ["nothing played"])
    }

    @Test func thereAreAtMostSixLayers() {
        let rig = Rig()
        rig.recordFirstLoop()
        for _ in 1..<QuickLoopState.maxLoops {
            rig.startTake()
            rig.play(.IV, beats: 1)
            rig.clock.advance(beats: 3)
        }
        #expect(rig.loops.loops.count == QuickLoopState.maxLoops)
        #expect(!rig.loops.canStartNew)
        rig.loops.triggerTapped()
        #expect(rig.loops.phase == .idle)
        rig.state.tap(.loop)
        #expect(rig.loops.phase == .idle)
    }

    // MARK: – How it was played

    /// A chord played from a key zone with a key and an octave of its own
    /// is recorded in them, so the loop plays it back as it was heard.
    @Test func aChordFromAKeyZoneIsRecordedInTheZonesKey() {
        let rig = Rig()
        rig.state.effects.zones.zones = [KeyZone(), KeyZone(key: Key(root: .Ds, scale: .major), octave: 2)]
        rig.state.effects.zones.isOn = true
        rig.startTake()
        rig.state.slide(on: .degree(.I), to: 0.8)
        rig.state.press(.degree(.I))
        rig.clock.advance(beats: 4)
        rig.state.release(.degree(.I))

        let note = rig.timeline.layers[0].notes[0]
        #expect(note.playing.key == Key(root: .Ds, scale: .major))
        #expect(note.playing.octave == 2)
        rig.sink.reset()
        rig.clock.advance(beats: 4.01)                        // round to the loop's start
        #expect(rig.sink.playCalls.map(\.notes) == [[39, 43, 46]])
    }

    /// A slide played while a chord was held is kept with the note.
    @Test func aSlideInsideAHeldChordIsRecorded() {
        let rig = Rig()
        rig.state.effects.vocoder = VocoderSettings(isOn: true, followsSlide: true)
        rig.startTake()
        rig.state.slide(on: .degree(.I), to: 0.2)
        rig.state.press(.degree(.I))
        rig.clock.advance(beats: 2)
        rig.state.slide(on: .degree(.I), to: 0.8)
        rig.clock.advance(beats: 1.9)
        rig.state.release(.degree(.I))
        rig.clock.advance(beats: 0.1)

        let note = rig.timeline.layers[0].notes[0]
        #expect(note.playing.effects?.vocoder.amount == 0.2)
        #expect(note.changes.map(\.offset) == [960])
        #expect(note.changes.first?.effects.vocoder.amount == 0.8)
    }

    /// A chord that was arpeggiated is recorded as the chord, with the
    /// arpeggiator among its effects: it is arpeggiated again when it plays.
    @Test func anArpeggiatedChordIsRecordedAsItsChord() {
        let rig = Rig()
        rig.state.effects.arpeggiator.isOn = true
        rig.startTake()
        rig.play(.I, beats: 3.9)
        rig.state.effects.arpeggiator.isOn = false
        rig.sink.reset()
        rig.clock.advance(beats: 0.1)

        let note = rig.timeline.layers[0].notes[0]
        #expect(note.pitch == .chord)
        #expect(note.playing.effects?.arpeggiator.isOn == true)
        rig.clock.advance(beats: 0.7)
        #expect(rig.sink.playCalls.map(\.notes) == [[60], [64], [67]])
    }

    // MARK: – A loop's effects are its own

    /// The keys and the layers on players of their own, as in the app, so
    /// what each line's notes sound like can be told apart.
    @MainActor
    private final class SoundRig {
        let keys = RecordingNoteSink()
        let layers = RecordingNoteSink()
        let clock = ManualClock()
        let sequencer = SequencerState(defaults: isolatedDefaults())
        let state: PerformanceState

        init() {
            let player = NotePlayer([keys], clock: clock)
            state = PerformanceState(sink: player,
                                     layerSink: { [layers, clock] in NotePlayer([layers], clock: clock) },
                                     sequencer: sequencer, liveSound: player, clock: clock)
        }

        /// Records a first loop: I held for a bar.
        func recordLoop() {
            startTake()
            state.press(.degree(.I))
            clock.advance(beats: 4)
            state.release(.degree(.I))
        }

        /// Chooses a take of one bar and counts in: it is recording.
        func startTake() {
            state.quickLoopState.triggerTapped()
            state.quickLoopState.choose(bars: 1)
            clock.advance(seconds: Double(QuickLoopState.countIn))
        }
    }

    /// A loop recorded dry stays dry, and is not arpeggiated, whatever is
    /// switched on for the keys while it plays.
    @Test func effectsSwitchedOnAfterwardsDoNotReachTheLoop() {
        let rig = SoundRig()
        rig.recordLoop()
        rig.layers.reset()

        rig.state.effects.chorus.isOn = true
        rig.state.effects.reverb = ReverbSettings(isOn: true)
        rig.state.effects.arpeggiator.isOn = true
        rig.clock.advance(beats: 4.01)

        #expect(rig.layers.changes.isEmpty)
        #expect(rig.layers.started == [60, 64, 67])
        #expect(rig.layers.sounds.allSatisfy {
            $0.chorus == ChorusSettings() && $0.reverb == ReverbSettings()
        })
    }

    /// A loop recorded with effects keeps them when the keys' are changed.
    @Test func aLoopKeepsItsEffectsWhenTheKeysAreChanged() {
        let rig = SoundRig()
        let reverb = ReverbSettings(isOn: true)
        rig.state.effects.reverb = reverb
        rig.recordLoop()
        rig.layers.reset()

        rig.state.effects.reverb = ReverbSettings(isOn: false)
        rig.state.press(.degree(.V))
        rig.state.slide(on: .degree(.V), to: 0.9)
        rig.clock.advance(beats: 4.01)
        rig.state.release(.degree(.V))

        #expect(rig.layers.changes.isEmpty)
        #expect(!rig.layers.sounds.isEmpty)
        #expect(rig.layers.sounds.allSatisfy { $0.reverb == reverb })
    }

    /// With the slide playing brightness, a key struck low is heard dark
    /// and a slide up it sweeps the chord, and the loop plays both again.
    @Test func theBrightnessAChordIsPlayedWithIsHeardAndKeptByItsLoop() {
        let rig = SoundRig()
        rig.state.effects.slidePlaysBrightness = true
        rig.startTake()
        rig.state.slide(on: .degree(.I), to: 0.2)
        rig.state.press(.degree(.I))
        rig.clock.advance(beats: 2)
        rig.state.slide(on: .degree(.I), to: 0.8)
        rig.clock.advance(beats: 1.9)
        rig.state.release(.degree(.I))
        rig.clock.advance(beats: 0.1)
        #expect(rig.keys.sounds.map(\.brightness) == [0.2, 0.2, 0.2])
        #expect(rig.keys.changes.map(\.brightness) == [0.8, 0.8, 0.8])

        rig.layers.reset()
        rig.clock.advance(beats: 4.01)
        #expect(!rig.layers.sounds.isEmpty && rig.layers.sounds.allSatisfy { $0.brightness == 0.2 })
        #expect(!rig.layers.changes.isEmpty && rig.layers.changes.allSatisfy { $0.brightness == 0.8 })
    }

    /// A loop's effects are edited by themselves: the loop is heard in
    /// them, the keys' stay as set, and a run of edits is one undo.
    @Test func aLoopsEffectsAreEditedApartFromTheKeys() {
        let rig = SoundRig()
        rig.recordLoop()
        let loop = rig.sequencer.timeline.layers[0].id
        let live = rig.state.effects.asSet
        rig.layers.reset()

        rig.sequencer.editEffects(ofLayer: loop, following: live) { $0.reverb.isOn = true }
        rig.sequencer.editEffects(ofLayer: loop, following: live) { $0.chorus.isOn = true }

        // The chord sounding glides to them, and is not struck again.
        #expect(rig.layers.started.isEmpty)
        #expect(rig.layers.changes.last.map { $0.reverb.isOn && $0.chorus.isOn } == true)
        rig.clock.advance(beats: 4.01)
        #expect(rig.layers.sounds.allSatisfy { $0.reverb.isOn && $0.chorus.isOn })
        #expect(rig.state.effects.asSet == live)
        rig.state.press(.degree(.V))
        #expect(rig.keys.sounds.allSatisfy { !$0.reverb.isOn })

        rig.sequencer.undo()
        #expect(rig.sequencer.effects(ofLayer: loop) == NoteEffects())
    }

    // MARK: – Layers

    /// A loop's chit pauses it, and resumes it in time.
    @Test func aLoopCanBePausedAndResumedInTime() {
        let rig = Rig()
        rig.recordFirstLoop()
        let id = rig.loops.loops[0].id
        rig.loops.loopTapped(id: id)
        #expect(rig.loops.loops[0].isPlaying == false)
        rig.sink.reset()
        rig.clock.advance(beats: 1)
        #expect(rig.sink.playCalls.isEmpty)

        rig.loops.loopTapped(id: id)
        #expect(rig.loops.loops[0].isPlaying)
        rig.clock.advance(beats: 1.01)
        #expect(rig.sink.lastPlay?.notes == [67, 71, 74])            // the V, in its place
    }

    // MARK: – Deleting

    /// With the trash on, a loop's chit deletes it, and the trash stays on
    /// for the next.
    @Test func whileDeletingALoopsChitDeletesIt() {
        let rig = Rig()
        rig.recordFirstLoop()
        rig.startTake()
        rig.play(.IV, beats: 1)
        rig.clock.advance(beats: 3)
        rig.loops.toggleDeleting()
        #expect(rig.loops.isDeleting)

        rig.loops.loopTapped(id: rig.loops.loops[0].id)
        #expect(rig.loops.loops.count == 1)
        #expect(rig.timeline.layers.flatMap(\.notes).map(\.chord.degree) == [.IV])
        #expect(rig.loops.isDeleting)
        rig.loops.toggleDeleting()
        #expect(!rig.loops.isDeleting)
    }

    /// A tap anywhere else, or on LOOP, stops deleting, as does there being
    /// nothing left to delete.
    @Test func deletingStopsWithATapElsewhere() {
        let rig = Rig()
        rig.recordFirstLoop()
        rig.loops.toggleDeleting()
        rig.loops.dismiss()
        #expect(!rig.loops.isDeleting)
        #expect(rig.loops.loops.count == 1)

        rig.loops.toggleDeleting()
        rig.loops.triggerTapped()
        #expect(!rig.loops.isDeleting)
        #expect(rig.loops.phase == .choosing)
        rig.loops.dismiss()
        #expect(rig.loops.phase == .idle)

        rig.loops.toggleDeleting()
        rig.loops.loopTapped(id: rig.loops.loops[0].id)
        #expect(rig.loops.loops.isEmpty)
        #expect(!rig.loops.isDeleting)
    }

    /// The layers a take is laid on stay while it is made.
    @Test func nothingIsDeletedWhileATakeIsMade() {
        let rig = Rig()
        rig.recordFirstLoop()
        rig.startTake()
        rig.loops.toggleDeleting()
        #expect(!rig.loops.isDeleting)
    }

    /// Deleting every layer frees the length, so the next take sets a new one.
    @Test func deletingEveryLayerFreesTheLength() {
        let rig = Rig()
        rig.recordFirstLoop()
        rig.loops.removeLoop(id: rig.loops.loops[0].id)
        #expect(rig.loops.loops.isEmpty)
        #expect(!rig.loops.isRunning)
        #expect(rig.clock.pendingCount == 0)

        rig.startTake(bars: 2)
        rig.play(.I, beats: 8)
        #expect(rig.timeline.barCount == 2)
    }

    @Test func clearingEverythingAlsoDropsTheTakeBeingMade() {
        let rig = Rig()
        rig.recordFirstLoop()
        rig.startTake()
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

        rig.loops.triggerTapped()
        rig.loops.choose(bars: 1)                                    // starts the sequence, to play along to
        #expect(rig.loops.isRunning)
        rig.clock.advance(seconds: 3)                                // to its third beat
        rig.clock.advance(beats: 1)
        rig.play(.IV, beats: 1)
        rig.clock.advance(beats: 2)

        #expect(rig.loops.loops.count == 2)
        #expect(rig.state.bpm == 120)
        #expect(rig.timeline.layers[1].notes.map(\.start) == [1440])
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
