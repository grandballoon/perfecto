@MainActor
final class SequencerMode: PerformanceMode {
    var name: String { "Sequencer" }
    var requiresClock: Bool { true }

    private let seqState: SequencerState
    private var gateTask: Task<Void, Never>?

    init(_ seqState: SequencerState) {
        self.seqState = seqState
    }

    // Sequencer handles its own step progression — chord buttons do nothing during playback.
    func onButtonDown(degree: Degree, state: PerformanceState) { }
    func onButtonUp(degree: Degree, state: PerformanceState) { }
    func onJoystickChange(direction: JoystickDirection, state: PerformanceState) { }

    func onClockTick(state: PerformanceState) {
        guard seqState.isPlaying else { return }

        // Advance the global playhead. In chain mode it runs through every bar;
        // otherwise it loops the 16 steps of the current bar. The visible page
        // follows the playhead so the grid shows the bar that's sounding.
        let total = seqState.steps.count
        let idx: Int
        if seqState.chain {
            idx = (seqState.currentStep + 1) % total
            seqState.currentPage = idx / 16
        } else {
            let base = seqState.currentPage * 16
            let within = (((seqState.currentStep - base) + 1) % 16 + 16) % 16
            idx = base + within
        }
        seqState.currentStep = idx

        guard idx < seqState.steps.count else { return }
        let step = seqState.steps[idx]
        gateTask?.cancel()

        if step.isRest {
            state.stopAudioOnly()
            return
        }

        state.playSequencerStep(degree: step.degree,
                                joystickMode: step.joystickMode,
                                joystickDirection: step.joystickDirection)

        // Gate shapes note length within the 1/16th step:
        //  • ≥ 98% → legato/tie: skip the note-off so the chord rings into the
        //    next step, where the next note-on (or a rest) takes over. This is
        //    the clearly-audible top of the range.
        //  • otherwise → release after `gate` fraction of the step (staccato as
        //    the value drops).
        guard step.gate < 0.98 else { return }
        let stepSecs = 60.0 / state.bpm / 4.0
        let gateNs   = UInt64(step.gate * stepSecs * 1_000_000_000)
        gateTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: gateNs)
            guard !Task.isCancelled else { return }
            state.stopAudioOnly()
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
