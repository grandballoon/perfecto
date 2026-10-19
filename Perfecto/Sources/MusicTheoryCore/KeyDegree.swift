// A chord named by its root. The chord keys name a chord by its degree, so
// the key says what it is; an octave of roots names it by its note, and the
// key still says what it is: a note of the key plays its own degree's chord,
// and a note outside it a chord borrowed from the scale nearest the key's.

/// A degree of a key: the triad a chord is built on, with the scale its
/// colors are read through.
public struct KeyDegree: Hashable, Sendable {
    public let key: Key
    public let degree: Degree

    public init(key: Key, degree: Degree) {
        self.key = key
        self.degree = degree
    }

    /// The chord on `root` as `key` has it.
    ///
    /// A note of the key is its own degree there. A note outside the key is
    /// borrowed from a parallel mode: of the modes of the major scale on the
    /// key's tonic that have the note, the one that changes the fewest of the
    /// key's notes (of two as near, the brighter). So C major has B♭ major
    /// from Mixolydian, E♭ and A♭ major from Dorian and Aeolian, D♭ major
    /// from Phrygian and F♯ diminished from Lydian.
    ///
    /// The mode is given as a key on the same tonic where there is a scale
    /// for it (C Mixolydian), and as its relative major where there is not
    /// (C Phrygian is A♭ major, read from its third).
    public init(root: PitchClass, in key: Key) {
        if let degree = key.degree(of: root) {
            self.init(key: key, degree: degree)
            return
        }
        let home = key.scale.intervals
        let offset = key.offset(of: root)
        // Every note is in one of them: Lydian and Locrian have all twelve
        // between them.
        let mode = Self.parallelModes
            .filter { $0.intervals.contains(offset) }
            .map { (mode: $0, changes: $0.intervals.count { !home.contains($0) }) }
            .min { $0.changes < $1.changes }!
            .mode
        let borrowed = Self.key(of: mode, on: key.root)
        self.init(key: borrowed, degree: borrowed.degree(of: root)!)
    }

    /// The modes a note outside the key is borrowed from, brightest first.
    static let parallelModes: [HeptatonicMode] = [
        .lydian, .ionian, .mixolydian, .dorian, .aeolian, .phrygian, .locrian,
    ]

    /// The key whose notes are `mode`'s on `tonic`: on that tonic where a
    /// scale has the mode's intervals, the relative major otherwise.
    private static func key(of mode: HeptatonicMode, on tonic: PitchClass) -> Key {
        if let scale = ScaleType.allCases.first(where: { $0.intervals == mode.intervals }) {
            return Key(root: tonic, scale: scale)
        }
        // The mode is the major scale read from one of its steps, so the
        // major key that far below the tonic has the same notes.
        let step = ScaleType.major.intervals.first { step in
            ScaleType.major.intervals.map { ($0 - step + 12) % 12 }.sorted() == mode.intervals
        }!
        return Key(root: PitchClass(rawValue: (tonic.rawValue - step + 12) % 12)!, scale: .major)
    }

    /// The note the chord is built on.
    public var root: PitchClass { chordRootPitchClass(key: key, degree: degree) }
}

extension Key {
    /// Semitones from the tonic up to `pitch`, within an octave.
    func offset(of pitch: PitchClass) -> Int {
        (pitch.rawValue - root.rawValue + 12) % 12
    }

    /// The degree whose chord is built on `pitch`; nil for a note outside
    /// the scale.
    public func degree(of pitch: PitchClass) -> Degree? {
        scale.intervals.firstIndex(of: offset(of: pitch)).flatMap { Degree(rawValue: $0 + 1) }
    }
}
