import GameController
import UIKit

/// Hears the game controllers and hands what they do to `GamepadState`.
///
/// The system reports a controller only while the app is in front, and a
/// button that is down when the app stops being so, or when its controller
/// goes, is never reported as lifted, so everything is let go then.
@MainActor
final class GamepadInput {
    private weak var gamepad: GamepadState?
    private var observers: [any NSObjectProtocol] = []

    /// Starts handing the controllers to `gamepad`: the ones connected now
    /// and any that come.
    func play(_ gamepad: GamepadState) {
        guard self.gamepad == nil else { return }
        self.gamepad = gamepad
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.follow() }
            },
            center.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.gamepad?.releaseAll()
                    self?.follow()
                }
            },
            center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.gamepad?.releaseAll() }
            },
        ]
        follow()
    }

    /// Hears every controller there is now. Any of them plays, and the
    /// first is the one named.
    private func follow() {
        let pads = GCController.controllers().filter { $0.extendedGamepad != nil }
        gamepad?.connected(to: pads.first.map { $0.vendorName ?? "Controller" })
        pads.forEach(hear)
    }

    private func hear(_ controller: GCController) {
        guard let pad = controller.extendedGamepad else { return }
        let inputs: [(GamepadButton, GCControllerButtonInput?)] = [
            (.a, pad.buttonA), (.b, pad.buttonB), (.x, pad.buttonX), (.y, pad.buttonY),
            (.leftShoulder, pad.leftShoulder), (.rightShoulder, pad.rightShoulder),
            (.leftTrigger, pad.leftTrigger), (.rightTrigger, pad.rightTrigger),
            (.up, pad.dpad.up), (.down, pad.dpad.down), (.left, pad.dpad.left), (.right, pad.dpad.right),
            (.menu, pad.buttonMenu), (.options, pad.buttonOptions),
            (.leftStick, pad.leftThumbstickButton), (.rightStick, pad.rightThumbstickButton),
        ]
        for (button, input) in inputs {
            input?.pressedChangedHandler = { [weak self] _, _, isPressed in
                MainActor.assumeIsolated { self?.gamepad?.button(button, isPressed: isPressed) }
            }
        }
        pad.leftThumbstick.valueChangedHandler = { [weak self] _, x, y in
            MainActor.assumeIsolated { self?.gamepad?.stickMoved(x: Double(x), y: Double(y)) }
        }
    }
}
