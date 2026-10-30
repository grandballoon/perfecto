import MusicTheoryCore

/// Face Chords: the key's chords by number on the four face buttons, as a
/// guitarist's chart has them. A always plays I; without LT, B, X and Y play
/// the other major chords and the diminished (IV, V, vii°), and with LT held
/// the minor ones (ii, iii, vi). The map is a value, so a shell can read
/// another from a file.
///
/// What sounds is always the latest face button held, read in the layer LT is
/// in now: pulling or letting go of LT while a button is held is a change of
/// chord as a new press is, and with no button held nothing sounds.
///
/// A second voice can be added (R3), a line of chords of its own over the
/// first: the desk's melody line, in its sound and on its MIDI channel, an
/// octave up. Each press goes to one voice or both, chosen as it is pressed,
/// and each voice sounds the latest button it holds:
///
/// - with one voice, every press is the first's;
/// - with LB held, a press is the second's alone;
/// - with both voices on (LB double-clicked), a press is both's, but with LB
///   held, or with LT pulled at the same moment (either first, within
///   `together`), the second's alone, over what the first is holding.
///
/// A pull of LT that strikes with a face button so is the second voice's: it
/// plays that button's LT chord there, and the first voice reads LT as let go
/// for as long as the pull is held, so it keeps its chord. Every other pull is
/// both voices' layer, as with one. A press already struck on both before the
/// pull came is taken back from the first, which returns to what it held.
public struct FaceChords: Layout {
    /// A degree for each face button, without LT and with it held. A button
    /// a layer leaves out strikes nothing in it.
    public struct Map: Equatable, Sendable {
        public var plain: [PadButton: Degree]
        public var layered: [PadButton: Degree]

        public init(plain: [PadButton: Degree], layered: [PadButton: Degree]) {
            self.plain = plain
            self.layered = layered
        }

        /// A I; B IV, X V, Y vii°; with LT, B ii, X iii, Y vi.
        public static let standard = Map(plain: [.a: .I, .b: .IV, .x: .V, .y: .viiDim],
                                         layered: [.a: .I, .b: .ii, .x: .iii, .y: .vi])

        public func degree(_ button: PadButton, layered isLayered: Bool) -> Degree? {
            (isLayered ? layered : plain)[button]
        }
    }

    /// The buttons where they are on the controller, rising clockwise from
    /// the bottom.
    public static let faces: [PadButton] = [.a, .x, .y, .b]

    /// Where `button` is in the diamond, as a bearing: A at the bottom.
    public static func bearing(_ button: PadButton) -> Double {
        switch button {
        case .a: 180
        case .x: 270
        case .y: 0
        case .b: 90
        default: 0
        }
    }

    /// LT as a switch: on past halfway, held a little either side of it.
    static let layerTrigger = TriggerSteps(edges: [0.5])

    /// Two presses of LB within this many seconds are a double-click.
    public static let doubleClick = 0.3
    /// A face button and LT within this many seconds of each other are struck
    /// together.
    public static let together = 0.08
    /// How far over the first voice the second sounds, in octaves.
    public static let overOctaves = 1

    /// What one voice holds and sounds.
    public struct Voice: Equatable, Sendable {
        /// The face buttons it holds, the most recent last.
        public fileprivate(set) var held: [PadButton] = []
        /// What was last struck, or refused: a chord is struck once for it.
        fileprivate var struck: Struck?
        /// The color it was struck in.
        fileprivate var color = ChordColor.base
        public fileprivate(set) var line: ChordLine

        /// The button and degree it sounds now, if it sounds one.
        public var heard: (button: PadButton, degree: Degree)? {
            guard line.isSounding, let struck else { return nil }
            return (struck.button, struck.degree)
        }
    }

    fileprivate struct Struck: Equatable, Sendable {
        let button: PadButton
        let degree: Degree
    }

    /// A face button pressed, and when: LT pulled soon after, with both
    /// voices on, makes it the second voice's alone.
    private struct Press: Equatable, Sendable {
        let button: PadButton
        let time: Double
    }

    public var map: Map
    /// Whether LT is held: the second layer.
    public private(set) var isLayered = false
    /// The first voice, and the second (silent until it is added).
    public private(set) var voices = [Voice(line: ChordLine(.chord)), Voice(line: ChordLine(.melody))]
    /// Whether the second voice has been added (R3).
    public private(set) var hasSecond = false
    /// Whether a press plays both voices (LB double-clicked).
    public private(set) var isTogether = false
    /// Whether the pull of LT held is the second voice's alone.
    public private(set) var isOverPull = false
    /// When LT was last pulled past halfway.
    private var layeredAt = 0.0
    /// When LB was last pressed, while a second press would be a double-click.
    private var lbPressedAt: Double?
    private var latePresses: [Press] = []
    /// The color each degree's chord is struck in, as the left hand colors
    /// them; a degree not here is plain.
    public var colors: [Degree: ChordColor] = [:]

    public init(map: Map = .standard) {
        self.map = map
    }

    public var line: ChordLine { voices[0].line }

    /// The button and degree the first voice sounds now, if it sounds one.
    public var heard: (button: PadButton, degree: Degree)? { voices[0].heard }

    /// Whether `voice` reads LT as held.
    private func isLayered(_ voice: Int) -> Bool { isLayered && !(voice == 0 && isOverPull) }

    /// What the hands ask `voice` for: its latest press with a chord in its
    /// layer.
    private func wanted(_ voice: Int) -> Struck? {
        for press in voices[voice].held.reversed() {
            if let degree = map.degree(press, layered: isLayered(voice)) { return Struck(button: press, degree: degree) }
        }
        return nil
    }

