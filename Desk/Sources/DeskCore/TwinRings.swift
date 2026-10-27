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
    private var lb = TapOrHold()
    private var rb = TapOrHold()

    public init() {}

    /// Whether RB is extending the ring to the 13th.
    public private(set) var isExtended = false
    /// Whether LB has the right stick on the step compass.
    public private(set) var isOnCompass = false

    public mutating func step(_ input: PadInput, settings: inout DeskSettings) -> [DeskEffect] {
        var out: [DeskEffect] = []
        let time = input.time

        if input.pressed(.b) {
            holds = false
            out += line.release()
        }
        if input.pressed(.y) {
            holds.toggle()
            if !holds, !strike.isHeld, !input.isDown(.a) { out += line.release() }
        }
        if input.pressed(.x) { settings.voiceLeading.toggle() }
        if input.pressed(.l3) || (input.pressed(.r3) && aim == nil && compassAim == nil) {
            kept = nil
            keptStep = nil
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

        // The right stick: the ring, or with LB the compass.
        if isOnCompass {
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
            let gate = RingPie.gate(key: settings.key, degree: degree)
            for event in ring.step(input.frame.right, gate: gate, at: time) {
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
                aim = RingPie.cell(sector: sector, band: next, extended: isExtended, key: settings.key, degree: degree)
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
            out += line.strike(chord(settings), level: 0.8, settings: settings, at: time)
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
        let cell = aim ?? kept
        let color = cell.map { RingPie.color(of: $0, key: settings.key, degree: degree) } ?? .base
        let ringChord = DeskChord(key: settings.key, degree: degree, color: color)
        guard let place = compassAim ?? keptStep else { return ringChord }
        return CompassPie.chord(at: place, from: ringChord, ranking: settings.ranking) ?? ringChord
    }

    // MARK: – What the screen shows

    public func degreeTargets(_ settings: DeskSettings) -> [Target] {
        DeskCore.degreeTargets(chosen: degree, sounding: line.isSounding ? line.chord : nil, settings: settings)
    }

    /// The ring's cells for the degree chosen, ring by ring (inside out),
    /// each sector darkest first.
    public func ringTargets(_ settings: DeskSettings) -> [[Target]] {
        let offsets = RingPie.offsets(key: settings.key, degree: degree)
        let sounding = line.isSounding ? line.chord : nil
        return RingPie.heights(extended: isExtended).map { height in
            offsets.map { offset in
                let cell = RingCell(offset: offset, height: height)
                let chord = DeskChord(key: settings.key, degree: degree,
                                      color: RingPie.color(of: cell, key: settings.key, degree: degree))
                let mode = RingPie.mode(at: offset, key: settings.key, degree: degree)
                return Target(bearing: Double(offset) * RingPie.sectorSpan, name: chord.name,
                              detail: mode?.displayName ?? "", fit: chord.fit(in: settings.key),
                              isNear: chord.isOneStep(from: sounding), isAimed: cell == aim, isKept: cell == kept)
            }
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
        legend[.rightStick] = isOnCompass ? "Step compass: flick keeps, hold plays"
            : isExtended ? "Ring to the 13th: flick keeps, hold plays"
            : "Color ring: flick keeps, hold plays"
        legend[.rightTrigger] = "Strike · pull = swell"
        legend[.leftTrigger] = "Arpeggio " + (ArpeggioRate(rawValue: arpeggioStep)?.name ?? "off")
        legend[.button(.a)] = "Strike"
        legend[.button(.b)] = "Let go"
        legend[.button(.x)] = "Voice leading " + (settings.voiceLeading ? "on" : "off")
        legend[.button(.y)] = "Hold " + (holds ? "on" : "off")
        legend[.button(.lb)] = "Tap: key a 5th down · hold: compass"
        legend[.button(.rb)] = "Tap: key a 5th up · hold: to 13th"
        legend[.button(.l3)] = "Plain color"
        legend[.button(.r3)] = "Keep aimed cell"
        return legend
    }
}
