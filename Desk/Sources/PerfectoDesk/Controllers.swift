import AppKit
import CoreHaptics
import DeskCore
import GameController
import os

/// The controllers the system knows (Xbox One and Series, PlayStation,
/// MFi): the first with an extended gamepad is read once a frame, and its
/// motors play the desk's rumbles.
@MainActor
final class SystemGamepads {
    private var haptics: CHHapticEngine?
    private weak var hapticController: GCController?
    private let log = Logger(subsystem: "com.perfecto.desk", category: "gamepad")

    init() {
        // The desk is played while another app (a DAW) may be in front.
        GCController.shouldMonitorBackgroundEvents = true
        GCController.startWirelessControllerDiscovery()
    }

    private var controller: GCController? {
        GCController.controllers().first { $0.extendedGamepad != nil }
    }

    /// The name of the controller read; nil with none.
    var name: String? {
        controller.map { $0.vendorName ?? "Controller" }
    }

    /// What the controller is doing at `time`; nil with none.
    func frame(at time: Double) -> GamepadFrame? {
        guard let pad = controller?.extendedGamepad else { return nil }
        let buttons: [(PadButton, GCControllerButtonInput?)] = [
            (.a, pad.buttonA), (.b, pad.buttonB), (.x, pad.buttonX), (.y, pad.buttonY),
            (.lb, pad.leftShoulder), (.rb, pad.rightShoulder),
            (.back, pad.buttonOptions), (.start, pad.buttonMenu),
            (.l3, pad.leftThumbstickButton), (.r3, pad.rightThumbstickButton),
            (.up, pad.dpad.up), (.down, pad.dpad.down), (.left, pad.dpad.left), (.right, pad.dpad.right),
        ]
        return GamepadFrame(
            time: time,
            left: Stick(x: Double(pad.leftThumbstick.xAxis.value), y: Double(pad.leftThumbstick.yAxis.value)),
            right: Stick(x: Double(pad.rightThumbstick.xAxis.value), y: Double(pad.rightThumbstick.yAxis.value)),
            leftTrigger: Double(pad.leftTrigger.value), rightTrigger: Double(pad.rightTrigger.value),
            buttons: Set(buttons.filter { $0.1?.isPressed == true }.map(\.0)))
    }

    /// Plays `rumble` on the controller's motors, if it has any.
    func play(_ rumble: Rumble) {
        guard let engine = engine() else { return }
        let (intensity, sharpness) = rumble == .tick ? (0.45, 0.9) : (0.9, 0.3)
        let event = CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(intensity)),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: Float(sharpness)),
        ], relativeTime: 0)
        do {
            let player = try engine.makePlayer(with: CHHapticPattern(events: [event], parameters: []))
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            log.debug("rumble failed: \(error.localizedDescription)")
        }
    }

    /// The haptic engine of the controller read now, made when first asked for.
    private func engine() -> CHHapticEngine? {
        guard let controller else { return nil }
        if controller !== hapticController {
            hapticController = controller
            haptics = controller.haptics?.createEngine(withLocality: .default)
            try? haptics?.start()
            haptics?.resetHandler = { [weak self] in
                Task { @MainActor in try? self?.haptics?.start() }
            }
        }
        return haptics
    }
}

/// The computer keyboard as a controller (`KeyboardPad`), heard while the
/// desk's window is in front. A key with Command held is the system's.
@MainActor
final class KeyboardKeys {
    private(set) var held: Set<String> = []
    private(set) var shift = false
    private var monitor: Any?
    private var resign: (any NSObjectProtocol)?

    func start() {
        // The monitor is called on the main thread with an event it hands
        // back, or nil to keep it from the window.
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            nonisolated(unsafe) let event = event
            nonisolated(unsafe) var passed: NSEvent? = event
            MainActor.assumeIsolated { passed = self?.handle(event) ?? event }
            return passed
        }
        resign = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
                                                        object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.held = [] }
        }
    }

    func frame(at time: Double) -> GamepadFrame {
        KeyboardPad.frame(holding: held, shift: shift, at: time)
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        shift = event.modifierFlags.contains(.shift)
        guard event.type != .flagsChanged, !event.modifierFlags.contains(.command),
              let key = Self.name(of: event), KeyboardPad.keys.contains(key) else { return event }
        if event.type == .keyDown {
            if !event.isARepeat { held.insert(key) }
        } else {
            held.remove(key)
        }
        return nil
    }

    private static func name(of event: NSEvent) -> String? {
        switch event.keyCode {
        case 126: "up"
        case 125: "down"
        case 123: "left"
        case 124: "right"
        case 36, 76: "return"
        case 48: "tab"
        default: event.charactersIgnoringModifiers?.lowercased()
        }
    }
}
