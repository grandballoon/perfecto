import Testing
@testable import Perfecto

@Suite("PlayMode")
@MainActor
struct PlayModeTests {

    // MARK: – Helpers

    private func makeState(clock: ManualClock = ManualClock()) -> (PerformanceState, RecordingSink) {
        let sink = RecordingSink()
        let state = PerformanceState(sink: sink, clock: clock)
        return (state, sink)
    }

    // MARK: – Phase-exit test (spec §12.1)
    //
    // PlayMode.onButtonDown should emit exactly one playChord with the correct voicing
    // for the default key (C major) and degree I at octave 4 with no joystick.
    //
    // Expected: Cmaj (C-E-G) = [60, 64, 67]

    @Test func buttonDownPlaysCorrectVoicing() {
        let (state, sink) = makeState()
        state.press(degree: .I)

        #expect(sink.playCalls.count == 1)
        #expect(sink.playCalls.first?.notes == [60, 64, 67])
    }

    @Test func buttonUpStopsChord() {
        let (state, sink) = makeState()
        state.press(degree: .I)
        state.release(degree: .I)

        #expect(sink.calls.last == .stop)
        #expect(state.activeDegree == nil)
    }

    @Test func joystickChangeWhileHeldRecomputesVoicing() {
        let (state, sink) = makeState()
        state.press(degree: .I)          // Cmaj [60,64,67]
        sink.reset()
        state.joystickMoved(to: .right)  // → Cmaj7 [60,64,67,71]

        #expect(sink.playCalls.first?.notes == [60, 64, 67, 71])
    }

    @Test func joystickChangedWithNoHeldDegreeDoesNothing() {
        let (state, sink) = makeState()
        state.joystickMoved(to: .up)

        #expect(sink.calls.isEmpty)
    }

    @Test func pressingNewDegreeWhileHoldingPreviousReplaces() {
        let (state, sink) = makeState()
        state.press(degree: .I)   // Cmaj
        state.release(degree: .I)
        state.press(degree: .IV)  // Fmaj [65,69,72]

        #expect(sink.playCalls.last?.notes == [65, 69, 72])
    }

    // MARK: – Two fingers

    /// Holding I, then IV, then lifting I (e.g. two fingers on the grid layout's
    /// buttons) must leave IV sounding: the release belongs to a press that
    /// IV already replaced.
    @Test func liftingAnEarlierFingerKeepsTheLaterChord() {
        let (state, sink) = makeState()
        state.press(degree: .I)
        state.press(degree: .IV)
        state.release(degree: .I)

        #expect(sink.stopCount == 0)
        #expect(sink.lastPlay?.notes == [65, 69, 72])
        #expect(state.activeDegree == .IV)
    }

    /// Holding I, tapping IV: lifting IV hands the chord back to I, with no
    /// stop in between. The sound is I, IV, I.
    @Test func liftingTheLaterFingerReturnsToTheEarlierChord() {
        let (state, sink) = makeState()
        state.press(degree: .I)
        state.press(degree: .IV)
        state.release(degree: .IV)

        #expect(sink.stopCount == 0)
        #expect(sink.playCalls.map(\.notes) == [[60, 64, 67], [65, 69, 72], [60, 64, 67]])
        #expect(state.activeDegree == .I)
        #expect(state.heldDegrees == [.I])

        state.release(degree: .I)
        #expect(sink.calls.last == .stop)
        #expect(state.activeDegree == nil)
    }

    /// Three fingers unwind in order: lifting the active one resumes the most
    /// recent press still held, skipping any lifted in the meantime.
    @Test func liftingFingersUnwindsToTheMostRecentHeldChord() {
        let (state, sink) = makeState()
        state.press(degree: .I)
        state.press(degree: .IV)
        state.press(degree: .V)
        state.release(degree: .IV)
        sink.reset()
        state.release(degree: .V)

        #expect(sink.stopCount == 0)
        #expect(sink.playCalls.map(\.notes) == [[60, 64, 67]])
        #expect(state.activeDegree == .I)
    }

    /// Two fingers lifted at once (or the chord surface going away) stop the
    /// chord: the earlier key is gone too, so there is nothing to hand back to.
    @Test func liftingBothFingersTogetherStops() {
        let (state, sink) = makeState()
        state.press(degree: .I)
        state.press(degree: .IV)
        sink.reset()
        state.release([.IV, .I])

        #expect(sink.playCalls.isEmpty)
        #expect(sink.stopCount == 1)
        #expect(state.heldDegrees.isEmpty)
        #expect(state.activeDegree == nil)
    }

