/// Identifies a performance mode. Views, settings and logs decide by kind,
/// never by display name, so renaming or localizing a mode changes nothing else.
/// The app has Play mode alone; Strum, Lead, Drone, Repeat and the
/// sequencer are parked on the `color-ring` branch.
enum ModeKind: CaseIterable {
    case play

    var displayName: String {
        switch self {
        case .play: return "Play"
        }
    }
}

/// One way of turning chord-button presses into sound.
///
/// Button contract (enforced by `PerformanceState`, so modes can rely on it):
/// - Several keys may be held at once (several fingers). The most recent
///   press is the active one. Releasing an older press is not reported.
/// - Releasing the active key while older presses are still held makes the
///   most recent of them active again: it arrives as a new `onButtonDown`,
///   with no `onButtonUp` in between, so the chord changes without a gap.
/// - `onButtonUp` is called only when the last held key is released.
///   Every `onButtonDown(key)` is therefore eventually followed by one
///   `onButtonUp` for the same key, unless another `onButtonDown`
///   supersedes it first.
///
/// A mode is told which key (`ChordKey`), and gives it back to the state to
/// play (`startChord`), which works out its chord as the keys are then.
@MainActor
protocol PerformanceMode: AnyObject {
    var kind: ModeKind { get }
    var requiresClock: Bool { get }
    func onButtonDown(key: ChordKey, state: PerformanceState)
    func onButtonUp(key: ChordKey, state: PerformanceState)
    /// The chord a held key plays changed: the live chord color (a place of
    /// the compass), or the key or octave (the finger moved into a key
    /// zone with its own). Modes that are sounding a chord play its key
    /// again, as `state` now has it.
    func onColorChange(state: PerformanceState)
    func onClockTick(state: PerformanceState)
    /// The mode has just become the active one.
    func activate(state: PerformanceState)
    func deactivate(state: PerformanceState)
}

extension PerformanceMode {
    var name: String { kind.displayName }
    func onClockTick(state: PerformanceState) { }
    func activate(state: PerformanceState) { }
    func deactivate(state: PerformanceState) { state.endChord() }
}
