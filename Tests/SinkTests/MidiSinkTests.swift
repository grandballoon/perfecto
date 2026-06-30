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
        sink.playChord(Voicing(notes: [60, 64, 67]))
        let ons = backend.noteOnCalls
        #expect(ons.count == 3)
        #expect(ons.map(\.note).sorted() == [60, 64, 67])
        #expect(ons.allSatisfy { $0.velocity == 100 })
        #expect(ons.allSatisfy { $0.channel == 0 })
    }

    @Test func stopChordSendsNoteOffForEachActiveNote() {
        let (sink, backend) = makeSubject()
        sink.playChord(Voicing(notes: [60, 64, 67]))
        backend.reset()
        sink.stopChord()
        let offs = backend.noteOffCalls
        #expect(offs.count == 3)
        #expect(offs.map(\.note).sorted() == [60, 64, 67])
    }

    @Test func playChordStopsPreviousNotesBeforeNewOnes() {
        let (sink, backend) = makeSubject()
        sink.playChord(Voicing(notes: [60, 64, 67]))
        sink.playChord(Voicing(notes: [62, 65, 69]))
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
        sink.playChord(Voicing(notes: [60, 64, 67]))
        sink.stopChord()
        backend.reset()
        sink.stopChord()
        #expect(backend.calls.isEmpty)
    }
}
