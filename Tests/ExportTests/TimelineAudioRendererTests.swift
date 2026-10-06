import AVFoundation
import Testing
@testable import Perfecto

/// A timeline rendered to an audio file: what is written is what plays,
/// each note on its frame.
@Suite("Timeline audio export", .serialized)
@MainActor
struct TimelineAudioRendererTests {

    private let live = LiveSettings(key: Key(root: .C, scale: .major), octave: 4, preset: .squareLead,
                                    effects: NoteEffects())

    /// One bar at 120 (two seconds) of single notes: each a start step and
    /// a length in steps.
    private func timeline(_ notes: [(step: Int, steps: Int)]) -> Timeline {
        var timeline = Timeline(barCount: 1)
        timeline.layers[0].notes = notes.map {
            TimelineNote(start: $0.step * TimelineTime.ticksPerStep, length: $0.steps * TimelineTime.ticksPerStep,
                         chord: ChordSpec(degree: .I, color: .base), pitch: .lead)
        }
        return timeline
    }

    private func render(_ timeline: Timeline, live: LiveSettings? = nil,
                        sample: Recording? = nil) async throws -> (left: [Float], seconds: Double, file: AVAudioFile) {
        let url = FileManager.default.temporaryDirectory.appending(path: "export-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let seconds = try await TimelineAudioRenderer.render(timeline, live: live ?? self.live, bpm: 120,
                                                             sample: sample, to: url)
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                   frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let left = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
        return (left, seconds, file)
    }

    @Test func theFileIsStereoAtFullQualityAndAsLongAsTheTimelineAndItsTail() async throws {
        let (left, seconds, file) = try await render(timeline([(0, 4)]))
        #expect(file.fileFormat.sampleRate == 48_000)
        #expect(file.fileFormat.channelCount == 2)
        #expect(file.fileFormat.settings[AVLinearPCMBitDepthKey] as? Int == 24)
        #expect(abs(seconds - Double(left.count) / 48_000) < 0.001)
        // One bar at 120 is two seconds; the tail of a short release is short.
        #expect(seconds >= 2)
        #expect(seconds < 4)
    }

    @Test func eachNoteStartsOnItsExactFrame() async throws {
        // A short note on the first step and one on the thirteenth, a
        // second and a half in.
        let (left, _, _) = try await render(timeline([(0, 1), (12, 1)]))
        func firstSound(from frame: Int) -> Int? {
            left[frame...].firstIndex { abs($0) > 0.05 }
        }
        let first = try #require(firstSound(from: 0))
        // Within the few milliseconds its attack takes.
        #expect(first < 240)
        // The first has died away before the second starts.
        #expect(loudest(left[60_000..<71_990]) < 0.05)
        let second = try #require(firstSound(from: 60_000))
        #expect(abs(second - 72_000 - first) <= 1)
    }

    @Test func theTimelineIsPlayedOnceAndItsLastNotesRingOut() async throws {
        // A note held to the very end: it is not started again, and what
        // is written ends in silence.
        let (left, seconds, _) = try await render(timeline([(0, 16)]))
        #expect(loudest(left[90_000..<96_000]) > 0.01)
        #expect(loudest(left.suffix(480)) < 0.001)
        #expect(seconds < 4)
        // Nothing starts at the end: no louder there than the held note was.
        #expect(loudest(left[96_000...]) <= loudest(left[90_000..<96_000]) * 1.05)
    }

    @Test func notesOfTheMicSamplePlayTheSample() async throws {
        var live = live
        live.preset = .micSample
        let silent = try await render(timeline([(0, 8)]), live: live)
        #expect(loudest(silent.left) == 0)
        let heard = try await render(timeline([(0, 8)]), live: live, sample: .tone())
        #expect(loudest(heard.left[4800..<24_000]) > 0.05)
    }

    @Test func anEmptyTimelineIsSilence() async throws {
        let (left, seconds, _) = try await render(timeline([]))
        #expect(loudest(left) == 0)
        #expect(abs(seconds - 2) < 0.02)
    }
}
