import AVKit
import SwiftUI

/// The side panel's Sound page: the synth sounds by category, and where the
/// audio goes.
struct SoundPanel: View {
    @Environment(PerformanceState.self) private var state
    @State private var outputName = SoundPanel.currentOutputName()

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(SynthPreset.Category.allCases) { category in
                presetSection(category)
            }
            outputSection
            samplesSection
        }
        .onReceive(NotificationCenter.default.publisher(
            for: AVAudioSession.routeChangeNotification
        ).receive(on: RunLoop.main)) { _ in
            outputName = Self.currentOutputName()
        }
    }

    private static func currentOutputName() -> String {
        AVAudioSession.sharedInstance().currentRoute.outputs.first?.portName ?? "No output"
    }

    // MARK: – Sounds

    private func presetSection(_ category: SynthPreset.Category) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SidePanelSectionLabel(category.displayName.uppercased())
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2),
                spacing: 8
            ) {
                ForEach(category.presets) { preset in
                    SidePanelChip(label: preset.name, selected: state.synthPreset == preset) {
                        state.setSynthPreset(preset)
                    }
                }
            }
        }
    }

    // MARK: – Output

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SidePanelSectionLabel("OUTPUT")
            HStack {
                Text(outputName)
                    .font(.system(size: 15, design: .monospaced))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                RoutePicker()
                    .frame(width: 32, height: 32)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.10)))
            Text("Send audio to a Mac via AirPlay, or to Bluetooth speakers.")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color(white: 0.3))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: – Samples

    private var samplesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SidePanelSectionLabel("SAMPLES")
            VStack(alignment: .leading, spacing: 3) {
                Text("Salamander Piano")
                    .font(.system(size: 15, design: .monospaced))
                    .foregroundStyle(Color(white: 0.3))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("coming soon")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color(white: 0.22))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.07))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(white: 0.13), lineWidth: 1)))
        }
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
