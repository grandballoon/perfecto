import Foundation

/// What a key of a computer keyboard plays.
enum KeyboardAction: Hashable, Codable, Sendable {
    /// A chord key.
    case chord(Degree)
    /// The joystick pushed one way. Keys held together add up, so up and
    /// right held is up-right, as it is on a key of its own.
    case color(JoystickDirection)
    /// A cell of the solo strip, counted from its low end.
    case solo(cell: Int)
}

/// A key of a computer keyboard: where it is (its HID usage, the same key
/// whatever is printed on it) and what to call it.
struct KeyboardKey: Hashable, Codable, Sendable {
    var code: Int
    var name: String
}

extension KeyboardKey {
    /// Ends the choosing of a key, leaving the action as it was.
    static let escapeCode = 41
    /// Takes an action's key away while one is being chosen for it.
    static let deleteCode = 42

    /// The key at `code`, named by what it types (`characters`, as the
    /// system reports them without modifiers), or by what it is where it
    /// types nothing that can be shown.
    init(code: Int, characters: String) {
        self.code = code
        name = Self.names[code] ?? (characters.isEmpty ? "Key \(code)" : characters.uppercased())
    }

    private static let names: [Int: String] = [
        40: "Return", 43: "Tab", 44: "Space",
        79: "→", 80: "←", 81: "↓", 82: "↑",
    ]
}

/// Which key plays what: at most one key for an action, and one action for
/// a key.
struct KeyboardMap: Equatable, Codable, Sendable {

    /// How many of the solo strip's cells can be given a key.
    static let soloCells = 10

    private(set) var keys: [KeyboardAction: KeyboardKey]

    func key(for action: KeyboardAction) -> KeyboardKey? { keys[action] }

    func action(for code: Int) -> KeyboardAction? {
        keys.first { $0.value.code == code }?.key
    }

    /// Makes `key` what plays `action`, in place of whatever either had.
    mutating func assign(_ key: KeyboardKey, to action: KeyboardAction) {
        if let taken = self.action(for: key.code) { keys[taken] = nil }
        keys[action] = key
    }

    /// Leaves `action` with no key.
    mutating func clear(_ action: KeyboardAction) {
        keys[action] = nil
    }
}

extension KeyboardMap {
    /// The chords along the home row from A to J, the joystick on the
    /// arrows, and the solo strip along the number row.
    static let standard: KeyboardMap = {
        var keys: [KeyboardAction: KeyboardKey] = [:]
        let homeRow = [(4, "A"), (22, "S"), (7, "D"), (9, "F"), (10, "G"), (11, "H"), (13, "J")]
        for (degree, key) in zip(Degree.allCases, homeRow) {
            keys[.chord(degree)] = KeyboardKey(code: key.0, name: key.1)
        }
        let arrows: [(JoystickDirection, Int)] = [(.right, 79), (.left, 80), (.down, 81), (.up, 82)]
        for (direction, code) in arrows {
            keys[.color(direction)] = KeyboardKey(code: code, characters: "")
        }
        for cell in 0..<soloCells {
            // The number row runs 1 to 9 and then 0.
            keys[.solo(cell: cell)] = KeyboardKey(code: 30 + cell, name: String((cell + 1) % 10))
        }
        return KeyboardMap(keys: keys)
    }()
}

extension JoystickDirection {
    /// Which way the direction points: right and up are positive.
    var lean: (x: Int, y: Int) {
        switch self {
        case .center:    return (0, 0)
        case .up:        return (0, 1)
        case .upRight:   return (1, 1)
        case .right:     return (1, 0)
        case .downRight: return (1, -1)
        case .down:      return (0, -1)
        case .downLeft:  return (-1, -1)
        case .left:      return (-1, 0)
        case .upLeft:    return (-1, 1)
        }
    }

    /// The direction several held together make: opposite ones cancel.
    static func combined(_ directions: some Sequence<JoystickDirection>) -> JoystickDirection {
        let sum = directions.reduce((x: 0, y: 0)) { ($0.x + $1.lean.x, $0.y + $1.lean.y) }
        let lean = (x: sum.x.signum(), y: sum.y.signum())
        return allCases.first { $0.lean == lean } ?? .center
    }
}
