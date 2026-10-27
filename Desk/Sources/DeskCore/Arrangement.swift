import MusicTheoryCore

// What the arranger writes: chords placed in time, each with its own start
// and length in beats, and silence between them where nothing is placed. A
// value with its edits, so the arranger only decides when to make them.

/// The grid times are snapped to, or none.
public enum BeatGrid: String, CaseIterable, Codable, Sendable {
    case free, sixteenth, eighth, quarter, half

    /// Beats from one line of the grid to the next; nil with no grid.
    public var step: Double? {
        switch self {
        case .free: nil
        case .sixteenth: 0.25
        case .eighth: 0.5
        case .quarter: 1
        case .half: 2
        }
    }

    public var name: String {
        switch self {
        case .free: "Free"
        case .sixteenth: "1/16"
        case .eighth: "1/8"
        case .quarter: "1/4"
        case .half: "1/2"
        }
    }

    /// The shortest a chord can be: a line of the grid, or with none a
    /// thirty-second note.
    public var shortest: Double { step ?? 0.125 }

    /// How far the cursor moves at a step: a line of the grid, or with none
    /// a sixteenth.
    public var move: Double { step ?? 0.25 }

    /// `beats` on the nearest line of the grid.
    public func nearest(_ beats: Double) -> Double {
        guard let step else { return beats }
        return (beats / step).rounded() * step
    }

    /// A length on the grid at least `beats` long (but for a hair under a
    /// line, which a finger let go of a moment early means as that line),
    /// and never shorter than `shortest`.
    public func length(_ beats: Double) -> Double {
        guard let step else { return max(shortest, beats) }
        return max(step, ((beats - step * 0.15) / step).rounded(.up) * step)
    }
}

/// A chord placed in time.
public struct Placed: Hashable, Sendable {
    /// In beats from the start of the arrangement.
    public let start: Double
    public let length: Double
    public let chord: DeskChord

    public init(start: Double, length: Double, chord: DeskChord) {
        self.start = start
        self.length = length
        self.chord = chord
    }

    public var end: Double { start + length }

    public func covers(_ beats: Double) -> Bool { start <= beats && beats < end }
}

/// Chords placed in a loop of bars: never two at once, so one line plays them.
public struct Arrangement: Equatable, Sendable {
    public static let beatsPerBar = 4
    public static let bars = 4
    public static let length = Double(beatsPerBar * bars)

    /// In order of their starts, none overlapping, all within the loop.
    public private(set) var chords: [Placed] = []

    public init(_ chords: [Placed] = []) {
        for chord in chords { place(chord.chord, at: chord.start, length: chord.length) }
    }

    public var isEmpty: Bool { chords.isEmpty }

    /// Places `chord` from `start` for `length` beats, ending at the loop's
    /// end at the latest. What was there gives way: a chord that started
    /// before it ends where it starts, and one that starts under it is gone.
    public mutating func place(_ chord: DeskChord, at start: Double, length: Double) {
        let start = max(0, min(start, Self.length))
        let end = min(Self.length, start + length)
        guard end > start else { return }
        chords = chords.compactMap { placed in
            if placed.start >= start && placed.start < end { return nil }
            if placed.start < start && placed.end > start {
                return Placed(start: placed.start, length: start - placed.start, chord: placed.chord)
            }
            return placed
        }
        chords.append(Placed(start: start, length: end - start, chord: chord))
        chords.sort { $0.start < $1.start }
    }

    /// The chord sounding at `beats`, if any.
    public func chord(at beats: Double) -> Placed? {
        chords.first { $0.covers(beats) }
    }

    /// The chord a cursor at `beats` is on: the one sounding there, or else
    /// the one that has just ended there (where the cursor is left after
    /// writing it).
    public func chord(near beats: Double) -> Placed? {
        chord(at: beats) ?? chords.last { abs($0.end - beats) < 1e-9 }
    }

    /// Takes away the chord sounding at `beats`, leaving silence.
    public mutating func clear(at beats: Double) {
        chords.removeAll { $0.covers(beats) }
    }

    /// Makes the chord starting at `start` `length` beats long, as far as
    /// the next chord or the loop's end, and no shorter than `shortest`.
    /// Returns the length it now has.
    @discardableResult
    public mutating func resize(_ start: Double, to length: Double, shortest: Double) -> Double? {
        guard let index = chords.firstIndex(where: { $0.start == start }) else { return nil }
        let limit = index + 1 < chords.count ? chords[index + 1].start : Self.length
        let length = min(limit - start, max(shortest, length))
        chords[index] = Placed(start: start, length: length, chord: chords[index].chord)
        return length
    }
}

extension DeskSettings {
    /// The grid laid the next way (`steps` < 0, the way before).
    public mutating func moveGrid(by steps: Int) {
        let all = BeatGrid.allCases
        let at = all.firstIndex(of: grid)!
        grid = all[((at + steps) % all.count + all.count) % all.count]
    }
}
