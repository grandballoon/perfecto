// The chord grid: the geometry that maps a finger's position to a chord
// color. Columns are stack heights (triad → 13th); rows are a window of
// `HeptatonicMode.byBrightness` around the degree's own mode. The same
// position means a different mode for a different degree, so input surfaces
// store the position and resolve it against the degree that plays.

/// A cell of the chord grid: a column and a row counted from the top.
public struct GridPosition: Hashable, Sendable {
    public let height: StackHeight
    public let row: Int

    public init(height: StackHeight, row: Int) {
        self.height = height
        self.row = row
    }
}

public enum ChordGrid {

    /// Rows on screen: the degree's own mode and three brighter and darker.
    public static let rowCount = 7

    /// The mode `degree` stacks through in `key` when no other row is chosen.
    /// Scales without seven notes have no diatonic mode (the Key sheet doesn't
    /// offer them; see docs/next-phase-plan.md, Open decision 1), so they use
    /// the major-scale mode with the degree's triad quality.
    public static func ownMode(key: Key, degree: Degree) -> HeptatonicMode {
        if let mode = HeptatonicMode(key: key, degree: degree) { return mode }
        switch triadBase(key: key, degree: degree) {
        case .major: return .ionian
        case .minor: return .aeolian
        case .dim:   return .locrian
        }
    }

    /// The modes of the grid's rows, top to bottom, for `degree` in `key`.
    public static func rows(key: Key, degree: Degree) -> [HeptatonicMode] {
        HeptatonicMode.rows(around: ownMode(key: key, degree: degree), count: rowCount)
    }

    /// The color a finger at `position` gives `degree`. The own mode's row
    /// resolves to the diatonic color (nil mode), so it follows the key.
    public static func color(at position: GridPosition, key: Key, degree: Degree) -> ChordColor {
        let rows = rows(key: key, degree: degree)
        precondition(rows.indices.contains(position.row), "grid row \(position.row) out of range")
        let mode = rows[position.row]
        return .grid(position.height, mode == ownMode(key: key, degree: degree) ? nil : mode)
    }

    /// Where `color` sits on `degree`'s grid, or nil if it isn't on it (a
    /// joystick color, or a mode outside this degree's window).
    public static func position(of color: ChordColor, key: Key, degree: Degree) -> GridPosition? {
        guard case let .grid(height, mode) = color else { return nil }
        let target = mode ?? ownMode(key: key, degree: degree)
        guard let row = rows(key: key, degree: degree).firstIndex(of: target) else { return nil }
        return GridPosition(height: height, row: row)
    }
}
