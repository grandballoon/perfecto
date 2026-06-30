import AVFoundation

@MainActor
final class MicrophonePermissionGate: PermissionGate {

    private let logger: (any Logger)?

    init(logger: (any Logger)? = nil) {
        self.logger = logger
        logger?.log(.permission_state_observed(permission: "microphone", state: String(describing: state)))
    }

    var state: PermissionState {
        switch AVAudioApplication.shared.recordPermission {
        case .undetermined: return .undetermined
        case .granted:      return .granted
        case .denied:       return .denied
        @unknown default:   return .restricted
        }
    }

    func requestSystemPrompt() async -> PermissionState {
        logger?.log(.permission_system_prompt_requested(permission: "microphone"))
        let granted = await AVAudioApplication.requestRecordPermission()
        let result: PermissionState = granted ? .granted : .denied
        logger?.log(.permission_system_prompt_response(permission: "microphone", granted: granted))
        return result
    }
}
