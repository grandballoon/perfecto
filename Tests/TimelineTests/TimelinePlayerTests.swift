import Testing
@testable import Perfecto

/// A timeline played against the clock, with time moved by hand.
@Suite("TimelinePlayer")
@MainActor
struct TimelinePlayerTests {

    private static let step = TimelineTime.ticksPerStep
    private let clock = ManualClock()
    private let live = LiveSettings(key: Key(root: .C, scale: .major), octave: 4,
                                    preset: .sinePad, effects: NoteEffects())

    /// A player, and the voices it has made, in the order it made them.
    @MainActor
    private final class Rig {
        private(set) var voices: [RecordingVoice] = []
        private(set) var steps: [Int?] = []
        private(set) var player: TimelinePlayer!

        init(_ timeline: Timeline, live: LiveSettings, clock: ManualClock) {
            player = TimelinePlayer(timeline: timeline, live: live, clock: clock) { [unowned self] _ in
                let voice = RecordingVoice()
                voices.append(voice)
                return voice
            }
            player.onStep = { [unowned self] in steps.append($0) }
        }
    }

    private func note(_ degree: Degree, step: Int, steps: Int = 1) -> TimelineNote {
        TimelineNote(start: step * Self.step, length: steps * Self.step,
                     chord: ChordSpec(degree: degree, color: .base))
    }

    private func timeline(_ notes: [TimelineNote]..., bars: Int = 1) -> Timeline {
        var timeline = Timeline(barCount: bars)
        timeline.layers = notes.map { Layer(notes: $0) }
        return timeline
    }

    /// Moves time on by `steps` sixteenths.
    private func advance(steps: Double) {
        clock.advance(beats: steps / Double(MusicalTime.stepsPerBeat))
    }

    // MARK: – Chords in time

    @Test func aChordStartsAndEndsOnItsOwnTicks() {
        var half = note(.IV, step: 2)
        half.length = 60                                             // half a step
        let rig = Rig(timeline([note(.I, step: 0), half]), live: live, clock: clock)
        rig.player.start()
        let voice = rig.voices[0]
        #expect(voice.degrees == [.I])                               // the first chord, at once

        advance(steps: 0.99)
        #expect(voice.stopCount == 0)
        advance(steps: 0.02)
        #expect(voice.stopCount == 1)                                // one step long

        advance(steps: 1)
        #expect(voice.degrees == [.I, .IV])
        advance(steps: 0.48)                                         // 2.49 steps in
        #expect(voice.stopCount == 1)
        advance(steps: 0.02)
        #expect(voice.stopCount == 2)                                // half a step long
    }

    @Test func itPlaysRoundAndRound() {
        let rig = Rig(timeline([note(.I, step: 0), note(.V, step: 8)]), live: live, clock: clock)
        rig.player.start()
        advance(steps: 16 * 3 + 1)
        #expect(rig.voices[0].degrees == [.I, .V, .I, .V, .I, .V, .I])
    }

    /// Many times round, the chords are still exactly on their ticks.
    @Test func itDoesNotDriftOverManyRounds() {
        let rig = Rig(timeline([note(.I, step: 3)]), live: live, clock: clock)
        rig.player.start()
        advance(steps: 16 * 200 + 2.99)
        #expect(rig.voices[0].played.count == 200)
        advance(steps: 0.02)
        #expect(rig.voices[0].played.count == 201)
    }

    @Test func aChordHeldToTheEndIsCutThereAndTheNextRoundStartsClean() {
        let rig = Rig(timeline([note(.I, step: 12, steps: 4)]), live: live, clock: clock)
        rig.player.start()
        advance(steps: 16.01)
        #expect(rig.voices[0].degrees == [.I])
        #expect(rig.voices[0].sounding == nil)
    }

    /// A step's gate is a share of the step: at any tempo it ends that far
    /// through, and a change of tempo mid-chord moves its end with it.
    @Test func tempoChangesMoveWhatIsStillToCome() {
        let rig = Rig(timeline([note(.I, step: 0, steps: 4)]), live: live, clock: clock)
        rig.player.start()
        advance(steps: 2)
        clock.bpm = 60                                               // half speed from here
        advance(steps: 1.99)
        #expect(rig.voices[0].stopCount == 0)
        advance(steps: 0.02)
        #expect(rig.voices[0].stopCount == 1)
    }

    @Test func onlyTheLoopedStretchPlays() {
        var looped = timeline([note(.I, step: 0), note(.IV, step: 4), note(.V, step: 6), note(.vi, step: 12)])
        looped.setLoop(steps: Set(4..<8))
        let rig = Rig(looped, live: live, clock: clock)
        rig.player.start()
        advance(steps: 8.5)
        #expect(rig.voices[0].degrees == [.IV, .V, .IV, .V, .IV])
    }

    @Test func stoppingSilencesEveryLayerAndNothingFollows() {
        let rig = Rig(timeline([note(.I, step: 0, steps: 8)], [note(.V, step: 0, steps: 8)]),
                      live: live, clock: clock)
        rig.player.start()
        advance(steps: 2)
        rig.player.stop()
        #expect(rig.voices.allSatisfy { $0.sounding == nil })
        #expect(rig.player.position == nil)
        #expect(clock.pendingCount == 0)

        let counts = rig.voices.map(\.calls.count)
        advance(steps: 64)
        #expect(rig.voices.map(\.calls.count) == counts)
    }

