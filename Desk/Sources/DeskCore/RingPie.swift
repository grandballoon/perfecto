import MusicTheoryCore

// The color ring on a stick: its angle the mode, its radius the stack
// height. Its sectors go from darkest anticlockwise to brightest clockwise,
// each a note or two from the next, so a step round is the gentlest change
// of color there is. How the ring is turned is the player's choice
// (`RingArrangement`), since each way gives up something the others keep.

/// How the color ring is laid round the stick.
public enum RingArrangement: String, CaseIterable, Codable, Sendable {
    /// The seven modes of the major scale, turned so the degree's own is at
    /// the top: up is always the chord as the key has it. The ring is
    /// lopsided by as much as the own mode is near an end, so its gap moves
    /// with the degree.
    case home
    /// The seven modes of the major scale, never turned: Dorian at the top
    /// and the gap at the bottom, so a direction is always the same mode.
    /// The key's own chord is wherever its mode is.
    case fixed
    /// The degree's own mode at the top with the modes nearest it in
    /// brightness either side, from all three scales' (the chord grid's
    /// rows, `HeptatonicMode.rows`): balanced on every degree, as far as the
    /// brightest and darkest modes allow.
    case centred

    public var name: String {
        switch self {
        case .home: "Home"
        case .fixed: "Fixed"
        case .centred: "Centred"
        }
    }

    /// What it keeps, in a line.
    public var summary: String {
        switch self {
        case .home: "The key's own chord at the top; the gap moves with the degree."
        case .fixed: "Every direction always the same mode; the gap always at the bottom."
        case .centred: "The key's own chord at the top, balanced, borrowing from minor scales at the ends."
        }
    }
}

/// A cell of the ring: a mode and a stack height. It names what it plays,
/// not where it is, so a cell kept stays kept whichever way the ring is
/// turned.
public struct RingCell: Hashable, Sendable {
    public let mode: HeptatonicMode
    public let height: StackHeight

    public init(mode: HeptatonicMode, height: StackHeight) {
        self.mode = mode
        self.height = height
    }
}

/// The ring for one degree of one key, as `arrangement` lays it.
public struct RingPie: Equatable, Sendable {
    public struct Sector: Equatable, Sendable {
        public let mode: HeptatonicMode
        /// Degrees clockwise from up.
        public let bearing: Double
        /// Whether it is the degree's own mode: the chord as the key has it.
        public let isOwn: Bool
    }

    /// Degrees of the stick a sector takes: seven in 300°, with a gap where
    /// the darkest and brightest would meet.
    public static let sectorSpan = 300.0 / 7

    public let arrangement: RingArrangement
    /// Darkest first.
    public let sectors: [Sector]
    public let own: HeptatonicMode

    public init(_ arrangement: RingArrangement, key: Key, degree: Degree) {
        self.arrangement = arrangement
        own = ChordGrid.ownMode(key: key, degree: degree)
        let modes: [HeptatonicMode]
        let top: Int
        switch arrangement {
        case .home, .fixed:
            modes = ColorRing.modes
            // A degree whose own mode is not on the ring (a key of harmonic
            // minor) has the ring unturned.
            top = arrangement == .home ? modes.firstIndex(of: own) ?? ColorRing.topSector : ColorRing.topSector
        case .centred:
            modes = HeptatonicMode.rows(around: own, count: 7).reversed()
            top = modes.firstIndex(of: own)!
        }
        let own = own
        sectors = modes.enumerated().map { index, mode in
            Sector(mode: mode, bearing: Double(index - top) * Self.sectorSpan, isOwn: mode == own)
        }
    }

    /// Where the gap is: midway round the long way between the darkest
    /// sector and the brightest.
    public var gap: Double {
        let middle = (sectors.first!.bearing + sectors.last!.bearing) / 2 + 180
        return (middle.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
    }

    /// The pie the stick chooses a sector from.
    public var gate: PieGate {
        PieGate(bearings: sectors.map(\.bearing), width: Self.sectorSpan / 2 + 4)
    }

    /// The mode `steps` sectors brighter than the own mode (below 0,
    /// darker), held at the ring's ends; the own mode is counted from the
    /// top for a ring it is not on.
    public func mode(steps: Int) -> HeptatonicMode {
        sectors[clamped(steps) + ownIndex].mode
    }

    /// Whether the ring reaches `steps` sectors from the own mode.
    public func reaches(_ steps: Int) -> Bool {
        clamped(steps) == steps
    }

    /// `steps` held to what the ring reaches from the own mode either way.
    public func clamped(_ steps: Int) -> Int {
        min(sectors.count - 1 - ownIndex, max(-ownIndex, steps))
    }

    /// The sector of the own mode, or the top one for a ring without it.
    private var ownIndex: Int {
        sectors.firstIndex(where: \.isOwn) ?? sectors.firstIndex { $0.bearing == 0 }!
    }

    /// The color a cell plays: thirds stacked to its height through its
    /// mode, the own mode's as the key has it (so it follows the key).
    public func color(of cell: RingCell) -> ChordColor {
        .grid(cell.height, cell.mode == own ? nil : cell.mode)
    }

    /// The cell a stick at `sector` (an index of `sectors`) in ring `band`
    /// chooses.
    public func cell(sector: Int, band: Int, extended: Bool) -> RingCell {
        RingCell(mode: sectors[sector].mode, height: Self.heights(extended: extended)[band])
    }

    /// The heights the stick's three rings reach: the 7th to the 11th, or
    /// with the extension held, the 9th to the 13th.
    public static func heights(extended: Bool) -> [StackHeight] {
        extended ? [.ninth, .eleventh, .thirteenth] : [.seventh, .ninth, .eleventh]
    }
}

extension DeskSettings {
    /// The ring for `degree` as these settings lay it.
    public func ring(_ degree: Degree) -> RingPie {
        RingPie(ringArrangement, key: key, degree: degree)
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
