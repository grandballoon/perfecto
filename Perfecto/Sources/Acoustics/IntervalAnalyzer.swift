// What makes two notes sound smooth or rough together, worked out from their
// partials: the pairs of partials near enough to beat or grate, how rough
// each pair is, and the root the two notes imply.
//
// Plain Swift on plain numbers, with nothing from a platform's audio or UI,
// so it is tested by itself and can go wherever the app does.

import Foundation

/// A note as the analysis sees it: its fundamental, and how strong each of
/// its partials is, the fundamental first. Partial n is at n times the
/// fundamental (no inharmonicity).
public struct Tone: Equatable, Sendable {
    public var fundamental: Double
    public var strengths: [Double]

    public init(fundamental: Double, strengths: [Double]) {
        self.fundamental = fundamental
        self.strengths = strengths
    }

    /// `count` partials falling away as 1/n^`brightness`: 1 is a
    /// sawtooth's, more is darker, less is brighter.
    public init(fundamental: Double, partials count: Int, brightness: Double) {
        self.init(fundamental: fundamental,
                  strengths: (0..<max(count, 0)).map { 1 / pow(Double($0 + 1), brightness) })
    }

    /// The frequency of partial `number`, counted from 1.
    public func frequency(ofPartial number: Int) -> Double {
        fundamental * Double(number)
    }
}

/// A partial of the lower note and one of the upper note near enough in
/// pitch to interact: closer than a critical band.
public struct CollidingPair: Equatable, Sendable {
    /// The partials' numbers, from 1, in the lower note and the upper one.
    public let low: Int
    public let high: Int
    public let lowHz: Double
    public let highHz: Double
    public let lowStrength: Double
    public let highStrength: Double

    /// How many times a second the two beat: the difference of their pitches.
    public var beatRate: Double { abs(highHz - lowHz) }

    /// How rough the pair sounds (Plomp and Levelt's curve).
    public let roughness: Double

    /// How far apart the two are, as a share of the critical band between
    /// them: 0 is one pitch, 1 the edge of the band.
    public let separation: Double

    /// How strongly the pair is heard as two partials meeting: the weaker
    /// one's strength, the more the nearer the two are. Roughness alone
    /// passes over a pair that beats slowly, which is the very pair whose
    /// beating a consonance is heard to settle by; this does not.
    public var prominence: Double { min(lowStrength, highStrength) * (1 - separation) }

    /// The offset, in Hz, that moves the upper partial so the pair beats
    /// `rate` times a second, on the side of the lower partial it is on now
    /// (above it, if the two are one pitch).
    public func offset(toBeatAt rate: Double) -> Double {
        let side: Double = highHz < lowHz ? -1 : 1
        return lowHz + side * rate - highHz
    }

    /// How loud the two are together `seconds` after they were last in
    /// step: the envelope of the beating, from the difference of their
    /// strengths up to their sum.
    public func envelope(at seconds: Double) -> Double {
        let angle = 2 * Double.pi * beatRate * seconds
        let squared = lowStrength * lowStrength + highStrength * highStrength
            + 2 * lowStrength * highStrength * cos(angle)
        return max(squared, 0).squareRoot()
    }
}

/// The root two notes imply: the fundamental of a harmonic series both are
/// in, from the simple ratio their pitches are nearest.
public struct ImpliedRoot: Equatable, Sendable {
    /// The upper note's pitch over the lower one's, as a ratio of whole
    /// numbers in lowest terms.
    public let numerator: Int
    public let denominator: Int
    /// The root's frequency: the lower note's over the denominator.
    public let hz: Double

    public init(numerator: Int, denominator: Int, hz: Double) {
        self.numerator = numerator
        self.denominator = denominator
        self.hz = hz
    }
}

/// Everything the analysis finds of two notes.
public struct IntervalAnalysis: Equatable, Sendable {
    public let low: Tone
    public let high: Tone
    /// The pairs closer than a critical band, the roughest first: the
    /// most guilty.
    public let pairs: [CollidingPair]
    /// Every pair's roughness, added.
    public let totalRoughness: Double
    /// The root the two imply, or nil if they imply none clearly.
    public let impliedRoot: ImpliedRoot?

    /// The `count` pairs most heard as two partials meeting, the most
    /// first (`CollidingPair.prominence`): what to point the ear at.
    public func spotlight(_ count: Int) -> [CollidingPair] {
        Array(pairs.sorted { ($0.prominence, $1.roughness) > ($1.prominence, $0.roughness) }
            .prefix(max(count, 0)))
    }
}

