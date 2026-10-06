@MainActor
final class SequencerMode: PerformanceMode {
    var kind: ModeKind { .sequencer }
    var requiresClock: Bool { true }

    private let seqState: SequencerState
    /// The clock's call to end the step that is sounding, at its gate.
    private var gate: ClockCall?
    /// Ticks elapsed within the current step (0 = the step starts on this tick).
    private var tickInStep = 0

    init(_ seqState: SequencerState) {
        self.seqState = seqState
    }

    // Sequencer handles its own step progression — chord buttons do nothing during playback.
    func onButtonDown(degree: Degree, state: PerformanceState) { }
    func onButtonUp(degree: Degree, state: PerformanceState) { }
    func onColorChange(state: PerformanceState) { }

    func onClockTick(state: PerformanceState) {
        guard seqState.isPlaying else { return }

        // Steps are sixteenth notes; the clock may tick more finely.
        let ticksPerStep = state.ticksPerBeat / MusicalTime.stepsPerBeat
        defer { tickInStep = (tickInStep + 1) % ticksPerStep }
        guard tickInStep == 0 else { return }

        // Advance the global playhead through the loop (or the whole pattern).
        // The focused bar follows it so the grid shows the bar that's sounding.
        let previousIdx = seqState.currentStep
        let idx = seqState.step(after: previousIdx)
        seqState.currentStep = idx
        seqState.focusedBar = idx / SequencerState.stepsPerBar

        let step = seqState.steps[idx]
        let previous = seqState.steps.indices.contains(previousIdx) ? seqState.steps[previousIdx] : nil
        gate?.cancel()

        if step.isRest {
            state.stopSounding()
            return
        }

        if !step.continues(previous) {
            state.playSequencerStep(step.spec)
        }

        // Gate shapes note length within the step:
        //  • ≥ 98% → legato/tie: skip the note-off so the chord rings into the
        //    next step, where the next note-on (or a rest) takes over — or, for
        //    the same chord, simply continues. This is the clearly-audible top
        //    of the range.
        //  • otherwise → release after `gate` fraction of the step (staccato as
        //    the value drops).
        guard !step.isTied else { return }
        gate = state.after(beats: step.gate / Double(MusicalTime.stepsPerBeat)) { [weak state] in
            state?.stopSounding()
        }
    }

    func deactivate(state: PerformanceState) {
        gate?.cancel()
        gate = nil
        seqState.isPlaying = false
        seqState.currentStep = -1
        state.endChord()
    }
}
