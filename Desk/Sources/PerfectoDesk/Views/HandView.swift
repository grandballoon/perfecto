import DeskCore
import SwiftUI

/// The hand, as the screen shows it: what every control does now, relabelled
/// as layers change, each lit while it is held. The left hand's controls on
/// the left, the right hand's on the right, as they are on the controller.
struct HandView: View {
    let legend: Legend
    let frame: GamepadFrame
    /// Whether the keyboard is what plays: each control shows its key too.
    let isKeyboard: Bool

    private static let left: [PadControl] = [
        .leftTrigger, .button(.lb), .leftStick, .button(.l3),
        .button(.up), .button(.down), .button(.left), .button(.right), .button(.back),
    ]
    private static let right: [PadControl] = [
        .rightTrigger, .button(.rb), .rightStick, .button(.r3),
        .button(.y), .button(.x), .button(.b), .button(.a), .button(.start),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Caption(control: isKeyboard ? "Keyboard" : "Controller", title: "What each control does")
            HStack(alignment: .top, spacing: 18) {
                column(Self.left)
                column(Self.right)
            }
        }
    }

    private func column(_ controls: [PadControl]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(controls, id: \.self) { control in
                if let text = legend[control] {
                    HStack(spacing: 8) {
                        ControlChip(control: control, isHeld: isHeld(control))
                        VStack(alignment: .leading, spacing: 0) {
                            Text(text)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.text)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                            if isKeyboard {
                                Text(KeyboardPad.key(for: control))
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Theme.faint)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func isHeld(_ control: PadControl) -> Bool {
        switch control {
        case .button(let button): frame.isDown(button)
        case .leftStick: frame.left.radius > 0.3
        case .rightStick: frame.right.radius > 0.3
        case .leftTrigger: frame.leftTrigger > 0.08
        case .rightTrigger: frame.rightTrigger > 0.08
        }
    }
}

/// A control's own mark: a face button in its color, the rest in grey.
struct ControlChip: View {
    let control: PadControl
    let isHeld: Bool

    var body: some View {
        let tint = color
        Text(label)
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .foregroundStyle(isHeld ? Color.black : tint ?? Theme.text)
            .frame(minWidth: 22, minHeight: 20)
            .padding(.horizontal, isRound ? 0 : 4)
            .background(isHeld ? (tint ?? Theme.chord) : Theme.raised,
                        in: RoundedRectangle(cornerRadius: isRound ? 10 : 5, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: isRound ? 10 : 5, style: .continuous)
                .strokeBorder((tint ?? Theme.rule).opacity(isHeld ? 0 : 0.6)))
    }

    private var isRound: Bool {
        if case .button(let button) = control { return [.a, .b, .x, .y].contains(button) }
        return false
    }

    private var color: Color? {
        if case .button(let button) = control { return Theme.color(of: button) }
        return nil
    }

    private var label: String {
        switch control {
        case .leftStick: "LS"
        case .rightStick: "RS"
        default: control.name
        }
    }
}

/// The notes sounding, on a piano's keys: the chords in orange, the line in blue.
struct PianoView: View {
    let sounding: [Line: [Int]]
    /// From C2 to C7: where the desk's chords and lines are.
    static let range = 36...96

    var body: some View {
        GeometryReader { proxy in
            let whites = Self.range.filter { !Self.isBlack($0) }
            let width = proxy.size.width / CGFloat(whites.count)
            ZStack(alignment: .topLeading) {
                ForEach(Array(whites.enumerated()), id: \.element) { index, note in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(fill(note) ?? Color(white: 0.96))
                        .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(Color(white: 0.55), lineWidth: 0.5))
                        .overlay(alignment: .bottom) {
                            if note % 12 == 0 {
                                Text("C\(note / 12 - 1)")
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundStyle(Color(white: 0.45))
                                    .padding(.bottom, 3)
                            }
                        }
                        .frame(width: width - 1, height: proxy.size.height)
                        .offset(x: CGFloat(index) * width)
                }
                ForEach(Self.range.filter(Self.isBlack), id: \.self) { note in
                    let before = whites.firstIndex(of: note - 1) ?? 0
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(fill(note) ?? Color(white: 0.12))
                        .frame(width: width * 0.62, height: proxy.size.height * 0.6)
                        .offset(x: CGFloat(before + 1) * width - width * 0.31)
                }
            }
        }
    }

    private func fill(_ note: Int) -> Color? {
        if sounding[.melody]?.contains(note) == true { return Theme.melody }
        if sounding[.chord]?.contains(note) == true { return Theme.chord }
        return nil
    }

    static func isBlack(_ note: Int) -> Bool {
        [1, 3, 6, 8, 10].contains(note % 12)
    }
}
