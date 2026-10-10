import Testing
@testable import Perfecto

@Suite("PianoState")
@MainActor
struct PianoStateTests {

    private let clock = ManualClock()
    private let piano = PianoState()

    /// A line of chords shown on the piano as `source`.
    private func player(_ source: PianoSource) -> NotePlayer {
        NotePlayer([piano.line(source)], clock: clock)
    }

    @Test func aChordsNotesAreLitInItsSourcesColorUntilItEnds() {
        let keys = player(.keys)
        keys.playChord(.block([60, 64, 67]))
        #expect(piano.lights == [60: [.keys], 64: [.keys], 67: [.keys]])

        keys.playChord(.block([62, 65, 69]))
        #expect(Set(piano.lights.keys) == [62, 65, 69])

        keys.stopChord()
        #expect(piano.lights.isEmpty)
    }

    @Test func aNoteSeveralSourcesSoundIsLitByEachInAFixedOrder() {
        let solo = player(.solo), keys = player(.keys)
        solo.playChord(.block([67]))
        keys.playChord(.block([60, 64, 67]))
        #expect(piano.lights[67] == [.keys, .solo])
        #expect(piano.lights[60] == [.keys])

        // Each source ends only its own.
        keys.stopChord()
        #expect(piano.lights == [67: [.solo]])
    }

    @Test func twoLayersOnOneNoteKeepItLitUntilBothHaveEnded() {
        let first = player(.layers), second = player(.layers)
        first.playChord(.block([60]))
        second.playChord(.block([60]))
        #expect(piano.lights == [60: [.layers]])

        first.stopChord()
        #expect(piano.lights == [60: [.layers]])
        second.stopChord()
        #expect(piano.lights.isEmpty)
    }

    @Test func aSourceThatIsNotLitIsLeftOutAndShownAgainWithWhatItIsSounding() {
        let keys = player(.keys), tonnetz = player(.tonnetz)
        keys.playChord(.block([60]))
        tonnetz.playChord(.block([60, 64]))

        piano.light(.tonnetz, false)
        #expect(piano.lights == [60: [.keys]])

        piano.light(.tonnetz, true)
        #expect(piano.lights == [60: [.keys, .tonnetz], 64: [.tonnetz]])
    }

    @Test func aStrumsNotesAreLitAsEachIsSounded() {
        let keys = player(.keys)
        keys.playChord(ChordEvent(voicing: Voicing(notes: [60, 64]), articulation: .strum(interval: 0.05),
                                  context: .cMajorI))
        #expect(Set(piano.lights.keys) == [60])
        clock.advance(seconds: 0.05)
        #expect(Set(piano.lights.keys) == [60, 64])
    }

    @Test func switchingThePianoOnAndOffIsLogged() {
        let logger = RecordingLogger()
        let piano = PianoState(logger: logger)
        piano.isOn = true
        piano.isOn = true
        piano.isOn = false
        let switches = logger.events.compactMap { if case let .piano_switched(isOn) = $0 { isOn } else { nil } }
        #expect(switches == [true, false])
    }

    /// The app's own wiring: what the keys play reaches the piano through
    /// the arpeggiator, like every other note sink.
    @Test func theKeysOfAPerformanceLightThePiano() {
        let state = PerformanceState(sink: player(.keys), piano: piano, clock: clock)
        state.press(degree: .I)
        #expect(Set(state.piano.lights.keys) == [60, 64, 67])
        state.release(degree: .I)
        #expect(state.piano.lights.isEmpty)
    }
}
