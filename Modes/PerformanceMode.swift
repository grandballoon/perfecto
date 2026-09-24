/// Identifies a performance mode. Views, settings and logs decide by kind,
/// never by display name, so renaming or localizing a mode changes nothing else.
enum ModeKind: CaseIterable {
    case play, strum, lead, drone, arpeggio, `repeat`, sequencer, looper, micSample

    var displayName: String {
        switch self {
        case .play:      return "Play"
        case .strum:     return "Strum"
        case .lead:      return "Lead"
        case .drone:     return "Drone"
        case .arpeggio:  return "Arpeggio"
        case .repeat:    return "Repeat"
        case .sequencer: return "Sequencer"
        case .looper:    return "Looper"
        case .micSample: return "Mic Sample"
        }
    }

    var summary: String {
        switch self {
        case .play:      return "Chord sustains while held"
        case .strum:     return "Notes arpeggiate on button press"
        case .lead:      return "Single melody note per button"
        case .drone:     return "Press to latch; press again to stop"
        case .arpeggio:  return "Sequential notes at tempo"
        case .repeat:    return "Chord retriggers at tempo"
        case .sequencer: return "16-step chord sequence"
        case .looper:    return "2-track audio looper"
        case .micSample: return "Record a clip; play it via buttons"
        }
    }

    /// The screen the mode is played from.
    var surface: ModeSurface {
        switch self {
        case .sequencer: return .sequencer
        case .looper:    return .looper
        case .micSample: return .micSample
        case .play, .strum, .lead, .drone, .arpeggio, .repeat: return .chords
        }
    }
}

/// What the main screen shows for a mode.
enum ModeSurface {
    /// The chord buttons and coloration bar.
    case chords
    /// The step sequencer, which replaces the chord buttons.
    case sequencer
    /// The looper's track controls with its own chord buttons.
    case looper
    /// The chord buttons with the mic recorder above them.
    case micSample
}

/// One way of turning chord-button presses into sound.
///
/// Button contract (enforced by `PerformanceState`, so modes can rely on it):
/// - Every `onButtonDown(degree)` is eventually followed by exactly one
///   `onButtonUp` for the same degree, unless a later press supersedes it.
/// - Several degrees may be held at once (several fingers). The most recent
///   press is the active one; `onButtonUp` is called only when the active
///   degree is released. Releasing an older, superseded press is not reported.
@MainActor
protocol PerformanceMode: AnyObject {
    var kind: ModeKind { get }
    var requiresClock: Bool { get }
    func onButtonDown(degree: Degree, state: PerformanceState)
    func onButtonUp(degree: Degree, state: PerformanceState)
    func onJoystickChange(direction: JoystickDirection, state: PerformanceState)
    func onClockTick(state: PerformanceState)
    func deactivate(state: PerformanceState)
}

extension PerformanceMode {
    var name: String { kind.displayName }
    func onClockTick(state: PerformanceState) { }
    func deactivate(state: PerformanceState) { state.endChord() }
}
