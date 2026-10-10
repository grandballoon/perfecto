import Foundation
import Observation

/// What a computer keyboard plays through.
@MainActor
protocol KeyboardHost: AnyObject {
    func press(degree: Degree)
    func release(degree: Degree)
    func joystickMoved(to direction: JoystickDirection)
    var solo: SoloState { get }
    var tonnetz: TonnetzState { get }
    /// Does what tapping `button` on screen does.
    func tap(_ button: KeyboardButton)
}

/// The computer keyboard as a way to play: its keys are chord keys, the
/// joystick, the solo strip's cells, the Tonnetz's moves and some of the
/// screen's buttons, by a map that can be changed key by key
/// (`KeyboardMap`) and is remembered across launches.
///
/// A key is one more finger: it presses and releases through the host's own
/// calls, so the modes, the loops and the effects know nothing of it, and a
/// key and a finger on the same chord are two presses of it. A key has no
/// place on the chord key it plays, so it plays no slide.
@Observable
@MainActor
final class KeyboardState {

    private(set) var map: KeyboardMap {
        didSet {
            guard map != oldValue else { return }
            save()
        }
    }

    /// The action a key is being chosen for: the next key pressed becomes
    /// its key and plays nothing. Escape leaves it as it was, and Delete
    /// leaves it with no key.
    var choosing: KeyboardAction?

    @ObservationIgnored weak var host: (any KeyboardHost)?

    /// The keys that are down, and what each was playing when it went down:
    /// a key lifted ends what it started, whatever the map says by then.
    private var held: [Int: KeyboardAction] = [:]

    private let defaults: UserDefaults
    private let logger: (any Logger)?
    private static let storageKey = "keyboardMap"

    init(defaults: UserDefaults = .standard, logger: (any Logger)? = nil) {
        self.defaults = defaults
        self.logger = logger
        map = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode(KeyboardMap.self, from: $0) } ?? .standard
    }

    // MARK: – Keys

    /// `key` went down. Returns whether it was taken: a key that plays
    /// nothing is left to the system.
    @discardableResult
    func keyDown(_ key: KeyboardKey) -> Bool {
        if let action = choosing {
            choose(key, for: action)
            return true
        }
        // A key held down is reported again and again.
        guard held[key.code] == nil else { return true }
        guard let action = map.action(for: key.code) else { return false }
        held[key.code] = action
        switch action {
        case .chord(let degree): host?.press(degree: degree)
        case .color:             followColor()
        case .solo(let cell):
            if host?.solo.isOn == true { host?.solo.press(cell: cell) }
        case .button(let button): host?.tap(button)
        case .tonnetz(let move):
            if host?.tonnetz.isShown == true { host?.tonnetz.apply(move) }
        }
        return true
    }

    /// The key at `code` came up. Returns whether it was one that was taken.
    @discardableResult
    func keyUp(code: Int) -> Bool {
        guard let action = held.removeValue(forKey: code) else { return false }
        release(action)
        return true
    }

    /// Every key is let go: the keyboard is no longer the app's.
    func releaseAll() {
        let actions = Array(held.values)
        held = [:]
        actions.forEach(release)
    }

    private func release(_ action: KeyboardAction) {
        switch action {
        case .chord(let degree): host?.release(degree: degree)
        case .color:             followColor()
        case .solo(let cell):    host?.solo.release([cell])
        // A button is tapped as its key goes down.
        case .button:            break
        // Each move starts from the last one's triad, so there is none to
        // hand back to: the triad sounds until the last move's key is up.
        case .tonnetz:
            if !held.values.contains(where: \.isTonnetzMove) { host?.tonnetz.release() }
        }
    }

    /// Pushes the joystick the way the held color keys add up to.
    private func followColor() {
        let directions = held.values.compactMap { action -> JoystickDirection? in
            if case .color(let direction) = action { direction } else { nil }
        }
        host?.joystickMoved(to: .combined(directions))
    }

    // MARK: – The map

    /// The name of the key that taps `button`, which a pointer over the
    /// button is shown; nil if it has none.
    func keyName(for button: KeyboardButton) -> String? {
        map.key(for: .button(button))?.name
    }

    private func choose(_ key: KeyboardKey, for action: KeyboardAction) {
        choosing = nil
        switch key.code {
        case KeyboardKey.escapeCode: return
        case KeyboardKey.deleteCode: map.clear(action)
        default:                     map.assign(key, to: action)
        }
        logger?.log(.keyboard_key_chosen(action: String(describing: action), key: map.key(for: action)?.name))
    }

    /// Goes back to the keys the app starts with.
    func reset() {
        choosing = nil
        map = .standard
        logger?.log(.keyboard_map_reset)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(map) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}

private extension KeyboardAction {
    var isTonnetzMove: Bool {
        if case .tonnetz = self { true } else { false }
    }
}
