import SwiftUI

struct SettingsSheet: View {
    @Environment(PerformanceState.self) private var state
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var state = state
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: $state.horizontalLandscapeChords) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Horizontal chord row")
                                .font(.system(size: 15, design: .monospaced))
                                .foregroundStyle(.white)
                            Text("In landscape, show the seven chord buttons in one tall row on the right, instead of the staggered grid.")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Color(white: 0.45))
                        }
                    }
                    .tint(.orange)
                    .listRowBackground(Color(white: 0.10))
                } header: {
                    sectionLabel("LAYOUT")
                }

                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Press and hold the KEY button to quick-pick a key without opening this menu.")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color(white: 0.45))
                        Picker("Style", selection: $state.keyQuickStyle) {
                            ForEach(KeyQuickStyle.allCases, id: \.self) { style in
                                Text(style.label).tag(style)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(Color(white: 0.10))
                } header: {
                    sectionLabel("KEY QUICK-SELECT")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .navigationTitle("Settings")
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
