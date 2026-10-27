import MusicTheoryCore

// The color ring on a stick: its angle the mode, its radius the stack
// height. Turned as the ring's Home arrangement turns it (`ColorRing`): the
// held degree's own mode at the top, darker anticlockwise, brighter
// clockwise, each sector a note from the next.

/// A cell of the ring as a stick reaches it: sectors from the degree's own
/// mode (below 0 darker), and a stack height.
public struct RingCell: Hashable, Sendable {
    public let offset: Int
    public let height: StackHeight

    public init(offset: Int, height: StackHeight) {
        self.offset = offset
        self.height = height
    }
}

public enum RingPie {
    /// Degrees of the stick a sector takes: the ring's seven in 300°, with a
    /// gap where the darkest and brightest would meet.
    public static let sectorSpan = 300.0 / 7

    /// The sectors' offsets from the own mode for `degree` in `key`, darkest
    /// first. A degree whose own mode is not on the ring (a key of harmonic
    /// minor) has the ring unturned, Dorian at the top.
    public static func offsets(key: Key, degree: Degree) -> [Int] {
        let own = ColorRing.modes.firstIndex(of: ChordGrid.ownMode(key: key, degree: degree)) ?? ColorRing.topSector
        return ColorRing.modes.indices.map { $0 - own }
    }

    /// The pie the stick chooses a sector from.
    public static func gate(key: Key, degree: Degree) -> PieGate {
        PieGate(bearings: offsets(key: key, degree: degree).map { Double($0) * sectorSpan }, width: sectorSpan / 2 + 4)
    }

    /// The mode at `offset` from `degree`'s own, if the ring reaches it.
    public static func mode(at offset: Int, key: Key, degree: Degree) -> HeptatonicMode? {
        let offsets = offsets(key: key, degree: degree)
        return offsets.firstIndex(of: offset).map { ColorRing.modes[$0] }
    }

    /// The color a cell plays: thirds stacked to its height through its
    /// mode, the own mode's as the key has it.
    public static func color(of cell: RingCell, key: Key, degree: Degree) -> ChordColor {
        guard let mode = mode(at: cell.offset, key: key, degree: degree) else { return .grid(cell.height, nil) }
        let own = ChordGrid.ownMode(key: key, degree: degree)
        return .grid(cell.height, mode == own ? nil : mode)
    }

    /// The heights the stick's three rings reach: the 7th to the 11th, or
    /// with the extension held, the 9th to the 13th.
    public static func heights(extended: Bool) -> [StackHeight] {
        extended ? [.ninth, .eleventh, .thirteenth] : [.seventh, .ninth, .eleventh]
    }

    /// The cell a stick at `sector` (an index of `offsets`) in ring `band`
    /// chooses.
    public static func cell(sector: Int, band: Int, extended: Bool, key: Key, degree: Degree) -> RingCell {
        RingCell(offset: offsets(key: key, degree: degree)[sector], height: heights(extended: extended)[band])
    }
}

/// The step compass on a stick: its four kinds of step at the cardinals,
/// each kind's first choice and its second a little clockwise of it.
/// Up adds a tone, right raises one, down takes one away, left lowers one.
public enum CompassPie {
    public static let places: [CompassPlace] = [
        CompassPlace(.add, 1), CompassPlace(.add, 2),
        CompassPlace(.raise, 1), CompassPlace(.raise, 2),
        CompassPlace(.takeAway, 1), CompassPlace(.takeAway, 2),
        CompassPlace(.lower, 1), CompassPlace(.lower, 2),
    ]

    public static let gate = PieGate.even(8)

    /// The chord the place at `index` makes from `chord`, if it has one.
    public static func chord(at index: Int, from chord: DeskChord, ranking: ColorStepRanking) -> DeskChord? {
        StepCompass.step(at: places[index], from: chord.tones, key: chord.key, degree: chord.spec.degree,
                         ranking: ranking)
            .map { DeskChord(key: chord.key, degree: chord.spec.degree, color: .tones($0.tones)) }
    }

    /// What the place at `index` does, by its tones: "+7", "3→4".
    public static func edit(at index: Int, from chord: DeskChord, ranking: ColorStepRanking) -> String? {
        StepCompass.step(at: places[index], from: chord.tones, key: chord.key, degree: chord.spec.degree,
                         ranking: ranking)?.editName
    }
}
