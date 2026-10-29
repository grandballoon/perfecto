import DeskCore
import DeskCoreProbe
import Foundation
import MusicTheoryCore
import Testing

/// The C++ desk core (PerfectoDeskCore, through `DeskCoreProbe`) against
/// the Swift one it was ported from: both desks are played with the same
/// controller frames, long runs of them from a seeded chance, and after
/// every frame what each did and what each shows must read the same. The
/// Swift desk is the reference.
@Suite("Desk parity")
struct DeskParityTests {

    /// How many runs, and how many frames each: fewer in a debug build, which
    /// is many times slower here.
    #if DEBUG
    static let runs = 12, frames = 1_500
    #else
    static let runs = 60, frames = 6_000
    #endif

    @Test func longRunsOfFramesPlayTheSame() {
        for run in 0..<Self.runs {
            // Each run starts on a layout of its own, so every one is played
            // from its start as well as reached by Back.
            Self.play(seed: UInt64(run), startingOn: LayoutKind.allCases[run % LayoutKind.allCases.count])
        }
    }

    /// Plays one run: frames from `seed`'s chance, now and then a layout
    /// chosen, the menu toggled or everything let go, as the shell can.
    static func play(seed: UInt64, startingOn layout: LayoutKind) {
        var swift = Desk(catalog: DeskParityText.catalog)
        let probe = pdp_desk_new()!
        defer { pdp_desk_free(probe) }
        var random = SeededRandom(seed: seed)
        var hands = Hands()
        var log: [String] = []

        func compare(_ what: String, _ swiftText: String, _ cxxText: String) -> Bool {
            guard swiftText != cxxText else { return true }
            Issue.record("""
                Run \(seed) differs at \(what).
                Swift:
                \(swiftText)
                C++:
                \(cxxText)
                The frames before it, last first:
                \(log.suffix(12).reversed().joined(separator: "\n"))
                """)
            return false
        }

        guard compare("the choice of \(layout)", DeskParityText.effects(swift.choose(layout)),
                      read { pdp_desk_choose(probe, Int32(LayoutKind.allCases.firstIndex(of: layout)!), $0, $1) })
        else { return }

        for index in 0..<Self.frames {
            let roll = Double.random(in: 0..<1, using: &random)
            let swiftOut: [DeskEffect], cxxOut: String, what: String
            if roll < 0.002 {
                let next = LayoutKind.allCases.randomElement(using: &random)!
                what = "choose \(next)"
                swiftOut = swift.choose(next)
                cxxOut = read { pdp_desk_choose(probe, Int32(LayoutKind.allCases.firstIndex(of: next)!), $0, $1) }
            } else if roll < 0.003 {
                what = "toggleMenu"
                swiftOut = swift.toggleMenu()
                cxxOut = read { pdp_desk_toggle_menu(probe, $0, $1) }
            } else if roll < 0.0035 {
                what = "letGo"
                swiftOut = swift.letGo()
                cxxOut = read { pdp_desk_let_go(probe, $0, $1) }
            } else {
                var frame = hands.next(&random)
                what = "frame \(index): \(frame.described)"
                swiftOut = swift.step(frame.gamepad)
                cxxOut = read { pdp_desk_step(probe, &frame.probe, $0, $1) }
            }
            log.append(what)
            guard compare(what, DeskParityText.effects(swiftOut), cxxOut) else { return }
            // What is shown is the desk's state, and a state that differs
            // stays different, so it is read every few frames: a difference is
            // still found, a frame or two after it began.
            guard index % 4 == 3 || index == Self.frames - 1 else { continue }
            guard compare("what is shown after \(what)", DeskParityText.shown(swift),
                          read { pdp_desk_shown(probe, $0, $1) })
            else { return }
        }
    }

    /// The text a probe call writes, with as much room as it needs.
    static func read(_ call: (UnsafeMutablePointer<CChar>, Int32) -> Int32) -> String {
        var buffer = [CChar](repeating: 0, count: 1 << 14)
        let needed = Int(call(&buffer, Int32(buffer.count)))
        if needed >= buffer.count {
            Issue.record("A probe's text of \(needed) bytes did not fit")
        }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}

/// A player's two hands on the controller, from a seeded chance: buttons
/// pressed and let go, sticks that drift, flick and come back to rest,
/// triggers squeezed slowly or at once, and time that mostly runs at sixty
/// frames a second but now and then stands still for a held press.
struct Hands {
    var time = 0.0
    var buttons: Set<PadButton> = []
    var left = Stick.rest, right = Stick.rest
    var leftAim = Stick.rest, rightAim = Stick.rest
    var leftTrigger = 0.0, rightTrigger = 0.0
    var leftTriggerAim = 0.0, rightTriggerAim = 0.0

    struct Frame {
        var gamepad: GamepadFrame
        var probe: pdp_frame

