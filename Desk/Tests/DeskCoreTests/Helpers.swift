import Foundation
import DeskCore

/// A stick leaning towards `bearing` (degrees clockwise from up), `radius` out.
func lean(_ bearing: Double, _ radius: Double = 1) -> Stick {
    let radians = bearing * .pi / 180
    return Stick(x: sin(radians) * radius, y: cos(radians) * radius)
}

/// Steps a layout through frames, keeping the frame before.
struct Rig<L: Layout> {
    var layout: L
    var settings = DeskSettings()
    var last = GamepadFrame(time: 0)

    init(_ layout: L) {
        self.layout = layout
    }

    @discardableResult
    mutating func step(_ frame: GamepadFrame) -> [DeskEffect] {
        defer { last = frame }
        return layout.step(PadInput(frame: frame, previous: last), settings: &settings)
    }

    /// The frame before, at `time`, changed by `change`.
    @discardableResult
    mutating func at(_ time: Double, _ change: (inout GamepadFrame) -> Void = { _ in }) -> [DeskEffect] {
        var frame = last
        frame.time = time
        change(&frame)
        return step(frame)
    }
}

/// The notes of the chords `effects` sound on `line`, in order.
func sounded(_ effects: [DeskEffect], on line: Line = .chord) -> [[Int]] {
    effects.compactMap {
        if case let .sound(l, notes, _, _, _, _) = $0, l == line { return notes }
        return nil
    }
}
