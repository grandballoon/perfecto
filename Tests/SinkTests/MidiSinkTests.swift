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

    /// A MIDI sink playing chords, as it does in the app: behind a `NotePlayer`.
    private func makePlayer() -> (NotePlayer, RecordingMidiBackend) {
        let (midi, backend) = makeSubject()
        return (NotePlayer([midi], clock: ManualClock()), backend)
    }

    @Test func playChordSendsNoteOnForEachNote() {
        let (sink, backend) = makePlayer()
        sink.playChord(.block([60, 64, 67]))
        let ons = backend.noteOnCalls
        #expect(ons.count == 3)
        #expect(ons.map(\.note).sorted() == [60, 64, 67])
        #expect(ons.allSatisfy { $0.velocity == 100 })
        #expect(ons.allSatisfy { $0.channel == 0 })
    }

    @Test func stopChordSendsNoteOffForEachActiveNote() {
        let (sink, backend) = makePlayer()
        sink.playChord(.block([60, 64, 67]))
        backend.reset()
        sink.stopChord()
        let offs = backend.noteOffCalls
        #expect(offs.count == 3)
        #expect(offs.map(\.note).sorted() == [60, 64, 67])
    }

    @Test func playChordStopsPreviousNotesBeforeNewOnes() {
        let (sink, backend) = makePlayer()
        sink.playChord(.block([60, 64, 67]))
        sink.playChord(.block([62, 65, 69]))
        // First play: 3 noteOns. Second play: 3 noteOffs (for [60,64,67]) then 3 noteOns.
        #expect(backend.noteOffCalls.map(\.note).sorted() == [60, 64, 67])
        #expect(backend.noteOnCalls.count == 6)
    }

    @Test func stopWithNoActiveNotesSendsNothing() {
        let (sink, backend) = makePlayer()
        sink.stopChord()
        #expect(backend.calls.isEmpty)
    }

    @Test func secondStopAfterStopSendsNothing() {
        let (sink, backend) = makePlayer()
        sink.playChord(.block([60, 64, 67]))
        sink.stopChord()
        backend.reset()
        sink.stopChord()
        #expect(backend.calls.isEmpty)
    }

    // MARK: – Notes

    /// Two layers can hold the same pitch. MIDI has one note per pitch, so
    /// it is ended only when both have let go.
    @Test func aPitchTwoNotesShareEndsWithTheLastOfThem() {
        let (sink, backend) = makeSubject()
        let first = NoteID.next(), second = NoteID.next()
        sink.noteOn(first, note: 60, sound: NoteSound(), at: 0)
        sink.noteOn(second, note: 60, sound: NoteSound(), at: 0)
        sink.noteOff(first, at: 0)
        #expect(backend.noteOffCalls.isEmpty)
        sink.noteOff(second, at: 0)
        #expect(backend.noteOffCalls.map(\.note) == [60])
    }

    @Test func endingANoteThatIsNotSoundingSendsNothing() {
        let (sink, backend) = makeSubject()
        sink.noteOff(.next(), at: 0)
        #expect(backend.calls.isEmpty)
    }

    // MARK: – Through a real button press

    /// B major, octave 7, vii with ↘ (add9) reaches MIDI note 132. Bytes above
    /// 127 are status bytes (132 = 0x84, Note Off on channel 5), so every note
    /// on the wire must be a valid 7-bit data byte.
    @Test func chordsNearTheTopOfTheRangeStayValidMidi() {
        let backend = RecordingMidiBackend()
        let clock = ManualClock()
        let state = PerformanceState(sink: NotePlayer([MidiSink(backend: backend)], clock: clock), clock: clock)
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
    @Test func strumReachesMidiLowToHigh() {
        let backend = RecordingMidiBackend()
        let clock = ManualClock()
        let state = PerformanceState(sink: NotePlayer([MidiSink(backend: backend)], clock: clock), clock: clock)
        state.setMode(StrumMode())
        state.press(degree: .I)

        clock.advance(seconds: 3 * StrumMode.noteInterval)
        #expect(backend.noteOnCalls.map(\.note) == [60, 64, 67])
    }

    /// Stopping mid-strum ends the notes already started and cancels the rest.
    @Test func stoppingMidStrumLeavesNothingHanging() {
        let backend = RecordingMidiBackend()
        let clock = ManualClock()
        let sink = NotePlayer([MidiSink(backend: backend)], clock: clock)
        sink.playChord(ChordEvent(voicing: Voicing(notes: [60, 64, 67]),
                                  articulation: .strum(interval: 0.05),
                                  context: .cMajorI))
        clock.advance(seconds: 0.06)
        sink.stopChord()
        #expect(backend.noteOnCalls.count == 2)

        clock.advance(seconds: 1)
        #expect(backend.noteOnCalls.count == 2)
        #expect(backend.noteOffCalls.map(\.note) == backend.noteOnCalls.map(\.note))
    }

    // MARK: – Filter (CC 74)

    private func brightnessValues(_ backend: RecordingMidiBackend) -> [UInt8] {
        backend.controlChangeCalls.map(\.velocity)
    }

    @Test func theFiltersBrightnessIsSentAsController74() {
        let (sink, backend) = makeSubject()
        sink.setFilter(FilterSettings(isOn: true, brightness: 0))
        sink.setFilter(FilterSettings(isOn: true, brightness: 0.5))
        sink.setFilter(FilterSettings(isOn: true, brightness: 1))

        #expect(brightnessValues(backend) == [0, 64, 127])
        #expect(backend.controlChangeCalls.allSatisfy { $0.note == 74 && $0.channel == 0 })
    }

    /// A finger moves far more finely than a controller's 128 steps.
    @Test func aBrightnessThatRoundsToTheSameValueIsSentOnce() {
        let (sink, backend) = makeSubject()
        sink.setFilter(FilterSettings(isOn: true, brightness: 0.500))
        sink.setFilter(FilterSettings(isOn: true, brightness: 0.501))
        #expect(brightnessValues(backend) == [64])
    }

    @Test func aFilterNeverSwitchedOnSendsNothing() {
        let (sink, backend) = makeSubject()
        sink.setFilter(FilterSettings(isOn: false, brightness: 0.2))
        #expect(backend.calls.isEmpty)
    }

    /// Off is fully open, so the receiving synth is not left dark.
    @Test func switchingTheFilterOffOpensItAgain() {
        let (sink, backend) = makeSubject()
        sink.setFilter(FilterSettings(isOn: true, brightness: 0.2))
        sink.setFilter(FilterSettings(isOn: false, brightness: 0.2))
        #expect(brightnessValues(backend) == [25, 127])
    }

    @Test func chorusAndReverbHaveControllersOfTheirOwn() {
        let (sink, backend) = makeSubject()
        sink.setChorus(ChorusSettings(isOn: true, amount: 1))
        sink.setReverb(ReverbSettings(isOn: true, mix: 0.5))
        sink.setFilter(FilterSettings(isOn: true, brightness: 0))

        #expect(backend.controlChangeCalls.map(\.note) == [93, 91, 74])
        #expect(brightnessValues(backend) == [127, 64, 0])
    }

    /// Off, a chorus or reverb is none of it; neither says so unless it was on.
    @Test func switchingChorusOrReverbOffSendsZero() {
        let (sink, backend) = makeSubject()
        sink.setReverb(ReverbSettings(isOn: false, mix: 0.5))
        sink.setChorus(ChorusSettings(isOn: true, amount: 0.5))
        sink.setChorus(ChorusSettings(isOn: false, amount: 0.5))

        #expect(backend.controlChangeCalls.map(\.note) == [93, 93])
        #expect(brightnessValues(backend) == [64, 0])
    }

    /// A chord starts at the brightness its finger landed on, so the
    /// controller goes out ahead of the notes.
    @Test func theSlideIsSentBeforeTheChordItStarts() {
        let backend = RecordingMidiBackend()
        let midi = MidiSink(backend: backend)
        let clock = ManualClock()
        let state = PerformanceState(sink: NotePlayer([midi], clock: clock), effectsListener: midi, clock: clock)
        state.effects.filter.isOn = true
        backend.reset()

        state.slide(on: .I, to: 0.5)
        state.movePointer(from: nil, to: .I)

        #expect(backend.calls.map(\.kind) == [.controlChange, .noteOn, .noteOn, .noteOn])
        #expect(brightnessValues(backend) == [64])
    }
}
