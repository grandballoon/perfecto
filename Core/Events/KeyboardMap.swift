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
    /// One of the screen's buttons, tapped.
    case button(KeyboardButton)
    /// A move on the Tonnetz, whose triad sounds while the key is held.
    case tonnetz(TonnetzMove)
}

/// The buttons of the screen that a key can tap.
enum KeyboardButton: String, CaseIterable, Hashable, Codable, Sendable {
    /// Starts a loop's take, or closes the one being recorded.
    case loop
    /// Shows or hides the solo strip.
    case solo
    /// Silences the app's own sound, or brings it back.
    case midi
    /// Starts the loops and the sequence from the top, or stops them.
    case playStop
    /// Shows the sequencer.
    case sequencer
    /// Shows the Tonnetz.
    case tonnetz
    /// Shows the Tonnetz as the net of notes, while it is on screen.
    case net
    /// Shows the Tonnetz one triad at a time, while it is on screen.
    case triad
    /// Switches the Tonnetz's hold on or off, while it is on screen.
    case hold

    var displayName: String {
        switch self {
        case .loop:      return "Loop"
        case .solo:      return "Solo"
        case .midi:      return "MIDI"
        case .playStop:  return "Play/stop"
        case .sequencer: return "Sequencer"
        case .tonnetz:   return "Tonnetz"
        case .net:       return "Net"
        case .triad:     return "Triad"
        case .hold:      return "Hold"
        }
    }
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
    /// The actions left with no key on purpose (`clear`), which is how they
    /// are told from actions a saved map is too old to know of.
    private(set) var cleared: Set<KeyboardAction> = []

    func key(for action: KeyboardAction) -> KeyboardKey? { keys[action] }

    func action(for code: Int) -> KeyboardAction? {
        keys.first { $0.value.code == code }?.key
    }

    /// Makes `key` what plays `action`, in place of whatever either had.
    mutating func assign(_ key: KeyboardKey, to action: KeyboardAction) {
        if let taken = self.action(for: key.code) { clear(taken) }
        keys[action] = key
        cleared.remove(action)
    }

    /// Leaves `action` with no key.
    mutating func clear(_ action: KeyboardAction) {
        keys[action] = nil
        cleared.insert(action)
    }
}

extension KeyboardMap {
    /// A map saved before an action existed has no key for it. It is given
    /// the key it starts with, unless that key now plays something else.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keys = try container.decode([KeyboardAction: KeyboardKey].self, forKey: .keys)
        cleared = try container.decodeIfPresent(Set<KeyboardAction>.self, forKey: .cleared) ?? []
        for (action, key) in Self.standard.keys
        where keys[action] == nil && !cleared.contains(action) && self.action(for: key.code) == nil {
            keys[action] = key
        }
    }
}

extension KeyboardMap {
    /// The chords along the home row from A to J, the joystick on the
    /// arrows, the solo strip along the number row, the buttons on Return
    /// (loop), Space (play and stop), O (solo), M (MIDI), Q (sequencer),
    /// Z (Tonnetz), N (net), T (triad) and K (hold: it keeps), and the
    /// Tonnetz's moves on their own letters, P, L and R.
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
        keys[.button(.loop)] = KeyboardKey(code: 40, characters: "")
        keys[.button(.playStop)] = KeyboardKey(code: 44, characters: "")
        keys[.button(.solo)] = KeyboardKey(code: 18, name: "O")
        keys[.button(.midi)] = KeyboardKey(code: 16, name: "M")
        keys[.button(.sequencer)] = KeyboardKey(code: 20, name: "Q")
        keys[.button(.tonnetz)] = KeyboardKey(code: 29, name: "Z")
        keys[.button(.net)] = KeyboardKey(code: 17, name: "N")
        keys[.button(.triad)] = KeyboardKey(code: 23, name: "T")
        keys[.button(.hold)] = KeyboardKey(code: 14, name: "K")
        keys[.tonnetz(.parallel)] = KeyboardKey(code: 19, name: "P")
        keys[.tonnetz(.leading)] = KeyboardKey(code: 15, name: "L")
        keys[.tonnetz(.relative)] = KeyboardKey(code: 21, name: "R")
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
