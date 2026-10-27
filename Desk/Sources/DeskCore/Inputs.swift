// The ways a frame is made, as pure functions of what the hardware says:
// a wired Xbox 360 controller's USB report, and the computer keyboard
// standing in for a controller. The shell reads the hardware and asks these
// what it means.

/// A wired Xbox 360 controller, read from its USB reports. macOS has no
/// driver for it (GameController sees Xbox One and Series controllers, not
/// the 360), so the shell reads its interrupt endpoint itself and these
/// bytes are what it reads.
public enum Xbox360 {
    public static let vendor = 0x045E
    /// The wired controller. The wireless one comes through a receiver that
    /// speaks another protocol.
    public static let product = 0x028E

    /// How far a 360's stick wanders from the middle at rest, of its reach.
    public static let deadZone = 0.24

    /// The frame a 20-byte input report says, at `time`; nil for a report of
    /// another kind (the controller also reports its LEDs and headset).
    public static func frame(_ report: [UInt8], at time: Double) -> GamepadFrame? {
        guard report.count >= 14, report[0] == 0x00, report[1] >= 0x14 else { return nil }
        let bits: [(Int, UInt8, PadButton)] = [
            (2, 0x01, .up), (2, 0x02, .down), (2, 0x04, .left), (2, 0x08, .right),
            (2, 0x10, .start), (2, 0x20, .back), (2, 0x40, .l3), (2, 0x80, .r3),
            (3, 0x01, .lb), (3, 0x02, .rb),
            (3, 0x10, .a), (3, 0x20, .b), (3, 0x40, .x), (3, 0x80, .y),
        ]
        let buttons = Set(bits.filter { report[$0.0] & $0.1 != 0 }.map(\.2))
        func axis(_ at: Int) -> Double {
            let raw = Int16(bitPattern: UInt16(report[at]) | UInt16(report[at + 1]) << 8)
            return max(-1, Double(raw) / 32767)
        }
        return GamepadFrame(time: time,
                            left: stick(axis(6), axis(8)), right: stick(axis(10), axis(12)),
                            leftTrigger: Double(report[4]) / 255, rightTrigger: Double(report[5]) / 255,
                            buttons: buttons)
    }

    /// A stick with its loose middle taken out: nothing inside the dead
    /// zone, and the rest stretched to the whole reach.
    static func stick(_ x: Double, _ y: Double) -> Stick {
        let radius = (x * x + y * y).squareRoot()
        guard radius > deadZone else { return .rest }
        let scale = min(1, (radius - deadZone) / (1 - deadZone)) / radius
        return Stick(x: x * scale, y: y * scale)
    }

    /// The output report that spins the motors: the heavy low one on the
    /// left, the light high one on the right, each 0 to 1.
    public static func rumble(low: Double, high: Double) -> [UInt8] {
        func level(_ value: Double) -> UInt8 { UInt8(max(0, min(1, value)) * 255) }
        return [0x00, 0x08, 0x00, level(low), level(high), 0x00, 0x00, 0x00]
    }

    /// The output report that lights the ring's first quarter: player one.
    public static let playerOne: [UInt8] = [0x01, 0x03, 0x06]
}

/// The computer keyboard as a controller, so every layout can be tried
/// without one: WASD the left stick, IJKL the right (Shift holds it half
/// out, for the inner ring), the arrows the d-pad, Space A.
public enum KeyboardPad {
    /// Each key's control, by the character it types (lowercased) or its
    /// name for keys that type none.
    public static let buttons: [String: PadButton] = [
        " ": .a, "b": .b, "x": .x, "y": .y,
        "q": .lb, "e": .rb, "r": .l3, "o": .r3,
        "up": .up, "down": .down, "left": .left, "right": .right,
        "return": .start, "tab": .back,
    ]
    public static let leftTrigger = "z"
    public static let rightTrigger = "c"
    public static let leftStick = (up: "w", left: "a", down: "s", right: "d")
    public static let rightStick = (up: "i", left: "j", down: "k", right: "l")

    /// Every key the map reads.
    public static var keys: Set<String> {
        Set(buttons.keys).union([leftTrigger, rightTrigger, leftStick.up, leftStick.left, leftStick.down,
                                 leftStick.right, rightStick.up, rightStick.left, rightStick.down, rightStick.right])
    }

    /// What the keys held mean at `time`.
    public static func frame(holding keys: Set<String>, shift: Bool, at time: Double) -> GamepadFrame {
        func stick(_ map: (up: String, left: String, down: String, right: String), reach: Double) -> Stick {
            let x = (keys.contains(map.right) ? 1.0 : 0) - (keys.contains(map.left) ? 1 : 0)
            let y = (keys.contains(map.up) ? 1.0 : 0) - (keys.contains(map.down) ? 1 : 0)
            let length = (x * x + y * y).squareRoot()
            return length == 0 ? .rest : Stick(x: x / length * reach, y: y / length * reach)
        }
        return GamepadFrame(time: time, left: stick(leftStick, reach: 1),
                            right: stick(rightStick, reach: shift ? 0.62 : 1),
                            leftTrigger: keys.contains(leftTrigger) ? 1 : 0,
                            rightTrigger: keys.contains(rightTrigger) ? 1 : 0,
                            buttons: Set(keys.compactMap { buttons[$0] }))
    }

    /// The key that stands for each control, for the screen's legend.
    public static func key(for control: PadControl) -> String {
        switch control {
        case .leftStick: return "WASD"
        case .rightStick: return "IJKL"
        case .leftTrigger: return "Z"
        case .rightTrigger: return "C"
        case .button(let button):
            let names = ["up": "↑", "down": "↓", "left": "←", "right": "→", "return": "⏎", "tab": "⇥", " ": "Space"]
            let key = buttons.first { $0.value == button }!.key
            return names[key] ?? key.uppercased()
        }
    }
}
