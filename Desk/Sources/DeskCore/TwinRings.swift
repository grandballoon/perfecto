import MusicTheoryCore

/// Model 1, Twin rings: each stick is a ring the app already has. The left
/// stick is a pie of the seven degrees in the cycle of thirds; the right is
/// the color ring, its angle the mode and its radius the stack height; the
/// right trigger strikes, how fast it is pulled how loud. A colored chord is
/// one gesture, and a change of color under a held chord is the right thumb
/// moving.
///
/// The right stick is played, not kept: a lean is heard while it is held
/// and goes back when it is let go. A flick (out and back quickly) keeps
/// the cell it pointed at, so the kept color and the played one are told
/// apart by the hand, with no latch to press.
public struct TwinRings: Layout {
    public private(set) var degree = Degree.I
    private var degreeSector: Int? = DegreePie.sector(of: .I)
    /// The ring's cell leaned at, and the one kept.
    public private(set) var aim: RingCell?
    public private(set) var kept: RingCell?
    /// The step compass's place leaned at and kept, while LB is held.
    public private(set) var compassAim: Int?
    public private(set) var keptStep: Int?
    /// The favorite leaned at and kept, while Y is held: an index of the
    /// degree's favorites in the table played.
    public private(set) var favoriteAim: Int?
    public private(set) var keptFavorite: Int?
    /// Whether a chord goes on sounding when the strike lets go.
    public private(set) var holds = false
    public private(set) var line = ChordLine()
    /// The arpeggio's step on LT: 0 off.
    public private(set) var arpeggioStep = 0

    private var ring = StickGesture()
    private var band: Int?
    private var compass = StickGesture()
    private var strike = TriggerStrike()
    private var struckLevel = 0.8
    private var favorites = StickGesture()
    private var lb = TapOrHold()
    private var rb = TapOrHold()
    private var y = TapOrHold()

    public init() {}

    /// Whether RB is extending the ring to the 13th.
    public private(set) var isExtended = false
    /// Whether LB has the right stick on the step compass.
    public private(set) var isOnCompass = false
    /// Whether Y has the right stick on the favorites.
    public private(set) var isOnFavorites = false

    /// The favorites' gate: a direction for each of a chord's eight.
    public static let favoritesGate = PieGate.even(Favorites.perChord)

