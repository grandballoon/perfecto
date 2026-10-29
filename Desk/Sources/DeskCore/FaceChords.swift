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

    /// What the hands ask for: the latest press with a chord in this layer.
    private struct Wanted: Equatable, Sendable {
        let button: PadButton
        let degree: Degree
    }

    public var map: Map
    /// Whether LT is held: the second layer.
    public private(set) var isLayered = false
    /// The face buttons held, the most recent last.
    public private(set) var held: [PadButton] = []
    /// What was last struck, or refused: a chord is struck once for it.
    private var struck: Wanted?
    public private(set) var line = ChordLine()

    public init(map: Map = .standard) {
        self.map = map
    }

    /// The button and degree heard now, if one is.
    public var heard: (button: PadButton, degree: Degree)? {
        guard line.isSounding, let struck else { return nil }
        return (struck.button, struck.degree)
    }

    private var wanted: Wanted? {
        for press in held.reversed() {
            if let degree = map.degree(press, layered: isLayered) { return Wanted(button: press, degree: degree) }
        }
        return nil
    }

    public mutating func step(_ input: PadInput, settings: inout DeskSettings) -> [DeskEffect] {
        var out: [DeskEffect] = []
        if voicingPad(input, settings: &settings) { out += line.revoice(settings) }

        let layered = Self.layerTrigger.step(input.frame.leftTrigger, from: isLayered ? 1 : 0) == 1
        if layered != isLayered { out.append(.rumble(.tick)) }
        isLayered = layered

        for button in Self.faces {
            if input.pressed(button) { held.append(button) }
            if input.released(button) { held.removeAll { $0 == button } }
        }

        // What sounds is what the hands ask for now: a new press, a press let
        // go and LT pulled or let go are each a change of chord, and nothing
        // held is silence.
        let next = wanted
        if next != struck {
            struck = next
            if let next {
                let chord = DeskChord(key: settings.key, degree: next.degree)
                if let why = settings.consonance.refusal(of: chord, in: settings.key) {
                    out.append(.refuse(why))
                    out += line.release()
                } else {
                    out += line.strike(chord, level: 0.8, settings: settings, at: input.time)
                }
            } else {
                out += line.release()
            }
        }
        return out
    }

    public mutating func releaseAll() -> [DeskEffect] {
        held = []
        struck = nil
        return line.release()
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
        legend[.leftTrigger] = isLayered ? "Let go: \(other)" : "Hold: \(other)"
        return legend
    }
}
