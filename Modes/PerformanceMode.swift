/// Identifies a performance mode. Views, settings and logs decide by kind,
/// never by display name, so renaming or localizing a mode changes nothing else.
enum ModeKind: CaseIterable {
    case play, strum, lead, drone, `repeat`, sequencer

    var displayName: String {
        switch self {
        case .play:      return "Play"
        case .strum:     return "Strum"
        case .lead:      return "Lead"
        case .drone:     return "Drone"
        case .repeat:    return "Repeat"
        case .sequencer: return "Sequencer"
        }
    }

    var summary: String {
        switch self {
        case .play:      return "Chord sustains while held"
        case .strum:     return "Notes arpeggiate on button press"
        case .lead:      return "Single melody note per button"
        case .drone:     return "Press to latch; press again to stop"
        case .repeat:    return "Chord retriggers at tempo"
        case .sequencer: return "Chords in sequence, bar by bar"
        }
    }

    /// The screen the mode is played from.
    var surface: ModeSurface {
        switch self {
        case .sequencer: return .sequencer
        case .play, .strum, .lead, .drone, .repeat: return .chords
        }
    }
}

/// What the main screen shows for a mode.
enum ModeSurface {
    /// The chord buttons and coloration bar.
    case chords
    /// The step sequencer, which replaces the chord buttons.
    case sequencer
}

/// One way of turning chord-button presses into sound.
///
/// Button contract (enforced by `PerformanceState`, so modes can rely on it):
/// - Several degrees may be held at once (several fingers). The most recent
///   press is the active one. Releasing an older press is not reported.
/// - Releasing the active degree while older presses are still held makes the
///   most recent of them active again: it arrives as a new `onButtonDown`,
///   with no `onButtonUp` in between, so the chord changes without a gap.
/// - `onButtonUp` is called only when the last held degree is released.
///   Every `onButtonDown(degree)` is therefore eventually followed by one
///   `onButtonUp` for the same degree, unless another `onButtonDown`
///   supersedes it first.
@MainActor
protocol PerformanceMode: AnyObject {
    var kind: ModeKind { get }
    var requiresClock: Bool { get }
    func onButtonDown(degree: Degree, state: PerformanceState)
    func onButtonUp(degree: Degree, state: PerformanceState)
    /// The chord a held key plays changed: the live chord color (joystick
    /// or grid moved), or the key or octave (the finger moved into a key
    /// zone with its own). Modes that are sounding a chord play it again
    /// as `state` now has it.
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
