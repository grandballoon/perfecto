/// The sequencer's screen, as a mode: while it is on, the chord keys are not
/// played and the sequencer is heard.
///
/// Playing the sequence is not this mode's work. A `TimelinePlayer` runs the
/// timeline against the clock; the mode only connects the sequencer on
/// screen to it, and stops it on the way out.
@MainActor
final class SequencerMode: PerformanceMode {
    var kind: ModeKind { .sequencer }
    var requiresClock: Bool { false }

    private let seqState: SequencerState

    init(_ seqState: SequencerState) {
        self.seqState = seqState
    }

    func activate(state: PerformanceState) {
        state.attach(seqState)
    }

    // The chord buttons do nothing while the sequencer is on screen.
    func onButtonDown(degree: Degree, state: PerformanceState) { }
    func onButtonUp(degree: Degree, state: PerformanceState) { }
    func onColorChange(state: PerformanceState) { }

    func deactivate(state: PerformanceState) {
        state.detach(seqState)
        state.endChord()
    }
}
