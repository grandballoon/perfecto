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
    /// The chord last struck, which the ring's nearest order is turned to:
    /// not the chord sounding, which a lean changes, or the ring would turn
    /// under the thumb.
    public private(set) var struck: DeskChord?
    private var favorites = StickGesture()
    private var lb = TapOrHold()
    private var rb = TapOrHold()
    private var y = TapOrHold()

    public init() {}

    /// Whether RB is extending the ring to the 13th.
    public private(set) var isExtended = false
    /// Whether LB has the right stick on the step compass.
    public private(set) var isOnCompass = false
    /// Whether a long-press of LB has left the compass on, so it stays on
    /// the right stick without LB held, until another long-press.
    public private(set) var compassLatched = false
    /// When LB went down, while it is held and has not yet been held long.
    private var lbHeldSince: Double?
    /// Whether Y has the right stick on the favorites.
    public private(set) var isOnFavorites = false
    /// Whether the LB layer is on with the voices on the sticks.
    public private(set) var isOnVoices = false
    /// The move of the upper voices leaned at, and of the bass.
    public private(set) var voiceAim: VoiceMove?
    public private(set) var bassAim: VoiceMove?
    /// The chord the voices have walked to, kept until R3 takes it back or
    /// another degree is chosen.
    public private(set) var walked: DeskChord?
    private var voices = StickGesture()
    private var voiceBand: Int?
    private var bass = StickGesture()
    private var bassBand: Int?

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
        // R3 with the stick at rest, the middle: the voices' walk taken back
        // first, then a step of the compass, then the color, to the plain chord.
        if input.pressed(.r3), aim == nil, compassAim == nil, favoriteAim == nil, voiceAim == nil, bassAim == nil,
           resetsTo(settings) != nil {
            if walked != nil {
                walked = nil
            } else if keptStep != nil {
                keptStep = nil
            } else {
                kept = nil
                keptFavorite = nil
            }
            out.append(.rumble(.tick))
        }
        // L3: with the LB layer on, compass or voices; otherwise the ring's arrangement.
        if input.pressed(.l3) {
            if isOnCompass {
                settings.lbLayer = settings.lbLayer == .compass ? .voices : .compass
                compass.reset()
                compassAim = nil
                letGoOfVoices()
            } else {
                settings.moveRingArrangement(by: 1)
            }
            out.append(.rumble(.tick))
        }
        let revoiced = voicingPad(input, settings: &settings)

        // The bumpers: a tap moves the key a fifth, a hold is a layer. LB
        // held long turns the compass on to stay, or off again.
        if input.pressed(.lb) {
            lb.press(at: time)
            lbHeldSince = time
            ring.reset()
            aim = nil
        }
        if let since = lbHeldSince, input.isDown(.lb), time - since >= TapOrHold.tapTime {
            lbHeldSince = nil
            lb.use()
            compassLatched.toggle()
            out.append(.rumble(.bump))
        }
        if input.released(.lb) {
            lbHeldSince = nil
            if !compassLatched {
                compass.reset()
                compassAim = nil
                letGoOfVoices()
            }
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
        isOnCompass = input.isDown(.lb) || compassLatched
        isOnVoices = isOnCompass && settings.lbLayer == .voices
        isExtended = input.isDown(.rb)

        // The left stick: the degree, kept when the stick comes back; with
        // the voices on, the bass.
        if isOnVoices {
            out += stepBass(input, settings)
        } else {
            degreeSector = DegreePie.gate.select(input.frame.left, from: degreeSector)
            if let degreeSector, input.frame.left.radius >= PieGate.rest {
                let chosen = DegreePie.degree(at: degreeSector)
                if chosen != degree { walked = nil }
                degree = chosen
            }
        }

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
        } else if isOnVoices {
            out += stepVoices(input, settings)
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
            let pie = settings.ring(degree, near: struck)
            let (gate, reachable) = pie.gate(extended: isExtended)
            for event in ring.step(input.frame.right, gate: gate, at: time) {
                switch event {
                case .aim: break
                case .flick:
                    kept = aim
                    out.append(.rumble(.bump))
                case .lift: break
                }
            }
            if let target = ring.target, reachable.indices.contains(target) {
                if isExtended { rb.use() }
                let next = RadialBands.three.band(input.frame.right.radius, from: band)
                if band != nil, next != band { out.append(.rumble(.tick)) }
                band = next
                aim = pie.cell(sector: reachable[target], band: next, extended: isExtended)
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
                struck = chord(settings)
                out += line.strike(struck!, level: level, brightness: 1, settings: settings, at: time)
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
                struck = chord(settings)
                out += line.strike(struck!, level: 0.8, settings: settings, at: time)
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
        letGoOfVoices()
        holds = false
        lbHeldSince = nil
        ring.reset()
        compass.reset()
        aim = nil
        compassAim = nil
        strike = TriggerStrike()
        return line.release()
    }

    /// The chord the hands are on now.
    public func chord(_ settings: DeskSettings) -> DeskChord {
        let from = voiced(settings)
        if let voiceAim, let moved = VoiceLeading.neighbour(of: from.notes(settings), by: voiceAim, in: settings.key) {
            return moved
        }
        if let bassAim, let moved = VoiceLeading.bassNeighbour(of: from.notes(settings), by: bassAim, in: settings.key) {
            return moved
        }
        return from
    }

    /// The chord the voices move from: where they have walked to, or the
    /// colored chord.
    func voiced(_ settings: DeskSettings) -> DeskChord {
        walked ?? colored(settings)
    }

    /// The chord the degree, the ring or a favorite, and the compass make.
    func colored(_ settings: DeskSettings) -> DeskChord {
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

    /// The chord R3 at rest goes back to: the chord before the compass's
    /// step, or with none the plain chord; nil when it is plain already.
    public func resetsTo(_ settings: DeskSettings) -> DeskChord? {
        var back = self
        back.compassAim = nil
        back.favoriteAim = nil
        back.aim = nil
        back.voiceAim = nil
        back.bassAim = nil
        if back.walked != nil {
            back.walked = nil
        } else if back.keptStep != nil {
            back.keptStep = nil
        } else if back.kept != nil || back.keptFavorite != nil {
            back.kept = nil
            back.keptFavorite = nil
        } else {
            return nil
        }
        return back.chord(settings)
    }

    // MARK: – The voices

    /// The right stick on the upper voices: a lean plays the move, a flick
    /// takes it, R3 while leaning takes it too; the outer ring moves each
    /// voice two semitones.
    private mutating func stepVoices(_ input: PadInput, _ settings: DeskSettings) -> [DeskEffect] {
        var out: [DeskEffect] = []
        for event in voices.step(input.frame.right, gate: VoiceLeading.gate, at: input.time) {
            lb.use()
            if case .flick = event, let move = voiceAim, let next = move.chord(from: voiced(settings), settings, bass: false) {
                walked = next
                out.append(.rumble(.bump))
            }
        }
        if let direction = voices.target {
            let band = RadialBands.two.band(input.frame.right.radius, from: voiceBand)
            if voiceBand != nil, band != voiceBand { out.append(.rumble(.tick)) }
            voiceBand = band
            let move = VoiceMove(direction: direction, shell: band + 1)
            let next = move.chord(from: voiced(settings), settings, bass: false)
            voiceAim = next == nil ? nil : move
            if input.pressed(.r3), let next {
                walked = next
                voiceAim = nil
            }
        } else {
            voiceBand = nil
            voiceAim = nil
        }
        return out
    }

    /// The left stick on the bass, up and down, as the right is on the upper voices.
    private mutating func stepBass(_ input: PadInput, _ settings: DeskSettings) -> [DeskEffect] {
        var out: [DeskEffect] = []
        for event in bass.step(input.frame.left, gate: VoiceLeading.bassGate, at: input.time) {
            lb.use()
            if case .flick = event, let move = bassAim, let next = move.chord(from: voiced(settings), settings, bass: true) {
                walked = next
                out.append(.rumble(.bump))
            }
        }
        if let direction = bass.target {
            let band = RadialBands.two.band(input.frame.left.radius, from: bassBand)
            if bassBand != nil, band != bassBand { out.append(.rumble(.tick)) }
            bassBand = band
            let move = VoiceMove(direction: direction, shell: band + 1)
            bassAim = move.chord(from: voiced(settings), settings, bass: true) == nil ? nil : move
        } else {
            bassBand = nil
            bassAim = nil
        }
        return out
    }

    private mutating func letGoOfVoices() {
        voices.reset()
        bass.reset()
        voiceAim = nil
        bassAim = nil
        voiceBand = nil
        bassBand = nil
    }

    /// The moves of the upper voices from the chord the voices are on, the
    /// inner shell (a semitone) and the outer (two), clockwise from up; nil
    /// where a move crosses voices, and dimmed where it is not consonant.
    public func voiceTargets(_ settings: DeskSettings) -> (inner: [Target?], outer: [Target?]) {
        let from = voiced(settings)
        let notes = from.notes(settings)
        func targets(_ shell: Int) -> [Target?] {
            VoiceLeading.moves.indices.map { direction in
                let move = VoiceMove(direction: direction, shell: shell)
                guard VoiceLeading.moved(notes, by: move) != nil else { return nil }
                let bearing = VoiceLeading.gate.bearings[direction]
                guard let chord = VoiceLeading.neighbour(of: notes, by: move, in: settings.key) else {
                    return Target(bearing: bearing, name: "·", detail: VoiceLeading.names[direction], isHidden: true)
                }
                return Target(bearing: bearing, name: chord.name, detail: shell == 1 ? VoiceLeading.names[direction] : "",
                              fit: chord.fit(in: settings.key), isAimed: move == voiceAim)
            }
        }
        return (targets(1), targets(2))
    }

    /// The bass's moves: up a semitone and two, then down a semitone and two.
    public func bassTargets(_ settings: DeskSettings) -> [Target?] {
        let notes = voiced(settings).notes(settings)
        return [(0, 1), (0, 2), (1, 1), (1, 2)].map { direction, shell in
            let move = VoiceMove(direction: direction, shell: shell)
            guard VoiceLeading.bassMoved(notes, by: move) != nil else { return nil }
            let arrow = direction == 0 ? "↑" : "↓"
            let detail = "bass " + String(repeating: arrow, count: shell)
            guard let chord = VoiceLeading.bassNeighbour(of: notes, by: move, in: settings.key) else {
                return Target(bearing: direction == 0 ? 0 : 180, name: "·", detail: detail, isHidden: true)
            }
            return Target(bearing: direction == 0 ? 0 : 180, name: chord.name, detail: detail,
                          fit: chord.fit(in: settings.key), isAimed: move == bassAim)
        }
    }

    public func degreeTargets(_ settings: DeskSettings) -> [Target] {
        DeskCore.degreeTargets(chosen: degree, sounding: line.isSounding ? line.chord : nil, settings: settings)
    }

    /// The ring's cells for the degree chosen, ring by ring (inside out),
    /// each sector darkest first.
    public func ringTargets(_ settings: DeskSettings) -> [[Target]] {
        let pie = settings.ring(degree, near: struck)
        let sounding = line.isSounding ? line.chord : nil
        return RingPie.heights(extended: isExtended).map { height in
            pie.sectors.map { sector in
                let cell = RingCell(mode: sector.mode, height: height)
                let chord = DeskChord(key: settings.key, degree: degree, color: pie.color(of: cell))
                return Target(bearing: sector.bearing, name: chord.name, detail: sector.mode.displayName,
                              fit: chord.fit(in: settings.key), isNear: chord.isOneStep(from: sounding),
                              isAimed: cell == aim, isKept: cell == kept, isHidden: !pie.allows(cell))
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
        let from = base.colored(settings)
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
        legend[.button(.lb)] = "Tap: key a 5th down · long-press: compass " + (compassLatched ? "off" : "on")
        legend[.button(.rb)] = "Tap: key a 5th up · hold: to 13th"
        legend[.button(.l3)] = "Ring: \(settings.ringArrangement.name) → next"
        legend[.button(.r3)] = resetsTo(settings).map { "Keep aimed · at rest: back to \($0.name)" } ?? "Keep the cell aimed"
        if isOnCompass {
            legend[.button(.l3)] = "LB layer: \(settings.lbLayer.name) → " + (settings.lbLayer == .compass ? "Voices" : "Compass")
        }
        if isOnVoices {
            legend[.leftStick] = "Bass ↑ ↓: flick takes, hold plays"
            legend[.rightStick] = "Voices: ↕ top, ↔ middle, diagonals both; outer ring two semitones"
        }
        return legend
    }
}

extension VoiceMove {
    /// The consonant chord this move makes from `chord`'s notes, if there is one.
    func chord(from chord: DeskChord, _ settings: DeskSettings, bass: Bool) -> DeskChord? {
        let notes = chord.notes(settings)
        return bass ? VoiceLeading.bassNeighbour(of: notes, by: self, in: settings.key)
            : VoiceLeading.neighbour(of: notes, by: self, in: settings.key)
    }
}
