import SwiftUI

/// Where the color pad's cells are: every color the joystick has, a column
/// to each direction from the centre round clockwise from up, and a row to
/// each of its modes, the plainest at the bottom. The directions are drawn
/// along the top as the joystick's arrows and the modes down the leading
/// edge. A color field's finger is read by the same cells (`PadSwipe`).
enum ColorSpan: PadMap {
    static let directions = JoystickDirection.allCases
    static let modes = JoystickMode.allCases

    static let span = PadSpan(columns: 0...(directions.count - 1), rows: 0...(modes.count - 1),
                              cell: CGSize(width: 36, height: 28), top: 18, leading: 26)

    static func cell(of color: KeyColor) -> PadFieldCell {
        PadFieldCell(column: directions.firstIndex(of: color.direction) ?? 0,
                row: modes.firstIndex(of: color.mode) ?? 0)
    }

    static func value(at cell: PadFieldCell) -> KeyColor {
        KeyColor(mode: modes[cell.row.clamped(to: span.rows)],
                 direction: directions[cell.column.clamped(to: span.columns)])
    }
}

extension JoystickDirection {
    /// The direction as an arrow; the centre is a dot.
    var arrow: String {
        switch self {
        case .center:    return "·"
        case .up:        return "↑"
        case .upRight:   return "↗"
        case .right:     return "→"
        case .downRight: return "↘"
        case .down:      return "↓"
        case .downLeft:  return "↙"
        case .left:      return "←"
        case .upLeft:    return "↖"
        }
    }
}

extension JoystickMode {
    /// The mode's name where there is room for three letters.
    var shortName: String {
        switch self {
        case .default:   return "DEF"
        case .extended:  return "EXT"
        case .chromatic: return "CHR"
        }
    }
}

/// Every color there is, with the one chosen lit: the span a color field's
/// finger moves over (`ColorSpan`). Each cell is named by what it does to a
/// chord, the row of the mode chosen is the brighter one, and the plain
/// chord's column is marked in every row.
struct ColorPad: View {
    let color: KeyColor

    private static let rowInset: CGFloat = 2

    var body: some View {
        let chosen = ColorSpan.span.frame(of: ColorSpan.cell(of: color))
        ZStack(alignment: .topLeading) {
            ForEach(ColorSpan.modes, id: \.self) { mode in
                row(mode)
            }
            ForEach(ColorSpan.directions, id: \.self) { direction in
                let isChosen = direction == color.direction
                let column = frame(KeyColor(mode: .default, direction: direction))
                Text(direction.arrow)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(isChosen ? Color.orange : Color(white: direction == .center ? 0.8 : 0.5))
                    .frame(width: column.width, height: ColorSpan.span.top)
                    .offset(x: column.minX)
            }
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.orange)
                .frame(width: chosen.width, height: chosen.height - 2 * Self.rowInset)
                .offset(x: chosen.minX, y: chosen.minY + Self.rowInset)
            name(of: color, in: .black, weight: .bold)
                .frame(width: chosen.width, height: chosen.height)
                .offset(x: chosen.minX, y: chosen.minY)
        }
        .frame(width: ColorSpan.span.size.width, height: ColorSpan.span.size.height, alignment: .topLeading)
        .animation(.snappy(duration: 0.12), value: color)
    }

    private func frame(_ color: KeyColor) -> CGRect {
        ColorSpan.span.frame(of: ColorSpan.cell(of: color))
    }

    /// One mode's row: its name, its track through the directions with each
    /// cell named, and the mark of the plain chord.
    private func row(_ mode: JoystickMode) -> some View {
        let isChosen = mode == color.mode
        let first = frame(KeyColor(mode: mode, direction: ColorSpan.directions[0]))
        let width = CGFloat(ColorSpan.directions.count) * first.width
        let height = first.height - 2 * Self.rowInset
        return ZStack(alignment: .topLeading) {
            Text(mode.shortName)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(isChosen ? Color.orange : Color(white: 0.5))
                .frame(width: ColorSpan.span.leading, height: first.height)
                .offset(y: first.minY)
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(white: isChosen ? 0.24 : 0.14))
                .frame(width: width, height: height)
                .offset(x: first.minX, y: first.minY + Self.rowInset)
            Rectangle()
                .fill(Color(white: isChosen ? 0.5 : 0.3))
                .frame(width: 1, height: height)
                .offset(x: first.maxX, y: first.minY + Self.rowInset)
            ForEach(ColorSpan.directions, id: \.self) { direction in
                let cell = KeyColor(mode: mode, direction: direction)
                let place = frame(cell)
                name(of: cell, in: Color(white: isChosen ? 0.8 : 0.5), weight: .semibold)
                    .frame(width: place.width, height: place.height)
                    .offset(x: place.minX, y: place.minY)
            }
        }
    }

    private func name(of color: KeyColor, in style: Color, weight: Font.Weight) -> some View {
        Text(color.label)
            .font(.system(size: 8, weight: weight, design: .monospaced))
            .foregroundStyle(style)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 2)
    }
}

/// The keys' color on the key strip: a joystick color given to every chord
/// they play while no finger is on the chord colors (`PadField`, over
/// `ColorSpan`), with the switch that says whether the field keeps what it
/// is set to (`PerformanceState.keepsColor`). While it does, the field sets
/// the color, and every chord is played in it until it is set again. While
/// it does not, the field is played: the chord being held, or struck while
/// the finger is on the field, takes the color the finger is at, and keeps
/// it only until it is over or another is struck. Either way a chord being
/// held follows the finger.
struct KeyColorField: View {
    @Environment(PerformanceState.self) private var state

    private static let width: CGFloat = 78

    var body: some View {
        let color = state.heldKeyColor
        HStack(spacing: 4) {
            PadField<ColorSpan, ColorPad>(name: "COLOR", value: color, text: color.label,
                                          onBegin: state.grabKeyColor, onEnd: state.releaseKeyColor,
                                          pad: { ColorPad(color: $0) }) {
                state.holdKeyColor(at: $0)
            }
            .accessibilityLabel("Chord color")
            .accessibilityValue("\(color.label), \(color.mode.shortName)")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: step(direction: 1)
                case .decrement: step(direction: -1)
                @unknown default: break
                }
            }
            .accessibilityAction(named: "Next mode") { step(mode: 1) }
            .accessibilityAction(named: "Previous mode") { step(mode: -1) }
            .frame(width: Self.width)
            @Bindable var state = state
            KeepSwitch(label: "Keep the color", keeps: $state.keepsColor)
        }
    }

    /// A change made in one step, with no finger on the field.
    private func step(direction: Int = 0, mode: Int = 0) {
        let cell = ColorSpan.cell(of: state.heldKeyColor)
        state.grabKeyColor()
        state.holdKeyColor(at: ColorSpan.value(at: PadFieldCell(column: cell.column + direction, row: cell.row + mode)))
        state.releaseKeyColor()
    }
}
