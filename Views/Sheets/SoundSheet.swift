import AVKit
import SwiftUI

struct SoundSheet: View {
    @Environment(PerformanceState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var outputName = SoundSheet.currentOutputName()

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
                        Text(outputName)
                            .font(.system(size: 15, design: .monospaced))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer()
                        RoutePicker()
                            .frame(width: 32, height: 32)
                    }
                    .listRowBackground(Color(white: 0.1))
                } header: {
                    sectionLabel("OUTPUT")
                } footer: {
                    Text("Send audio to a Mac via AirPlay, or to Bluetooth speakers.")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color(white: 0.3))
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
        .onReceive(NotificationCenter.default.publisher(
            for: AVAudioSession.routeChangeNotification
        ).receive(on: RunLoop.main)) { _ in
            outputName = Self.currentOutputName()
        }
    }

    private static func currentOutputName() -> String {
        AVAudioSession.sharedInstance().currentRoute.outputs.first?.portName ?? "No output"
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(Color(white: 0.4))
            .kerning(2)
    }
}

/// System AirPlay/Bluetooth output picker.
private struct RoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = UIColor(white: 0.6, alpha: 1)
        picker.activeTintColor = .systemOrange
        picker.prioritizesVideoDevices = false
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
