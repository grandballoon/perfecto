/// Which chord to play, independent of key and voicing: a scale degree and how
/// its base triad is colored. The key comes from the performance context;
/// octave, inversion and voice leading are voicing choices applied afterwards
/// by `computeVoicing`. A sequencer step stores one of these, and a live
/// press builds one from the current input surface.
public struct ChordSpec: Hashable, Sendable {
    public let degree: Degree
    public let color: ChordColor

    public init(degree: Degree, color: ChordColor) {
        self.degree = degree
        self.color = color
    }
}

/// How a degree's base triad is transformed into the chord that sounds.
/// Each input surface contributes a case, so the rest of the app depends on
/// "a color" rather than on any one surface's coordinates.
public enum ChordColor: Hashable, Sendable {
    /// A direction on the joystick in one of its three modes (JoystickMap).
    case joystick(JoystickMode, JoystickDirection)

    /// The unmodified base triad.
    public static let base = ChordColor.joystick(.default, .center)
}