    public mutating func step(_ input: PadInput, settings: inout DeskSettings) -> [DeskEffect] {
        var out: [DeskEffect] = []
        let time = input.time

        if input.pressed(.b) {
            holds = false
            out += line.release()
        }
        // Y: a tap holds; held, it is the favorites' layer.
        if input.pressed(.y) {
            y.press(at: time)
            ring.reset()
            aim = nil
        }
        if input.released(.y) {
            favorites.reset()
            favoriteAim = nil
            if y.release(at: time) {
                holds.toggle()
                if !holds, !strike.isHeld, !input.isDown(.a) { out += line.release() }
            }
        }
        isOnFavorites = input.isDown(.y)
        if input.pressed(.x) {
            if isOnFavorites {
                y.use()
                if let favoriteAim {
                    settings.favorites.unpin(settings.key, degree, at: favoriteAim)
                    if keptFavorite == favoriteAim { keptFavorite = nil }
                    self.favoriteAim = nil
                    out.append(.rumble(.bump))
                }
            } else {
                settings.voiceLeading.toggle()
            }
        }
        if input.pressed(.r3), aim == nil, compassAim == nil, favoriteAim == nil {
            kept = nil
            keptStep = nil
            keptFavorite = nil
        }
        if input.pressed(.l3) {
            settings.moveRingArrangement(by: 1)
            out.append(.rumble(.tick))
        }
        let revoiced = voicingPad(input, settings: &settings)

        // The bumpers: a tap moves the key a fifth, a hold is a layer.
        if input.pressed(.lb) {
            lb.press(at: time)
            ring.reset()
            aim = nil
        }
        if input.released(.lb) {
            compass.reset()
            compassAim = nil
            if lb.release(at: time) {
                settings.moveKey(byFifths: -1)
                out.append(.rumble(.bump))
            }
        }
        if input.pressed(.rb) { rb.press(at: time) }
        if input.released(.rb), rb.release(at: time) {
            settings.moveKey(byFifths: 1)
            out.append(.rumble(.bump))
        }
        isOnCompass = input.isDown(.lb)
        isExtended = input.isDown(.rb)

        // The left stick: the degree, kept when the stick comes back.
        degreeSector = DegreePie.gate.select(input.frame.left, from: degreeSector)
        if let degreeSector, input.frame.left.radius >= PieGate.rest { degree = DegreePie.degree(at: degreeSector) }

        // The right stick: the ring, with LB the compass, with Y the favorites.
        if isOnFavorites {
            let count = settings.favorites.colors(settings.key, degree).count
            for event in favorites.step(input.frame.right, gate: Self.favoritesGate, at: time) {
                y.use()
                switch event {
                case .aim(let index): favoriteAim = index < count ? index : nil
                case .flick(let index):
                    guard index < count else { continue }
                    keptFavorite = keptFavorite == index ? nil : index
                    favoriteAim = nil
                    out.append(.rumble(.bump))
                case .lift: favoriteAim = nil
                }
            }
            if input.pressed(.r3), let favoriteAim { keptFavorite = favoriteAim }
        } else if isOnCompass {
            for event in compass.step(input.frame.right, gate: CompassPie.gate, at: time) {
                lb.use()
                switch event {
                case .aim(let place): compassAim = place
                case .flick(let place):
                    keptStep = keptStep == place ? nil : place
                    compassAim = nil
                    out.append(.rumble(.bump))
                case .lift: compassAim = nil
                }
            }
            if input.pressed(.r3), let compassAim { keptStep = compassAim }
        } else {
            let pie = settings.ring(degree)
            for event in ring.step(input.frame.right, gate: pie.gate, at: time) {
                switch event {
                case .aim: break
                case .flick:
                    kept = aim
                    out.append(.rumble(.bump))
                case .lift: break
                }
            }
            if let sector = ring.target {
                if isExtended { rb.use() }
                let next = RadialBands.three.band(input.frame.right.radius, from: band)
                if band != nil, next != band { out.append(.rumble(.tick)) }
                band = next
                aim = pie.cell(sector: sector, band: next, extended: isExtended)
                if input.pressed(.r3) { kept = aim }
            } else {
                band = nil
                aim = nil
            }
        }

        // Striking: RT with a level, A at a fixed one.
        for event in strike.step(input.frame.rightTrigger, at: time) {
            switch event {
            case .strike(let level):
                struckLevel = level
                out += line.strike(chord(settings), level: level, brightness: 1, settings: settings, at: time)
            case .depth(let depth):
                out += line.shape(level: struckLevel * (0.6 + 0.4 * depth), brightness: 0.55 + 0.45 * depth)
            case .release:
                if !holds, !input.isDown(.a) { out += line.release() }
            }
        }
        if input.pressed(.a) {
            if isOnFavorites {
                // Y + A pins the chord the hands are on.
                y.use()
                out.append(.rumble(settings.favorites.pin(chord(settings), in: settings.key) ? .bump : .tick))
            } else {
                out += line.strike(chord(settings), level: 0.8, settings: settings, at: time)
            }
        }
        if input.released(.a), !holds, !strike.isHeld { out += line.release() }

        // What sounds follows the hands.
        out += line.change(to: chord(settings), settings: settings)
        if revoiced { out += line.revoice(settings) }

        // LT: the arpeggio, off and then faster as it is pulled.
        let next = TriggerSteps.three.step(input.frame.leftTrigger, from: arpeggioStep)
        if next != arpeggioStep {
            arpeggioStep = next
            out.append(.rumble(.tick))
            out += line.arpeggiate(ArpeggioRate(rawValue: next), settings: settings, at: time)
        }
        out += line.tick(settings, at: time)
        return out
    }

    public mutating func releaseAll() -> [DeskEffect] {
        holds = false
        ring.reset()
        compass.reset()
        aim = nil
        compassAim = nil
        strike = TriggerStrike()
        return line.release()
    }

