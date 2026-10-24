import Foundation

/// A button of a game controller, by where it is: a controller of another
/// make has the same buttons under other names.
///
/// A button is a key (`key`), so a controller's buttons play by a
/// `KeyboardMap` as a computer keyboard's keys do. The numbers are saved in
/// that map, and none is the keyboard's Escape or Delete.
enum GamepadButton: Int, CaseIterable, Sendable {
    case a = 1, b, x, y
    case leftShoulder, rightShoulder, leftTrigger, rightTrigger
    case up, down, left, right
    case menu, options
    /// The sticks, pressed in.
    case leftStick, rightStick

    var name: String {
        switch self {
        case .a:             return "A"
        case .b:             return "B"
        case .x:             return "X"
        case .y:             return "Y"
        case .leftShoulder:  return "L1"
        case .rightShoulder: return "R1"
        case .leftTrigger:   return "L2"
        case .rightTrigger:  return "R2"
        case .up:            return "↑"
        case .down:          return "↓"
        case .left:          return "←"
        case .right:         return "→"
        case .menu:          return "Menu"
        case .options:       return "Options"
        case .leftStick:     return "L3"
        case .rightStick:    return "R3"
        }
    }

    var key: KeyboardKey { KeyboardKey(code: rawValue, name: name) }
}

extension KeyboardMap {
    /// A game controller's buttons to start with: the chords on A, B, X and
    /// Y (I to IV) and the d-pad's up, right and down (V to vii°), loop on
    /// R1, solo on L1, and play and stop on Menu. The left stick is the
    /// compass, which no map says (`GamepadStick`).
    static let gamepad: KeyboardMap = {
        var keys: [KeyboardAction: KeyboardKey] = [:]
        let chords: [GamepadButton] = [.a, .b, .x, .y, .up, .right, .down]
        for (degree, button) in zip(Degree.allCases, chords) {
            keys[.chord(degree)] = button.key
        }
        keys[.button(.loop)] = GamepadButton.rightShoulder.key
        keys[.button(.solo)] = GamepadButton.leftShoulder.key
        keys[.button(.playStop)] = GamepadButton.menu.key
        return KeyboardMap(keys: keys)
    }()
}

/// A game controller's stick as the step compass: which of its four kinds
/// of step the stick is pushed towards, each its first choice (up adds a
/// tone, right raises one, left lowers one, down takes one away).
enum GamepadStick {
    /// How far out a kind starts, of the stick's whole reach, and how far
    /// in it ends: a stick resting at the edge of the middle cannot flicker
    /// in and out of it.
    static let reach = 0.5
    static let rest = 0.35
    /// How far past the line between two kinds the stick has to turn to
    /// leave the one it is in, in degrees.
    static let hold = 6.0

    /// The kind a stick at (`x`, `y`) is pushed towards, each from -1 to 1
    /// with right and up positive, given the one it was at; nil in the
    /// middle.
    static func kind(x: Double, y: Double, from last: ColorStepKind?) -> ColorStepKind? {
        let distance = (x * x + y * y).squareRoot()
        guard distance >= (last == nil ? reach : rest) else { return nil }
        let angle = atan2(y, x) * 180 / .pi
        if let last, turn(from: last, to: angle) <= 45 + hold { return last }
        return ColorStepKind.allCases.min { turn(from: $0, to: angle) < turn(from: $1, to: angle) }
    }

    /// The way `kind` points, in degrees from the right.
    private static func angle(of kind: ColorStepKind) -> Double {
        switch kind {
        case .raise:    return 0
        case .add:      return 90
        case .lower:    return 180
        case .takeAway: return -90
        }
    }

    /// How many degrees `angle` is from the way `kind` points.
    private static func turn(from kind: ColorStepKind, to angle: Double) -> Double {
        let difference = abs(angle - Self.angle(of: kind))
        return min(difference, 360 - difference)
    }
}