    /// One finger holds I while another slides IV → V and lifts: each chord
    /// replaces the last, and lifting hands the chord back to I.
    @Test func slidingWithOneFingerWhileAnotherHolds() {
        let (state, sink) = makeState()
        state.movePointer(from: nil, to: .I)
        state.movePointer(from: nil, to: .IV)
        state.movePointer(from: .IV, to: .V)
        state.movePointer(from: .V, to: nil)

        #expect(sink.stopCount == 0)
        #expect(sink.playCalls.map(\.notes) == [[60, 64, 67], [65, 69, 72], [67, 71, 74], [60, 64, 67]])
        #expect(state.heldDegrees == [.I])
    }

    /// Every chord-surface mode gets the hand-back, because PerformanceState
    /// delivers it as a press: the earlier degree is the selected chord again.
    @Test func everyModeReturnsToTheEarlierChord() {
        for kind in ModeKind.allCases where kind.surface == .chords {
            let (state, _) = makeState()
            state.selectMode(kind)
            state.press(degree: .I)
            state.press(degree: .IV)
            state.release(degree: .IV)

            #expect(state.activeDegree == .I, "\(kind)")
            #expect(state.heldDegrees == [.I], "\(kind)")
        }
    }

    /// A finger sliding I → IV → V and lifting: each chord replaces the last
    /// with no stop in between, and one stop at the end.
    @Test func slidingAcrossChordsNeverLeavesAGap() {
        let (state, sink) = makeState()
        state.movePointer(from: nil, to: .I)
        state.movePointer(from: .I, to: .IV)
        state.movePointer(from: .IV, to: .V)
        state.movePointer(from: .V, to: nil)

        #expect(sink.calls.map { $0 == .stop } == [false, false, false, true])
        #expect(state.heldDegrees.isEmpty)
    }

    /// The pointer contract holds for every mode, because PerformanceState
    /// enforces it: a superseded release never reaches the mode.
    @Test func noModeHearsASupersededRelease() {
        for kind in ModeKind.allCases where kind.surface == .chords {
            let (state, sink) = makeState()
            state.selectMode(kind)
            state.press(degree: .I)
            state.press(degree: .IV)
            sink.reset()
            state.release(degree: .I)

            #expect(sink.calls.isEmpty, "\(kind)")
            #expect(state.heldDegrees == [.IV], "\(kind)")
        }
    }

    // MARK: – Key slide

    /// The slide that is heard is the active key's, as the chord is.
    @Test func theSlideHeardIsTheMostRecentPresss() {
        let (state, _) = makeState()
        state.slide(on: .I, to: 0.2)
        state.movePointer(from: nil, to: .I)
        #expect(state.effects.slide == 0.2)

        state.slide(on: .IV, to: 0.9)
        state.movePointer(from: nil, to: .IV)
        #expect(state.effects.slide == 0.9)

        // The finger underneath moves: not heard until it is the active key again.
        state.slide(on: .I, to: 0.4)
        #expect(state.effects.slide == 0.9)

        state.movePointer(from: .IV, to: nil)
        #expect(state.effects.slide == 0.4)
    }

    @Test func liftingTheLastKeyEndsTheSlide() {
        let (state, _) = makeState()
        state.slide(on: .I, to: 0.2)
        state.movePointer(from: nil, to: .I)
        state.movePointer(from: .I, to: nil)
        #expect(state.effects.slide == nil)

        // A key pressed without a finger's position (the sequencer's, a test's) has none.
        state.press(degree: .I)
        #expect(state.effects.slide == nil)
    }

    @Test func slidingOntoAnotherKeyCarriesTheSlideAcross() {
        let (state, _) = makeState()
        state.slide(on: .I, to: 0.2)
        state.movePointer(from: nil, to: .I)
        state.slide(on: .IV, to: 0.7)
        state.movePointer(from: .I, to: .IV)
        #expect(state.effects.slide == 0.7)
    }

    @Test func changingModeEndsTheSlide() {
        let (state, _) = makeState()
        state.slide(on: .I, to: 0.2)
        state.movePointer(from: nil, to: .I)
        state.selectMode(.strum)
        #expect(state.effects.slide == nil)
    }