        var described: String {
            let pad = gamepad
            let held = PadButton.allCases.filter(pad.buttons.contains).map(\.name).joined(separator: " ")
            return String(format: "t %.3f L (%.2f, %.2f) R (%.2f, %.2f) LT %.2f RT %.2f [%@]", pad.time,
                          pad.left.x, pad.left.y, pad.right.x, pad.right.y, pad.leftTrigger, pad.rightTrigger, held)
        }
    }

    mutating func next(_ random: inout SeededRandom) -> Frame {
        time += Double.random(in: 0..<1, using: &random) < 0.02 ? Double.random(in: 0.2...1.5, using: &random) : 1 / 60
        for button in PadButton.allCases {
            // Start and Back change the whole desk, so they are pressed less.
            let chance = button == .start || button == .back ? 0.002 : 0.03
            if Double.random(in: 0..<1, using: &random) < chance { buttons.formSymmetricDifference([button]) }
        }
        func aim(_ random: inout SeededRandom) -> Stick {
            switch Int.random(in: 0..<6, using: &random) {
            case 0, 1: return .rest
            default:
                let bearing = Double.random(in: 0..<360, using: &random) * .pi / 180
                let radius = [1.0, 1, 0.9, 0.6, 0.4][Int.random(in: 0..<5, using: &random)]
                return Stick(x: sin(bearing) * radius, y: cos(bearing) * radius)
            }
        }
        if Double.random(in: 0..<1, using: &random) < 0.04 { leftAim = aim(&random) }
        if Double.random(in: 0..<1, using: &random) < 0.04 { rightAim = aim(&random) }
        // A stick moves most of the way to where it is aimed each frame, or
        // now and then is there at once: a flick.
        func move(_ stick: Stick, to aim: Stick, _ random: inout SeededRandom) -> Stick {
            if Double.random(in: 0..<1, using: &random) < 0.2 { return aim }
            return Stick(x: stick.x + (aim.x - stick.x) * 0.45, y: stick.y + (aim.y - stick.y) * 0.45)
        }
        left = move(left, to: leftAim, &random)
        right = move(right, to: rightAim, &random)
        if Double.random(in: 0..<1, using: &random) < 0.03 { leftTriggerAim = [0, 0, 0.5, 1][Int.random(in: 0..<4, using: &random)] }
        if Double.random(in: 0..<1, using: &random) < 0.03 { rightTriggerAim = [0, 0, 0.5, 1][Int.random(in: 0..<4, using: &random)] }
        let speed = Double.random(in: 0..<1, using: &random) < 0.3 ? 1 : 0.25
        leftTrigger += (leftTriggerAim - leftTrigger) * speed
        rightTrigger += (rightTriggerAim - rightTrigger) * speed

        let gamepad = GamepadFrame(time: time, left: left, right: right, leftTrigger: leftTrigger,
                                   rightTrigger: rightTrigger, buttons: buttons)
        let mask = PadButton.allCases.enumerated().reduce(Int32(0)) {
            buttons.contains($1.element) ? $0 | 1 << $1.offset : $0
        }
        return Frame(gamepad: gamepad,
                     probe: pdp_frame(time: time, leftX: left.x, leftY: left.y, rightX: right.x, rightY: right.y,
                                      leftTrigger: leftTrigger, rightTrigger: rightTrigger, buttons: mask))
    }
}

/// What a desk did and shows, as the text the probe writes for the C++ one
/// (`Tests/DeskCoreProbe/probe.cpp`): the two must be kept in step.
enum DeskParityText {
    /// The sounds both desks are given.
    static let catalog = SoundCatalog([
        .init(name: "Keys", sounds: [.init(id: "electricPiano", name: "Electric Piano"), .init(id: "piano", name: "Piano")]),
        .init(name: "Leads", sounds: [.init(id: "soloLead", name: "Solo Lead"), .init(id: "squareLead", name: "Square Lead"),
                                      .init(id: "saw", name: "Saw")]),
        .init(name: "Pads", sounds: [.init(id: "warmPad", name: "Warm Pad")]),
    ])

    /// A number as C's `%.17g` writes it: every digit, so two that differ in
    /// their last bit read differently.
    static func number(_ value: Double) -> String { String(format: "%.17g", value) }

    static func notes(_ notes: [Int]) -> String { notes.map(String.init).joined(separator: ",") }

    static func index<T: CaseIterable & Equatable>(_ value: T) -> Int {
        T.allCases.firstIndex(of: value)! as! Int
    }

    static func effects(_ effects: [DeskEffect]) -> String {
        effects.map(effect).joined(separator: "\n")
    }

