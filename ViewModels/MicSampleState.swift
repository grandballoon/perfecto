import Observation

enum PermissionFlowStep {
    case prePrompt, settingsRedirect, restricted
}

@Observable
@MainActor
final class MicSampleState {
    var isRecording: Bool = false
    var hasContent:  Bool = false
    var permissionFlow: PermissionFlowStep? = nil
}
