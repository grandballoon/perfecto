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
    /// The key's own chord is wherever its mode is. In brightness order its
    /// sides are mirror images: each mode faces its inversion across the
    /// stick (Lydian and Locrian, Ionian and Phrygian, Mixolydian and
    /// Aeolian), Dorian, its own, at the top.
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

/// The order the ring's sectors go round in, so a direction and a grouping
/// can come to mean a quality.
public enum RingOrder: String, CaseIterable, Codable, Sendable {
    /// Darkest anticlockwise to brightest clockwise, each a note from the
    /// next (for the major scale's modes, the circle of fifths).
    case brightness
    /// Major-third modes on one side and minor-third on the other, each
    /// brightest by the seam between them, and the diminished at the far end.
    case quality
    /// By the note that makes each mode itself: Ionian and Aeolian, which
    /// alter nothing, in the middle; modes with a note raised (Lydian ♯4,
    /// Dorian ♮6) clockwise; with a note lowered (Mixolydian ♭7, Phrygian
    /// ♭2) anticlockwise; Locrian, with two, furthest.
    case character
    /// The fewest notes from outside the key at the top, more to either
    /// side, the most by the gap.
    case borrowed
    /// The modes most played at the top (Ionian, Aeolian, Dorian,
    /// Mixolydian, Lydian, Phrygian, Locrian), less played to either side.
    case common
    /// Nearest the chord sounding at the top, further to either side: it
    /// turns as you play.
    case nearness

    public var name: String {
        switch self {
        case .brightness: "Brightness"
        case .quality: "Quality"
        case .character: "Character note"
        case .borrowed: "Fewest borrowed"
        case .common: "Common first"
        case .nearness: "Nearest"
        }
    }
}

/// Which of the ring's cells can be reached; the rest keep their places,
/// dimmed, so a direction still means what it did.
public enum RingFilter: String, CaseIterable, Codable, Sendable {
    case all
    /// Only chords whose every note is in the key.
    case inKey
    /// Only modes with a major third.
    case majorThird
    /// Only modes with a minor third.
    case minorThird
    /// Only chords with no tone a semitone over another.
    case noClash

