// The intervals within an octave, by the semitones they span, with what each
// is called and the simple ratio of frequencies it is nearest in just
// intonation.

/// A ratio of two whole numbers, in lowest terms: a frequency ratio of just
/// intonation, the upper note's frequency over the lower one's.
public struct Ratio: Hashable, Sendable, CustomStringConvertible {
    public let numerator: Int
    public let denominator: Int

    public init(_ numerator: Int, _ denominator: Int) {
        precondition(numerator > 0 && denominator > 0, "a frequency ratio is positive")
        let divisor = Self.gcd(numerator, denominator)
        self.numerator = numerator / divisor
        self.denominator = denominator / divisor
    }

    public var description: String { "\(numerator)/\(denominator)" }

    private static func gcd(_ a: Int, _ b: Int) -> Int {
        b == 0 ? a : gcd(b, a % b)
    }
}

/// An interval of no more than an octave, by the semitones it spans.
public enum Interval: Int, CaseIterable, Hashable, Sendable {
    case unison = 0
    case minorSecond, majorSecond, minorThird, majorThird, perfectFourth, tritone
    case perfectFifth, minorSixth, majorSixth, minorSeventh, majorSeventh, octave

    public var semitones: Int { rawValue }

    /// The interval from `low` up to `high`, two MIDI notes, brought within
    /// an octave: a tenth is a third, and any number of octaves an octave.
    /// Two notes of one pitch are a unison.
    public init(from low: Int, to high: Int) {
        let span = abs(high - low)
        self = span == 0 ? .unison : Interval(rawValue: (span - 1) % 12 + 1)!
    }

    public var name: String {
        switch self {
        case .unison:        return "Unison"
        case .minorSecond:   return "Minor 2nd"
        case .majorSecond:   return "Major 2nd"
        case .minorThird:    return "Minor 3rd"
        case .majorThird:    return "Major 3rd"
        case .perfectFourth: return "Perfect 4th"
        case .tritone:       return "Tritone"
        case .perfectFifth:  return "Perfect 5th"
        case .minorSixth:    return "Minor 6th"
        case .majorSixth:    return "Major 6th"
        case .minorSeventh:  return "Minor 7th"
        case .majorSeventh:  return "Major 7th"
        case .octave:        return "Octave"
        }
    }

    public var shortName: String {
        switch self {
        case .unison:        return "P1"
        case .minorSecond:   return "m2"
        case .majorSecond:   return "M2"
        case .minorThird:    return "m3"
        case .majorThird:    return "M3"
        case .perfectFourth: return "P4"
        case .tritone:       return "TT"
        case .perfectFifth:  return "P5"
        case .minorSixth:    return "m6"
        case .majorSixth:    return "M6"
        case .minorSeventh:  return "m7"
        case .majorSeventh:  return "M7"
        case .octave:        return "P8"
        }
    }

    /// The simple ratio just intonation tunes it to.
    public var justRatio: Ratio {
        switch self {
        case .unison:        return Ratio(1, 1)
        case .minorSecond:   return Ratio(16, 15)
        case .majorSecond:   return Ratio(9, 8)
        case .minorThird:    return Ratio(6, 5)
        case .majorThird:    return Ratio(5, 4)
        case .perfectFourth: return Ratio(4, 3)
        case .tritone:       return Ratio(45, 32)
        case .perfectFifth:  return Ratio(3, 2)
        case .minorSixth:    return Ratio(8, 5)
        case .majorSixth:    return Ratio(5, 3)
        case .minorSeventh:  return Ratio(16, 9)
        case .majorSeventh:  return Ratio(15, 8)
        case .octave:        return Ratio(2, 1)
        }
    }

    /// Whether common practice counts it consonant: the unison, the
    /// octave, the perfect fourth and fifth, and the thirds and sixths.
    public var isConsonant: Bool {
        switch self {
        case .unison, .minorThird, .majorThird, .perfectFourth, .perfectFifth,
             .minorSixth, .majorSixth, .octave:
            return true
        case .minorSecond, .majorSecond, .tritone, .minorSeventh, .majorSeventh:
            return false
        }
    }
}