public enum IntervalAnalyzer {

    /// The equivalent rectangular bandwidth of hearing at `hz`, in Hz
    /// (Glasberg and Moore): the critical band.
    public static func erb(_ hz: Double) -> Double {
        24.7 * (4.37 * hz / 1000 + 1)
    }

    /// How rough two sines of the given pitches and strengths sound
    /// together, by Plomp and Levelt's curve as Sethares writes it: nothing
    /// at one pitch, most at about a quarter of a critical band apart, and
    /// little again by a whole band.
    public static func roughness(_ first: Double, _ second: Double,
                                 strengths: (Double, Double)) -> Double {
        let lower = min(first, second)
        let apart = abs(first - second)
        let s = 0.24 / (0.0207 * lower + 18.96)
        return min(strengths.0, strengths.1) * (exp(-3.5 * s * apart) - exp(-5.75 * s * apart))
    }

    /// The lowest an implied root can be and still be heard as a pitch, in Hz.
    public static let lowestRoot = 20.0
    /// The most a ratio's denominator can be for its root to be clear.
    public static let largestDenominator = 16
    /// How far, in cents, two pitches may be from a simple ratio and still
    /// be heard as it: equal temperament's thirds and sixths are 14 to 16
    /// cents from theirs.
    public static let ratioTolerance = 20.0

    public static func analyze(low: Tone, high: Tone) -> IntervalAnalysis {
        var pairs: [CollidingPair] = []
        for (i, lowStrength) in low.strengths.enumerated() where lowStrength > 0 {
            let lowHz = low.frequency(ofPartial: i + 1)
            for (j, highStrength) in high.strengths.enumerated() where highStrength > 0 {
                let highHz = high.frequency(ofPartial: j + 1)
                let band = erb((lowHz + highHz) / 2)
                let apart = abs(highHz - lowHz)
                guard apart < band else { continue }
                pairs.append(CollidingPair(
                    low: i + 1, high: j + 1, lowHz: lowHz, highHz: highHz,
                    lowStrength: lowStrength, highStrength: highStrength,
                    roughness: roughness(lowHz, highHz, strengths: (lowStrength, highStrength)),
                    separation: apart / band))
            }
        }
        pairs.sort { ($0.roughness, $1.low, $1.high) > ($1.roughness, $0.low, $0.high) }
        return IntervalAnalysis(low: low, high: high, pairs: pairs,
                                totalRoughness: pairs.reduce(0) { $0 + $1.roughness },
                                impliedRoot: impliedRoot(low: low.fundamental, high: high.fundamental))
    }

    /// How rough `high` is over `low` beside a minor second over `low` in
    /// the same tone: 1 is as rough as that, the roughest interval there is
    /// in most registers. 0 if the minor second is not rough at all.
    public static func roughnessBesideMinorSecond(low: Tone, high: Tone) -> Double {
        var second = high
        second.fundamental = low.fundamental * pow(2, 1.0 / 12)
        let reference = analyze(low: low, high: second).totalRoughness
        guard reference > 0 else { return 0 }
        return analyze(low: low, high: high).totalRoughness / reference
    }

    /// The root of the simplest ratio within `ratioTolerance` of the two
    /// pitches with a denominator of no more than `largestDenominator`: the
    /// lower pitch over the denominator. nil when there is no such ratio or
    /// its root is under `lowestRoot`.
    public static func impliedRoot(low: Double, high: Double) -> ImpliedRoot? {
        let (lower, upper) = (min(low, high), max(low, high))
        guard lower > 0 else { return nil }
        guard let (numerator, denominator) = simplestRatio(near: upper / lower) else { return nil }
        let hz = lower / Double(denominator)
        return hz >= lowestRoot ? ImpliedRoot(numerator: numerator, denominator: denominator, hz: hz) : nil
    }

    /// The ratio with the smallest denominator, up to `largestDenominator`,
    /// within `ratioTolerance` cents of `ratio`. The first found for each
    /// denominator is in lowest terms, since a smaller one would have been
    /// found first.
    static func simplestRatio(near ratio: Double) -> (Int, Int)? {
        for denominator in 1...largestDenominator {
            let numerator = (ratio * Double(denominator)).rounded()
            guard numerator > 0 else { continue }
            let cents = 1200 * log2(numerator / Double(denominator) / ratio)
            if abs(cents) <= ratioTolerance { return (Int(numerator), denominator) }
        }
        return nil
    }
}
