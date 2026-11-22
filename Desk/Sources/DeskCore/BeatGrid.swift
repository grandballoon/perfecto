// The grid the timeline's times are snapped to.

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

extension DeskSettings {
    /// The grid laid the next way (`steps` < 0, the way before).
    public mutating func moveGrid(by steps: Int) {
        let all = BeatGrid.allCases
        let at = all.firstIndex(of: grid)!
        grid = all[((at + steps) % all.count + all.count) % all.count]
    }
}
