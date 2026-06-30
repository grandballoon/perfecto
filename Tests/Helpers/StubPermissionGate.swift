@testable import Perfecto

@MainActor
final class StubPermissionGate: PermissionGate {
    var state: PermissionState
    var nextResult: PermissionState
    private(set) var requestCallCount = 0

    init(state: PermissionState = .undetermined, nextResult: PermissionState = .granted) {
        self.state = state
        self.nextResult = nextResult
    }

    func requestSystemPrompt() async -> PermissionState {
        requestCallCount += 1
        state = nextResult
        return nextResult
    }
}
