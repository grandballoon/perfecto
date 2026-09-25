@MainActor
final class SequencerMode: PerformanceMode {
    var kind: ModeKind { .sequencer }
    var requiresClock: Bool { true }

    private let seqState: SequencerState
    private var gateTask: Task<Void, Never>?
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

        // Advance the global playhead. In chain mode it runs through every bar;
        // otherwise it loops the current bar. The visible page follows the
        // playhead so the grid shows the bar that's sounding.
        let total = seqState.steps.count
        let perBar = SequencerState.stepsPerBar
        let previousIdx = seqState.currentStep
        let idx: Int
        if seqState.chain {
            idx = (previousIdx + 1) % total
            seqState.currentPage = idx / perBar
        } else {
            let base = seqState.currentPage * perBar
            let within = (((previousIdx - base) + 1) % perBar + perBar) % perBar
            idx = base + within
        }
        seqState.currentStep = idx

        guard idx < total else { return }
        let step = seqState.steps[idx]
        let previous = seqState.steps.indices.contains(previousIdx) ? seqState.steps[previousIdx] : nil
        gateTask?.cancel()

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
        let stepSecs = 60.0 / state.bpm / Double(MusicalTime.stepsPerBeat)
        let gateNs   = UInt64(step.gate * stepSecs * 1_000_000_000)
        gateTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: gateNs)
            guard !Task.isCancelled else { return }
            state.stopSounding()
        }
    }

    func deactivate(state: PerformanceState) {
        gateTask?.cancel()
        gateTask = nil
        seqState.isPlaying = false
        seqState.currentStep = -1
        state.endChord()
    }
}
