import Foundation
import Testing
@testable import Perfecto

@Suite("Logger")
@MainActor
struct LoggerTests {

    // MARK: RecordingLogger

    @Test func recordingLoggerCapturesEvents() {
        let logger = RecordingLogger()
        logger.log(.audio_engine_started)
        logger.log(.chord_played(notes: [60, 64, 67], source: .button))
        #expect(logger.events.count == 2)
    }

    @Test func recordingLoggerReset() {
        let logger = RecordingLogger()
        logger.log(.audio_engine_started)
        logger.reset()
        #expect(logger.events.isEmpty)
    }

    // MARK: LogEvent encoding

    @Test func noArgCaseEncodesToTypeKey() throws {
        let data = try JSONEncoder().encode(LogEvent.audio_engine_started)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["type"] as? String == "audio_engine_started")
    }

    @Test func chordPlayedEncodesNotesAndSource() throws {
        let data = try JSONEncoder().encode(LogEvent.chord_played(notes: [60, 64, 67], source: .button))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["type"] as? String == "chord_played")
        #expect(json["source"] as? String == "button")
        #expect((json["notes"] as? [Int])?.sorted() == [60, 64, 67])
    }

    @Test func modeChangedEncodesFromAndTo() throws {
        let data = try JSONEncoder().encode(LogEvent.mode_changed(from: "Play", to: "Drone"))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["type"] as? String == "mode_changed")
        #expect(json["from"] as? String == "Play")
        #expect(json["to"] as? String == "Drone")
    }

    @Test func midiNoteSentEncodesKind() throws {
        let data = try JSONEncoder().encode(LogEvent.midi_note_sent(note: 60, velocity: 100, channel: 0, kind: .noteOn))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["type"] as? String == "midi_note_sent")
        #expect(json["kind"] as? String == "noteOn")
    }

    // MARK: FileLogger

    @Test func fileLoggerWritesToDisk() throws {
        let logger = FileLogger()
        logger.log(.audio_engine_started)
        logger.log(.chord_played(notes: [60, 64, 67], source: .button))
        let content = try String(contentsOf: logger.logFileURL, encoding: .utf8)
        #expect(content.contains("audio_engine_started"))
        #expect(content.contains("chord_played"))
    }
}
