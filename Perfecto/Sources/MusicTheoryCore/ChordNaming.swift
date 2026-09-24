// Chord labelling — the single source of truth for the text the player sees.
//
// The on-screen chord name is derived from the *same* inputs that produce the
// notes: the scale-driven base quality (major/minor/dim) and the shape the
// chord's color resolves to (`chordShape`). Nothing here maintains a parallel
// table, so the label cannot say "maj7" while a min7 sounds, and it stays
// correct across scales rather than assuming the major scale's diatonic qualities.

/// The natural triad quality of a scale degree.
public enum TriadBase: Sendable {
    case major, minor, dim
}

/// The natural triad quality of `degree` within `key`'s scale — the exact
/// major/minor/dim determination `computeVoicing` uses to pick chord intervals.
/// Extracted so the sounding notes and the displayed label share one rule.
public func triadBase(key: Key, degree: Degree) -> TriadBase {
    let scale = key.scale
    let root = scale.offset(of: degree)
    let thirdInterval = scale.semitones(atStep: degree.index + 2) - root
    let fifthInterval = scale.semitones(atStep: degree.index + 4) - root

    let isMinor = thirdInterval < 4          // minor or augmented-4th third
    let isDim   = isMinor && fifthInterval < 7  // flat fifth confirms diminished
    return isDim ? .dim : isMinor ? .minor : .major
}

extension Key {
    /// Whether the key is minor: its scale has a minor third above the tonic and
    /// no major third. D Dorian is minor, G Mixolydian major. On seven-note
    /// scales this is exactly whether degree I plays a minor triad; unlike
    /// `triadBase`, it is also right for pentatonic and blues scales.
    public var isMinor: Bool { scale.intervals.contains(3) && !scale.intervals.contains(4) }
}

/// Pitch class of the chord root for `degree` in `key`.
public func chordRootPitchClass(key: Key, degree: Degree) -> PitchClass {
    let raw = (key.root.rawValue + key.scale.offset(of: degree)) % 12
    return PitchClass(rawValue: raw)!
}

/// Roman numeral for `degree` in `key`, cased by the degree's triad quality:
/// uppercase for major, lowercase for minor, lowercase with "°" for diminished.
/// Numerals count scale steps, so C natural minor reads i ii° III iv v VI VII.
public func degreeNumeral(key: Key, degree: Degree) -> String {
    let numeral = ["I", "II", "III", "IV", "V", "VI", "VII"][degree.index]
    switch triadBase(key: key, degree: degree) {
    case .major: return numeral
    case .minor: return numeral.lowercased()
    case .dim:   return numeral.lowercased() + "°"
    }
}

/// The intervals and quality name `spec` resolves to in `key`. The one place a
/// chord color is turned into a shape, shared by `computeVoicing` (the notes)
/// and `chordQualityName` (the label).
func chordShape(key: Key, spec: ChordSpec) -> ChordShape {
    let base = triadBase(key: key, degree: spec.degree)
    switch spec.color {
    case let .joystick(mode, direction):
        return JoystickMap.outcome(mode: mode, direction: direction).shape(for: base)
    }
}

/// Quality name for `spec` (e.g. "maj7", "min7♭5").
public func chordQualityName(key: Key, spec: ChordSpec) -> String {
    chordShape(key: key, spec: spec).name
}

/// Full chord label for the OLED display, e.g. "D min7".
public func chordLabel(key: Key, spec: ChordSpec) -> String {
    let root = chordRootPitchClass(key: key, degree: spec.degree)
    return "\(root.name) \(chordQualityName(key: key, spec: spec))"
}

/// Base-independent gesture legend for the joystick ring, e.g. "Dom 7".
public func joystickActionLabel(mode: JoystickMode,
                                direction: JoystickDirection) -> String {
    JoystickMap.outcome(mode: mode, direction: direction).action
}
