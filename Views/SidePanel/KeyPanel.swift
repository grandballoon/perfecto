import SwiftUI

/// The side panel's Key page: root, scale and octave.
struct KeyPanel: View {
    @Environment(PerformanceState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            rootSection
            scaleSection
            octaveSection
        }
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
