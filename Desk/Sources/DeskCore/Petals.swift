import MusicTheoryCore

/// Model 2, Petals and depth: strike with the face buttons, so rhythm is
/// crisp, and bend the mode with the triggers. The left stick chooses the
/// degree; the face button pressed strikes it at one of four stack heights,
/// laid out as a diamond rising clockwise from A; LT darkens the mode a
/// sector at a time and RT brightens it. It is the color ring again, read
/// on other surfaces: its bands on the buttons, its sectors on the triggers.
///
/// The diamond on screen always shows the four chords the buttons would
/// strike, at the triggers' depth now, so a change is read before it is
/// struck.
public struct Petals: Layout {
    /// A face button's chord: a height, or with LB a mark.
    public enum Petal: Hashable, Sendable {
        case height(StackHeight)
        case mark(Mark)
    }

    /// The four marks LB puts on the buttons: the joystick's staples, each a
    /// step from the triad.
    public enum Mark: String, CaseIterable, Sendable {
        case sus4, sixth, add9, raisedFifth

        public var name: String {
            switch self {
            case .sus4: "▲3 sus4"
            case .sixth: "+6"
            case .add9: "+9"
            case .raisedFifth: "▲5"
            }
        }

        func applied(to triad: ChordTones) -> ChordTones {
            let tones = triad.pitchClasses
            switch self {
            case .sus4: return ChordTones(tones.filter { $0 != 3 && $0 != 4 } + [5])
            case .sixth: return ChordTones(tones + [9])
            case .add9: return ChordTones(tones + [2])
            case .raisedFifth: return ChordTones(tones.map { (6...7).contains($0) ? $0 + 1 : $0 })
            }
        }
    }

    /// The buttons in the diamond, rising clockwise from the bottom.
    public static let diamond: [PadButton] = [.a, .x, .y, .b]
    static let heights: [PadButton: StackHeight] = [.a: .triad, .x: .seventh, .y: .ninth, .b: .eleventh]
    static let marks: [PadButton: Mark] = [.a: .sus4, .x: .add9, .y: .raisedFifth, .b: .sixth]

    public private(set) var degree = Degree.I
    private var degreeSector: Int? = DegreePie.sector(of: .I)
    /// How far each trigger is pulled, in sectors.
    public private(set) var darker = 0
    public private(set) var brighter = 0
    /// The face buttons held, the most recent last: it is the one heard.
    private var presses: [(button: PadButton, petal: Petal)] = []
    public private(set) var holds = false
    public private(set) var line = ChordLine()
    public private(set) var arpeggio: ArpeggioRate?
    /// The voicing the right stick bends to, and whether it has been kept
    /// and so is not bent again until the stick comes back.
    public private(set) var bend = (octaves: 0, roll: 0)
    private var bendKept = false
    public private(set) var isMarking = false
    public private(set) var isOnEffects = false

    public init() {}

    public static func == (a: Petals, b: Petals) -> Bool {
        a.degree == b.degree && a.darker == b.darker && a.brighter == b.brighter
            && a.presses.map(\.button) == b.presses.map(\.button) && a.presses.map(\.petal) == b.presses.map(\.petal)
            && a.holds == b.holds && a.line == b.line && a.arpeggio == b.arpeggio && a.bend == b.bend
            && a.bendKept == b.bendKept && a.isMarking == b.isMarking && a.isOnEffects == b.isOnEffects
    }

    /// Sectors from the degree's own mode: the deeper trigger wins.
    public var shift: Int { brighter > darker ? brighter : -darker }

