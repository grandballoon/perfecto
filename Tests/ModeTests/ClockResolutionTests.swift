import Testing
@testable import Perfecto

/// Fix #2 — the clock's tick resolution is part of the ClockTickable contract
/// (`ticksPerBeat`), not a "4" hardcoded in each mode. These tests pin that a
/// tempo-aware mode subdivides according to the injected clock, so changing the
/// clock's resolution changes the mode without editing the mode.
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

    @Test func performanceStateReportsClockResolution() {
        let clock = ManualClock()
        clock.ticksPerBeat = 3
        let (state, _) = makeState(clock: clock)
        #expect(state.ticksPerBeat == 3)
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

    @Test func repeatRetriggersOncePerBeat() {
        let clock = ManualClock()               // ticksPerBeat = 4
        let (state, sink) = makeState(clock: clock)
        state.setMode(RepeatMode())
        state.press(degree: .I)                 // initial chord
        sink.reset()

        clock.tick(); clock.tick(); clock.tick()
        #expect(sink.calls.isEmpty)             // nothing before the beat lands
        clock.tick()
        // On the beat, Repeat silences the chord (stopSounding) to start the
        // retrigger gap; that stop is the observable per-beat event.
        #expect(sink.calls.contains(.stop))
    }

    /// Sequencer steps stay sixteenth notes on a finer clock: at 8 ticks per
    /// beat the playhead moves every second tick.
    @Test func sequencerStepsStaySixteenthsOnAFinerClock() {
        let clock = ManualClock()
        clock.ticksPerBeat = 8
        let (state, _) = makeState(clock: clock)
        let seq = SequencerState(defaults: isolatedDefaults())
        state.setMode(SequencerMode(seq))
        seq.isPlaying = true

        var playhead: [Int] = []
        for _ in 0..<6 { clock.tick(); playhead.append(seq.currentStep) }
        #expect(playhead == [0, 0, 1, 1, 2, 2])
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

/// Fix #3 — `stopSounding()` (formerly the misnamed `stopAudioOnly()`) stops the
/// chord on every sink yet keeps the display/gesture state, unlike `endChord()`.
@Suite("StopSounding")
@MainActor
struct StopSoundingTests {

    private func makeState() -> (PerformanceState, RecordingSink) {
        let sink = RecordingSink()
        return (PerformanceState(sink: sink, clock: ManualClock()), sink)
    }

    @Test func stopSoundingReachesSinkButKeepsGesture() {
        let (state, sink) = makeState()
        state.startChord(degree: .I)
        sink.reset()

        state.stopSounding()

        // It really stops on the sink (audio/MIDI/ChordLink all fan out from here)…
        #expect(sink.calls.contains(.stop))
        // …but the held gesture and display survive, so a mode can retrigger.
        #expect(state.activeDegree == .I)
        #expect(state.activeVoicingText != "—")
    }

    @Test func endChordClearsGestureUnlikeStopSounding() {
        let (state, _) = makeState()
        state.startChord(degree: .I)

        state.endChord()

        #expect(state.activeDegree == nil)
        #expect(state.activeVoicingText == "—")
    }
}
