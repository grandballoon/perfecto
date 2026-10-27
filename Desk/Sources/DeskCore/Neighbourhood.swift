import MusicTheoryCore

/// Model 3, the neighbourhood: no chord is chosen by name. The screen is
/// centred on the chord sounding, and round it, at the right stick's eight
/// directions, are the chords one step away, by a lens the bumpers choose.
/// A flick moves there and strikes it; a lean held plays it while it is held
/// and comes back. Every move offered is a note, or one rule, from where the
/// music is, so consonance is the default and the theory is the layout.
public struct Neighbourhood: Layout {
    /// What "one step" means.
    public enum Lens: String, CaseIterable, Sendable {
        /// The colors of this degree a step away: a tone added (up), raised
        /// (right), taken away (down) or lowered (left).
        case color
        /// The triads a voice-leading move away: the Tonnetz's flips and
        /// their nearest compounds.
        case tonnetz
        /// The key's other degrees, by the cycle of thirds: those sharing
        /// two notes to either side, the fifths above them.
        case degrees

        public var name: String {
            switch self {
            case .color: "Color"
            case .tonnetz: "Tonnetz"
            case .degrees: "Degrees"
            }
        }
    }

    /// A neighbour: the chord, and the move that reaches it.
    public struct Neighbour: Equatable, Sendable {
        public let chord: DeskChord
        public let move: String
    }

    public private(set) var centre = DeskChord(key: Key(root: .C, scale: .major), degree: .I)
    public private(set) var lens = Lens.color
    /// The chords moved through, and where along them the centre is.
    public private(set) var path: [DeskChord] = []
    public private(set) var pathIndex = -1
    /// Eight chords kept to come back to.
    public private(set) var palette: [DeskChord?] = Array(repeating: nil, count: 8)
    /// The neighbour or bookmark being listened to while the stick leans.
    public private(set) var audition: Int?
    public private(set) var line = ChordLine()
    public private(set) var isOnPalette = false

    private var gesture = StickGesture()
    private var wasSounding = false
    private var swell = 0.8
    private var brightness = 1.0
    /// The left stick walks the path a step each time it is pushed aside.
    private var pathArmed = true

    public static let gate = PieGate.even(8)

    public init() {}

    public mutating func step(_ input: PadInput, settings: inout DeskSettings) -> [DeskEffect] {
        var out: [DeskEffect] = []
        let time = input.time
        if path.isEmpty || centre.key != settings.key && path.count == 1 && !line.isSounding {
            centre = DeskChord(key: settings.key, degree: .I)
            path = [centre]
            pathIndex = 0
        }

        if input.pressed(.b) { out += line.release() }
        if input.pressed(.a) { out += line.strike(centre, level: swell, brightness: brightness, settings: settings, at: time) }
        if input.pressed(.x) { out += move(to: DeskChord(key: settings.key, degree: .I), settings, at: time) }
        if input.pressed(.lb) || input.pressed(.rb) {
            let lenses = Lens.allCases
            let at = lenses.firstIndex(of: lens)! + (input.pressed(.rb) ? 1 : -1)
            lens = lenses[(at % lenses.count + lenses.count) % lenses.count]
            out += endAudition(settings)
            out.append(.rumble(.tick))
        }
        if input.pressed(.l3) {
            if let free = palette.firstIndex(of: nil) {
                palette[free] = centre
            } else {
                palette = Array(palette.dropFirst()) + [centre]
            }
            out.append(.rumble(.tick))
        }
        if voicingPad(input, settings: &settings) { out += line.revoice(settings) }

        // The left stick walks back and forward along the path.
        let left = input.frame.left
        if left.radius < 0.3 { pathArmed = true }
        if pathArmed, abs(left.x) > 0.7, abs(left.x) > abs(left.y) {
            pathArmed = false
            let next = pathIndex + (left.x > 0 ? 1 : -1)
            if path.indices.contains(next) {
                pathIndex = next
                centre = path[next]
                out += line.strike(centre, level: swell, brightness: brightness, settings: settings, at: time)
                out.append(.rumble(.bump))
            }
        }

        // The right stick: a neighbour, or with Y held a bookmark.
        if input.pressed(.y) || input.released(.y) { out += endAudition(settings) }
        isOnPalette = input.isDown(.y)
        let targets = isOnPalette ? palette : neighbours(settings).map { $0?.chord }
        for event in gesture.step(input.frame.right, gate: Self.gate, at: time) {
            switch event {
            case .aim(let index):
                out += endAudition(settings)
                guard let chord = targets[index] else { continue }
                wasSounding = line.isSounding
                audition = index
                out += line.isSounding ? line.change(to: chord, settings: settings)
                    : line.strike(chord, level: swell, brightness: brightness, settings: settings, at: time)
            case .flick(let index):
                audition = nil
                guard let chord = targets[index] else { continue }
                out += move(to: chord, settings, at: time)
            case .lift:
                out += endAudition(settings)
            }
        }
        if input.pressed(.r3), let audition, let chord = targets[audition] {
            self.audition = nil
            out += move(to: chord, settings, at: time)
        }

        // The triggers: RT swells, LT darkens.
        let level = input.frame.rightTrigger > 0.04 ? 0.2 + 0.8 * input.frame.rightTrigger : 0.8
        let dark = 1 - 0.75 * input.frame.leftTrigger
        swell = level
        brightness = dark
        out += line.shape(level: level, brightness: dark)
        out += line.tick(settings, at: time)
        return out
    }

