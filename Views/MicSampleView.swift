import SwiftUI

struct MicSampleView: View {
    @Environment(PerformanceState.self) private var state

    var body: some View {
        let micState = state.micSampleState
        VStack(spacing: 20) {
            recordButton(micState: micState)
            if micState.hasContent {
                Text("Sample ready — press chord buttons to play")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color(white: 0.5))
            } else if !micState.isRecording {
                Text("Press REC to record a sample")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color(white: 0.35))
            }
        }
        .sheet(item: Binding(
            get: { micState.permissionFlow },
            set: { micState.permissionFlow = $0 }
        )) { step in
            PermissionFlowView(
                step: step,
                gate: state.micGate,
                flowStep: Binding(
                    get: { micState.permissionFlow },
                    set: { micState.permissionFlow = $0 }
                )
            )
            .presentationDetents([.medium])
        }
    }

    private func recordButton(micState: MicSampleState) -> some View {
        Button {
            if micState.isRecording {
                state.stopMicRecording()
            } else {
                state.startMicRecording()
            }
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(micState.isRecording ? Color.red : Color.orange)
                    .frame(width: 10, height: 10)
                Text(micState.isRecording ? "STOP" : "REC")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(white: 0.13))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(micState.isRecording ? Color.red : Color(white: 0.28), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }
}

extension PermissionFlowStep: Identifiable {
    var id: Int {
        switch self {
        case .prePrompt:        return 0
        case .settingsRedirect: return 1
        case .restricted:       return 2
        }
    }
}
