import SwiftUI

/// The side panel's Key page, the first the menu shows: a quick way to the
/// whole-screen piano, then root, scale and octave.
struct KeyPanel: View {
    @Environment(PerformanceState.self) private var state
    @Environment(SidePanelState.self) private var panel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            pianoButton
            rootSection
            scaleSection
            octaveSection
        }
    }

    // MARK: – Piano

    /// Gives the piano the whole screen, showing it first if it is off, and
    /// closes the menu, so it is not still open when the piano is shrunk.
    private var pianoButton: some View {
        Button {
            panel.close()
            state.piano.isOn = true
            withAnimation(.easeOut(duration: 0.25)) { state.piano.isExpanded = true }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "pianokeys")
                    .font(.system(size: 16, weight: .medium))
                Text("Piano")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(white: 0.5))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.15)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open the piano")
        .help("Give the piano the whole screen, to practise a score run by run")
    }

    // MARK: – Root

    private var rootSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SidePanelSectionLabel("ROOT")
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                spacing: 8
            ) {
                ForEach(PitchClass.allCases) { pitch in
                    SidePanelChip(label: pitch.name, selected: state.key.root == pitch) {
                        state.key = Key(root: pitch, scale: state.key.scale)
                    }
                }
            }
        }
    }

    // MARK: – Scale

    private var scaleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SidePanelSectionLabel("SCALE")
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2),
                spacing: 8
            ) {
                // Pentatonic and blues are hidden until chords on scales with
                // fewer than seven notes are defined (docs/next-phase-plan.md).
                ForEach(ScaleType.allCases.filter(\.isHeptatonic)) { scale in
                    SidePanelChip(label: scale.displayName, selected: state.key.scale == scale) {
                        state.key = Key(root: state.key.root, scale: scale)
                    }
                }
            }
        }
    }

    // MARK: – Octave

    private var octaveSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SidePanelSectionLabel("OCTAVE")
            HStack(spacing: 24) {
                Button {
                    if state.octave > PerformanceState.octaves.lowerBound { state.octave -= 1 }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(state.octave > PerformanceState.octaves.lowerBound ? Color.orange : Color(white: 0.25))
                }
                .buttonStyle(.plain)

                Text("\(state.octave)")
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .frame(minWidth: 24)

                Button {
                    if state.octave < PerformanceState.octaves.upperBound { state.octave += 1 }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(state.octave < PerformanceState.octaves.upperBound ? Color.orange : Color(white: 0.25))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
