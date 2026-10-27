import Foundation

// A game controller as values: what every stick, trigger and button is
// doing at one moment. The design reference is the Xbox 360 controller
// (docs/gamepad-desk-ui.md, "The hand, as a budget"); any extended gamepad
// has the same controls under other names.

/// A button of the controller, by where it is.
public enum PadButton: String, CaseIterable, Hashable, Codable, Sendable {
    case a, b, x, y
    /// The bumpers.
    case lb, rb
    /// The small buttons in the middle: Back (View) and Start (Menu).
    case back, start
    /// The sticks, pressed in.
    case l3, r3
    /// The d-pad. Its diagonals are not reliable on a 360, so nothing asks
    /// for them.
    case up, down, left, right

    public var name: String {
        switch self {
        case .a: "A"
        case .b: "B"
        case .x: "X"
        case .y: "Y"
        case .lb: "LB"
        case .rb: "RB"
        case .back: "Back"
        case .start: "Start"
        case .l3: "L3"
        case .r3: "R3"
        case .up: "↑"
        case .down: "↓"
        case .left: "←"
        case .right: "→"
        }
    }
}

/// A stick's place, each axis from -1 to 1 with right and up positive.
public struct Stick: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double = 0, y: Double = 0) {
        self.x = x
        self.y = y
    }

    public static let rest = Stick()

    /// How far from the middle, 0 to 1 (a corner of a square gate is cut
    /// to 1).
    public var radius: Double { min(1, (x * x + y * y).squareRoot()) }

    /// Which way it leans, as a compass bearing: degrees clockwise from up,
    /// 0 up to 360.
    public var bearing: Double {
        let degrees = atan2(x, y) * 180 / .pi
        return degrees < 0 ? degrees + 360 : degrees
    }
}

/// Everything the controller is doing at `time` (seconds, on any clock that
/// only goes forward).
public struct GamepadFrame: Equatable, Sendable {
    public var time: Double
    public var left: Stick
    public var right: Stick
    /// How far each trigger is pulled, 0 to 1.
    public var leftTrigger: Double
    public var rightTrigger: Double
    public var buttons: Set<PadButton>

    public init(time: Double, left: Stick = .rest, right: Stick = .rest, leftTrigger: Double = 0,
                rightTrigger: Double = 0, buttons: Set<PadButton> = []) {
        self.time = time
        self.left = left
        self.right = right
        self.leftTrigger = leftTrigger
        self.rightTrigger = rightTrigger
        self.buttons = buttons
    }

    public func isDown(_ button: PadButton) -> Bool { buttons.contains(button) }

    /// The frame as if it came at no time: what the controls are doing,
    /// for telling whether anything changed.
    public var untimed: GamepadFrame {
        var frame = self
        frame.time = 0
        return frame
    }

    /// The frame with its sticks and triggers to the nearest hundredth: what
    /// a screen can show of it, so a stick's jitter at rest redraws nothing.
    public var shown: GamepadFrame {
        func round(_ value: Double) -> Double { (value * 100).rounded() / 100 }
        return GamepadFrame(time: 0, left: Stick(x: round(left.x), y: round(left.y)),
                            right: Stick(x: round(right.x), y: round(right.y)),
                            leftTrigger: round(leftTrigger), rightTrigger: round(rightTrigger), buttons: buttons)
    }

    /// Two hands' worth of frames as one: the buttons either holds, each
    /// stick and trigger the one leaning or pulled further. How the
    /// computer keyboard and a controller play at once.
    public func merged(with other: GamepadFrame) -> GamepadFrame {
        func further(_ a: Stick, _ b: Stick) -> Stick { a.radius >= b.radius ? a : b }
        return GamepadFrame(time: max(time, other.time), left: further(left, other.left),
                            right: further(right, other.right),
                            leftTrigger: max(leftTrigger, other.leftTrigger),
                            rightTrigger: max(rightTrigger, other.rightTrigger),
                            buttons: buttons.union(other.buttons))
    }
}

/// What changed between two frames: the buttons pressed and let go.
public struct PadEdges: Equatable, Sendable {
    public var pressed: Set<PadButton>
    public var released: Set<PadButton>

    public init(pressed: Set<PadButton> = [], released: Set<PadButton> = []) {
        self.pressed = pressed
        self.released = released
    }

    public init(from previous: GamepadFrame, to frame: GamepadFrame) {
        pressed = frame.buttons.subtracting(previous.buttons)
        released = previous.buttons.subtracting(frame.buttons)
    }

    public func pressed(_ button: PadButton) -> Bool { pressed.contains(button) }
    public func released(_ button: PadButton) -> Bool { released.contains(button) }
}

/// One step of input for a layout: the frame, what changed since the last,
/// and the frame before it.
public struct PadInput: Equatable, Sendable {
    public var frame: GamepadFrame
    public var previous: GamepadFrame
    public var edges: PadEdges

    public init(frame: GamepadFrame, previous: GamepadFrame) {
        self.frame = frame
        self.previous = previous
        edges = PadEdges(from: previous, to: frame)
    }

    public var time: Double { frame.time }
    public func pressed(_ button: PadButton) -> Bool { edges.pressed(button) }
    public func released(_ button: PadButton) -> Bool { edges.released(button) }
    public func isDown(_ button: PadButton) -> Bool { frame.isDown(button) }
}

/// A control of the controller, for saying what each does: a button, or a
/// stick or trigger as a whole.
public enum PadControl: Hashable, Sendable {
    case button(PadButton)
    case leftStick, rightStick, leftTrigger, rightTrigger

    public var name: String {
        switch self {
        case .button(let button): button.name
        case .leftStick: "Left stick"
        case .rightStick: "Right stick"
        case .leftTrigger: "LT"
        case .rightTrigger: "RT"
        }
    }
}

/// What every control does now, for the screen to show the hand
/// ("The screen shows the hand").
public typealias Legend = [PadControl: String]
