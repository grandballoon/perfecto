import SwiftUI

struct ModeSheet: View {
    @Environment(PerformanceState.self) private var state
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(ModeKind.allCases, id: \.self) { kind in
                        modeRow(kind)
                    }
                }

                Section {
                    bpmRow
                } header: {
                    sectionLabel("TEMPO")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .navigationTitle("Mode")
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

    // MARK: – Mode row

    private func modeRow(_ kind: ModeKind) -> some View {
        Button {
            state.selectMode(kind)
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(kind.displayName)
                        .font(.system(size: 15, design: .monospaced))
                        .foregroundStyle(.white)
                    Text(kind.summary)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color(white: 0.45))
                }
                Spacer()
                if state.mode.kind == kind {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.orange)
                        .fontWeight(.semibold)
                }
            }
        }
        .listRowBackground(Color(white: 0.10))
    }

    // MARK: – BPM row

    private var bpmRow: some View {
        HStack(spacing: 20) {
            Button {
                state.setBPM(state.bpm - 5)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(state.bpm > MusicalTime.tempoRange.lowerBound ? Color.orange : Color(white: 0.25))
            }
            .buttonStyle(.plain)

            Spacer()

            Text("\(Int(state.bpm)) BPM")
                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)

            Spacer()

            Button {
                state.setBPM(state.bpm + 5)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(state.bpm < MusicalTime.tempoRange.upperBound ? Color.orange : Color(white: 0.25))
            }
            .buttonStyle(.plain)
        }
        .listRowBackground(Color(white: 0.10))
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(Color(white: 0.4))
            .kerning(2)
    }
}
