/// The color the color field gives the keys' chords (`KeyColorField`): one
/// of the joystick's, in any of its modes, so every shape the joystick has
/// is within reach of one finger. Its centre is the plain chord.
struct KeyColor: Hashable, Sendable {
    var mode: JoystickMode
    var direction: JoystickDirection

    static let base = KeyColor(mode: .default, direction: .center)

    /// Whether this is the plain chord, in whichever mode.
    var isBase: Bool { direction == .center }

    var color: ChordColor { .joystick(mode, direction) }

    /// What it does to any degree's triad, e.g. "Dom 7".
    var label: String { joystickActionLabel(mode: mode, direction: direction) }

    /// The color as the log has it: its mode and what it does, e.g.
    /// "extended Dom 9".
    var logName: String { "\(mode) \(label)" }
}
