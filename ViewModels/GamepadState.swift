import Foundation
import Observation

/// A game controller as a way to play: its buttons are keys, by a map of
/// their own that is changed and remembered as the computer keyboard's is,
/// and its left stick is the joystick.
///
/// It is one more finger, as the keyboard is: it plays through the same
/// host by the same calls, so nothing downstream knows of it. `GamepadInput`
/// hears the controller and tells this what it does.
@Observable
@MainActor
final class GamepadState {

    /// The controller's buttons, which are a keyboard of a few keys.
    let buttons: KeyboardState

    /// The name of the controller that is connected; nil with none.
    private(set) var controller: String?

    /// The direction the stick is pushed in.
    private var stick = JoystickDirection.center

    private let logger: (any Logger)?

    init(defaults: UserDefaults = .standard, logger: (any Logger)? = nil) {
        buttons = KeyboardState(saved: "gamepadMap", standard: .gamepad, defaults: defaults, logger: logger)
        self.logger = logger
    }

    var host: (any KeyboardHost)? {
        get { buttons.host }
        set { buttons.host = newValue }
    }

    // MARK: – The controller

    /// The controller connected is now the one called `name`; nil: there is
    /// none, and whatever the last one held is let go.
    func connected(to name: String?) {
        guard name != controller else { return }
        controller = name
        if name == nil { releaseAll() }
        logger?.log(.gamepad_connected(name: name))
    }

    func button(_ button: GamepadButton, isPressed: Bool) {
        if isPressed {
            buttons.keyDown(button.key)
        } else {
            buttons.keyUp(code: button.rawValue)
        }
    }

    /// The left stick is at (`x`, `y`), each from -1 to 1 with right and up
    /// positive. The joystick is moved only as the stick changes direction,
    /// so a stick at rest leaves it to whatever else plays it.
    func stickMoved(x: Double, y: Double) {
        point(GamepadStick.direction(x: x, y: y, from: stick))
    }

    /// Every button is let go and the stick is at rest: the controller is
    /// no longer the app's.
    func releaseAll() {
        buttons.releaseAll()
        point(.center)
    }

    private func point(_ direction: JoystickDirection) {
        guard direction != stick else { return }
        stick = direction
        host?.joystickMoved(to: direction)
    }
}
