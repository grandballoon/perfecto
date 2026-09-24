import Foundation
import Testing
@testable import Perfecto

/// Playhead movement across bars, driven through the clock as in the app.
@Suite("SequencerPlayback")
@MainActor
struct SequencerPlaybackTests {

    /// Returns the PerformanceState too: the clock holds it weakly, so the
    /// caller must keep it alive for ticks to reach the mode.
    private func start(bars: Int, chain: Bool, page: Int = 0)
        -> (SequencerState, ManualClock, PerformanceState) {
        let seq = SequencerState(defaults: isolatedDefaults())
        seq.setBars(bars)
        seq.chain = chain
        seq.currentPage = page
        let clock = ManualClock()
        let state = PerformanceState(sink: RecordingSink(), clock: clock)
        state.setMode(SequencerMode(seq))
        seq.isPlaying = true
        return (seq, clock, state)
    }

    @Test func chainPlaysEveryBarAndThePageFollowsThePlayhead() {
        let (seq, clock, state) = start(bars: 2, chain: true)
        var visited: [Int] = []
        for _ in 0..<32 {
            clock.tick()
            visited.append(seq.currentStep)
            #expect(seq.currentPage == seq.currentStep / 16)
        }
        #expect(visited == Array(0..<32))

        clock.tick()                         // wraps back to the first bar
        #expect(seq.currentStep == 0)
        #expect(seq.currentPage == 0)
        withExtendedLifetime(state) {}
    }

    @Test func withoutChainTheVisibleBarLoops() {
        let (seq, clock, state) = start(bars: 2, chain: false, page: 1)
        var visited: [Int] = []
        for _ in 0..<20 {
            clock.tick()
            visited.append(seq.currentStep)
        }
        #expect(visited == Array(16..<32) + Array(16..<20))
        #expect(seq.currentPage == 1)
        withExtendedLifetime(state) {}
    }

    @Test func stoppedSequencerDoesNotAdvance() {
        let (seq, clock, state) = start(bars: 1, chain: true)
        seq.isPlaying = false
        clock.tick()
        #expect(seq.currentStep == -1)
        withExtendedLifetime(state) {}
    }

    /// The landscape sequencer's SEQ button, tapped while already in the
    /// sequencer, used to re-enter the mode and stop playback.
    @Test func tappingSeqInTheSequencerKeepsItPlaying() {
        let (seq, clock, state) = start(bars: 1, chain: true)
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
