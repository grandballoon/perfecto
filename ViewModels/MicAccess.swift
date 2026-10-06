import Observation

/// Whether the app may use the mic, asked for when something first needs
/// it. Everything that needs the mic asks here, so the system's question
/// is put once and a refusal is said in one way.
@MainActor
@Observable
final class MicAccess {

    /// The app has been refused the mic, which only Settings can change.
    private(set) var isRefused: Bool

    private let gate: any PermissionGate

    init(gate: any PermissionGate = NoopPermissionGate()) {
        self.gate = gate
        isRefused = gate.state == .denied || gate.state == .restricted
    }

    /// Runs `use` if the app may use the mic, asking first if it has never
    /// asked; `refused` if it may not.
    func ask(then use: @escaping @MainActor () -> Void, refused: @escaping @MainActor () -> Void = {}) {
        switch gate.state {
        case .granted:
            isRefused = false
            use()
        case .undetermined:
            Task {
                let answer = await gate.requestSystemPrompt()
                isRefused = answer != .granted
                if answer == .granted { use() } else { refused() }
            }
        case .denied, .restricted:
            isRefused = true
            refused()
        }
    }
}
