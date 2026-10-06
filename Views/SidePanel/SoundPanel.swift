import AVKit
import SwiftUI

/// The side panel's Sound page: the sounds by category, the mic sample's
/// recording, and where the audio goes.
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
            if category == .recorded { MicSampleRecorderRow(sample: state.micSample) }
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

/// Records the mic sample, and says what there is of it.
private struct MicSampleRecorderRow: View {
    let sample: MicSampleState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button { sample.toggle() } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(sample.isRecording ? Color.red : Color.orange)
                            .frame(width: 10, height: 10)
                        Text(sample.isRecording ? "STOP" : "REC")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.13))
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .stroke(sample.isRecording ? Color.red : Color(white: 0.28), lineWidth: 1)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(sample.isRecording ? "Stop recording" : "Record a sample")

                status
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Color(white: 0.6))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }
            Text(hint)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color(white: 0.3))
                .fixedSize(horizontal: false, vertical: true)
            if sample.isRefused, let settings = URL(string: UIApplication.openSettingsURLString) {
                Link("Open Settings", destination: settings)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        if let startedAt = sample.startedAt {
            TimelineView(.periodic(from: startedAt, by: 0.1)) { context in
                Text(Self.seconds(context.date.timeIntervalSince(startedAt)) + " / \(MicSampleState.longest) s")
            }
        } else if sample.hasSample {
            Text(Self.seconds(sample.duration) + " s recorded")
        } else {
            Text("No sample yet")
        }
    }

    private var hint: String {
        if sample.isRefused { return "Perfecto is not allowed to use the microphone." }
        if sample.heardNothing { return "Nothing was heard. Record again, closer or louder." }
        return "Record a sound, then play it on the keys at any pitch."
    }

    private static func seconds(_ seconds: TimeInterval) -> String {
        String(format: "%.1f", max(seconds, 0))
    }
}
