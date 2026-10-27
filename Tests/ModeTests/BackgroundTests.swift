import Testing
@testable import Perfecto

/// The app leaving the screen (the phone locked, another app opened): nothing
/// it was playing goes on sounding, and nothing held is left down for when it
/// comes back.
@Suite("Background")
@MainActor
struct BackgroundTests {

    private func makeState(clock: ManualClock = ManualClock()) -> (PerformanceState, RecordingSink) {
        let sink = RecordingSink()
        let state = PerformanceState(sink: sink,
                                     sequencer: SequencerState(defaults: isolatedDefaults()),
                                     keyboard: KeyboardState(defaults: isolatedDefaults()),
                                     clock: clock)
        return (state, sink)
    }

    /// A chord on each beat of a bar.
    private let progression: [TimelineNote] = [Degree.I, .vi, .IV, .V].enumerated().map { beat, degree in
        TimelineNote(start: beat * TimelineTime.ticksPerBeat, length: TimelineTime.ticksPerBeat / 2,
                     chord: ChordSpec(degree: degree, color: .base))
    }

    @Test func aChordHeldStopsAndItsKeyIsLetGo() {
        let (state, sink) = makeState()
        state.press(.degree(.I))
        state.press(.degree(.V))
        state.enterBackground()
        #expect(state.heldKeys.isEmpty)
        #expect(state.activeDegree == nil)
        #expect(sink.stopCount == 1)
        // Nothing struck again on the way out.
        #expect(sink.playCalls.count == 2)
    }

    @Test func aPlaceHeldOnTheCompassIsLetGo() {
        let (state, _) = makeState()
        state.compassPressed(CompassPlace(.add, 1))
        state.enterBackground()
        #expect(state.compassPlaces.isEmpty)
        // The next chord after coming back is plain.
        state.enterForeground()
        #expect(state.color(for: .V) == .base)
    }

    /// A walk kept is a setting, not a finger, so it stays.
    @Test func aKeptWalkStays() {
        let (state, _) = makeState()
        state.keepsCompassColor = true
        state.compassPressed(CompassPlace(.add, 1))
        state.enterBackground()
        #expect(state.compassPlaces == [CompassPlace(.add, 1)])
    }

    @Test func aVoicingBentIsLetGo() {
        let (state, _) = makeState()
        state.keepsVoicing = false
        state.holdVoicing(at: state.voicing.bent(by: VoicingBend(octaves: 1, steps: 0)))
        state.enterBackground()
        #expect(state.voicingBend == .none)
    }

    @Test func aKeyHeldOnTheKeyboardIsLetGo() {
        let (state, sink) = makeState()
        let a = KeyboardKey(code: 4, name: "A")
        state.keyboard.keyDown(a)
        state.enterBackground()
        #expect(state.heldKeys.isEmpty)
        // Its key coming up later finds nothing to let go.
        state.keyboard.keyUp(code: a.code)
        #expect(sink.stopCount == 1)
        // And it can be played again.
        state.keyboard.keyDown(a)
        #expect(state.heldKeys == [.degree(.I)])
    }

    @Test func theLoopsStopAndStayStoppedOnComingBack() {
        let (state, _) = makeState()
        state.sequencerState.addLayers([progression])
        state.quickLoopState.toggleRunning()
        #expect(state.quickLoopState.isRunning)
        state.enterBackground()
        #expect(!state.quickLoopState.isRunning)
        state.enterForeground()
        #expect(!state.quickLoopState.isRunning)
        #expect(state.quickLoopState.loops.count == 1)
    }

    @Test func aTakeCountingInIsCalledOff() {
        let clock = ManualClock()
        let (state, _) = makeState(clock: clock)
        state.quickLoopState.hotkeyTapped()
        #expect(state.quickLoopState.isTaking)
        state.enterBackground()
        #expect(state.quickLoopState.phase == .idle)
        clock.advance(seconds: Double(QuickLoopState.countIn) + 60)
        #expect(state.quickLoopState.phase == .idle)
        #expect(state.quickLoopState.loops.isEmpty)
    }
}
