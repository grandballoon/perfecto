import SwiftUI

/// The color ring and the tone marks under it, wired to the live
/// performance. While the ring keeps its color (the pin beside the marks),
/// a cell tapped is kept, and so are the marks, until another cell or mark
/// is tapped or COLOR ↺ goes back to the plain chord. While it does not,
/// the cell plays while a finger is on the ring and a mark while its button
/// is held. The ring is drawn for the chord being held, or the tonic's with
/// none held.
struct ColorRingSurface: View {
    @Environment(PerformanceState.self) private var state

    var body: some View {
        let degree = state.activeDegree ?? .I
        VStack(spacing: ToneMarksRow.spacing) {
            ColorRingPad(key: state.playedKey, degree: degree, arrangement: state.ringArrangement,
                         chosen: state.ringCell, marks: state.ringMarks,
                         onChoose: { state.ringChose($0) }, onLift: { state.ringLifted() })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            ToneMarksRow(mode: ColorRing.mode(of: state.ringCell, key: state.playedKey, degree: degree),
                         height: state.ringCell.height, marks: state.ringMarks)
        }
    }
}

/// The tone marks: a column to each tone of the chord above the root, with
/// a semitone up, a semitone down, and leave it out. Each is one step
/// (`colorSteps`). A tone the cell has not got is dimmed, and one the stack
/// leaves out because it clashes is outlined, to be brought back. Every
/// button is named by what it would make of the tone: ▲ sus4, ▼ ♭9.
struct ToneMarksRow: View {
    let mode: HeptatonicMode
    let height: StackHeight
    let marks: ToneMarks

    @Environment(PerformanceState.self) private var state

    static let rowHeight: CGFloat = 22
    /// Between the rows of buttons, and between the ring and the first.
    static let spacing: CGFloat = 3

    var body: some View {
        let options = toneMarkOptions(mode.intervals, height: height, marks: marks)
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(options, id: \.tone) { option in
                VStack(spacing: Self.spacing) {
                    move(option, by: 1, name: option.up)
                    move(option, by: -1, name: option.down)
                    skip(option)
                }
            }
            VStack(spacing: Self.spacing) {
                @Bindable var state = state
                KeepSwitch(label: "Keep the ring's color", keeps: $state.keepsRingColor)
                    .frame(width: 52, height: Self.rowHeight)
                // Only what is kept needs undoing.
                Button { state.resetRingColor() } label: {
                    Text("COLOR\n↺")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color(white: state.keepsRingColor ? 0.8 : 0.3))
                        .frame(width: 52, height: Self.rowHeight * 2 + Self.spacing)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color(white: 0.12)))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(white: 0.25), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(!state.keepsRingColor)
                .accessibilityLabel("Back to the plain chord")
            }
        }
    }

    private func move(_ option: ToneMarkOption, by offset: Int, name: String?) -> some View {
        let isOn = option.moved == offset
        return ToneMarkChip(text: (offset > 0 ? "▲ " : "▼ ") + (name ?? ""), isOn: isOn,
                            isEnabled: name != nil || isOn, outlined: false,
                            onPress: { state.pressToneMark(.move(option.tone, by: offset)) },
                            onRelease: { state.releaseToneMark(.move(option.tone, by: offset)) })
            .accessibilityLabel("\(option.tone.rawValue) \(offset > 0 ? "up" : "down")")
    }

    private func skip(_ option: ToneMarkOption) -> some View {
        let byStack = option.isDroppedByStack && option.isLeftOut
        let isOn = option.isLeftOut && !byStack
        return ToneMarkChip(text: "✕ " + String(option.tone.rawValue), isOn: isOn,
                            isEnabled: option.isInStack, outlined: byStack,
                            onPress: { state.pressToneMark(.skip(option.tone)) },
                            onRelease: { state.releaseToneMark(.skip(option.tone)) })
            .accessibilityLabel(byStack ? "Bring back the \(option.tone.rawValue)" : "Leave out the \(option.tone.rawValue)")
    }
}

/// One tone mark's button. It acts as its finger comes down and says when
/// it lifts, so a mark can be held as well as tapped; each button is read
/// by itself, so several can be held at once.
private struct ToneMarkChip: View {
    let text: String
    let isOn: Bool
    let isEnabled: Bool
    let outlined: Bool
    let onPress: () -> Void
    let onRelease: () -> Void

    @State private var isDown = false

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(isOn ? Color.black : Color(white: isEnabled ? 0.9 : 0.3))
            .frame(maxWidth: .infinity)
            .frame(height: ToneMarksRow.rowHeight)
            .background(RoundedRectangle(cornerRadius: 5).fill(isOn ? Color.orange : Color(white: 0.12)))
            .overlay(RoundedRectangle(cornerRadius: 5)
                .stroke(outlined ? Color.orange : Color(white: isEnabled ? 0.25 : 0.12),
                        style: StrokeStyle(lineWidth: 1, dash: outlined ? [3, 2] : [])))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard isEnabled, !isDown else { return }
                        isDown = true
                        onPress()
                    }
                    .onEnded { _ in
                        guard isDown else { return }
                        isDown = false
                        onRelease()
                    }
            )
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onPress(); onRelease() }
    }
}
