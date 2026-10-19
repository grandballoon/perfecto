public enum JoystickMode: CaseIterable, Hashable, Codable, Sendable {
    case `default`, extended, chromatic
}

public enum JoystickDirection: CaseIterable, Hashable, Codable, Sendable {
    case center, up, upRight, right, downRight, down, downLeft, left, upLeft
}

/// How far a chord's notes are rolled from root position, as a pianist
/// inverts a chord. The notes within an octave of the root take turns in
/// the bass: each step up takes the lowest of them up an octave, and each
/// step down the highest of them down one, so the first two steps up are
/// the first and second inversions. The notes a ninth or more above the
/// root (the 9th, 11th and 13th) are not inverted: they stay on top, as
/// they are spaced, an octave further up where a note rolled up would
/// otherwise pass them. So once each note within the octave has had its
/// turn the chord is as it was in root position, an octave up or down,
/// whatever it has above. It has no end either way.
public struct Inversion: Hashable, Codable, Sendable {
    /// Steps up from root position; below 0 is steps down.
    public var steps: Int

    public init(steps: Int) {
        self.steps = steps
    }

    public static let root = Inversion(steps: 0)
    public static let first = Inversion(steps: 1)
    public static let second = Inversion(steps: 2)

    /// This inversion rolled `steps` further.
    public func rolled(by steps: Int) -> Inversion {
        Inversion(steps: self.steps + steps)
    }

    /// `intervals` (a chord's notes, in semitones from its root) rolled
    /// this far: the same pitch classes, sorted.
    public func applied(to intervals: [Int]) -> [Int] {
        let octave = 12
        let sorted = intervals.sorted()
        // The notes that are inverted, and those kept above them. A chord
        // with nothing within an octave of its root is all inverted.
        var core = sorted.filter { $0 < octave }
        var upper = sorted.filter { $0 >= octave }
        if core.isEmpty { (core, upper) = (upper, []) }
        guard !core.isEmpty, sorted.count >= 2 else { return sorted }

        // Whole turns of the inverted notes are octaves; the steps left
        // over each take the lowest of them up one.
        let turns = Int((Double(steps) / Double(core.count)).rounded(.down))
        let left = steps - turns * core.count
        core = (core.dropFirst(left) + core.prefix(left).map { $0 + octave }).map { $0 + turns * octave }
        upper = upper.map { $0 + turns * octave }
        if let top = core.last, let lowest = upper.first, lowest <= top {
            let lift = (top - lowest) / octave + 1
            upper = upper.map { $0 + lift * octave }
        }
        return core + upper
    }
}
