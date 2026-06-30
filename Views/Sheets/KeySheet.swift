import SwiftUI

struct KeySheet: View {
    @Environment(PerformanceState.self) private var state
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    rootSection
                    scaleSection
                    octaveSection
                }
                .padding(20)
            }
            .background(Color.black)
            .navigationTitle("Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(white: 0.07), for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.orange)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: – Root

    private var rootSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("ROOT")
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                spacing: 8
            ) {
                ForEach(PitchClass.allCases) { pitch in
                    chipButton(
                        label: pitch.name,
                        selected: state.key.root == pitch
                    ) {
                        state.key = Key(root: pitch, scale: state.key.scale)
                    }
                }
            }
        }
    }

    // MARK: – Scale

    private var scaleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("SCALE")
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2),
                spacing: 8
            ) {
                ForEach(ScaleType.allCases) { scale in
                    chipButton(
                        label: scale.displayName,
                        selected: state.key.scale == scale
                    ) {
                        state.key = Key(root: state.key.root, scale: scale)
                    }
                }
            }
        }
    }

    // MARK: – Octave

    private var octaveSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("OCTAVE")
            HStack(spacing: 24) {
                Button {
                    if state.octave > 2 { state.octave -= 1 }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(state.octave > 2 ? Color.orange : Color(white: 0.25))
                }
                .buttonStyle(.plain)

                Text("\(state.octave)")
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .frame(minWidth: 24)

                Button {
                    if state.octave < 7 { state.octave += 1 }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(state.octave < 7 ? Color.orange : Color(white: 0.25))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: – Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(Color(white: 0.4))
            .kerning(2)
    }

    private func chipButton(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(selected ? .black : .white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(selected ? Color.orange : Color(white: 0.15))
                )
        }
        .buttonStyle(.plain)
    }
}
