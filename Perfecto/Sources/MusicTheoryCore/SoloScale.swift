// The notes a run can be played from over a chord with none of them
// sounding wrong: what the solo strip offers. They are worked out from the
// chord that sounds and the scale it sits in, not looked up, so every chord
// color in every key has an answer.

/// What a note of the solo scale is to the chord it is played over.
public enum SoloRole: Sendable {
    /// The chord's root.
    case root
    /// Another note of the triad the chord is built on.
    case chordTone
    /// A note of the scale that sits clear of the triad.
    case passing
}

/// One note of the solo scale.
public struct SoloNote: Equatable, Sendable {
    /// A MIDI note, within `Voicing.midiRange`.
    public let note: Int
    public let role: SoloRole
}

/// The solo scale over `spec` in `key`, as semitones above the chord's root
/// (ascending, within an octave, starting with the root at 0).
///
/// It is the pentatonic the chord implies:
/// - the triad the chord is built on (its first three tones), always;
/// - with it, each note of the chord's scale that is not a semitone from a
///   note of the triad (the fourth over a major chord, the second over a
///   minor one);
/// - and of two such notes a semitone apart, only the upper (the seventh
///   over a Dorian chord, not its sixth).
///
/// The chord's scale is the mode a grid color names, and the key's scale
/// otherwise. So no two notes of the result are a semitone apart: a major
/// chord gets the major pentatonic and a minor chord the minor one, and a
/// chord whose triad leaves the scale little room (diminished, augmented)
/// gets little more than its own tones.
public func soloIntervals(key: Key, spec: ChordSpec) -> [Int] {
    let triad = Set(chordShape(key: key, spec: spec).intervals.prefix(3).map { $0 % 12 })
    let scale = chordScale(key: key, spec: spec)
    let clear = scale.filter { step in
        !triad.contains(step) && !triad.contains((step + 1) % 12) && !triad.contains((step + 11) % 12)
    }
    let passing = clear.filter { !clear.contains(($0 + 1) % 12) }
    return triad.union(passing).sorted()
}

/// The first `count` notes of the solo scale over `spec` at or above `low`,
/// ascending; fewer where MIDI's range ends first.
public func soloNotes(key: Key, spec: ChordSpec, from low: Int, count: Int) -> [SoloNote] {
    let root = chordRootPitchClass(key: key, degree: spec.degree).rawValue
    let roles = soloRoles(key: key, spec: spec)
    var notes: [SoloNote] = []
    var note = max(low, Voicing.midiRange.lowerBound)
    while notes.count < count, note <= Voicing.midiRange.upperBound {
        if let role = roles[((note - root) % 12 + 12) % 12] {
            notes.append(SoloNote(note: note, role: role))
        }
        note += 1
    }
    return notes
}

/// The solo scale's intervals, each with what it is to the chord.
private func soloRoles(key: Key, spec: ChordSpec) -> [Int: SoloRole] {
    let triad = Set(chordShape(key: key, spec: spec).intervals.prefix(3).map { $0 % 12 })
    var roles: [Int: SoloRole] = [:]
    for interval in soloIntervals(key: key, spec: spec) {
        roles[interval] = interval == 0 ? .root : triad.contains(interval) ? .chordTone : .passing
    }
    return roles
}

/// The scale `spec`'s chord sits in, as semitones above the chord's root
/// within an octave: the mode a grid color stacks through, or `key`'s scale
/// read from the chord's degree.
private func chordScale(key: Key, spec: ChordSpec) -> [Int] {
    if case let .grid(_, mode?) = spec.color { return mode.intervals }
    let root = key.scale.offset(of: spec.degree)
    return key.scale.intervals.map { (($0 - root) % 12 + 12) % 12 }
}
