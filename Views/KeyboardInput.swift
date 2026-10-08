import SwiftUI
import UIKit

/// Hears the computer keyboard for the screen it lies behind, and hands its
/// keys to `KeyboardState`. It shows nothing and takes no touches.
///
/// It is the window's first responder, which is where the system sends
/// keys. A key that plays nothing, or is pressed with Command, Control or
/// Option, is passed on, so the system's own shortcuts work as ever.
struct KeyboardInput: UIViewRepresentable {
    let keyboard: KeyboardState

    func makeUIView(context: Context) -> KeyboardInputView {
        let view = KeyboardInputView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: KeyboardInputView, context: Context) {
        view.keyboard = keyboard
    }
}

/// A key that stops being the app's (the window goes, or another app comes
/// forward) is never reported as lifted, so every key is let go then: a key
/// can never be left down.
final class KeyboardInputView: UIView {
    weak var keyboard: KeyboardState?

    private var observers: [any NSObjectProtocol] = []

    override var canBecomeFirstResponder: Bool { true }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        guard window != nil else {
            keyboard?.releaseAll()
            return
        }
        becomeFirstResponder()
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.keyboard?.releaseAll() }
            },
            center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { _ = self?.becomeFirstResponder() }
            },
        ]
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let passedOn = presses.filter { press in
            guard let key = press.key, key.modifierFlags.isDisjoint(with: [.command, .control, .alternate]),
                  let keyboard else { return true }
            return !keyboard.keyDown(KeyboardKey(code: key.keyCode.rawValue,
                                                 characters: key.charactersIgnoringModifiers))
        }
        if !passedOn.isEmpty { super.pressesBegan(passedOn, with: event) }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        lift(presses) { super.pressesEnded($0, with: event) }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        lift(presses) { super.pressesCancelled($0, with: event) }
    }

    private func lift(_ presses: Set<UIPress>, passingOn: (Set<UIPress>) -> Void) {
        let passedOn = presses.filter { press in
            guard let key = press.key, let keyboard else { return true }
            return !keyboard.keyUp(code: key.keyCode.rawValue)
        }
        if !passedOn.isEmpty { passingOn(passedOn) }
    }
}