    static func effect(_ effect: DeskEffect) -> String {
        switch effect {
        case let .sound(line, notes, sound, level, brightness, tie):
            return "sound \(line.rawValue) \(Self.notes(notes)) \(sound) \(number(level)) \(number(brightness)) \(tie ? 1 : 0)"
        case let .shape(line, level, brightness, bend):
            return "shape \(line.rawValue) \(number(level)) \(number(brightness)) \(number(bend))"
        case let .silence(line):
            return "silence \(line.rawValue)"
        case let .rumble(rumble):
            return "rumble \(rumble)"
        case let .preview(sound, notes):
            return "preview \(sound) \(Self.notes(notes))"
        case let .saveMIDI(bytes, name):
            return "saveMIDI \(name) " + bytes.map { String(format: "%02x", $0) }.joined()
        case let .refuse(reason):
            return "refuse \(reason)"
        }
    }

    static func shown(_ desk: Desk) -> String {
        var lines = ["layout \(index(desk.layout))"]
        // A legend is a dictionary, so it is written in the order of its
        // controls' names.
        lines += desk.legend.map { "legend \($0.key.name)=\($0.value)" }.sorted()
        lines.append("pinnable " + (desk.pinnable?.name ?? "-"))
        if let menu = desk.menu {
            lines.append("menu \(index(menu.row))")
            if let library = menu.library {
                lines.append("library \(library.line.rawValue) \(library.category) \(library.index)")
            }
        } else {
            lines.append("menu -")
        }
        lines += DeskMenu.Row.allCases.map { "value \($0.name)=\(desk.value(of: $0))" }
        let s = desk.settings
        lines.append("settings \(s.key.root.rawValue) \(index(s.key.scale)) \(s.octave) \(s.inversion.steps)"
                     + " \(s.voiceLeading ? 1 : 0) \(s.chordSound) \(s.lineSound) \(number(s.tempo)) \(index(s.output))"
                     + " \(index(s.ranking)) \(index(s.ringArrangement)) \(index(s.ringOrder)) \(index(s.ringFilter))"
                     + " \(index(s.grid)) \(index(s.lbLayer)) \(index(s.consonance.mode)) \(s.consonance.inKey ? 1 : 0)")
        lines.append("summary \(s.summary) · \(s.voicingName)")
        lines += screen(desk)
        return lines.joined(separator: "\n")
    }

    /// What the layout played draws: every target round its sticks.
    static func screen(_ desk: Desk) -> [String] {
        let s = desk.settings
        func targets(_ name: String, _ targets: [Target?]) -> [String] {
            targets.map { "\(name) " + ($0.map(target) ?? "-") }
        }
        switch desk.layout {
        case .faceChords:
            let faces = desk.faceChords
            let index = { (button: PadButton) in FaceChords.faces.firstIndex(of: button)! }
            return FaceChords.faces.map { button in
                "face \(index(button)) " + (faces.map.degree(button, layered: faces.isLayered).map { numeral($0, in: s.key) } ?? "-")
            } + faces.voices.enumerated().map { voice, line in
                "heard \(voice) " + (line.heard.map { "\(index($0.button)) \(numeral($0.degree, in: s.key))" } ?? "-")
            } + ["voices " + (faces.hasSecond ? "second" : "one") + (faces.isTogether ? " together" : "")
                + (faces.isOverPull ? " over" : "")]
        case .twinRings:
            let rings = desk.twinRings
            let voices = rings.voiceTargets(s)
            return ["resetsTo " + (rings.resetsTo(s)?.name ?? "-")]
                + targets("voice inner", voices.inner) + targets("voice outer", voices.outer)
                + targets("bass", rings.bassTargets(s)) + targets("degree", rings.degreeTargets(s))
                + rings.ringTargets(s).enumerated().flatMap { targets("ring \($0.offset)", $0.element) }
                + targets("favorite", rings.favoriteTargets(s)) + targets("compass", rings.compassTargets(s))
        case .petals:
            let petals = desk.petals
            return targets("degree", petals.degreeTargets(s)) + targets("petal", petals.petalTargets(s))
                + targets("depth", petals.depthTargets(s))
        case .neighbourhood:
            let neighbourhood = desk.neighbourhood
            return targets("neighbour", neighbourhood.neighbourTargets(s))
                + ["centre " + neighbourhood.centreDetail(s)]
        case .twoVoices:
            let voices = desk.twoVoices
            return targets("degree", voices.degreeTargets(s))
                + voices.petals(s).map { "petal \($0.note) \($0.isChordTone ? 1 : 0) \($0.isReachable ? 1 : 0)" }
        case .arranger:
            return targets("degree", desk.arranger.degreeTargets(s))
        }
    }

    static func target(_ t: Target) -> String {
        let fit = t.fit == .inKey ? 0 : t.fit == .tense ? 1 : 2
        return "\(number(t.bearing)) \(t.name)|\(t.detail)|\(fit)"
            + " \(t.isNear ? 1 : 0)\(t.isAimed ? 1 : 0)\(t.isKept ? 1 : 0)\(t.isHidden ? 1 : 0)"
    }
}

/// A chance that starts from the same place each run (SplitMix64).
struct SeededRandom: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
