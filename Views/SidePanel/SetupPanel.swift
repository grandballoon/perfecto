import SwiftUI

/// The menu's Setup page: how the chord keys, the chord color surface and
/// the sequencer's bars are laid out.
struct SetupPanel: View {
    @Environment(PerformanceState.self) private var state

    var body: some View {
        @Bindable var state = state
        @Bindable var sequencer = state.sequencerState
        VStack(alignment: .leading, spacing: 24) {
            chordLayoutSection

            choiceSection("CHORD COLOR",
                          detail: "How a second finger colors the chord: the joystick strip, or the grid of stacked thirds (columns) through brighter and darker modes (rows).") {
                Picker("Surface", selection: $state.colorSurface) {
                    ForEach(ColorSurface.allCases, id: \.self) { surface in
                        Text(surface.displayName).tag(surface)
                    }
                }
            }

            choiceSection("SEQUENCER BARS",
                          detail: "How the sequencer shows its bars: one at a time behind numbered tabs, or all of them in one scrolling column (there, one finger selects and two fingers scroll).") {
                Picker("Layout", selection: $sequencer.layout) {
                    ForEach(SequencerLayout.allCases, id: \.self) { layout in
                        Text(layout.displayName).tag(layout)
                    }
                }
            }
        }
    }

    // MARK: – Chord layout

    private var chordLayoutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SidePanelSectionLabel("CHORD LAYOUT")
            VStack(spacing: 8) {
                ForEach(ChordGridLayout.allCases, id: \.self) { layout in
                    chordLayoutRow(layout)
                }
            }
        }
    }

    private func chordLayoutRow(_ layout: ChordGridLayout) -> some View {
        let selected = state.chordGridLayout == layout
        return Button {
            state.chordGridLayout = layout
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(layout.displayName)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(selected ? .black : .white)
                Text(layout.detail)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(selected ? Color.black.opacity(0.65) : Color(white: 0.45))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selected ? Color.orange : Color(white: 0.15))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: – Two-way choices

    private func choiceSection<Choice: View>(_ title: String,
                                             detail: String,
                                             @ViewBuilder picker: () -> Choice) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SidePanelSectionLabel(title)
            picker()
                .pickerStyle(.segmented)
            Text(detail)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color(white: 0.3))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
