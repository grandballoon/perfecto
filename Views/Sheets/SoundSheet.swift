import SwiftUI

struct SoundSheet: View {
    @Environment(PerformanceState.self) private var state
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(SynthPreset.allCases) { preset in
                        Button {
                            state.setSynthPreset(preset)
                        } label: {
                            HStack {
                                Text(preset.name)
                                    .font(.system(size: 15, design: .monospaced))
                                    .foregroundStyle(.white)
                                Spacer()
                                if state.synthPreset == preset {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.orange)
                                        .fontWeight(.semibold)
                                }
                            }
                        }
                        .listRowBackground(Color(white: 0.1))
                    }
                } header: {
                    sectionLabel("SYNTH")
                }

                Section {
                    HStack {
                        Text("Salamander Piano")
                            .font(.system(size: 15, design: .monospaced))
                            .foregroundStyle(Color(white: 0.3))
                        Spacer()
                        Text("coming soon")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color(white: 0.22))
                    }
                    .listRowBackground(Color(white: 0.07))
                } header: {
                    sectionLabel("SAMPLES")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .navigationTitle("Sound")
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

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(Color(white: 0.4))
            .kerning(2)
    }
}
