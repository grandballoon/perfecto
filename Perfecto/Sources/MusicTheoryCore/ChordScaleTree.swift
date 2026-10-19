// The chord–scale tree: from a chord, every chord of every scale it is the
// home chord of, and from each of those the same again, as far as anyone
// likes. The scales are the 21 modes of the major, harmonic minor and
// melodic minor scales, and a chord is the home chord of a mode when
// stacking thirds from the mode's first note makes it.

/// How many thirds the tree's chords stack: triads, or seventh chords.
public enum ChordSize: CaseIterable, Hashable, Sendable {
    case triads, sevenths

    /// The chord's tones, counted in thirds from the root.
    var tones: Int { self == .triads ? 3 : 4 }

    public var displayName: String { self == .triads ? "Triads" : "Sevenths" }
}

/// The four families chords are colored by: a seventh chord is in its
/// triad's.
public enum QualityGroup: CaseIterable, Hashable, Sendable {
    case major, minor, diminished, augmented
}

/// A chord stacked in thirds, as the tree names it.
public enum ChordQuality: CaseIterable, Hashable, Sendable {
    case major, minor, diminished, augmented
    case major7, dominant7, minor7, minorMajor7, halfDiminished7, diminished7, augmentedMajor7, augmented7

    /// The tones as semitones above the root, from 0.
    public var intervals: [Int] {
        switch self {
        case .major:           return [0, 4, 7]
        case .minor:           return [0, 3, 7]
        case .diminished:      return [0, 3, 6]
        case .augmented:       return [0, 4, 8]
        case .major7:          return [0, 4, 7, 11]
        case .dominant7:       return [0, 4, 7, 10]
        case .minor7:          return [0, 3, 7, 10]
        case .minorMajor7:     return [0, 3, 7, 11]
        case .halfDiminished7: return [0, 3, 6, 10]
        case .diminished7:     return [0, 3, 6, 9]
        case .augmentedMajor7: return [0, 4, 8, 11]
        case .augmented7:      return [0, 4, 8, 10]
        }
    }

    /// What follows the root's name: "" (C), "m" (Cm), "ø7" (Cø7).
    public var symbol: String {
        switch self {
        case .major:           return ""
        case .minor:           return "m"
        case .diminished:      return "°"
        case .augmented:       return "+"
        case .major7:          return "maj7"
        case .dominant7:       return "7"
        case .minor7:          return "m7"
        case .minorMajor7:     return "m(maj7)"
        case .halfDiminished7: return "ø7"
        case .diminished7:     return "°7"
        case .augmentedMajor7: return "+maj7"
        case .augmented7:      return "+7"
        }
    }

    public var displayName: String {
        switch self {
        case .major:           return "Major triad"
        case .minor:           return "Minor triad"
        case .diminished:      return "Diminished triad"
        case .augmented:       return "Augmented triad"
        case .major7:          return "Major seventh"
        case .dominant7:       return "Dominant seventh"
        case .minor7:          return "Minor seventh"
        case .minorMajor7:     return "Minor-major seventh"
        case .halfDiminished7: return "Half-diminished seventh"
        case .diminished7:     return "Diminished seventh"
        case .augmentedMajor7: return "Augmented major seventh"
        case .augmented7:      return "Augmented seventh"
        }
    }

    public var group: QualityGroup {
        switch self {
        case .major, .major7, .dominant7:                       return .major
        case .minor, .minor7, .minorMajor7:                     return .minor
        case .diminished, .halfDiminished7, .diminished7:       return .diminished
        case .augmented, .augmentedMajor7, .augmented7:         return .augmented
        }
    }

    public var size: ChordSize { intervals.count == 3 ? .triads : .sevenths }

    /// What follows a Roman numeral on this chord: the case of the numeral
    /// already says major or minor, so a minor seventh is "ii7".
    var numeralSuffix: String {
        switch self {
        case .major, .minor:   return ""
        case .minor7:          return "7"
        case .minorMajor7:     return "(maj7)"
        default:               return symbol
        }
    }

    /// The quality with these tones, if the tree has one.
    public init?(intervals: [Int]) {
        guard let quality = Self.allCases.first(where: { $0.intervals == intervals }) else { return nil }
        self = quality
    }

    /// The qualities of `size`, in the order they are offered.
    public static func all(_ size: ChordSize) -> [ChordQuality] {
        allCases.filter { $0.size == size }
    }

    /// The modes whose home chord this is, family by family (`ScaleFamily.allModes`).
    /// None, for a chord that is no mode's (+7).
    public var hosts: [HeptatonicMode] {
        ScaleFamily.allModes.filter { $0.chord(onDegree: 0, size: size) == self }
    }

    /// The chord's tones written from `root`, a letter for each third.
    public func spelled(from root: NoteName) -> [NoteName] {
        intervals.enumerated().map { root.spelled($0.element, letters: 2 * $0.offset) }
    }
}

