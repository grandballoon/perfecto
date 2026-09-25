// The modes the chord grid's rows stack thirds through: every mode of the
// major, melodic minor and harmonic minor scales. Every seven-note scale the
// app offers is one of these read from some degree, so a degree's own
// diatonic mode is always in the catalog.

/// A seven-note mode, named by the scale it is a rotation of.
public enum HeptatonicMode: CaseIterable, Hashable, Codable, Sendable {
    // Modes of the major scale
    case ionian, dorian, phrygian, lydian, mixolydian, aeolian, locrian
    // Modes of melodic minor
    case melodicMinor, dorianFlat2, lydianAugmented, lydianDominant,
         mixolydianFlat6, locrianNatural2, altered
    // Modes of harmonic minor
    case harmonicMinor, locrianNatural6, ionianSharp5, dorianSharp4,
         phrygianDominant, lydianSharp2, ultralocrian

    public var displayName: String {
        switch self {
        case .ionian:           return "Ionian"
        case .dorian:           return "Dorian"
        case .phrygian:         return "Phrygian"
        case .lydian:           return "Lydian"
        case .mixolydian:       return "Mixolydian"
        case .aeolian:          return "Aeolian"
        case .locrian:          return "Locrian"
        case .melodicMinor:     return "Melodic Minor"
        case .dorianFlat2:      return "Dorian ♭2"
        case .lydianAugmented:  return "Lydian Augmented"
        case .lydianDominant:   return "Lydian Dominant"
        case .mixolydianFlat6:  return "Mixolydian ♭6"
        case .locrianNatural2:  return "Locrian ♮2"
        case .altered:          return "Altered"
        case .harmonicMinor:    return "Harmonic Minor"
        case .locrianNatural6:  return "Locrian ♮6"
        case .ionianSharp5:     return "Ionian ♯5"
        case .dorianSharp4:     return "Dorian ♯4"
        case .phrygianDominant: return "Phrygian Dominant"
        case .lydianSharp2:     return "Lydian ♯2"
        case .ultralocrian:     return "Ultralocrian"
        }
    }

    /// The parent scale and the step it is read from.
    private var rotation: (parent: ScaleType, step: Int) {
        switch self {
        case .ionian:           return (.major, 0)
        case .dorian:           return (.major, 1)
        case .phrygian:         return (.major, 2)
        case .lydian:           return (.major, 3)
        case .mixolydian:       return (.major, 4)
        case .aeolian:          return (.major, 5)
        case .locrian:          return (.major, 6)
        case .melodicMinor:     return (.melodicMinor, 0)
        case .dorianFlat2:      return (.melodicMinor, 1)
        case .lydianAugmented:  return (.melodicMinor, 2)
        case .lydianDominant:   return (.melodicMinor, 3)
        case .mixolydianFlat6:  return (.melodicMinor, 4)
        case .locrianNatural2:  return (.melodicMinor, 5)
        case .altered:          return (.melodicMinor, 6)
        case .harmonicMinor:    return (.harmonicMinor, 0)
        case .locrianNatural6:  return (.harmonicMinor, 1)
        case .ionianSharp5:     return (.harmonicMinor, 2)
        case .dorianSharp4:     return (.harmonicMinor, 3)
        case .phrygianDominant: return (.harmonicMinor, 4)
        case .lydianSharp2:     return (.harmonicMinor, 5)
        case .ultralocrian:     return (.harmonicMinor, 6)
        }
    }

    /// Seven ascending semitone offsets from 0. Lydian → `[0, 2, 4, 6, 7, 9, 11]`.
    public var intervals: [Int] {
        let (parent, step) = rotation
        let root = parent.semitones(atStep: step)
        return (0..<7).map { parent.semitones(atStep: step + $0) - root }
    }

    /// The mode with exactly these seven intervals, if it is in the catalog.
    public init?(intervals: [Int]) {
        guard let mode = Self.allCases.first(where: { $0.intervals == intervals }) else { return nil }
        self = mode
    }

    /// `degree`'s own mode in `key` (C major ii → Dorian); nil for scales
    /// without seven notes.
    public init?(key: Key, degree: Degree) {
        guard let intervals = diatonicMode(key: key, degree: degree) else { return nil }
        self.init(intervals: intervals)
    }

    // MARK: – Brightness

    /// Every mode from brightest to darkest: the grid's rows, top to bottom.
    ///
    /// Brightness is the sum of the intervals, so each raised note brightens
    /// by one: along the major modes this is the familiar Lydian → Locrian
    /// order. Several modes share each sum; within a sum, each next row is the
    /// mode that changes the fewest notes from the row above (ties go to the
    /// higher intervals, the brighter-sounding low notes). Sorting ties by
    /// intervals alone would put some neighbours three notes apart; this way
    /// every step down the grid moves one or two notes (HeptatonicModeTests).
    public static let byBrightness: [HeptatonicMode] = {
        func brightness(_ m: HeptatonicMode) -> Int { m.intervals.reduce(0, +) }
        func changes(_ a: HeptatonicMode, _ b: HeptatonicMode) -> Int {
            zip(a.intervals, b.intervals).filter { $0 != $1 }.count
        }
        func higher(_ a: HeptatonicMode, _ b: HeptatonicMode) -> Bool {
            b.intervals.lexicographicallyPrecedes(a.intervals)
        }
        let levels = Set(allCases.map(brightness)).sorted(by: >)
        var order: [HeptatonicMode] = []
        for level in levels {
            var remaining = allCases.filter { brightness($0) == level }
            while !remaining.isEmpty {
                let next = remaining.min { a, b in
                    guard let above = order.last else { return higher(a, b) }
                    let (ca, cb) = (changes(above, a), changes(above, b))
                    return ca != cb ? ca < cb : higher(a, b)
                }!
                order.append(next)
                remaining.removeAll { $0 == next }
            }
        }
        return order
    }()

    /// `count` consecutive rows of `byBrightness` centred on `center`, shifted
    /// inward at the brightest and darkest ends so there are always `count`.
    public static func rows(around center: HeptatonicMode, count: Int) -> [HeptatonicMode] {
        let all = byBrightness
        precondition((1...all.count).contains(count), "row count out of range")
        let middle = all.firstIndex(of: center)!
        let start = min(max(middle - count / 2, 0), all.count - count)
        return Array(all[start ..< start + count])
    }
}