    public mutating func step(_ input: PadInput, settings: inout DeskSettings) -> [DeskEffect] {
        var out: [DeskEffect] = []
        let time = input.time
        isMarking = input.isDown(.lb)
        isOnEffects = input.isDown(.rb)

        // The d-pad: the key round the circle of fifths, and its scale.
        if input.pressed(.left) { settings.moveKey(byFifths: -1) }
        if input.pressed(.right) { settings.moveKey(byFifths: 1) }
        if input.pressed(.up) { settings.moveScale(by: 1) }
        if input.pressed(.down) { settings.moveScale(by: -1) }
        if input.pressed(.l3) {
            holds.toggle()
            if !holds, presses.isEmpty { out += line.release() }
        }

        degreeSector = DegreePie.gate.select(input.frame.left, from: degreeSector)
        if let degreeSector, input.frame.left.radius >= PieGate.rest { degree = DegreePie.degree(at: degreeSector) }

        // The triggers: darker and brighter, a detent felt at each sector.
        let dark = TriggerSteps.three.step(input.frame.leftTrigger, from: darker)
        let bright = TriggerSteps.three.step(input.frame.rightTrigger, from: brighter)
        if dark != darker || bright != brighter { out.append(.rumble(.tick)) }
        darker = dark
        brighter = bright

        // The right stick: the voicing bent while it leans, R3 keeps it.
        let right = input.frame.right
        if right.radius < PieGate.rest { bendKept = false }
        let leaned = bendKept ? (octaves: 0, roll: 0) : Self.bend(of: right)
        if input.pressed(.r3), leaned != (0, 0) {
            settings.moveOctave(by: leaned.octaves)
            settings.roll(by: leaned.roll)
            bendKept = true
            out.append(.rumble(.bump))
        }
        bend = bendKept ? (0, 0) : leaned

        // The face buttons: a petal each, or on RB the effects.
        for button in Self.diamond {
            if input.pressed(button) {
                if isOnEffects {
                    out += effect(button, settings: &settings, at: time)
                } else {
                    let petal: Petal = isMarking ? .mark(Self.marks[button]!) : .height(Self.heights[button]!)
                    presses.append((button, petal))
                    out += line.strike(chord(petal, settings), level: 0.8, settings: settings, at: time)
                }
            }
            if input.released(button), let at = presses.firstIndex(where: { $0.button == button }) {
                presses.remove(at: at)
                if presses.isEmpty, !holds { out += line.release() }
            }
        }

        // What sounds follows the hands: the press heard is the latest.
        if let petal = presses.last?.petal {
            out += line.change(to: chord(petal, settings), settings: settings)
        } else if let held = line.chord, line.isSounding {
            out += line.change(to: DeskChord(key: settings.key, degree: degree, color: held.spec.color), settings: settings)
        }
        out += line.bend(octaves: bend.octaves, roll: bend.roll, settings: settings)
        out += line.arpeggiate(arpeggio, settings: settings, at: time)
        out += line.tick(settings, at: time)
        return out
    }

    /// RB's layer: A and X the arpeggio, Y voice leading, B hold.
    private mutating func effect(_ button: PadButton, settings: inout DeskSettings, at time: Double) -> [DeskEffect] {
        switch button {
        case .a:
            arpeggio = arpeggio == nil ? .eighth : nil
        case .x:
            let rates = ArpeggioRate.allCases
            arpeggio = rates[((rates.firstIndex(of: arpeggio ?? .quarter) ?? 0) + 1) % rates.count]
        case .y:
            settings.voiceLeading.toggle()
        case .b:
            holds.toggle()
            if !holds, presses.isEmpty { return line.release() + [.rumble(.tick)] }
        default:
            break
        }
        return [.rumble(.tick)]
    }

    public mutating func releaseAll() -> [DeskEffect] {
        presses = []
        holds = false
        return line.release()
    }

    /// The voicing a stick at `stick` bends to: across is the inversion, up
    /// and down the octave.
    static func bend(of stick: Stick) -> (octaves: Int, roll: Int) {
        func steps(_ value: Double, _ edges: [Double]) -> Int {
            let count = edges.filter { abs(value) >= $0 }.count
            return value < 0 ? -count : count
        }
        return (steps(stick.y, [0.6]), steps(stick.x, [0.45, 0.9]))
    }

