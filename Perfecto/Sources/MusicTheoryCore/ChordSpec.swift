/// Which chord to play, independent of key and voicing: a scale degree and how
/// its base triad is colored. The key comes from the performance context;
/// octave, inversion and voice leading are voicing choices applied afterwards
/// by `computeVoicing`. A sequencer step stores one of these, and a live
/// press builds one from the current input surface.
public struct ChordSpec: Hashable, Codable, Sendable {
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
///
/// Codable by case name, so stored colors survive reordering; an unknown case
/// fails to decode rather than silently becoming another color.
public enum ChordColor: Hashable, Codable, Sendable {
    /// A direction on the joystick in one of its three modes (JoystickMap).
    case joystick(JoystickMode, JoystickDirection)
    /// A cell of the chord grid: thirds stacked to `height` through `mode`.
    /// A nil mode is the degree's own diatonic mode, so the chord follows the
    /// key (C major ii stacks through Dorian, C minor ii through Locrian); a
    /// named mode is the same chord quality in every key.
    case grid(StackHeight, HeptatonicMode?)

    /// The unmodified base triad.
    public static let base = ChordColor.joystick(.default, .center)

    /// Whether the color leaves the base triad unchanged.
    public var isBase: Bool {
        switch self {
        case let .joystick(_, direction): return direction == .center
        case let .grid(height, mode):     return height == .triad && mode == nil
        }
    }
}
