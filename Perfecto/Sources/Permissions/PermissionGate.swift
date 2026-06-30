import Foundation

enum PermissionState {
    case undetermined, granted, denied, restricted
}

@MainActor
protocol PermissionGate: AnyObject {
    var state: PermissionState { get }
    func requestSystemPrompt() async -> PermissionState
}

/// Always-granted fallback used when no gate is injected (e.g. tests that don't need permission).
@MainActor
final class NoopPermissionGate: PermissionGate {
    var state: PermissionState { .granted }
    func requestSystemPrompt() async -> PermissionState { .granted }
}