extension HeptatonicMode {
    /// The chord stacked in thirds on `degree` (0...6) of the mode. Every
    /// mode's chords are in the tree's table (ChordScaleTreeTests).
    public func chord(onDegree degree: Int, size: ChordSize) -> ChordQuality {
        let tones = (0..<size.tones).map { ((intervals[(degree + 2 * $0) % 7] - intervals[degree]) % 12 + 12) % 12 }
        guard let quality = ChordQuality(intervals: tones) else {
            preconditionFailure("\(displayName) has a chord the tree does not name on degree \(degree)")
        }
        return quality
    }

    /// The Roman numeral of the chord on `degree` (0...6): upper case for
    /// a major or augmented chord, lower for a minor or diminished one,
    /// flattened or sharpened by how far the degree is from the major
    /// scale's, and marked with what the chord adds to its case ("♭III+",
    /// "viiø7").
    public func numeral(ofDegree degree: Int, size: ChordSize) -> String {
        let quality = chord(onDegree: degree, size: size)
        let numerals = ["I", "II", "III", "IV", "V", "VI", "VII"]
        let numeral = [.minor, .diminished].contains(quality.group)
            ? numerals[degree].lowercased() : numerals[degree]
        let marks = [-2: "𝄫", -1: "♭", 0: "", 1: "♯", 2: "𝄪"]
        let shift = intervals[degree] - ScaleType.major.intervals[degree]
        return (marks[shift] ?? "") + numeral + quality.numeralSuffix
    }

    /// The mode's notes written from `root`, a letter for each.
    public func spelled(from root: NoteName) -> [NoteName] {
        intervals.enumerated().map { root.spelled($0.element, letters: $0.offset) }
    }
}

/// A chord the tree is at or can go to: a quality on a written root.
public struct TreeChord: Hashable, Sendable {
    public let root: NoteName
    public let quality: ChordQuality

    public init(root: NoteName, quality: ChordQuality) {
        self.root = root
        self.quality = quality
    }

    /// "C", "Dm7", "G♯°".
    public var label: String { root.name + quality.symbol }

    /// The notes, written.
    public var tones: [NoteName] { quality.spelled(from: root) }

    /// The scales it is the home chord of, on its root.
    public var scales: [HeptatonicMode] { quality.hosts }

    /// Where it can go: every chord of its scales but itself, each once,
    /// by how many letters its root is above this one's (the first branch
    /// is a letter up, the second's two, to the sixth's six), and within a
    /// branch from the lowest root to the highest. A root written with two
    /// sharps or flats is respelled before its scales are written
    /// (`NoteName.asRoot`), so the sharps and flats do not pile up along
    /// the way.
    public var next: [[TreeStep]] {
        let root = root.asRoot
        var branches = Array(repeating: [TreeStep](), count: 6)
        for mode in scales {
            let notes = mode.spelled(from: root)
            for degree in 1..<7 {
                let chord = TreeChord(root: notes[degree], quality: mode.chord(onDegree: degree, size: quality.size))
                if let index = branches[degree - 1].firstIndex(where: { $0.chord == chord }) {
                    branches[degree - 1][index].scales.append(mode)
                } else {
                    branches[degree - 1].append(TreeStep(chord: chord, numeral: mode.numeral(ofDegree: degree,
                                                                                         size: quality.size),
                                                         scales: [mode]))
                }
            }
        }
        let order = ChordQuality.allCases
        return branches.map { steps in
            steps.sorted {
                ($0.chord.root.accidental, order.firstIndex(of: $0.chord.quality)!)
                    < ($1.chord.root.accidental, order.firstIndex(of: $1.chord.quality)!)
            }
        }
    }

    /// The chord on the same root with chords of `size`: the first of its
    /// group (`QualityGroup`). A major triad is a major seventh, and a
    /// dominant seventh a major triad.
    public func resized(to size: ChordSize) -> TreeChord {
        guard size != quality.size else { return self }
        return TreeChord(root: root, quality: ChordQuality.all(size).first { $0.group == quality.group }!)
    }

    /// The chord on the tonic of `key`, of `size`: where the tree starts.
    public static func home(of key: Key, size: ChordSize) -> TreeChord {
        let root = NoteName.roots[key.root.rawValue]
        guard let mode = HeptatonicMode(key: key, degree: .I) else {
            return TreeChord(root: root, quality: size == .triads ? .major : .major7)
        }
        return TreeChord(root: root, quality: mode.chord(onDegree: 0, size: size))
    }
}

/// One way on from a chord: a chord of one or more of its scales.
public struct TreeStep: Hashable, Sendable {
    public let chord: TreeChord
    /// Its Roman numeral, the chord it is from being I.
    public let numeral: String
    /// The scales of the chord it is from that have it, in
    /// `ScaleFamily.allModes`' order.
    public internal(set) var scales: [HeptatonicMode]
}
