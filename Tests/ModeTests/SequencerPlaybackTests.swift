import Foundation
import Testing
@testable import Perfecto

/// Playhead movement across bars, driven through the clock as in the app.
@Suite("SequencerPlayback")
@MainActor
struct SequencerPlaybackTests {

    /// Returns the PerformanceState too: the clock holds it weakly, so the
    /// caller must keep it alive for ticks to reach the mode.
    private func start(bars: Int, loop: Set<Int> = [])
        -> (SequencerState, ManualClock, PerformanceState) {
        let seq = SequencerState(defaults: isolatedDefaults())
        for _ in 1..<bars { seq.addBar() }
        seq.focusedBar = 0
        if !loop.isEmpty {
            seq.selectedSteps = loop
            seq.loopSelection()
        }
        let clock = ManualClock()
        let state = PerformanceState(sink: RecordingSink(), clock: clock)
        state.setMode(SequencerMode(seq))
        seq.isPlaying = true
        return (seq, clock, state)
    }

    /// Moves time on by one step, a sixteenth.
    private func step(_ clock: ManualClock) {
        clock.advance(beats: 1 / Double(MusicalTime.stepsPerBeat))
    }

    /// Playback starts the moment it is asked for, on the first step.
    @Test func theWholePatternPlaysAndTheFocusedBarFollowsThePlayhead() {
        let (seq, clock, state) = start(bars: 3)
        var visited = [seq.currentStep]
        for _ in 1..<48 {
            step(clock)
            visited.append(seq.currentStep)
            #expect(seq.focusedBar == seq.currentStep / 16)
        }
        #expect(visited == Array(0..<48))

        step(clock)                          // wraps back to the first bar
        #expect(seq.currentStep == 0)
        #expect(seq.focusedBar == 0)
        withExtendedLifetime(state) {}
    }

    @Test func aLoopedPortionRepeatsOnItsOwn() {
        let (seq, clock, state) = start(bars: 2, loop: Set(12..<20))
        var visited = [seq.currentStep]
        for _ in 1..<12 {
            step(clock)
            visited.append(seq.currentStep)
        }
        #expect(visited == Array(12..<20) + Array(12..<16))
        #expect(seq.focusedBar == 0)
        withExtendedLifetime(state) {}
    }

    /// A loop is one stretch of time, from the first selected step to the
    /// last: every step between plays.
    @Test func aLoopPlaysEveryStepFromItsFirstToItsLast() {
        let seq = SequencerState(defaults: isolatedDefaults())
        seq.steps[4].degree = .IV
        seq.steps[8].degree = .V
        seq.selectedSteps = [0, 4, 8]
        seq.loopSelection()
        let sink = RecordingSink()
        let clock = ManualClock()
        let state = PerformanceState(sink: sink, clock: clock)
        state.setMode(SequencerMode(seq))
        seq.isPlaying = true
        for _ in 0..<9 { step(clock) }

        #expect(sink.playCalls.count == 10)          // nine steps, and the first again
        #expect(seq.currentStep == 0)
        withExtendedLifetime(state) {}
    }

    /// A loop set mid-playback that the playhead is outside of is joined at
    /// its start on the next step, keeping the pulse.
    @Test func settingALoopWhilePlayingJoinsItOnTheNextStep() {
        let (seq, clock, state) = start(bars: 1)
        for _ in 0..<6 { step(clock) }       // playhead on step 6
        seq.selectedSteps = [10, 11]
        seq.loopSelection()
        var visited: [Int] = []
        for _ in 0..<5 {
            step(clock)
            visited.append(seq.currentStep)
        }
        #expect(visited == [10, 11, 10, 11, 10])
        withExtendedLifetime(state) {}
    }

    /// A loop set round the playhead leaves it where it is.
    @Test func settingALoopRoundThePlayheadCarriesOn() {
        let (seq, clock, state) = start(bars: 1)
        for _ in 0..<6 { step(clock) }
        seq.selectedSteps = [4, 8]
        seq.loopSelection()
        var visited: [Int] = []
        for _ in 0..<4 {
            step(clock)
            visited.append(seq.currentStep)
        }
        #expect(visited == [7, 8, 4, 5])
        withExtendedLifetime(state) {}
    }

    @Test func stoppedSequencerDoesNotAdvance() {
        let (seq, clock, state) = start(bars: 1)
        seq.isPlaying = false
        step(clock)
        #expect(seq.currentStep == -1)
        withExtendedLifetime(state) {}
    }

    /// The landscape sequencer's SEQ button, tapped while already in the
    /// sequencer, used to re-enter the mode and stop playback.
    @Test func tappingSeqInTheSequencerKeepsItPlaying() {
        let (seq, clock, state) = start(bars: 1)
        step(clock)
        state.selectMode(.sequencer)   // what the SEQ button calls

        #expect(seq.isPlaying)
        withExtendedLifetime(state) {}
    }

    @Test func leavingTheSequencerStopsIt() {
        let (seq, clock, state) = start(bars: 1)
        step(clock)
        state.selectMode(.play)
        #expect(!seq.isPlaying)
        #expect(seq.currentStep == -1)
        #expect(clock.pendingCount == 0)
    }

    /// A tied step followed by the same chord holds it, as the MIDI export
    /// does: one note-on, no retrigger.
    @Test func tiedIdenticalStepsHoldTheChord() {
        let seq = SequencerState(defaults: isolatedDefaults())
        seq.steps[0] = SequencerStep(degree: .I, gate: 1)
        seq.steps[1] = SequencerStep(degree: .I, gate: 0.5)
        let sink = RecordingSink()
        let clock = ManualClock()
        let state = PerformanceState(sink: sink, clock: clock)
        state.setMode(SequencerMode(seq))
        seq.isPlaying = true
        step(clock)

        #expect(sink.playCalls.count == 1)
        withExtendedLifetime(state) {}
    }

    /// An edit is heard without stopping: the step changed ahead of the
    /// playhead plays its new chord this time round.
    @Test func anEditWhilePlayingIsHeardThisRound() {
        let seq = SequencerState(defaults: isolatedDefaults())
        let sink = RecordingSink()
        let clock = ManualClock()
        let state = PerformanceState(sink: sink, clock: clock)
        state.setMode(SequencerMode(seq))
        seq.isPlaying = true
        step(clock)
        seq.steps[3].degree = .V
        step(clock); step(clock)

        #expect(sink.lastPlay?.notes == [67, 71, 74])
        withExtendedLifetime(state) {}
    }
}
