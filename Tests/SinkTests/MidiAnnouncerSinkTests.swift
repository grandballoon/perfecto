import Testing
@testable import Perfecto

/// Recording double for SysExTransport — captures ChordLink frames instead of
/// touching CoreMIDI, mirroring RecordingMidiBackend.
@MainActor
final class RecordingSysExTransport: SysExTransport {
    private(set) var frames: [[UInt8]] = []
    func send(_ frame: [UInt8]) { frames.append(frame) }
}

@MainActor
@Suite("MidiAnnouncerSink")
struct MidiAnnouncerSinkTests {

    private static func makeContext() -> MidiAnnouncerSink.Context {
        MidiAnnouncerSink.Context(
            key: Key(root: .D, scale: .dorian),
            degree: .ii,
            joystickMode: .extended,
            joystickDirection: .upRight,
            inversion: .root,
            octave: 4,
            voiceLeading: false
        )
    }

    @Test func playChordSendsDecodableChordFrame() {
        let transport = RecordingSysExTransport()
        let sink = MidiAnnouncerSink(transport: transport)
        sink.contextProvider = { Self.makeContext() }

        let voicing = Voicing(notes: [62, 65, 69, 72, 76])
        sink.playChord(voicing)

        #expect(transport.frames.count == 1)
        guard case let .chord(announcement)? = ChordWire.decode(transport.frames[0]) else {
            Issue.record("frame did not decode as a chord")
            return
        }
        #expect(announcement.key == Key(root: .D, scale: .dorian))
        #expect(announcement.degree == .ii)
        #expect(announcement.joystickMode == .extended)
        #expect(announcement.joystickDirection == .upRight)
        #expect(announcement.voicing == voicing)
    }

    @Test func stopChordSendsReleaseFrame() {
        let transport = RecordingSysExTransport()
        let sink = MidiAnnouncerSink(transport: transport)
        sink.contextProvider = { Self.makeContext() }

        sink.stopChord()

        #expect(transport.frames == [ChordWire.encodeRelease()])
    }

    @Test func skipsChordWhenContextUnavailable() {
        let transport = RecordingSysExTransport()
        let sink = MidiAnnouncerSink(transport: transport)
        // No provider set (app startup), then a provider with no active degree.
        sink.playChord(Voicing(notes: [60]))
        sink.contextProvider = { nil }
        sink.playChord(Voicing(notes: [60]))

        #expect(transport.frames.isEmpty)
    }
}
