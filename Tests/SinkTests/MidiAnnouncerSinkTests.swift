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

    private static let context = performanceContext(
        key: Key(root: .D, scale: .dorian), octave: 4,
        spec: ChordSpec(degree: .ii, color: .joystick(.extended, .upRight)))

    @Test func playChordSendsDecodableChordFrame() {
        let transport = RecordingSysExTransport()
        let sink = MidiAnnouncerSink(transport: transport)

        let event = ChordEvent.block([62, 65, 69, 72, 76], context: Self.context)
        sink.playChord(event)

        #expect(transport.frames.count == 1)
        guard case let .chord(announcement)? = ChordWire.decode(transport.frames[0]) else {
            Issue.record("frame did not decode as a chord")
            return
        }
        #expect(announcement.key == Key(root: .D, scale: .dorian))
        #expect(announcement.degree == .ii)
        #expect(announcement.joystickMode == .extended)
        #expect(announcement.joystickDirection == .upRight)
        #expect(announcement.inversion == Self.context.inversion)
        #expect(announcement.voiceLeading == Self.context.voiceLeading)
        #expect(announcement.voicing == event.voicing)
    }

    @Test func stopChordSendsReleaseFrame() {
        let transport = RecordingSysExTransport()
        let sink = MidiAnnouncerSink(transport: transport)

        sink.stopChord()

        #expect(transport.frames == [ChordWire.encodeRelease()])
    }

    // MARK: – Through sequencer playback

    /// A sequencer step plays its own color; the frame must announce that
    /// color, not whatever the live joystick happens to be on.
    @Test func sequencerStepIsAnnouncedWithItsOwnColor() {
        let transport = RecordingSysExTransport()
        let clock = ManualClock()
        let state = PerformanceState(sink: MidiAnnouncerSink(transport: transport), clock: clock)

        let seq = SequencerState(defaults: isolatedDefaults())
        seq.steps[0] = SequencerStep(degree: .V, color: .joystick(.default, .upRight))
        state.setMode(SequencerMode(seq))
        seq.isPlaying = true
        clock.tick()

        let lastFrame: [UInt8] = transport.frames.last ?? []
        guard case let .chord(announcement)? = ChordWire.decode(lastFrame) else {
            Issue.record("no chord frame for the step")
            return
        }
        #expect(announcement.degree == .V)
        #expect(announcement.joystickDirection == .upRight)
        #expect(announcement.voicing.notes == [67, 71, 74, 77])   // G7
    }
}
