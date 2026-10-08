import Foundation
import Testing
@testable import Perfecto

/// The app's own output with the real audio session and the real mic: the
/// engine started again each time the mic is opened and let go.
///
/// It tells the most on a phone. The simulator's session always has an
/// input, so an engine starts there in states a phone refuses, as it once
/// refused the start after every recording.
@MainActor
@Suite(.serialized)
struct AudioOutputLiveTests {

    private let logger = RecordingLogger()

    /// An output that keeps no sample, so the app's own is left alone.
    private func output() -> AudioOutput {
        AudioOutput(sampleURL: nil, logger: logger)
    }

    /// How the engine's latest start went: nil if it has not been started.
    private var started: Bool? {
        logger.events.lazy.reversed().compactMap { event -> Bool? in
            switch event {
            case .audio_engine_started: true
            case .audio_engine_failed: false
            default: nil
            }
        }.first
    }

    /// How long the real session and engine are given to act. Beside the
    /// rest of the tests, on a simulator just started, they have taken
    /// longer than `waitUntil` allows by default.
    private let patience: Duration = .seconds(30)

    private func record(with output: AudioOutput) async throws {
        var ended = 0
        output.sampleRecorder.onEnd = { ended += 1 }
        output.sampleRecorder.start()
        #expect(try await waitUntil(timeout: patience) { output.sampleRecorder.phase == .recording })
        try await Task.sleep(for: .milliseconds(300))
        output.sampleRecorder.stop()
        #expect(try await waitUntil(timeout: patience) { ended == 1 })
    }

    @Test func theEngineRunsAgainAfterEachRecording() async throws {
        let output = output()
        for _ in 0..<2 {
            try await record(with: output)
            #expect(started == true)
        }
    }

    @Test func theEngineRunsAgainAfterTheVocoder() async throws {
        let output = output()
        output.isVocoding = true
        #expect(started == true)
        // A recording made through the open mic leaves it open.
        try await record(with: output)
        output.isVocoding = false
        #expect(started == true)
    }
}
