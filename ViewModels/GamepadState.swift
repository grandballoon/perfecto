import Foundation
import Observation

/// A game controller as a way to play: its buttons are keys, by a map of
/// their own that is changed and remembered as the computer keyboard's is,
/// and its left stick plays the step compass's first choices.
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

    /// The compass's place the stick is pushed to; nil in the middle.
    private var stick: CompassPlace?

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
    /// positive. The compass is played only as the stick changes place,
    /// so a stick at rest leaves it to whatever else plays it.
    func stickMoved(x: Double, y: Double) {
        point(GamepadStick.kind(x: x, y: y, from: stick?.kind).map { CompassPlace($0, 1) })
    }

    /// Every button is let go and the stick is at rest: the controller is
    /// no longer the app's.
    func releaseAll() {
        buttons.releaseAll()
        point(nil)
    }

    /// The stick moved to `place`: it is pressed before the place it left
    /// is lifted, so a stick turned from one to the next never passes
    /// through the plain chord.
    private func point(_ place: CompassPlace?) {
        guard place != stick else { return }
        let left = stick
        stick = place
        if let place { host?.compassPressed(place) }
        if let left { host?.compassLifted(left) }
    }
}