    /// Makes `chord` the centre, on the path after where the centre was,
    /// and strikes it.
    private mutating func move(to chord: DeskChord, _ settings: DeskSettings, at time: Double) -> [DeskEffect] {
        centre = chord
        path = Array(path.prefix(pathIndex + 1)) + [chord]
        pathIndex = path.count - 1
        return line.strike(chord, level: swell, brightness: brightness, settings: settings, at: time) + [.rumble(.bump)]
    }

    /// Lets go of a neighbour listened to: back to the centre if it was
    /// sounding, or to silence.
    private mutating func endAudition(_ settings: DeskSettings) -> [DeskEffect] {
        guard audition != nil else { return [] }
        audition = nil
        return wasSounding ? line.change(to: centre, settings: settings) : line.release()
    }

    public mutating func releaseAll() -> [DeskEffect] {
        gesture.reset()
        audition = nil
        return line.release()
    }

    // MARK: – The lenses

    /// The neighbours at the stick's eight directions, clockwise from up;
    /// nil where the lens has none.
    public func neighbours(_ settings: DeskSettings) -> [Neighbour?] {
        switch lens {
        case .color:
            return CompassPie.places.indices.map { index in
                CompassPie.chord(at: index, from: centre, ranking: settings.ranking).map {
                    Neighbour(chord: $0, move: CompassPie.edit(at: index, from: centre, ranking: settings.ranking) ?? "")
                }
            }
        case .tonnetz:
            let triad = Triad(centre)
            return Triad.Move.allCases.map { move in
                let next = triad.applying(move)
                return Neighbour(chord: DeskChord(root: next.root, tones: next.tones, in: settings.key), move: move.name)
            }
        case .degrees:
            let home = settings.key
            let degree = centre.key == home ? centre.spec.degree : home.degree(of: centre.root) ?? .I
            let around: [Int?] = [nil, 2, 1, 3, nil, -3, -1, -2]
            let names = [2: "5th up", 1: "3rd up", 3: "6th up", -3: "6th down", -1: "3rd down", -2: "5th down"]
            return around.map { steps in
                steps.map { steps in
                    Neighbour(chord: DeskChord(key: home, degree: DiatonicCycle.degree(steps, from: degree)),
                              move: names[steps]!)
                }
            }
        }
    }

    // MARK: – What the screen shows