    public var name: String {
        switch self {
        case .all: "All"
        case .inKey: "In key"
        case .majorThird: "Major third"
        case .minorThird: "Minor third"
        case .noClash: "No clash"
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

/// The ring for one degree of one key, as its arrangement, order and filter
/// lay it.
public struct RingPie: Equatable, Sendable {
    public struct Sector: Equatable, Sendable {
        public let mode: HeptatonicMode
        /// Degrees clockwise from up.
        public let bearing: Double
        /// Whether it is the degree's own mode: the chord as the key has it.
        public let isOwn: Bool
    }

    /// Degrees of the stick a sector takes: seven in 300°, with a gap where
    /// the ring's two ends would meet.
    public static let sectorSpan = 300.0 / 7

    public let arrangement: RingArrangement
    public let order: RingOrder
    public let filter: RingFilter
    /// In the order they go round, anticlockwise end first.
    public let sectors: [Sector]
    public let own: HeptatonicMode
    private let key: Key
    private let degree: Degree
    /// The consonance guard, which leaves out what it will not play as the
    /// filter does.
    private let consonance: ConsonanceGuard

    /// The modes most played, most first.
    static let popularity: [HeptatonicMode] = [.ionian, .aeolian, .dorian, .mixolydian, .lydian, .phrygian, .locrian]

    public init(_ arrangement: RingArrangement, order: RingOrder = .brightness, filter: RingFilter = .all,
                key: Key, degree: Degree, near sounding: DeskChord? = nil,
                consonance: ConsonanceGuard = ConsonanceGuard()) {
        self.consonance = consonance
        self.arrangement = arrangement
        self.order = order
        self.filter = filter
        self.key = key
        self.degree = degree
        let own = ChordGrid.ownMode(key: key, degree: degree)
        self.own = own
        // The modes, darkest first.
        let modes: [HeptatonicMode] = arrangement == .centred
            ? HeptatonicMode.rows(around: own, count: 7).reversed() : ColorRing.modes
        let ownIndex = modes.firstIndex(of: own).map(Double.init)
        func brightness(_ mode: HeptatonicMode) -> Int { mode.intervals.reduce(0, +) }
        func distance(_ mode: HeptatonicMode) -> Int { abs(brightness(mode) - brightness(own)) }
        func turned(_ list: [HeptatonicMode], natural: Double) -> (list: [HeptatonicMode], top: Double) {
            let top = arrangement == .fixed ? natural : list.firstIndex(of: own).map(Double.init) ?? natural
            return (list, top)
        }
        /// A ranking laid out from the top, the next two either side of it,
        /// the two after either side of them, and so on. Of two ranked alike
        /// by `score`, the brighter goes clockwise, as it does on the ring.
        func fanned(_ ranked: [HeptatonicMode], by score: (HeptatonicMode) -> Int) -> (list: [HeptatonicMode], top: Double) {
            var rights: [HeptatonicMode] = [], lefts: [HeptatonicMode] = []
            var rest = Array(ranked.dropFirst())
            while !rest.isEmpty {
                let first = rest.removeFirst()
                guard !rest.isEmpty else {
                    rights.append(first)
                    break
                }
                let second = rest.removeFirst()
                let swap = score(first) == score(second) && brightness(second) > brightness(first)
                rights.append(swap ? second : first)
                lefts.append(swap ? first : second)
            }
            return (lefts.reversed() + [ranked[0]] + rights, Double(lefts.count))
        }
        let laid: (list: [HeptatonicMode], top: Double)
        switch order {
        case .brightness:
            laid = arrangement == .fixed || ownIndex == nil
                ? (modes, arrangement == .centred ? Double(modes.count / 2) : Double(ColorRing.topSector))
                : (modes, ownIndex!)
        case .quality:
            let other = modes.filter { !$0.intervals.contains(7) }
            let minor = modes.filter { $0.intervals.contains(7) && $0.intervals.contains(3) && !$0.intervals.contains(4) }
            let major = modes.filter { $0.intervals.contains(7) && $0.intervals.contains(4) }
            laid = turned(other + minor + major.reversed(), natural: Double(other.count + minor.count) - 0.5)
        case .character:
            let scored = modes.sorted { (Self.alteration($0), brightness($0)) < (Self.alteration($1), brightness($1)) }
            let plain = scored.indices.filter { Self.alteration(scored[$0]) == 0 }
            let natural = plain.isEmpty ? Double(scored.count / 2) : Double(plain.reduce(0, +)) / Double(plain.count)
            laid = turned(scored, natural: natural)
        case .borrowed:
            let outside = { (mode: HeptatonicMode) in
                mode.intervals.count { !key.has(key.root.rawValue + key.scale.offset(of: degree) + $0) }
            }
            laid = fanned(modes.sorted { (outside($0), distance($0), brightness($0)) < (outside($1), distance($1), brightness($1)) },
                          by: outside)
        case .common:
            let rank = { (mode: HeptatonicMode) in Self.popularity.firstIndex(of: mode) ?? Self.popularity.count }
            var ranked = modes.sorted { (rank($0), distance($0), brightness($0)) < (rank($1), distance($1), brightness($1)) }
            if arrangement != .fixed, let at = ranked.firstIndex(of: own) { ranked.insert(ranked.remove(at: at), at: 0) }
            laid = fanned(ranked, by: rank)
        case .nearness:
            let steps = { (mode: HeptatonicMode) -> Int in
                guard let sounding else { return mode == own ? 0 : 1 }
                let chord = DeskChord(key: key, degree: degree, color: .grid(.seventh, mode == own ? nil : mode))
                return colorSteps(Array(chord.pitchClasses), Array(sounding.pitchClasses))
            }
            laid = fanned(modes.sorted { (steps($0), distance($0), brightness($0)) < (steps($1), distance($1), brightness($1)) },
                          by: steps)
        }
        sectors = laid.list.enumerated().map { index, mode in
            Sector(mode: mode, bearing: (Double(index) - laid.top) * Self.sectorSpan, isOwn: mode == own)
        }
    }

    /// How far a mode is from the plain major or minor scale of its third:
    /// notes raised count up, notes lowered count down, so Lydian is 1,
    /// Mixolydian -1 and Locrian -2.
    static func alteration(_ mode: HeptatonicMode) -> Int {
        let plain = mode.intervals.contains(4) ? HeptatonicMode.ionian.intervals : HeptatonicMode.aeolian.intervals
        let raised = zip(mode.intervals, plain).filter { $0 > $1 }.count
        let lowered = zip(mode.intervals, plain).filter { $0 < $1 }.count
        return raised > 0 && lowered == 0 ? raised : -lowered - raised
    }

    /// Where the gap is: midway round the long way between the ring's ends.
    public var gap: Double {
        let middle = (sectors.first!.bearing + sectors.last!.bearing) / 2 + 180
        return (middle.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Whether the filter lets `cell` be reached.
    public func allows(_ cell: RingCell) -> Bool {
        guard consonance.allows(DeskChord(key: key, degree: degree, color: color(of: cell)), in: key) else { return false }
        switch filter {
        case .all: return true
        case .majorThird: return cell.mode.intervals.contains(4)
        case .minorThird: return cell.mode.intervals.contains(3) && !cell.mode.intervals.contains(4)
        case .inKey, .noClash:
            let fit = DeskChord(key: key, degree: degree, color: color(of: cell)).fit(in: key)
            return filter == .inKey ? fit != .borrowed : fit != .tense
        }
    }

    /// The sectors the stick can reach (those with a cell the filter lets
    /// through), as indices of `sectors`, and the pie it chooses among them by.
    public func gate(extended: Bool) -> (gate: PieGate, sectors: [Int]) {
        let heights = Self.heights(extended: extended)
        let reachable = sectors.indices.filter { index in
            heights.contains { allows(RingCell(mode: sectors[index].mode, height: $0)) }
        }
        return (PieGate(bearings: reachable.map { sectors[$0].bearing }, width: Self.sectorSpan / 2 + 4), reachable)
    }

    /// The mode `steps` sectors brighter than the own mode (below 0,
    /// darker), held at the ring's ends; the own mode is counted from the
    /// top for a ring it is not on. For a ring in brightness order.
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
        sectors.firstIndex(where: \.isOwn) ?? sectors.indices.min { abs(sectors[$0].bearing) < abs(sectors[$1].bearing) }!
    }

    /// The color a cell plays: thirds stacked to its height through its
    /// mode, the own mode's as the key has it (so it follows the key).
    public func color(of cell: RingCell) -> ChordColor {
        .grid(cell.height, cell.mode == own ? nil : cell.mode)
    }

    /// The cell a stick at `sector` (an index of `sectors`) in ring `band`
    /// chooses, if the filter lets it be reached.
    public func cell(sector: Int, band: Int, extended: Bool) -> RingCell? {
        let cell = RingCell(mode: sectors[sector].mode, height: Self.heights(extended: extended)[band])
        return allows(cell) ? cell : nil
    }

    /// The heights the stick's three rings reach: the 7th to the 11th, or
    /// with the extension held, the 9th to the 13th.
    public static func heights(extended: Bool) -> [StackHeight] {
        extended ? [.ninth, .eleventh, .thirteenth] : [.seventh, .ninth, .eleventh]
    }
}

extension DeskSettings {
    /// The ring for `degree` as these settings lay it, turned to nearness
    /// from `sounding`.
    public func ring(_ degree: Degree, near sounding: DeskChord? = nil) -> RingPie {
        RingPie(ringArrangement, order: ringOrder, filter: ringFilter, key: key, degree: degree, near: sounding,
                consonance: consonance)
    }

    /// The ring in brightness order, unfiltered: what Petals' triggers step
    /// along, darker and brighter.
    public func brightnessRing(_ degree: Degree) -> RingPie {
        RingPie(ringArrangement, key: key, degree: degree)
    }

    /// The ring's order the next one along (`steps` < 0, the one before).
    public mutating func moveRingOrder(by steps: Int) {
        let all = RingOrder.allCases
        ringOrder = all[((all.firstIndex(of: ringOrder)! + steps) % all.count + all.count) % all.count]
    }

    public mutating func moveRingFilter(by steps: Int) {
        let all = RingFilter.allCases
        ringFilter = all[((all.firstIndex(of: ringFilter)! + steps) % all.count + all.count) % all.count]
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
