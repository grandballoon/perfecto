// The step compass: the colors one step from the chord sounding (a tone
// added, taken away, or moved a semitone; `colorSteps`), by kind of step,
// each kind in an order. Its places are the kinds and their first and
// second choices, so a place means the same before a chord is struck as
// after; what it plays is worked out from the chord (docs/chord-dependent-coloration.md).

/// A kind of step from a chord.
public enum ColorStepKind: CaseIterable, Hashable, Codable, Sendable {
    /// A tone it has not got.
    case add
    /// One of its tones a semitone up.
    case raise
    /// One of its tones a semitone down.
    case lower
    /// One of its tones, not the root, left out.
    case takeAway
}

/// A place on the compass: a kind of step and which of its choices, 1 the
/// first (the near place) and 2 the second (the far one).
public struct CompassPlace: Hashable, Codable, Sendable {
    public let kind: ColorStepKind
    public let rank: Int

    public init(_ kind: ColorStepKind, _ rank: Int) {
        precondition(StepCompass.ranks.contains(rank), "the compass has a first and a second choice")
        self.kind = kind
        self.rank = rank
    }

    /// Every place, each kind's first choice before its second.
    public static let all: [CompassPlace] = ColorStepKind.allCases.flatMap { kind in
        StepCompass.ranks.map { CompassPlace(kind, $0) }
    }
}

/// How well a step's chord fits the key, best first.
public enum ColorFit: Int, Comparable, Sendable {
    /// Every tone in the key, and none a semitone over another tone.
    case inKey = 1
    /// In the key, but the tone added or moved is a semitone over a tone of
    /// the chord: the minor 9th that jazz calls an avoid note (C add11).
    case avoid
    /// A tone from outside the key: borrowed (C minor on I in C major).
    case borrowed

    public static func < (a: ColorFit, b: ColorFit) -> Bool { a.rawValue < b.rawValue }
}

/// The order each kind's choices are in.
public enum ColorStepRanking: CaseIterable, Hashable, Codable, Sendable {
    /// In the key first; then, of adds, the degree's own next stack tone
    /// (its 7th, 9th, 13th, 11th); of moves, the 3rd before the 5th; of
    /// tones taken away, the 5th before the 3rd.
    case theory
    /// By how often the chord is played, the commonest first (7, maj7, min7,
    /// sus4, sus2, add9, 6 …), whether or not it is in the key; then as theory.
    case common
}

/// One step from a chord: its kind, the chord it makes, the tone it takes
/// from (moved or taken away) and to (added or moved), and how the chord fits.
public struct ColorStep: Hashable, Sendable {
    public let kind: ColorStepKind
    public let tones: ChordTones
    public let from: Int?
    public let to: Int?
    public let fit: ColorFit

    /// What the step does, by the tones' names above the root: "+♭7", "3→4", "−5".
    public var editName: String {
        let names = ["1", "♭2", "2", "♭3", "3", "4", "♭5", "5", "♭6", "6", "♭7", "7"]
        switch kind {
        case .add:      return "+" + names[to!]
        case .takeAway: return "−" + names[from!]
        case .raise, .lower:
            return names[from!] + "→" + (kind == .raise && from == 7 ? "♯5" : names[to!])
        }
    }
}

public enum StepCompass {
    /// A kind's choices on the compass.
    public static let ranks = 1...2

    /// The chord `degree` plays in `key` before it is colored: its triad.
    public static func base(key: Key, degree: Degree) -> ChordTones {
        ChordTones(chordShape(key: key, spec: ChordSpec(degree: degree, color: .base)).intervals)
    }

    /// Every step from `tones` on `degree` in `key`, by kind, each kind in
    /// `ranking`'s order.
    public static func steps(from tones: ChordTones, key: Key, degree: Degree,
                             ranking: ColorStepRanking) -> [ColorStepKind: [ColorStep]] {
        let root = key.scale.offset(of: degree)
        let own = ChordGrid.ownMode(key: key, degree: degree).intervals
        let all = neighbours(of: tones, inKey: { key.scale.intervals.contains((root + $0) % 12) })
        var byKind = Dictionary(grouping: all, by: \.kind)
        for kind in ColorStepKind.allCases {
            byKind[kind] = (byKind[kind] ?? []).sorted { precedes($0, $1, own: own, ranking: ranking) }
        }
        return byKind
    }

