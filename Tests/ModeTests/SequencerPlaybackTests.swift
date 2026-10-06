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

    @Test func theWholePatternPlaysAndTheFocusedBarFollowsThePlayhead() {
        let (seq, clock, state) = start(bars: 3)
        var visited: [Int] = []
        for _ in 0..<48 {
            clock.tick()
            visited.append(seq.currentStep)
            #expect(seq.focusedBar == seq.currentStep / 16)
        }
        #expect(visited == Array(0..<48))

        clock.tick()                         // wraps back to the first bar
        #expect(seq.currentStep == 0)
        #expect(seq.focusedBar == 0)
        withExtendedLifetime(state) {}
    }

    @Test func aLoopedPortionRepeatsOnItsOwn() {
        let (seq, clock, state) = start(bars: 2, loop: Set(12..<20))
        var visited: [Int] = []
        for _ in 0..<12 {
            clock.tick()
            visited.append(seq.currentStep)
        }
        #expect(visited == Array(12..<20) + Array(12..<16))
        withExtendedLifetime(state) {}
    }

    /// A loop need not be one run of steps: only the chosen steps sound.
    @Test func aLoopOfSeparateStepsPlaysOnlyThoseSteps() {
        let seq = SequencerState(defaults: isolatedDefaults())
        seq.steps[0].degree = .I
        seq.steps[4].degree = .IV
        seq.steps[8].degree = .V
        seq.selectedSteps = [0, 4, 8]
        seq.loopSelection()
        let sink = RecordingSink()
        let clock = ManualClock()
        let state = PerformanceState(sink: sink, clock: clock)
        state.setMode(SequencerMode(seq))
        seq.isPlaying = true
        for _ in 0..<4 { clock.tick() }

        #expect(sink.playCalls.count == 4)
        #expect(seq.currentStep == 0)
        withExtendedLifetime(state) {}
    }

    /// Setting a loop mid-playback brings the playhead into it at the next
    /// loop step rather than restarting.
    @Test func settingALoopWhilePlayingJoinsItFromThePlayhead() {
        let (seq, clock, state) = start(bars: 1)
        for _ in 0..<7 { clock.tick() }      // playhead on step 6
        seq.selectedSteps = [2, 3, 10, 11]
        seq.loopSelection()
        var visited: [Int] = []
        for _ in 0..<5 {
            clock.tick()
            visited.append(seq.currentStep)
        }
        #expect(visited == [10, 11, 2, 3, 10])
        withExtendedLifetime(state) {}
    }

    @Test func stoppedSequencerDoesNotAdvance() {
        let (seq, clock, state) = start(bars: 1)
        seq.isPlaying = false
        clock.tick()
        #expect(seq.currentStep == -1)
        withExtendedLifetime(state) {}
    }

    /// The landscape sequencer's SEQ button, tapped while already in the
    /// sequencer, used to re-enter the mode and stop playback.
    @Test func tappingSeqInTheSequencerKeepsItPlaying() {
        let (seq, clock, state) = start(bars: 1)
        clock.tick()
        state.selectMode(.sequencer)   // what the SEQ button calls

        #expect(seq.isPlaying)
        withExtendedLifetime(state) {}
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
        clock.tick()
        clock.tick()

        #expect(sink.playCalls.count == 1)
        withExtendedLifetime(state) {}
    }
}