    /// The chord the hands are on now.
    public func chord(_ settings: DeskSettings) -> DeskChord {
        // A favorite, or else the ring's cell, and the compass's step from it.
        let pinned = settings.favorites.colors(settings.key, degree)
        let color: ChordColor
        if let favorite = favoriteAim ?? keptFavorite, pinned.indices.contains(favorite) {
            color = pinned[favorite]
        } else {
            color = (aim ?? kept).map { settings.ring(degree).color(of: $0) } ?? .base
        }
        let base = DeskChord(key: settings.key, degree: degree, color: color)
        guard let place = compassAim ?? keptStep else { return base }
        return CompassPie.chord(at: place, from: base, ranking: settings.ranking) ?? base
    }

    // MARK: – What the screen shows

    public func degreeTargets(_ settings: DeskSettings) -> [Target] {
        DeskCore.degreeTargets(chosen: degree, sounding: line.isSounding ? line.chord : nil, settings: settings)
    }

    /// The ring's cells for the degree chosen, ring by ring (inside out),
    /// each sector darkest first.
    public func ringTargets(_ settings: DeskSettings) -> [[Target]] {
        let pie = settings.ring(degree)
        let sounding = line.isSounding ? line.chord : nil
        return RingPie.heights(extended: isExtended).map { height in
            pie.sectors.map { sector in
                let cell = RingCell(mode: sector.mode, height: height)
                let chord = DeskChord(key: settings.key, degree: degree, color: pie.color(of: cell))
                return Target(bearing: sector.bearing, name: chord.name, detail: sector.mode.displayName,
                              fit: chord.fit(in: settings.key), isNear: chord.isOneStep(from: sounding),
                              isAimed: cell == aim, isKept: cell == kept)
            }
        }
    }

    /// The degree's favorites in the table played, round the stick, while Y
    /// is held.
    public func favoriteTargets(_ settings: DeskSettings) -> [Target?] {
        let pinned = settings.favorites.colors(settings.key, degree)
        return (0..<Favorites.perChord).map { index in
            guard pinned.indices.contains(index) else { return nil }
            let chord = DeskChord(key: settings.key, degree: degree, color: pinned[index])
            return Target(bearing: Self.favoritesGate.bearings[index], name: chord.name, detail: "\(index + 1)",
                          fit: chord.fit(in: settings.key), isAimed: index == favoriteAim,
                          isKept: index == keptFavorite)
        }
    }

    /// The step compass's places from the ring's chord, while LB is held.
    public func compassTargets(_ settings: DeskSettings) -> [Target] {
        var base = self
        base.compassAim = nil
        base.keptStep = nil
        let from = base.chord(settings)
        return CompassPie.places.indices.map { index in
            let chord = CompassPie.chord(at: index, from: from, ranking: settings.ranking)
            return Target(bearing: CompassPie.gate.bearings[index], name: chord?.name ?? "—",
                          detail: CompassPie.edit(at: index, from: from, ranking: settings.ranking) ?? "",
                          fit: chord?.fit(in: settings.key) ?? .inKey, isAimed: index == compassAim,
                          isKept: index == keptStep)
        }
    }

    public func legend(_ settings: DeskSettings) -> Legend {
        var legend = commonLegend(settings)
        legend[.leftStick] = "Degree · \(numeral(degree, in: settings.key))"
        legend[.rightStick] = isOnFavorites ? "Favorites: flick keeps, hold plays"
            : isOnCompass ? "Step compass: flick keeps, hold plays"
            : isExtended ? "Ring to the 13th: flick keeps, hold plays"
            : "Color ring: flick keeps, hold plays"
        legend[.rightTrigger] = "Strike · pull = swell"
        legend[.leftTrigger] = "Arpeggio " + (ArpeggioRate(rawValue: arpeggioStep)?.name ?? "off")
        legend[.button(.a)] = isOnFavorites ? "Pin this chord to \(settings.favorites.table.name)" : "Strike"
        legend[.button(.b)] = "Let go"
        legend[.button(.x)] = isOnFavorites ? "Unpin the favorite aimed at"
            : "Voice leading " + (settings.voiceLeading ? "on" : "off")
        legend[.button(.y)] = "Tap: hold " + (holds ? "on" : "off") + " · hold: favorites"
        legend[.button(.lb)] = "Tap: key a 5th down · hold: compass"
        legend[.button(.rb)] = "Tap: key a 5th up · hold: to 13th"
        legend[.button(.l3)] = "Ring: \(settings.ringArrangement.name) → next"
        legend[.button(.r3)] = "Keep aimed cell · at rest: plain"
        return legend
    }
}