    /// The chord `petal` strikes now.
    public func chord(_ petal: Petal, _ settings: DeskSettings) -> DeskChord {
        let pie = settings.ring(degree)
        let mode = pie.mode(steps: shift)
        switch petal {
        case .height(let height):
            return DeskChord(key: settings.key, degree: degree, color: pie.color(of: RingCell(mode: mode, height: height)))
        case .mark(let mark):
            let triad = DeskChord(key: settings.key, degree: degree,
                                  color: pie.color(of: RingCell(mode: mode, height: .triad)))
            return DeskChord(key: settings.key, degree: degree, color: .tones(mark.applied(to: triad.tones)))
        }
    }

    // MARK: – What the screen shows

    public func degreeTargets(_ settings: DeskSettings) -> [Target] {
        DeskCore.degreeTargets(chosen: degree, sounding: line.isSounding ? line.chord : nil, settings: settings)
    }

    /// The diamond: what each face button would strike now, in `diamond`'s
    /// order.
    public func petalTargets(_ settings: DeskSettings) -> [Target] {
        let heard = presses.last?.button
        return Self.diamond.enumerated().map { index, button in
            let petal: Petal = isMarking ? .mark(Self.marks[button]!) : .height(Self.heights[button]!)
            let chord = chord(petal, settings)
            let detail: String
            switch petal {
            case .height(let height): detail = "\(button.name) · \(height.displayName)"
            case .mark(let mark): detail = "\(button.name) · \(mark.name)"
            }
            return Target(bearing: 180 + Double(index) * 90, name: chord.name, detail: detail,
                          fit: chord.fit(in: settings.key), isAimed: button == heard)
        }
    }

    /// The mode at each depth either way, darkest first, for the triggers'
    /// scale.
    public func depthTargets(_ settings: DeskSettings) -> [Target] {
        let height = presses.last.flatMap { press -> StackHeight? in
            if case .height(let height) = press.petal { return height } else { return nil }
        } ?? .seventh
        let pie = settings.ring(degree)
        return (-3...3).map { steps in
            guard pie.reaches(steps) else {
                return Target(bearing: Double(steps), name: "—", detail: "past the ring")
            }
            let mode = pie.mode(steps: steps)
            let chord = DeskChord(key: settings.key, degree: degree, color: pie.color(of: RingCell(mode: mode, height: height)))
            return Target(bearing: Double(steps), name: chord.name, detail: mode.displayName,
                          fit: chord.fit(in: settings.key), isAimed: steps == pie.clamped(shift))
        }
    }

    public func legend(_ settings: DeskSettings) -> Legend {
        var legend = commonLegend(settings, voicing: false)
        legend[.button(.left)] = "Key a 5th down"
        legend[.button(.right)] = "Key a 5th up"
        legend[.button(.up)] = "Next scale"
        legend[.button(.down)] = "Scale before"
        legend[.leftStick] = "Degree · \(numeral(degree, in: settings.key))"
        legend[.rightStick] = "Bend voicing: ↔ inversion, ↕ octave"
        legend[.button(.r3)] = "Keep the bend"
        legend[.leftTrigger] = "Darker by \(darker)"
        legend[.rightTrigger] = "Brighter by \(brighter)"
        legend[.button(.l3)] = "Hold " + (holds ? "on" : "off")
        legend[.button(.lb)] = "Hold: marks on the buttons"
        legend[.button(.rb)] = "Hold: effects on the buttons"
        if isOnEffects {
            legend[.button(.a)] = "Arpeggio " + (arpeggio == nil ? "on" : "off")
            legend[.button(.x)] = "Arpeggio rate " + (arpeggio?.name ?? "")
            legend[.button(.y)] = "Voice leading " + (settings.voiceLeading ? "off" : "on")
            legend[.button(.b)] = "Hold " + (holds ? "off" : "on")
        } else {
            for target in petalTargets(settings) {
                let button = Self.diamond[Int((target.bearing - 180) / 90)]
                legend[.button(button)] = target.name
            }
        }
        return legend
    }
}
