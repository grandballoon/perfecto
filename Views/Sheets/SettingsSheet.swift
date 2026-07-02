import SwiftUI

struct SettingsSheet: View {
    @Environment(PerformanceState.self) private var state
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var state = state
        NavigationStack {
            List {
                Section {
                    ForEach(KeyQuickStyle.allCases, id: \.self) { style in
                        Button {
                            state.keyQuickStyle = style
                        } label: {
                            HStack {
                                Text(style.label)
                                    .font(.system(size: 15, design: .monospaced))
                                    .foregroundStyle(.white)
                                Spacer()
                                if state.keyQuickStyle == style {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.orange)
                                        .fontWeight(.semibold)
                                }
                            }
                        }
                        .listRowBackground(Color(white: 0.10))
                    }
                } header: {
                    sectionLabel("KEY SELECTOR STYLE")
                } footer: {
                    Text("Press and hold the KEY button to activate.")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color(white: 0.35))
                }

                Section {
                    ForEach(ChordGridLayout.allCases, id: \.self) { layout in
                        Button {
                            state.chordGridLayout = layout
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(layout.displayName)
                                        .font(.system(size: 15, design: .monospaced))
                                        .foregroundStyle(.white)
                                    Text(layout.detail)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(Color(white: 0.45))
                                }
                                Spacer()
                                if state.chordGridLayout == layout {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.orange)
                                        .fontWeight(.semibold)
                                }
                            }
                        }
                        .listRowBackground(Color(white: 0.10))
                    }
                } header: {
                    sectionLabel("CHORD LAYOUT")
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
