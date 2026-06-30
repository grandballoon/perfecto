import SwiftUI

/// Handles all three stages of microphone permission gating.
/// Present as a sheet whenever MicSampleState.permissionFlow is non-nil.
struct PermissionFlowView: View {

    let step: PermissionFlowStep
    let gate: any PermissionGate
    @Binding var flowStep: PermissionFlowStep?

    var body: some View {
        switch step {
        case .prePrompt:       prePromptView
        case .settingsRedirect: settingsRedirectView
        case .restricted:      restrictedView
        }
    }

    // MARK: – Stage 1: Pre-prompt

    private var prePromptView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "mic.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("Microphone Access")
                .font(.system(size: 22, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
            Text("Mic Sample mode records a short audio clip that you play back via the chord buttons.")
                .font(.system(size: 15, design: .monospaced))
                .foregroundStyle(Color(white: 0.65))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            VStack(spacing: 12) {
                actionButton(label: "Continue") {
                    Task {
                        let result = await gate.requestSystemPrompt()
                        flowStep = result == .denied ? .settingsRedirect
                                 : result == .restricted ? .restricted
                                 : nil
                    }
                }
                dismissButton(label: "Not Now") { flowStep = nil }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.07))
    }

    // MARK: – Stage 3: Settings redirect (denied)

    private var settingsRedirectView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "mic.slash.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color(white: 0.45))
            Text("Microphone Denied")
                .font(.system(size: 22, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
            Text("To use Mic Sample mode, enable microphone access for Perfecto in Settings.")
                .font(.system(size: 15, design: .monospaced))
                .foregroundStyle(Color(white: 0.65))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            VStack(spacing: 12) {
                actionButton(label: "Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                    flowStep = nil
                }
                dismissButton(label: "Cancel") { flowStep = nil }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.07))
    }

    // MARK: – Restricted

    private var restrictedView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "lock.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color(white: 0.45))
            Text("Microphone Restricted")
                .font(.system(size: 22, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
            Text("Microphone access is restricted on this device and cannot be enabled.")
                .font(.system(size: 15, design: .monospaced))
                .foregroundStyle(Color(white: 0.65))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            dismissButton(label: "OK") { flowStep = nil }
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.07))
    }

    // MARK: – Shared buttons

    private func actionButton(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange))
        }
        .buttonStyle(.plain)
    }

    private func dismissButton(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 16, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(white: 0.6))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(white: 0.13))
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(white: 0.25), lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
    }
}
