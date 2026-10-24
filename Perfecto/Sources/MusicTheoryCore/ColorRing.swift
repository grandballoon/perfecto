// The color ring: the chord grid's colors round a circle, a band to each
// stack of thirds (the triad innermost) and a sector to each mode of the
// major scale, darkest to brightest. Each sector is one note from the next,
// so touching colors are almost always one step apart (`colorSteps`); the
// darkest and the brightest are five notes apart, so the ring has a gap
// where they would meet. Geometry is the view's: here the ring is sectors.

/// How the ring is turned: the same colors either way.
public enum ColorRingArrangement: CaseIterable, Hashable, Sendable {
    /// Never turned: a sector is always the same mode, so a place on the
    /// ring is always the same chord shape. Dorian, the middle of the
    /// order, is at the top.
    case fixed
    /// Turned so the held degree's own mode is at the top: the top is
    /// always the chord as the key has it.
    case home
}

/// A cell of the ring: a stack height, and the mode it stacks through; nil
/// is the degree's own mode, so the cell follows the degree and the key, as
/// the chord grid's own row does.
public struct ColorRingPosition: Hashable, Sendable {
    public let height: StackHeight
    public let mode: HeptatonicMode?

    public init(height: StackHeight, mode: HeptatonicMode?) {
        self.height = height
        self.mode = mode
    }
}

public enum ColorRing {

    /// The sectors' modes in order round the ring, darkest first: the major
    /// scale's seven of `HeptatonicMode.byBrightness`.
    public static let modes: [HeptatonicMode] = HeptatonicMode.byBrightness.filter { $0.family == .major }.reversed()

    /// The sector at the top of a ring that is not turned.
    public static let topSector = 3

    /// How many sectors `arrangement` turns the ring clockwise for `degree`
    /// in `key`. A home ring is not turned for a degree whose own mode is not
    /// on the ring (a key of harmonic minor).
    public static func turn(_ arrangement: ColorRingArrangement, key: Key, degree: Degree) -> Int {
        guard arrangement == .home,
              let own = modes.firstIndex(of: ChordGrid.ownMode(key: key, degree: degree)) else { return 0 }
        return topSector - own
    }

    /// The mode a cell stacks through, for `degree` in `key`.
    public static func mode(of position: ColorRingPosition, key: Key, degree: Degree) -> HeptatonicMode {
        position.mode ?? ChordGrid.ownMode(key: key, degree: degree)
    }

    /// The cell of `height` in sector `sector` (an index of `modes`), for
    /// `degree` in `key`. On a home ring the own mode's cell is nil, so it
    /// stays the own mode's whatever degree is played; on a fixed ring a
    /// sector is always its mode.
    public static func position(height: StackHeight, sector: Int, arrangement: ColorRingArrangement,
                                key: Key, degree: Degree) -> ColorRingPosition {
        precondition(modes.indices.contains(sector), "ring sector \(sector) out of range")
        let mode = modes[sector]
        let own = arrangement == .home && mode == ChordGrid.ownMode(key: key, degree: degree)
        return ColorRingPosition(height: height, mode: own ? nil : mode)
    }

    /// The sector a cell is in for `degree` in `key`, or nil if its mode is
    /// not on the ring.
    public static func sector(of position: ColorRingPosition, key: Key, degree: Degree) -> Int? {
        modes.firstIndex(of: mode(of: position, key: key, degree: degree))
    }

    /// The color a cell plays with `marks` on: a grid color, which the own
    /// mode's cell plays with a nil mode so it follows the key.
    public static func color(at position: ColorRingPosition, marks: ToneMarks,
                             key: Key, degree: Degree) -> ChordColor {
        let own = ChordGrid.ownMode(key: key, degree: degree)
        let mode = position.mode == own ? nil : position.mode
        return .tertian(position.height, mode, marks)
    }
}

extension ChordColor {
    /// Thirds stacked to `height` through `mode` with `marks`: a grid color
    /// when there are no marks.
    public static func tertian(_ height: StackHeight, _ mode: HeptatonicMode?, _ marks: ToneMarks) -> ChordColor {
        marks.isEmpty ? .grid(height, mode) : .marked(height, mode, marks)
    }
}
