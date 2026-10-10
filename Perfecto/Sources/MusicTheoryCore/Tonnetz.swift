// The Tonnetz: the twelve notes laid out so that a step along one line is a
// perfect fifth, along another a major third, and along the third a minor
// third. Every triangle of three neighbouring notes is then a major or a
// minor triad, and two triangles that share a side are two triads that share
// two notes: the neo-Riemannian moves P, L and R.
//
// Everything here is worked out from where a triangle is, so a move on a
// triad and a flip of its triangle cannot disagree (the tests hold them to it).

/// A major or a minor triad on a root, in no key.
public struct Triad: Hashable, Sendable {
    public enum Quality: Hashable, Sendable {
        case major, minor
    }

    public let root: PitchClass
    public let quality: Quality

    public init(root: PitchClass, quality: Quality) {
        self.root = root
        self.quality = quality
    }

    public var third: PitchClass { root.raised(by: quality == .major ? 4 : 3) }
    public var fifth: PitchClass { root.raised(by: 7) }

    /// Root, third, fifth.
    public var pitchClasses: [PitchClass] { [root, third, fifth] }

    /// "C" for C major, "Am" for A minor.
    public var name: String { root.name + (quality == .major ? "" : "m") }

    /// The triad `move` leads to. Every move is its own inverse.
    public func applying(_ move: TonnetzMove) -> Triad {
        switch (move, quality) {
        case (.parallel, .major): return Triad(root: root, quality: .minor)
        case (.parallel, .minor): return Triad(root: root, quality: .major)
        case (.relative, .major): return Triad(root: root.raised(by: 9), quality: .minor)
        case (.relative, .minor): return Triad(root: root.raised(by: 3), quality: .major)
        case (.leading, .major):  return Triad(root: root.raised(by: 4), quality: .minor)
        case (.leading, .minor):  return Triad(root: root.raised(by: 8), quality: .major)
        }
    }
}

extension Triad {
    /// The triad whose three notes are exactly `pitchClasses`; nil if they
    /// are not a major or a minor triad.
    public init?(_ pitchClasses: Set<PitchClass>) {
        let triads = pitchClasses.flatMap { [Triad(root: $0, quality: .major), Triad(root: $0, quality: .minor)] }
        guard let triad = triads.first(where: { Set($0.pitchClasses) == pitchClasses }) else { return nil }
        self = triad
    }
}

/// What MIDI `notes` played from the net are called: the triad they make,
/// if they make one ("Am"), and otherwise the notes themselves, low to high
/// ("C G D").
public func netLabel(of notes: [Int]) -> String {
    let pitchClasses = notes.sorted().compactMap { PitchClass(rawValue: ($0 % 12 + 12) % 12) }
    if let triad = Triad(Set(pitchClasses)) { return triad.name }
    var named: [PitchClass] = []
    for pitchClass in pitchClasses where !named.contains(pitchClass) { named.append(pitchClass) }
    return named.map(\.name).joined(separator: " ")
}

/// A move from a triad to the one that shares two of its notes; the third
/// note moves by a step.
public enum TonnetzMove: String, CaseIterable, Hashable, Codable, Sendable {
    /// Keeps the root and the fifth: C major to C minor.
    case parallel
    /// Keeps the notes of the minor third: C major to E minor.
    case leading
    /// Keeps the notes of the major third: C major to A minor.
    case relative

    public var symbol: String {
        switch self {
        case .parallel: return "P"
        case .leading:  return "L"
        case .relative: return "R"
        }
    }

    public var displayName: String {
        switch self {
        case .parallel: return "Parallel"
        case .leading:  return "Leading tone"
        case .relative: return "Relative"
        }
    }
}

/// A note's place on the net: so many perfect fifths along one line and so
/// many major thirds along the next. The net repeats, so a note has many
/// places.
public struct TonnetzPoint: Hashable, Sendable {
    public let fifths: Int
    public let thirds: Int

    public init(fifths: Int, thirds: Int) {
        self.fifths = fifths
        self.thirds = thirds
    }

    /// C is at the origin.
    public var pitchClass: PitchClass {
        PitchClass.C.raised(by: 7 * fifths + 4 * thirds)
    }

    func moved(fifths: Int = 0, thirds: Int = 0) -> TonnetzPoint {
        TonnetzPoint(fifths: self.fifths + fifths, thirds: self.thirds + thirds)
    }
}

/// One triangle of the net, which is one triad at one of its places. The
/// rhombus of four notes at `corner` holds two: the one that points up
/// (drawn with the major third upward) is a major triad on `corner`, and
/// the one that points down is the minor triad a major third above.
public struct TonnetzCell: Hashable, Sendable {
    public let corner: TonnetzPoint
    public let pointsUp: Bool

    public init(corner: TonnetzPoint, pointsUp: Bool) {
        self.corner = corner
        self.pointsUp = pointsUp
    }

    /// C major, at the origin.
    public static let home = TonnetzCell(corner: TonnetzPoint(fifths: 0, thirds: 0), pointsUp: true)

    public var root: TonnetzPoint { pointsUp ? corner : corner.moved(thirds: 1) }
    public var third: TonnetzPoint { pointsUp ? corner.moved(thirds: 1) : corner.moved(fifths: 1) }
    public var fifth: TonnetzPoint { pointsUp ? corner.moved(fifths: 1) : corner.moved(fifths: 1, thirds: 1) }

    /// Root, third, fifth.
    public var points: [TonnetzPoint] { [root, third, fifth] }

    public var triad: Triad {
        Triad(root: root.pitchClass, quality: pointsUp ? .major : .minor)
    }

    /// The two notes `move` keeps: the side the triangle is flipped over.
    public func kept(by move: TonnetzMove) -> [TonnetzPoint] {
        switch (move, pointsUp) {
        case (.parallel, _):                       return [root, fifth]
        case (.leading, true), (.relative, false): return [third, fifth]
        case (.relative, true), (.leading, false): return [root, third]
        }
    }

    /// The triangle on the other side of the side `move` keeps.
    public func flipped(_ move: TonnetzMove) -> TonnetzCell {
        switch (move, pointsUp) {
        case (.parallel, true):  return TonnetzCell(corner: corner.moved(thirds: -1), pointsUp: false)
        case (.parallel, false): return TonnetzCell(corner: corner.moved(thirds: 1), pointsUp: true)
        case (.leading, _):      return TonnetzCell(corner: corner, pointsUp: !pointsUp)
        case (.relative, true):  return TonnetzCell(corner: corner.moved(fifths: -1), pointsUp: false)
        case (.relative, false): return TonnetzCell(corner: corner.moved(fifths: 1), pointsUp: true)
        }
    }
}

extension PitchClass {
    /// The pitch class `semitones` above this one (below, if negative).
    func raised(by semitones: Int) -> PitchClass {
        PitchClass(rawValue: ((rawValue + semitones) % 12 + 12) % 12)!
    }
}
