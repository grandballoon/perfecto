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

    @Test func arpeggioFiresOncePerBeatAtDefaultResolution() {
        let clock = ManualClock()               // ticksPerBeat = 4
        let (state, sink) = makeState(clock: clock)
        state.setMode(ArpeggioMode())
        state.press(degree: .I)                 // arms Cmaj, no audio yet
        sink.reset()

        // Three ticks: below the four-tick beat, nothing fires.
        clock.tick(); clock.tick(); clock.tick()
        #expect(sink.playCalls.isEmpty)

        // Fourth tick completes the beat and plays one arpeggio note.
        clock.tick()
        #expect(sink.playCalls.count == 1)
    }

    @Test func arpeggioFollowsAChangedClockResolution() {
        let clock = ManualClock()
        clock.ticksPerBeat = 2                   // coarser clock: a beat is two ticks
        let (state, sink) = makeState(clock: clock)
        state.setMode(ArpeggioMode())
        state.press(degree: .I)
        sink.reset()

        clock.tick()                             // one tick: below the two-tick beat
        #expect(sink.playCalls.isEmpty)
        clock.tick()                             // second tick completes the beat
        #expect(sink.playCalls.count == 1)
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
        #expect(sink.calls.contains { $0.kind == .stop })
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
        #expect(sink.calls.contains { $0.kind == .stop })
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
