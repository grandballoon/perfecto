import Testing
@testable import Perfecto

/// The clock's tick resolution is part of the ClockTickable contract
/// (`ticksPerBeat`), not a "4" hardcoded anywhere: these tests pin that what
/// is timed by the clock keeps time on whatever clock is injected.
@Suite("ClockResolution")
@MainActor
struct ClockResolutionTests {

    private func makeState(clock: ManualClock) -> (PerformanceState, RecordingSink) {
        let sink = RecordingSink()
        let state = PerformanceState(sink: sink, clock: clock)
        return (state, sink)
    }

    @Test func defaultResolutionIsFourTicksPerBeat() {
        #expect(ManualClock().ticksPerBeat == 4)
        #expect(MasterClock().ticksPerBeat == 4)
    }

    /// The real clock's repeats: called over and over, and not after a cancel.
    @Test func aRepeatRunsUntilItIsCancelled() async throws {
        let clock = MasterClock()
        clock.bpm = 300                          // a beat is 0.2 s
        var calls = 0
        let repeating = clock.every(beats: 0.05) { calls += 1 }   // every 10 ms

        let ran = try await waitUntil { calls >= 3 }
        #expect(ran)
        repeating.cancel()
        let atCancel = calls
        try await Task.sleep(for: .milliseconds(60))
        #expect(calls == atCancel)
    }

    /// A step's gate is a share of the step, so it is timed in beats: the
    /// chord ends that far through the step at any tempo.
    @Test func aSequencerStepEndsAtItsGate() {
        for bpm in [120.0, 60.0] {
            let clock = ManualClock()
            clock.bpm = bpm
            let (state, sink) = makeState(clock: clock)
            let seq = SequencerState(defaults: isolatedDefaults())
            seq.steps[0] = SequencerStep(gate: 0.5)
            state.attach(seq)
            sink.reset()
            seq.isPlaying = true                                // step 1 starts
            #expect(sink.playCalls.count == 1)
            let step = 1.0 / Double(MusicalTime.stepsPerBeat)
            clock.advance(beats: 0.49 * step)
            #expect(sink.stopCount == 0, "\(bpm) BPM")
            clock.advance(beats: 0.02 * step)
            #expect(sink.stopCount == 1, "\(bpm) BPM")
        }
    }

    /// A tied step is not ended: it rings into the next one.
    @Test func aTiedSequencerStepRingsIntoTheNext() {
        let clock = ManualClock()
        let (state, sink) = makeState(clock: clock)
        let seq = SequencerState(defaults: isolatedDefaults())
        seq.steps[0] = SequencerStep(gate: 1)
        seq.steps[1] = SequencerStep(degree: .IV)
        state.attach(seq)
        sink.reset()
        seq.isPlaying = true
        clock.tick()
        #expect(sink.playCalls.count == 2)
        #expect(sink.stopCount == 0)
    }

    /// Stopping the sequencer inside a step leaves no gate waiting to fire.
    @Test func stoppingTheSequencerCancelsTheGate() {
        let clock = ManualClock()
        let (state, sink) = makeState(clock: clock)
        let seq = SequencerState(defaults: isolatedDefaults())
        seq.steps[0] = SequencerStep()
        state.attach(seq)
        seq.isPlaying = true
        seq.isPlaying = false
        sink.reset()

        clock.advance(beats: 4)
        #expect(sink.calls.isEmpty)
        #expect(clock.pendingCount == 0)
    }

    /// Sequencer steps stay sixteenth notes on a finer clock: at 8 ticks per
    /// beat the playhead, which starts on the first step, moves every second
    /// tick.
    @Test func sequencerStepsStaySixteenthsOnAFinerClock() {
        let clock = ManualClock()
        clock.ticksPerBeat = 8
        let (state, _) = makeState(clock: clock)
        let seq = SequencerState(defaults: isolatedDefaults())
        state.attach(seq)
        seq.isPlaying = true

        var playhead: [Int] = []
        for _ in 0..<6 { clock.tick(); playhead.append(seq.currentStep) }
        #expect(playhead == [0, 1, 1, 2, 2, 3])
    }

    /// What keeps time with the tempo is told it at the start and each
    /// time it is set, as it is kept in range.
    @Test func theTempoIsPassedOnToWhatKeepsTimeWithIt() {
        final class Listener: TempoControl {
            var tempos: [Double] = []
            func setTempo(_ bpm: Double) { tempos.append(bpm) }
        }
        let listener = Listener()
        let state = PerformanceState(sink: RecordingSink(), tempoListener: listener, clock: ManualClock())
        state.setBPM(90)
        state.setBPM(1000)
        #expect(listener.tempos == [MusicalTime.defaultTempo, 90, MusicalTime.tempoRange.upperBound])
    }

    @Test func tempoStaysInTheSupportedRange() {
        let clock = ManualClock()
        let (state, _) = makeState(clock: clock)
        state.setBPM(0)
        #expect(state.bpm == MusicalTime.tempoRange.lowerBound)
        #expect(clock.bpm == state.bpm)
        state.setBPM(1000)
        #expect(state.bpm == MusicalTime.tempoRange.upperBound)
        #expect(clock.bpm == state.bpm)
    }
}

/// `endChord()` stops the chord and clears the display and the gesture.
@Suite("EndChord")
@MainActor
struct EndChordTests {

    @Test func endChordClearsTheGesture() {
        let state = PerformanceState(sink: RecordingSink(), clock: ManualClock())
        state.startChord(.degree(.I))

        state.endChord()

        #expect(state.activeDegree == nil)
        #expect(state.activeVoicingText == "—")
    }
}