    // MARK: – Key zones with a key and an octave of their own

    /// Two zones: C minor at the bottom of every key, D# major two octaves
    /// down at the top.
    private func zoned(_ state: PerformanceState) {
        state.effects.zones.zones = [KeyZone(key: Key(root: .C, scale: .naturalMinor)),
                                     KeyZone(key: Key(root: .Ds, scale: .major), octave: 2)]
        state.effects.zones.isOn = true
    }

    @Test func aChordIsInTheKeyAndOctaveOfTheZoneItIsPlayedFrom() {
        let (state, sink) = makeState()
        zoned(state)

        state.slide(on: .I, to: 0.2)
        state.movePointer(from: nil, to: .I)
        #expect(sink.playCalls.last?.notes == [60, 63, 67])   // Cm, in the octave chosen
        #expect(sink.playEvents.last?.context.key == Key(root: .C, scale: .naturalMinor))
        state.movePointer(from: .I, to: nil)

        state.slide(on: .I, to: 0.8)
        state.movePointer(from: nil, to: .I)
        #expect(sink.playCalls.last?.notes == [39, 43, 46])   // D#, octave 2
        #expect(sink.playEvents.last?.context.octave == 2)
        #expect(state.playedKey == Key(root: .Ds, scale: .major))
        state.movePointer(from: .I, to: nil)

        // Nothing chosen was changed, and with no finger down it is what plays.
        #expect(state.key == Key(root: .C, scale: .major))
        #expect(state.playedKey == state.key)
        #expect(state.playedOctave == 4)
    }

    @Test func aZoneWithNoKeyOfItsOwnPlaysTheKeyChosen() {
        let (state, sink) = makeState()
        state.effects.zones.zones = [KeyZone(), KeyZone(octave: 5)]
        state.effects.zones.isOn = true
        state.key = Key(root: .D, scale: .major)

        state.slide(on: .I, to: 0.2)
        state.movePointer(from: nil, to: .I)
        #expect(sink.playCalls.last?.notes == [62, 66, 69])
        state.movePointer(from: .I, to: nil)

        state.slide(on: .I, to: 0.8)
        state.movePointer(from: nil, to: .I)
        #expect(sink.playCalls.last?.notes == [74, 78, 81])
    }

    @Test func slidingIntoAnotherZoneChangesTheHeldChord() {
        let (state, sink) = makeState()
        zoned(state)
        state.slide(on: .I, to: 0.2)
        state.movePointer(from: nil, to: .I)
        sink.reset()

        state.slide(on: .I, to: 0.3)                          // still the bottom zone
        #expect(sink.calls.isEmpty)

        state.slide(on: .I, to: 0.8)
        #expect(sink.playCalls.map(\.notes) == [[39, 43, 46]])
        #expect(state.heldDegrees == [.I])
    }

    /// A second finger's chord is in its own zone, and the first finger's
    /// chord is not played again on the way.
    @Test func eachFingerPlaysTheZoneItIsIn() {
        let (state, sink) = makeState()
        zoned(state)
        state.slide(on: .I, to: 0.2)
        state.movePointer(from: nil, to: .I)
        sink.reset()

        state.slide(on: .V, to: 0.8)
        state.movePointer(from: nil, to: .V)
        #expect(sink.playEvents.map(\.context.spec.degree) == [.V])
        #expect(sink.playEvents.last?.context.key == Key(root: .Ds, scale: .major))

        // Lifting it hands the chord back to the first finger, in its zone.
        state.movePointer(from: .V, to: nil)
        #expect(sink.playCalls.last?.notes == [60, 63, 67])
    }

    /// A latched chord stays in the key it was struck in when the finger lifts.
    @Test func aDroneKeepsItsZonesKeyOnceTheFingerIsUp() {
        let (state, sink) = makeState()
        zoned(state)
        state.selectMode(.drone)
        state.slide(on: .I, to: 0.8)
        state.movePointer(from: nil, to: .I)
        sink.reset()

        state.movePointer(from: .I, to: nil)
        #expect(sink.calls.isEmpty)
    }

    @Test func aLeadNoteIsInItsZonesKeyAndOctave() {
        let (state, sink) = makeState()
        zoned(state)
        state.selectMode(.lead)
        state.slide(on: .I, to: 0.8)
        state.movePointer(from: nil, to: .I)
        #expect(sink.playCalls.last?.notes == [39])
    }
}