    // MARK: – Layers

    /// Each layer has a voice of its own, so one layer's chord never ends
    /// another's.
    @Test func layersPlayTogetherEachOnItsOwnVoice() {
        let rig = Rig(timeline([note(.I, step: 0, steps: 16)],
                               [note(.V, step: 4), note(.vi, step: 8)]),
                      live: live, clock: clock)
        rig.player.start()
        advance(steps: 10)
        #expect(rig.voices.count == 2)
        let long = rig.voices.first { $0.degrees == [.I] }
        let short = rig.voices.first { $0.degrees == [.V, .vi] }
        #expect(long?.stopCount == 0)
        #expect(short?.stopCount == 2)
    }

    @Test func aMutedLayerIsSilentAndComesBackInTime() {
        var muted = timeline([note(.I, step: 0), note(.V, step: 8)])
        muted.layers[0].isMuted = true
        let rig = Rig(muted, live: live, clock: clock)
        rig.player.start()
        advance(steps: 4)
        #expect(rig.voices[0].played.isEmpty)

        rig.player.timeline.layers[0].isMuted = false
        advance(steps: 4.01)
        #expect(rig.voices[0].degrees == [.V])                       // in its place, not from the top
    }

    @Test func mutingALayerStopsItsChord() {
        let rig = Rig(timeline([note(.I, step: 0, steps: 16)]), live: live, clock: clock)
        rig.player.start()
        advance(steps: 2)
        rig.player.timeline.layers[0].isMuted = true
        #expect(rig.voices[0].sounding == nil)
    }

    // MARK: – Changes while playing

    @Test func aNoteAddedAheadOfThePlayheadIsHeardThisRound() {
        let rig = Rig(timeline([note(.I, step: 0)]), live: live, clock: clock)
        rig.player.start()
        advance(steps: 2.5)
        rig.player.timeline.layers[0].place(ChordSpec(degree: .V, color: .base), onSteps: [4])
        advance(steps: 1.6)
        #expect(rig.voices[0].degrees == [.I, .V])
    }

    /// The chord that is sounding is the same note as before: it carries on.
    @Test func editingElsewhereLeavesTheSoundingChordAlone() {
        let rig = Rig(timeline([note(.I, step: 0, steps: 8)]), live: live, clock: clock)
        rig.player.start()
        advance(steps: 2)
        rig.player.timeline.layers[0].place(ChordSpec(degree: .V, color: .base), onSteps: [12])
        #expect(rig.voices[0].calls.count == 1)
        advance(steps: 6.01)
        #expect(rig.voices[0].stopCount == 1)                        // and still ends where it should
    }

    @Test func removingTheSoundingNoteStopsIt() {
        let rig = Rig(timeline([note(.I, step: 0, steps: 8)]), live: live, clock: clock)
        rig.player.start()
        advance(steps: 2)
        rig.player.timeline.layers[0].rest(onSteps: [0])
        #expect(rig.voices[0].sounding == nil)
    }

    @Test func shorteningTheSoundingNoteEndsItSooner() {
        let rig = Rig(timeline([note(.I, step: 0, steps: 8)]), live: live, clock: clock)
        rig.player.start()
        advance(steps: 2)
        rig.player.timeline.layers[0].lengthen(notesIn: [0], by: -4 * Self.step, limit: 1920)
        #expect(rig.voices[0].stopCount == 0)
        advance(steps: 2.01)
        #expect(rig.voices[0].stopCount == 1)
    }

    /// A note that follows the live key changes key at its next start.
    @Test func aLiveKeyChangeIsHeardFromTheNextChord() {
        let rig = Rig(timeline([note(.I, step: 0), note(.I, step: 4)]), live: live, clock: clock)
        rig.player.start()
        advance(steps: 2)
        rig.player.live.key = Key(root: .D, scale: .major)
        advance(steps: 2.01)
        #expect(rig.voices[0].played.map(\.event.voicing.notes) == [[60, 64, 67], [62, 66, 69]])
    }

    @Test func removingALayerStopsItAndLeavesTheOthersPlaying() {
        let rig = Rig(timeline([note(.I, step: 0, steps: 16)], [note(.V, step: 0, steps: 16)]),
                      live: live, clock: clock)
        rig.player.start()
        advance(steps: 2)
        let gone = rig.player.timeline.layers[1].id
        rig.player.timeline.removeLayer(gone)
        #expect(rig.voices.filter { $0.sounding != nil }.count == 1)
    }

    // MARK: – The playhead

    @Test func thePlayheadIsReportedStepByStep() {
        let rig = Rig(timeline([note(.I, step: 0)]), live: live, clock: clock)
        rig.player.start()
        advance(steps: 17.5)
        #expect(rig.steps == Array(0..<16).map(Optional.some) + [0, 1])
        #expect(rig.player.position == Self.step + Self.step / 2)

        rig.player.stop()
        #expect(rig.steps.last == .some(nil))
    }

    @Test func startingTwiceDoesNotStartTwice() {
        let rig = Rig(timeline([note(.I, step: 0)]), live: live, clock: clock)
        rig.player.start()
        rig.player.start()
        #expect(rig.voices[0].played.count == 1)
        #expect(clock.pendingCount == 1)
    }
}