    /// The voices a face button pressed now goes to.
    private func route(_ input: PadInput) -> [Int] {
        if !hasSecond { return [0] }
        if input.isDown(.lb) { return [1] }
        if !isTogether { return [0] }
        if strikesWithLT(input) { return [1] }
        return [0, 1]
    }

    /// Whether a face button pressed now is struck together with LT, as the
    /// second voice's alone.
    private func strikesWithLT(_ input: PadInput) -> Bool {
        isTogether && isLayered && input.time - layeredAt <= Self.together
    }

    /// Strikes what `voice` is asked for, if it is not what it sounds.
    private mutating func settle(_ voice: Int, settings: DeskSettings, at time: Double) -> [DeskEffect] {
        // What sounds is what the hands ask for now: a new press, a press let
        // go and LT pulled or let go are each a change of chord, and nothing
        // held is silence.
        // A new color on the chord sounding is heard tied, as a change.
        let next = wanted(voice)
        let color = next.flatMap { colors[$0.degree] } ?? .base
        if next == voices[voice].struck, next == nil || color == voices[voice].color { return [] }
        let recolors = next != nil && next == voices[voice].struck && voices[voice].line.isSounding
        voices[voice].struck = next
        voices[voice].color = color
        guard let next else { return voices[voice].line.release() }
        let chord = DeskChord(key: settings.key, degree: next.degree, color: color)
        if let why = settings.consonance.refusal(of: chord, in: settings.key) {
            return [.refuse(why)] + voices[voice].line.release()
        }
        if recolors { return voices[voice].line.change(to: chord, settings: settings) }
        return voices[voice].line.strike(chord, level: 0.8, settings: settings, at: time)
    }

    private mutating func takeAwaySecond() -> [DeskEffect] {
        hasSecond = false
        isTogether = false
        isOverPull = false
        lbPressedAt = nil
        latePresses = []
        voices[1].held = []
        voices[1].struck = nil
        return voices[1].line.release()
    }

    public mutating func step(_ input: PadInput, settings: inout DeskSettings) -> [DeskEffect] {
        var out: [DeskEffect] = []
        let time = input.time
        if voicingPad(input, settings: &settings) {
            for voice in voices.indices { out += voices[voice].line.revoice(settings) }
        }

        if input.pressed(.r3) {
            if hasSecond {
                out += takeAwaySecond()
            } else {
                hasSecond = true
                out += voices[1].line.bend(octaves: Self.overOctaves, roll: 0, settings: settings)
            }
            out.append(.rumble(.bump))
        }
        if hasSecond, input.pressed(.lb) {
            if let lbPressedAt, time - lbPressedAt <= Self.doubleClick {
                isTogether.toggle()
                self.lbPressedAt = nil
                out.append(.rumble(.bump))
            } else {
                lbPressedAt = time
            }
        }

        let layered = Self.layerTrigger.step(input.frame.leftTrigger, from: isLayered ? 1 : 0) == 1
        if layered != isLayered { out.append(.rumble(.tick)) }
        if layered, !isLayered {
            layeredAt = time
            // LT just after a face button, with both voices on: they were
            // struck together, so the pull and the press are the second
            // voice's alone.
            for press in latePresses where isTogether && time - press.time <= Self.together {
                voices[0].held.removeAll { $0 == press.button }
                isOverPull = true
            }
        }
        if !layered { isOverPull = false }
        isLayered = layered
        latePresses.removeAll { time - $0.time > Self.together }

        for button in Self.faces {
            if input.pressed(button) {
                for voice in route(input) { voices[voice].held.append(button) }
                if strikesWithLT(input) { isOverPull = true } else { latePresses.append(Press(button: button, time: time)) }
            }
            if input.released(button) {
                for voice in voices.indices { voices[voice].held.removeAll { $0 == button } }
                latePresses.removeAll { $0.button == button }
            }
        }

        for voice in voices.indices { out += settle(voice, settings: settings, at: time) }
        return out
    }

    public mutating func releaseAll() -> [DeskEffect] {
        var out: [DeskEffect] = []
        for voice in voices.indices {
            voices[voice].held = []
            voices[voice].struck = nil
            out += voices[voice].line.release()
        }
        isOverPull = false
        lbPressedAt = nil
        latePresses = []
        return out
    }

    public func legend(_ settings: DeskSettings) -> Legend {
        var legend = commonLegend(settings)
        for button in Self.faces {
            if let degree = map.degree(button, layered: isLayered) {
                legend[.button(button)] = numeral(degree, in: settings.key) + " · "
                    + DeskChord(key: settings.key, degree: degree).name
            }
        }
        // The chords the other layer brings, in the key's order.
        var others: [Degree] = []
        for button in Self.faces {
            let mine = map.degree(button, layered: isLayered), theirs = map.degree(button, layered: !isLayered)
            if let theirs, mine != theirs, !others.contains(theirs) { others.append(theirs) }
        }
        let other = others.sorted { $0.rawValue < $1.rawValue }.map { numeral($0, in: settings.key) }
            .joined(separator: " ")
        legend[.leftTrigger] = (isLayered ? "Let go: \(other)" : "Hold: \(other)")
            + (isTogether ? " · with a face: voice 2" : "")
        legend[.button(.r3)] = hasSecond ? "Take away voice 2" : "Add a second voice"
        if hasSecond {
            legend[.button(.lb)] = isTogether ? "Hold: voice 2 over · double-click: voice 1"
                : "Hold: voice 2 · double-click: both"
        }
        return legend
    }
}
