import Foundation
import Observation

/// The mic sample as the Sound panel shows it: whether one is being
/// recorded and how long the one there is lasts.
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
    /// Called when a sample has been recorded and can be played.
    var onRecorded: () -> Void = {}

    /// Whether the app may use the mic.
    let access: MicAccess
    private let recorder: SampleRecorder?

    /// Without a recorder (tests, previews) there is nothing to record with.
    init(recorder: SampleRecorder? = nil, access: MicAccess = MicAccess()) {
        self.recorder = recorder
        self.access = access
        duration = recorder?.duration ?? 0
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
        access.ask { [weak self] in self?.record() }
    }

    private func record() {
        guard let recorder, !isRecording else { return }
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
