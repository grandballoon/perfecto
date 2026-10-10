import SwiftUI

/// The Tonnetz, wired to the live performance (`TonnetzState`): the net
/// from above or one triad at a time, under the chit that switches between
/// them and the name of the triad it is at.
struct TonnetzView: View {
    var body: some View {
        VStack(spacing: 16) {
            TonnetzControls()
            TonnetzBoard()
        }
    }
}

/// The Tonnetz's row of controls: the chit that switches between its views,
/// the name of the triad it is at, the switch that holds what is pressed,
/// and the net's zoom. A screen that has a row to spare for them puts them
/// there (a phone on its side).
struct TonnetzControls: View {
    @Environment(PerformanceState.self) private var state

    private static let chitWidth: CGFloat = 40
    private static let holdWidth: CGFloat = 52
    private static let chitSpacing: CGFloat = 8
    /// The least a side is: room for the hold switch and the zoom's two chits.
    private static let narrowSide = holdWidth + 2 * chitWidth + 2 * chitSpacing

    /// As wide as there is room for: the two sides narrower, and then the
    /// triad named without its notes, which the net shows.
    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(sideWidth: 200, namesNotes: true)
            row(sideWidth: Self.narrowSide, namesNotes: true)
            row(sideWidth: Self.narrowSide, namesNotes: false)
        }
    }

    /// The sides are alike, so the name is in the middle.
    private func row(sideWidth: CGFloat, namesNotes: Bool) -> some View {
        @Bindable var tonnetz = state.tonnetz
        return HStack(spacing: 12) {
            SegmentedToggle(choices: TonnetzViewKind.allCases, label: \.displayName,
                            hotkey: { $0 == .net ? .net : .triad },
                            selection: $tonnetz.view)
                .frame(width: sideWidth)
            triadName(namesNotes: namesNotes)
                .frame(maxWidth: .infinity)
            HStack(spacing: Self.chitSpacing) {
                holdButton
                // The triad view is as large as it can be, so only the net
                // is zoomed; the buttons keep their place either way.
                Group {
                    zoomButton("−", label: "Zoom out", by: -TonnetzState.netEdgeStep)
                    zoomButton("+", label: "Zoom in", by: TonnetzState.netEdgeStep)
                }
                .opacity(tonnetz.view == .net ? 1 : 0)
                .disabled(tonnetz.view != .net)
            }
            .frame(width: sideWidth, alignment: .trailing)
        }
    }

    /// The triad the Tonnetz is at and its notes, as the keys' display
    /// names their chord, and after them the notes sounding by themselves.
    private func triadName(namesNotes: Bool) -> some View {
        let triad = state.tonnetz.cell.triad
        let alone = state.tonnetz.soundingNotes
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(triad.name)
                .font(.system(size: 20, weight: .semibold, design: .monospaced))
                .foregroundStyle(TonnetzStyle.display)
            if namesNotes {
                Text(triad.pitchClasses.map(\.name).joined(separator: " "))
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(TonnetzStyle.display.opacity(0.6))
                if !alone.isEmpty {
                    Text("+ " + alone.map(\.name).joined(separator: " "))
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(TonnetzStyle.display)
                }
            }
        }
        .lineLimit(1)
    }

    /// The switch that keeps what is pressed sounding once the pointer
    /// lifts, lit while it is on as the screen's other switches are.
    private var holdButton: some View {
        let tonnetz = state.tonnetz
        return Button { tonnetz.holds.toggle() } label: {
            Text("HOLD")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(tonnetz.holds ? Color.black : Color(white: 0.85))
                .frame(width: Self.holdWidth)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(tonnetz.holds ? Color.orange : Color(white: 0.13))
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .stroke(tonnetz.holds ? Color.orange : Color(white: 0.25), lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
        .hotkeyTip(.hold)
        .accessibilityLabel("Hold")
        .accessibilityAddTraits(tonnetz.holds ? .isSelected : [])
    }

    private func zoomButton(_ symbol: String, label: String, by step: CGFloat) -> some View {
        let tonnetz = state.tonnetz
        let edge = tonnetz.netEdge + step
        let canZoom = TonnetzState.netEdgeRange.contains(edge)
        return Button { tonnetz.zoomNet(to: edge) } label: {
            Text(symbol)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(white: canZoom ? 0.85 : 0.35))
                .frame(width: Self.chitWidth)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(white: 0.13))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(white: 0.25), lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
        .disabled(!canZoom)
        .accessibilityLabel(label)
    }
}

/// The Tonnetz as it is played: whichever of its two views is chosen.
struct TonnetzBoard: View {
    @Environment(PerformanceState.self) private var state

    var body: some View {
        Group {
            switch state.tonnetz.view {
            case .net:   TonnetzNetView()
            case .triad: TonnetzTriadView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(white: 0.15), lineWidth: 1))
    }
}

/// The colors both Tonnetz views are drawn in.
enum TonnetzStyle {
    /// The keys' display's amber.
    static let display = Color(red: 1, green: 0.65, blue: 0)
    static let major = Color(white: 0.12)
    static let minor = Color(white: 0.07)
    static let line = Color(white: 0.25)
    static let note = Color(white: 0.1)

    /// The triangle the Tonnetz is at: tinted, and lit while it sounds.
    static func current(isSounding: Bool) -> Color {
        Color.orange.opacity(isSounding ? 0.85 : 0.25)
    }

    static func fill(of cell: TonnetzCell) -> Color {
        cell.pointsUp ? major : minor
    }

    /// Text on the triangle the Tonnetz is at.
    static func currentText(isSounding: Bool) -> Color {
        isSounding ? Color.black.opacity(0.8) : Color(white: 0.9)
    }
}

/// One note of the net: its name on a disc. `isCurrent` marks a note of the
/// triad the Tonnetz is at, and `isRoot` that triad's root. A note sounding
/// by itself (`isSounding`) is lit, as the triangle that sounds is.
struct TonnetzNote: View {
    let pitchClass: PitchClass
    let diameter: CGFloat
    var isCurrent = false
    var isRoot = false
    var isSounding = false

    var body: some View {
        Text(pitchClass.name)
            .font(.system(size: diameter * 0.4, weight: .medium, design: .monospaced))
            .foregroundStyle(isSounding ? Color.black.opacity(0.8) : Color(white: 0.85))
            .lineLimit(1)
            .frame(width: diameter, height: diameter)
            .background(
                Circle()
                    .fill(isSounding ? Color.orange : TonnetzStyle.note)
                    .overlay(Circle().strokeBorder(isCurrent || isSounding ? Color.orange : Color(white: 0.3),
                                                   lineWidth: isRoot ? 3 : 1))
            )
    }
}

extension TonnetzNet {
    /// The outlines of `cells`, as one path.
    func outline(of cells: [TonnetzCell]) -> Path {
        Path { path in
            for cell in cells {
                path.addLines(corners(of: cell))
                path.closeSubpath()
            }
        }
    }
}