    /// The step at `place` from `tones`, or nil if its kind has no choice
    /// that far down (a chord of two notes has nothing to take away).
    public static func step(at place: CompassPlace, from tones: ChordTones, key: Key, degree: Degree,
                            ranking: ColorStepRanking) -> ColorStep? {
        let choices = steps(from: tones, key: key, degree: degree, ranking: ranking)[place.kind] ?? []
        return choices.indices.contains(place.rank - 1) ? choices[place.rank - 1] : nil
    }

    /// The chord a walk of places makes from `degree`'s triad: each place a
    /// step from where the last one led, a place with no choice left out.
    /// The walk is of places, not chords, so the same walk on another degree
    /// is that degree's own (two adds are G9 on V and Dm9 on ii).
    public static func walk(_ places: [CompassPlace], key: Key, degree: Degree,
                            ranking: ColorStepRanking) -> ChordTones {
        places.reduce(base(key: key, degree: degree)) { tones, place in
            step(at: place, from: tones, key: key, degree: degree, ranking: ranking)?.tones ?? tones
        }
    }

    // MARK: – The neighbourhood

    private static func neighbours(of tones: ChordTones, inKey: (Int) -> Bool) -> [ColorStep] {
        let have = tones.pitchClasses
        func step(_ kind: ColorStepKind, _ next: [Int], from: Int?, to: Int?) -> ColorStep {
            let made = ChordTones(next)
            let fit: ColorFit
            if !made.pitchClasses.allSatisfy(inKey) { fit = .borrowed }
            else if let to, made.has((to + 11) % 12) { fit = .avoid }
            else { fit = .inKey }
            return ColorStep(kind: kind, tones: made, from: from, to: to, fit: fit)
        }
        var out: [ColorStep] = []
        for added in 1..<12 where !tones.has(added) {
            out.append(step(.add, have + [added], from: nil, to: added))
        }
        // A chord keeps two notes at least.
        if have.count > 2 {
            for tone in have where tone != 0 {
                out.append(step(.takeAway, have.filter { $0 != tone }, from: tone, to: nil))
            }
        }
        for tone in have where tone != 0 {
            for offset in [1, -1] {
                let moved = (tone + offset + 12) % 12
                guard moved != 0, !tones.has(moved) else { continue }
                out.append(step(offset > 0 ? .raise : .lower, have.filter { $0 != tone } + [moved],
                                from: tone, to: moved))
            }
        }
        return out
    }

    // MARK: – The order

    /// The commonest chord qualities, most played first: the joystick's
    /// staples, then the 9ths and the jazz colors.
    private static let common = [
        "maj", "min", "7", "maj7", "min7", "sus4", "sus2", "add9", "6", "min6", "min add9", "dim",
        "aug", "min7♭5", "5", "9", "min9", "maj9", "7sus4", "6/9", "min6/9", "dim7", "min(maj7)",
        "7♭9", "7♯9", "add11", "min add11",
    ]

    private static func precedes(_ a: ColorStep, _ b: ColorStep, own: [Int], ranking: ColorStepRanking) -> Bool {
        let ka = key(a, own: own, ranking: ranking), kb = key(b, own: own, ranking: ranking)
        return ka.lexicographicallyPrecedes(kb)
    }

    private static func key(_ step: ColorStep, own: [Int], ranking: ColorStepRanking) -> [Int] {
        let theory = [step.fit.rawValue, order(of: step, own: own), step.from ?? step.to ?? 0]
        switch ranking {
        case .theory: return theory
        case .common:
            let quality = step.tones.slash == nil ? step.tones.name : "slash"
            return [common.firstIndex(of: quality) ?? common.count] + theory
        }
    }

    /// Where a step comes within its kind by theory, before its fit is
    /// counted: the degree's own stack tones in the order they are added
    /// (7th, 9th, 13th, 11th) before other adds; the 3rd moved before the
    /// 5th, the 7th and a tension; the 5th taken away before a tension, the
    /// 7th and the 3rd.
    private static func order(of step: ColorStep, own: [Int]) -> Int {
        func role(_ tone: Int) -> Int {
            switch tone {
            case 3, 4:    return 0   // the 3rd
            case 6...8:   return 1   // the 5th
            case 9...11:  return 2   // the 7th (or a 6th)
            default:      return 3   // a tension, or a suspension
            }
        }
        switch step.kind {
        case .add:
            let stack = [own[6], own[1], own[5], own[3]]
            return stack.firstIndex(of: step.to!) ?? 10 + step.to!
        case .raise, .lower:
            return role(step.from!)
        case .takeAway:
            return [3, 0, 2, 1][role(step.from!)]
        }
    }
}
