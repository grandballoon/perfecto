@MainActor
final class MicSampleMode: PerformanceMode {
    var name: String { "Mic Sample" }
    var requiresClock: Bool { false }

    private let micSampler: MicSampler?
    private let micGate: any PermissionGate
    private let micState: MicSampleState

    init(_ micState: MicSampleState, sampler: MicSampler?, gate: any PermissionGate) {
        self.micState   = micState
        self.micSampler = sampler
        self.micGate    = gate
    }

    func onButtonDown(degree: Degree, state: PerformanceState) {
        switch micGate.state {
        case .undetermined: micState.permissionFlow = .prePrompt
        case .denied:       micState.permissionFlow = .settingsRedirect
        case .restricted:   micState.permissionFlow = .restricted
        case .granted:      handleButtonDown(degree: degree)
        }
    }

    func onButtonUp(degree: Degree, state: PerformanceState) {
        // Sample plays through to end — do not stop on release
    }

    func onJoystickChange(direction: JoystickDirection, state: PerformanceState) {}
    func onClockTick(state: PerformanceState) {}

    func deactivate(state: PerformanceState) {
        micSampler?.stop()
        if micState.isRecording { micSampler?.stopRecording() }
    }

    // MARK: – Private

    private func handleButtonDown(degree: Degree) {
        guard let sampler = micSampler else { return }
        if micState.isRecording {
            sampler.stopRecording()
            micState.isRecording = false
            micState.hasContent  = sampler.hasContent
        } else if micState.hasContent {
            let semitones = degree.index - 3
            sampler.play(semitones: semitones)
        } else {
            sampler.startRecording()
            micState.isRecording = true
        }
    }
}