    public func neighbourTargets(_ settings: DeskSettings) -> [Target?] {
        if isOnPalette {
            return palette.enumerated().map { index, chord in
                chord.map { Target(bearing: Self.gate.bearings[index], name: $0.name, detail: "bookmark \(index + 1)",
                                   fit: $0.fit(in: settings.key), isAimed: index == audition) }
            }
        }
        return neighbours(settings).enumerated().map { index, neighbour in
            neighbour.map { Target(bearing: Self.gate.bearings[index], name: $0.chord.name, detail: $0.move,
                                   fit: $0.chord.fit(in: settings.key), isAimed: index == audition) }
        }
    }

    /// What the centre is in the key: its numeral, or borrowed.
    public func centreDetail(_ settings: DeskSettings) -> String {
        if centre.key == settings.key { return numeral(centre.spec.degree, in: settings.key) }
        if let degree = settings.key.degree(of: centre.root), centre.fit(in: settings.key) != .borrowed {
            return numeral(degree, in: settings.key)
        }
        return "borrowed"
    }

    public func legend(_ settings: DeskSettings) -> Legend {
        var legend = commonLegend(settings)
        legend[.rightStick] = isOnPalette ? "Bookmarks: flick jumps, hold listens" : "\(lens.name) lens: flick moves, hold listens"
        legend[.leftStick] = "← → back and forward along the path"
        legend[.rightTrigger] = "Swell"
        legend[.leftTrigger] = "Darker"
        legend[.button(.a)] = "Strike the centre"
        legend[.button(.b)] = "Let go"
        legend[.button(.x)] = "Home: I"
        legend[.button(.y)] = "Hold: bookmarks"
        legend[.button(.lb)] = "Lens before"
        legend[.button(.rb)] = "Next lens"
        legend[.button(.l3)] = "Bookmark the centre"
        legend[.button(.r3)] = "Move to the chord listened to"
        return legend
    }
}

/// A major or minor triad, for the Tonnetz's moves. A chord that is
/// neither is read by its third: minor if it has a minor one, major otherwise.
public struct Triad: Equatable, Sendable {
    public let root: PitchClass
    public let isMajor: Bool

    public init(root: PitchClass, isMajor: Bool) {
        self.root = root
        self.isMajor = isMajor
    }

    init(_ chord: DeskChord) {
        let tones = chord.tones
        self.init(root: chord.root, isMajor: tones.has(4) || !tones.has(3))
    }

    public var tones: ChordTones { ChordTones(isMajor ? [0, 4, 7] : [0, 3, 7]) }

    /// The moves round a triad, clockwise from up as the stick reaches them.
    public enum Move: CaseIterable, Sendable {
        case parallel, relative, dominant, hexatonicUp, nebenverwandt, hexatonicDown, subdominant, leadingTone

        public var name: String {
            switch self {
            case .parallel: "P · parallel"
            case .relative: "R · relative"
            case .dominant: "a 5th up"
            case .hexatonicUp: "PR"
            case .nebenverwandt: "N"
            case .hexatonicDown: "PL"
            case .subdominant: "a 5th down"
            case .leadingTone: "L · leading tone"
            }
        }
    }

    private func moved(_ semitones: Int, major: Bool) -> Triad {
        Triad(root: PitchClass(rawValue: (root.rawValue + semitones + 12) % 12)!, isMajor: major)
    }

    /// The triad sharing two notes with this one and the other third.
    public var p: Triad { moved(0, major: !isMajor) }
    /// The relative: C major's A minor, A minor's C major.
    public var r: Triad { isMajor ? moved(9, major: false) : moved(3, major: true) }
    /// The leading-tone exchange: C major's E minor, E minor's C major.
    public var l: Triad { isMajor ? moved(4, major: false) : moved(8, major: true) }

    public func applying(_ move: Move) -> Triad {
        switch move {
        case .parallel: p
        case .relative: r
        case .leadingTone: l
        case .dominant: moved(7, major: isMajor)
        case .subdominant: moved(5, major: isMajor)
        case .hexatonicUp: p.r
        case .hexatonicDown: p.l
        case .nebenverwandt: r.l.p
        }
    }
}
