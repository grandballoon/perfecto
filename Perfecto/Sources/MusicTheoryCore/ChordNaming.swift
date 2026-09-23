// Chord labelling — the single source of truth for the text the player sees.
//
// The on-screen chord name is derived from the *same* inputs that produce the
// notes: the scale-driven base quality (major/minor/dim) and the JoystickMap
// entry for the current direction. Nothing here maintains a parallel table, so
// the label cannot say "maj7" while a min7 sounds, and it stays correct across
// all ten scales rather than assuming the major scale's diatonic qualities.

/// The natural triad quality of a scale degree.
public enum TriadBase: Sendable {
    case major, minor, dim
}

/// The natural triad quality of `degree` within `key`'s scale — the exact
/// major/minor/dim determination `computeVoicing` uses to pick chord intervals.
/// Extracted so the sounding notes and the displayed label share one rule.
public func triadBase(key: Key, degree: Degree) -> TriadBase {
    let scale = key.scale.intervals
    let n = scale.count
    let degIdx = degree.index

    let degreeOffset = scale[degIdx % n] + (degIdx / n) * 12
    let thirdSteps = degIdx + 2
    let fifthSteps = degIdx + 4
    let thirdInterval = scale[thirdSteps % n] + (thirdSteps / n) * 12 - degreeOffset
    let fifthInterval = scale[fifthSteps % n] + (fifthSteps / n) * 12 - degreeOffset

    let isMinor = thirdInterval < 4          // minor or augmented-4th third
    let isDim   = isMinor && fifthInterval < 7  // flat fifth confirms diminished
    return isDim ? .dim : isMinor ? .minor : .major
}

/// Pitch class of the chord root for `degree` in `key`.
public func chordRootPitchClass(key: Key, degree: Degree) -> PitchClass {
    let scale = key.scale.intervals
    let n = scale.count
    let degIdx = degree.index
    let degreeOffset = scale[degIdx % n] + (degIdx / n) * 12
    let raw = ((key.root.rawValue + degreeOffset) % 12 + 12) % 12
    return PitchClass(rawValue: raw)!
}

/// Quality name for the current selection (e.g. "maj7", "min7♭5"), taken from
/// the same JoystickMap entry that yields the notes and the degree's base quality.
public func chordQualityName(key: Key,
                             degree: Degree,
                             joystickMode: JoystickMode,
                             joystickDirection: JoystickDirection) -> String {
    let base = triadBase(key: key, degree: degree)
    return JoystickMap.outcome(mode: joystickMode, direction: joystickDirection)
        .shape(for: base).name
}

/// Full chord label for the OLED display, e.g. "D min7".
public func chordLabel(key: Key,
                       degree: Degree,
                       joystickMode: JoystickMode,
                       joystickDirection: JoystickDirection) -> String {
    let root = chordRootPitchClass(key: key, degree: degree)
    let quality = chordQualityName(key: key,
                                   degree: degree,
                                   joystickMode: joystickMode,
                                   joystickDirection: joystickDirection)
    return "\(root.name) \(quality)"
}

/// Base-independent gesture legend for the joystick ring, e.g. "Dom 7".
public func joystickActionLabel(mode: JoystickMode,
                                direction: JoystickDirection) -> String {
    JoystickMap.outcome(mode: mode, direction: direction).action
}
