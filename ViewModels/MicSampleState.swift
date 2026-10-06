import Foundation
import Observation

/// The mic sample as the Sound panel shows it: whether one is being
/// recorded, how long the one there is lasts, and whether the app may use
/// the mic at all.
@MainActor
@Observable
final class MicSampleState {

    /// The longest a sample can be, in seconds.
    static let longest = 30

    private(set) var isRecording = false
    /// When the recording under way was started.
    private(set) var startedAt: Date?
    /// Seconds of sound there are to play: 0 is no sample.
    private(set) var duration: TimeInterval
    /// The last recording had nothing audible in it.
    private(set) var heardNothing = false
    /// The app has been refused the mic, which only Settings can change.
    private(set) var isRefused: Bool

    /// Called when a sample has been recorded and can be played.
    var onRecorded: () -> Void = {}

    private let recorder: SampleRecorder?
    private let gate: any PermissionGate

    /// Without a recorder (tests, previews) there is nothing to record with.
    init(recorder: SampleRecorder? = nil, gate: any PermissionGate = NoopPermissionGate()) {
        self.recorder = recorder
        self.gate = gate
        duration = recorder?.duration ?? 0
        isRefused = gate.state == .denied || gate.state == .restricted
        recorder?.onEnd = { [weak self] in self?.ended() }
    }

    var hasSample: Bool { duration > 0 }

    /// Starts a recording, asking for the mic first if the app has never
    /// asked, or ends the one under way.
    func toggle() {
        if isRecording {
            recorder?.stop()
            return
        }
        switch gate.state {
        case .granted:
            record()
        case .undetermined:
            Task {
                let answer = await gate.requestSystemPrompt()
                isRefused = answer != .granted
                if answer == .granted { record() }
            }
        case .denied, .restricted:
            isRefused = true
        }
    }

    private func record() {
        guard let recorder, !isRecording else { return }
        isRefused = false
        heardNothing = false
        isRecording = true
        startedAt = Date()
        recorder.start()
    }

    private func ended() {
        isRecording = false
        startedAt = nil
        duration = recorder?.duration ?? 0
        heardNothing = duration == 0
        if hasSample { onRecorded() }
    }
}
