/// A chord key: what a finger plays a chord from. The layouts of seven keys
/// have a key for each degree; the octave has one for each note, the root of
/// its chord. `PerformanceState` and the modes hear of keys, and what a key
/// plays is worked out here from the key the keys are in, so nothing past
/// them knows which layout was played.
enum ChordKey: Hashable, Sendable {
    /// The key of a degree of the scale.
    case degree(Degree)
    /// A key of the octave: the chord on that note (`KeyDegree.init(root:in:)`).
    case root(PitchClass)

    /// The chord the key plays while the keys are in `key`: for a root
    /// outside it, in the key it is borrowed from.
    func chord(in key: Key) -> KeyDegree {
        switch self {
        case .degree(let degree): return KeyDegree(key: key, degree: degree)
        case .root(let root):     return KeyDegree(root: root, in: key)
        }
    }

    /// The degree of `key` this is the key of; nil for a root outside it.
    func degree(in key: Key) -> Degree? {
        switch self {
        case .degree(let degree): return degree
        case .root(let root):     return key.degree(of: root)
        }
    }

    /// The octaves its chord is moved by. The octave's chords go up from C
    /// to B as its keys do, so a root its key would build past B is an
    /// octave down.
    func octaveShift(in key: Key) -> Int {
        guard case .root = self else { return 0 }
        let chord = chord(in: key)
        return chord.key.root.rawValue + chord.key.scale.offset(of: chord.degree) >= 12 ? -1 : 0
    }
}
