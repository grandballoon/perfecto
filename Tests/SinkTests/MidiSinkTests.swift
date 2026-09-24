import Testing
@testable import Perfecto

@Suite("MidiSink")
@MainActor
struct MidiSinkTests {

    private func makeSubject() -> (MidiSink, RecordingMidiBackend) {
        let backend = RecordingMidiBackend()
        let sink    = MidiSink(backend: backend)
        return (sink, backend)
    }

    @Test func playChordSendsNoteOnForEachNote() {
        let (sink, backend) = makeSubject()
        sink.playChord(.block([60, 64, 67]))
        let ons = backend.noteOnCalls
        #expect(ons.count == 3)
        #expect(ons.map(\.note).sorted() == [60, 64, 67])
        #expect(ons.allSatisfy { $0.velocity == 100 })
        #expect(ons.allSatisfy { $0.channel == 0 })
    }

    @Test func stopChordSendsNoteOffForEachActiveNote() {
        let (sink, backend) = makeSubject()
        sink.playChord(.block([60, 64, 67]))
        backend.reset()
        sink.stopChord()
        let offs = backend.noteOffCalls
        #expect(offs.count == 3)
        #expect(offs.map(\.note).sorted() == [60, 64, 67])
    }

    @Test func playChordStopsPreviousNotesBeforeNewOnes() {
        let (sink, backend) = makeSubject()
        sink.playChord(.block([60, 64, 67]))
        sink.playChord(.block([62, 65, 69]))
        // First play: 3 noteOns. Second play: 3 noteOffs (for [60,64,67]) then 3 noteOns.
        #expect(backend.noteOffCalls.map(\.note).sorted() == [60, 64, 67])
        #expect(backend.noteOnCalls.count == 6)
    }

    @Test func stopWithNoActiveNotesSendsNothing() {
        let (sink, backend) = makeSubject()
        sink.stopChord()
        #expect(backend.calls.isEmpty)
    }

    @Test func secondStopAfterStopSendsNothing() {
        let (sink, backend) = makeSubject()
        sink.playChord(.block([60, 64, 67]))
        sink.stopChord()
        backend.reset()
        sink.stopChord()
        #expect(backend.calls.isEmpty)
    }

    // MARK: – Through a real button press

    /// B major, octave 7, vii with ↘ (add9) reaches MIDI note 132. Bytes above
    /// 127 are status bytes (132 = 0x84, Note Off on channel 5), so every note
    /// on the wire must be a valid 7-bit data byte.
    @Test func chordsNearTheTopOfTheRangeStayValidMidi() {
        let backend = RecordingMidiBackend()
        let state = PerformanceState(sink: MidiSink(backend: backend), clock: ManualClock())
        state.key = Key(root: .B, scale: .major)
        state.octave = 7
        state.joystickMoved(to: .downRight)
        state.press(degree: .viiDim)

        #expect(backend.noteOnCalls.count == 4)
        #expect(backend.noteOnCalls.allSatisfy { $0.note <= 127 },
                "notes sent: \(backend.noteOnCalls.map(\.note))")
    }

    // MARK: – Strum

    /// Strum mode used to call the audio engine directly, so MIDI got nothing.
    @Test func strumReachesMidiLowToHigh() async throws {
        let backend = RecordingMidiBackend()
        let state = PerformanceState(sink: MidiSink(backend: backend), clock: ManualClock())
        state.setMode(StrumMode())
        state.press(degree: .I)

        try await Task.sleep(for: .seconds(StrumMode.noteInterval * 2 + 0.3))
        #expect(backend.noteOnCalls.map(\.note) == [60, 64, 67])
    }

    /// Stopping mid-strum ends the notes already started and cancels the rest.
    @Test func stoppingMidStrumLeavesNothingHanging() async throws {
        let backend = RecordingMidiBackend()
        let sink = MidiSink(backend: backend)
        sink.playChord(ChordEvent(voicing: Voicing(notes: [60, 64, 67]),
                                  articulation: .strum(interval: 0.05),
                                  context: .cMajorI))
        try await Task.sleep(for: .milliseconds(20))
        sink.stopChord()
        let startedAtStop = backend.noteOnCalls.count

        try await Task.sleep(for: .milliseconds(200))
        #expect(backend.noteOnCalls.count == startedAtStop)
        #expect(backend.noteOffCalls.map(\.note) == backend.noteOnCalls.map(\.note))
    }
}
