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
        state.press(.degree(.I))

        #expect(sink.playCalls.count == 1)
        #expect(sink.playCalls.first?.notes == [60, 64, 67])
    }

    @Test func buttonUpStopsChord() {
        let (state, sink) = makeState()
        state.press(.degree(.I))
        state.release(.degree(.I))

        #expect(sink.calls.last == .stop)
        #expect(state.activeDegree == nil)
    }

    @Test func joystickChangeWhileHeldRecomputesVoicing() {
        let (state, sink) = makeState()
        state.press(.degree(.I))          // Cmaj [60,64,67]
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
        state.press(.degree(.I))   // Cmaj
        state.release(.degree(.I))
        state.press(.degree(.IV))  // Fmaj [65,69,72]

        #expect(sink.playCalls.last?.notes == [65, 69, 72])
    }

    // MARK: – Two fingers

    /// Holding I, then IV, then lifting I (e.g. two fingers on the grid layout's
    /// buttons) must leave IV sounding: the release belongs to a press that
    /// IV already replaced.
    @Test func liftingAnEarlierFingerKeepsTheLaterChord() {
        let (state, sink) = makeState()
        state.press(.degree(.I))
        state.press(.degree(.IV))
        state.release(.degree(.I))

        #expect(sink.stopCount == 0)
        #expect(sink.lastPlay?.notes == [65, 69, 72])
        #expect(state.activeDegree == .IV)
    }

    /// Holding I, tapping IV: lifting IV hands the chord back to I, with no
    /// stop in between. The sound is I, IV, I.
    @Test func liftingTheLaterFingerReturnsToTheEarlierChord() {
        let (state, sink) = makeState()
        state.press(.degree(.I))
        state.press(.degree(.IV))
        state.release(.degree(.IV))

        #expect(sink.stopCount == 0)
        #expect(sink.playCalls.map(\.notes) == [[60, 64, 67], [65, 69, 72], [60, 64, 67]])
        #expect(state.activeDegree == .I)
        #expect(state.heldKeys == [.degree(.I)])

        state.release(.degree(.I))
        #expect(sink.calls.last == .stop)
        #expect(state.activeDegree == nil)
    }

    /// Three fingers unwind in order: lifting the active one resumes the most
    /// recent press still held, skipping any lifted in the meantime.
    @Test func liftingFingersUnwindsToTheMostRecentHeldChord() {
        let (state, sink) = makeState()
        state.press(.degree(.I))
        state.press(.degree(.IV))
        state.press(.degree(.V))
        state.release(.degree(.IV))
        sink.reset()
        state.release(.degree(.V))

        #expect(sink.stopCount == 0)
        #expect(sink.playCalls.map(\.notes) == [[60, 64, 67]])
        #expect(state.activeDegree == .I)
    }

    /// Two fingers lifted at once (or the chord surface going away) stop the
    /// chord: the earlier key is gone too, so there is nothing to hand back to.
    @Test func liftingBothFingersTogetherStops() {
        let (state, sink) = makeState()
        state.press(.degree(.I))
        state.press(.degree(.IV))
        sink.reset()
        state.release([.degree(.IV), .degree(.I)])

        #expect(sink.playCalls.isEmpty)
        #expect(sink.stopCount == 1)
        #expect(state.heldKeys.isEmpty)
        #expect(state.activeDegree == nil)
    }

    /// One finger holds I while another slides IV → V and lifts: each chord
    /// replaces the last, and lifting hands the chord back to I.
    @Test func slidingWithOneFingerWhileAnotherHolds() {
        let (state, sink) = makeState()
        state.movePointer(from: nil, to: .degree(.I))
        state.movePointer(from: nil, to: .degree(.IV))
        state.movePointer(from: .degree(.IV), to: .degree(.V))
        state.movePointer(from: .degree(.V), to: nil)

        #expect(sink.stopCount == 0)
        #expect(sink.playCalls.map(\.notes) == [[60, 64, 67], [65, 69, 72], [67, 71, 74], [60, 64, 67]])
        #expect(state.heldKeys == [.degree(.I)])
    }

    /// Every chord-surface mode gets the hand-back, because PerformanceState
    /// delivers it as a press: the earlier degree is the selected chord again.
    @Test func everyModeReturnsToTheEarlierChord() {
        for kind in ModeKind.allCases where kind.surface == .chords {
            let (state, _) = makeState()
            state.selectMode(kind)
            state.press(.degree(.I))
            state.press(.degree(.IV))
            state.release(.degree(.IV))

            #expect(state.activeDegree == .I, "\(kind)")
            #expect(state.heldKeys == [.degree(.I)], "\(kind)")
        }
    }

    /// A finger sliding I → IV → V and lifting: each chord replaces the last
    /// with no stop in between, and one stop at the end.
    @Test func slidingAcrossChordsNeverLeavesAGap() {
        let (state, sink) = makeState()
        state.movePointer(from: nil, to: .degree(.I))
        state.movePointer(from: .degree(.I), to: .degree(.IV))
        state.movePointer(from: .degree(.IV), to: .degree(.V))
        state.movePointer(from: .degree(.V), to: nil)

        #expect(sink.calls.map { $0 == .stop } == [false, false, false, true])
        #expect(state.heldKeys.isEmpty)
    }

    /// The pointer contract holds for every mode, because PerformanceState
    /// enforces it: a superseded release never reaches the mode.
    @Test func noModeHearsASupersededRelease() {
        for kind in ModeKind.allCases where kind.surface == .chords {
            let (state, sink) = makeState()
            state.selectMode(kind)
            state.press(.degree(.I))
            state.press(.degree(.IV))
            sink.reset()
            state.release(.degree(.I))

            #expect(sink.calls.isEmpty, "\(kind)")
            #expect(state.heldKeys == [.degree(.IV)], "\(kind)")
        }
    }

    // MARK: – Key slide

    /// The slide that is heard is the active key's, as the chord is.
    @Test func theSlideHeardIsTheMostRecentPresss() {
        let (state, _) = makeState()
        state.slide(on: .degree(.I), to: 0.2)
        state.movePointer(from: nil, to: .degree(.I))
        #expect(state.effects.slide == 0.2)

        state.slide(on: .degree(.IV), to: 0.9)
        state.movePointer(from: nil, to: .degree(.IV))
        #expect(state.effects.slide == 0.9)

        // The finger underneath moves: not heard until it is the active key again.
        state.slide(on: .degree(.I), to: 0.4)
        #expect(state.effects.slide == 0.9)

        state.movePointer(from: .degree(.IV), to: nil)
        #expect(state.effects.slide == 0.4)
    }

    @Test func liftingTheLastKeyEndsTheSlide() {
        let (state, _) = makeState()
        state.slide(on: .degree(.I), to: 0.2)
        state.movePointer(from: nil, to: .degree(.I))
        state.movePointer(from: .degree(.I), to: nil)
        #expect(state.effects.slide == nil)

        // A key pressed without a finger's position (the sequencer's, a test's) has none.
        state.press(.degree(.I))
        #expect(state.effects.slide == nil)
    }

    @Test func slidingOntoAnotherKeyCarriesTheSlideAcross() {
        let (state, _) = makeState()
        state.slide(on: .degree(.I), to: 0.2)
        state.movePointer(from: nil, to: .degree(.I))
        state.slide(on: .degree(.IV), to: 0.7)
        state.movePointer(from: .degree(.I), to: .degree(.IV))
        #expect(state.effects.slide == 0.7)
    }

    @Test func changingModeEndsTheSlide() {
        let (state, _) = makeState()
        state.slide(on: .degree(.I), to: 0.2)
        state.movePointer(from: nil, to: .degree(.I))
        state.selectMode(.strum)
        #expect(state.effects.slide == nil)
    }

    // MARK: – The inversion

    @Test func theInversionRollsTheChordsTheKeysPlay() {
        let (state, sink) = makeState()
        state.inversion = .first
        state.press(.degree(.I))
        #expect(sink.playCalls.last?.notes == [64, 67, 72])
        #expect(sink.playEvents.last?.context.inversion == .first)
        state.release(.degree(.I))

        state.inversion = Inversion(steps: -1)
        state.press(.degree(.V))
        #expect(sink.playCalls.last?.notes == [62, 67, 71])
    }

    /// Unlike the key, a change of inversion rolls the chord being held,
    /// tied to it so only the note that moves is struck.
    @Test func aChangeOfInversionRollsTheChordBeingHeld() {
        let logger = RecordingLogger()
        let sink = RecordingSink()
        let state = PerformanceState(sink: sink, clock: ManualClock(), logger: logger)
        state.press(.degree(.I))
        state.inversion = .first
        state.inversion = .first

        #expect(sink.playCalls.map(\.notes) == [[60, 64, 67], [64, 67, 72]])
        #expect(sink.playEvents.map(\.articulation) == [.block, .tied])
        let changes = logger.events.compactMap { if case let .inversion_changed(steps) = $0 { steps } else { nil } }
        #expect(changes == [1])

        // With no chord held there is nothing to roll.
        state.release(.degree(.I))
        state.inversion = .second
        #expect(sink.playCalls.count == 2)
    }

    /// So does a change of octave: the chord being held is the one that
    /// goes up or down.
    @Test func aChangeOfOctaveMovesTheChordBeingHeld() {
        let (state, sink) = makeState()
        state.press(.degree(.I))
        state.octave = 5

        #expect(sink.playCalls.map(\.notes) == [[60, 64, 67], [72, 76, 79]])
        #expect(sink.playEvents.last?.context.octave == 5)
    }

    /// The octave and the inversion set together are one change, and a
    /// note the two voicings share is held over.
    @Test func aChangeOfVoicingIsOneChordTiedToTheLast() {
        let (state, sink) = makeState()
        state.press(.degree(.I))
        state.voicing = KeyVoicing(octave: 5, inversion: Inversion(steps: -1))

        #expect(sink.playCalls.map(\.notes) == [[60, 64, 67], [67, 72, 76]])
        #expect(sink.playEvents.map(\.articulation) == [.block, .tied])
    }

    // MARK: – The voicing field

    /// While the field keeps what it is set to, its finger sets the octave
    /// and the inversion, and lifting changes nothing.
    @Test func theVoicingFieldSetsTheVoicingWhileItKeepsIt() {
        let (state, sink) = makeState()
        state.press(.degree(.I))
        state.holdVoicing(at: KeyVoicing(octave: 5, inversion: .first))
        state.releaseVoicing()

        #expect(state.voicing == KeyVoicing(octave: 5, inversion: .first))
        #expect(sink.playCalls.map(\.notes) == [[60, 64, 67], [76, 79, 84]])
    }

    /// While it does not, the finger plays the voicing: the chord being
    /// held follows it, and goes back when it lifts.
    @Test func theVoicingFieldIsPlayedWhileItDoesNotKeep() {
        let logger = RecordingLogger()
        let sink = RecordingSink()
        let state = PerformanceState(sink: sink, clock: ManualClock(), logger: logger)
        state.keepsVoicing = false
        state.press(.degree(.I))
        state.holdVoicing(at: KeyVoicing(octave: 5, inversion: .root))
        state.holdVoicing(at: KeyVoicing(octave: 5, inversion: .first))

        #expect(state.voicing == KeyVoicing(octave: 4, inversion: .root))
        #expect(state.heldVoicing == KeyVoicing(octave: 5, inversion: .first))
        #expect(sink.playCalls.last?.notes == [76, 79, 84])
        #expect(sink.playEvents.last?.context.octave == 5)
        #expect(sink.playEvents.last?.context.inversion == .first)

        state.releaseVoicing()
        #expect(state.heldVoicing == state.voicing)
        #expect(sink.playCalls.map(\.notes) == [[60, 64, 67], [72, 76, 79], [76, 79, 84], [60, 64, 67]])

        let bends = logger.events.compactMap {
            if case let .voicing_bent(octaves, steps) = $0 { [octaves, steps] } else { nil }
        }
        #expect(bends == [[1, 0], [1, 1], [0, 0]])
        // Nothing was set.
        #expect(!logger.events.contains { if case .octave_changed = $0 { true } else { false } })
    }

    /// A chord struck while the field is played is voiced where the finger is.
    @Test func aChordStruckWhileTheVoicingIsPlayedIsVoicedThere() {
        let (state, sink) = makeState()
        state.keepsVoicing = false
        state.holdVoicing(at: KeyVoicing(octave: 3, inversion: Inversion(steps: -1)))
        state.press(.degree(.I))
        #expect(sink.playCalls.last?.notes == [43, 48, 52])
        #expect(sink.playCalls.count == 1)

        state.release(.degree(.I))
        state.releaseVoicing()
        state.press(.degree(.I))
        #expect(sink.playCalls.last?.notes == [60, 64, 67])
    }

    /// A new chord is struck whole, whatever the inversion.
    @Test func aChordOfAnotherKeyIsStruckWhole() {
        let (state, sink) = makeState()
        state.inversion = .first
        state.press(.degree(.I))
        state.movePointer(from: .degree(.I), to: .degree(.IV))
        #expect(sink.playEvents.map(\.articulation) == [.block, .block])
    }

    /// While the slide plays the inversion, the middle of a key is the
    /// inversion as set, and a finger sliding on the key rolls its chord.
    @Test func theSlideRollsTheChordWhileItPlaysTheInversion() {
        let (state, sink) = makeState()
        state.effects.slidePlaysInversion = true

        state.slide(on: .degree(.I), to: 0.5)
        state.movePointer(from: nil, to: .degree(.I))
        #expect(sink.playCalls.last?.notes == [60, 64, 67])

        state.slide(on: .degree(.I), to: 0.62)
        #expect(sink.playCalls.last?.notes == [64, 67, 72])
        #expect(sink.playEvents.last?.articulation == .tied)
        // Within the same step nothing is played again.
        let played = sink.playCalls.count
        state.slide(on: .degree(.I), to: 0.63)
        #expect(sink.playCalls.count == played)

        state.slide(on: .degree(.I), to: 0)
        #expect(sink.playCalls.last?.notes == [43, 48, 52])
        state.movePointer(from: .degree(.I), to: nil)
        #expect(state.playedInversion == .root)

        // The slide rolls from the inversion that is set.
        state.inversion = .first
        state.slide(on: .degree(.I), to: 0.62)
        state.movePointer(from: nil, to: .degree(.I))
        #expect(sink.playCalls.last?.notes == [67, 72, 76])
        #expect(state.inversion == .first)
    }

    @Test func aChordIsInTheInversionOfTheZoneItIsPlayedFrom() {
        let (state, sink) = makeState()
        state.effects.zones = KeyZoneSettings(isOn: true, zones: [KeyZone(), KeyZone(inversion: .second)])

        state.slide(on: .degree(.I), to: 0.2)
        state.movePointer(from: nil, to: .degree(.I))
        #expect(sink.playCalls.last?.notes == [60, 64, 67])
        // A finger sliding into the zone rolls the chord it holds.
        state.slide(on: .degree(.I), to: 0.8)
        #expect(sink.playCalls.last?.notes == [67, 72, 76])
        #expect(sink.playEvents.last?.articulation == .tied)
        state.movePointer(from: .degree(.I), to: nil)
        #expect(state.playedInversion == .root)
    }

    // MARK: – Key zones with a key and an octave of their own

    /// Two zones: C minor at the bottom of every key, D# major two octaves
    /// down at the top.
    private func zoned(_ state: PerformanceState) {
        state.effects.zones.zones = [KeyZone(key: Key(root: .C, scale: .naturalMinor)),
                                     KeyZone(key: Key(root: .Ds, scale: .major), octave: 2)]
        state.effects.zones.isOn = true
    }

    /// One key with a zone of its own: every chord from it is an octave up,
    /// from the screen or the computer keyboard, and no other key's is.
    @Test func aKeysOwnZoneGivesItsChordsThatZonesOctave() {
        let (state, sink) = makeState()
        state.effects.zones = KeyZoneSettings(isOn: true, zones: [KeyZone()])
        state.effects.keyZones[.I] = KeyZoneSettings(isOn: true, zones: [KeyZone(octave: 5)])

        state.movePointer(from: nil, to: .degree(.I))
        #expect(sink.playEvents.last?.context.octave == 5)
        state.movePointer(from: .degree(.I), to: .degree(.V))
        #expect(sink.playEvents.last?.context.octave == state.octave)
        state.movePointer(from: .degree(.V), to: nil)
    }

    /// One key split into three sections, each an octave of its own, while
    /// the other keys are whole.
    @Test func eachSectionOfASplitKeyPlaysInItsOwnOctave() {
        let (state, sink) = makeState()
        state.effects.zones = KeyZoneSettings(isOn: true, zones: [KeyZone()])
        state.effects.keyZones[.I] = KeyZoneSettings(isOn: true, zones: [
            KeyZone(octave: 3), KeyZone(), KeyZone(octave: 6),
        ])

        for (height, octave) in [(Float(0.1), 3), (0.5, 4), (0.9, 6)] {
            state.slide(on: .degree(.I), to: height)
            state.movePointer(from: nil, to: .degree(.I))
            #expect(sink.playEvents.last?.context.octave == octave)
            #expect(sink.playCalls.last?.notes == [0, 4, 7].map { $0 + 12 * (octave + 1) })
            state.movePointer(from: .degree(.I), to: nil)
        }

        // A finger sliding up the key changes the chord it holds.
        state.slide(on: .degree(.I), to: 0.1)
        state.movePointer(from: nil, to: .degree(.I))
        state.slide(on: .degree(.I), to: 0.9)
        #expect(sink.playCalls.last?.notes == [84, 88, 91])
        state.movePointer(from: .degree(.I), to: nil)

        state.slide(on: .degree(.V), to: 0.9)
        state.movePointer(from: nil, to: .degree(.V))
        #expect(sink.playEvents.last?.context.octave == 4)
    }

    @Test func aChordIsInTheKeyAndOctaveOfTheZoneItIsPlayedFrom() {
        let (state, sink) = makeState()
        zoned(state)

        state.slide(on: .degree(.I), to: 0.2)
        state.movePointer(from: nil, to: .degree(.I))
        #expect(sink.playCalls.last?.notes == [60, 63, 67])   // Cm, in the octave chosen
        #expect(sink.playEvents.last?.context.key == Key(root: .C, scale: .naturalMinor))
        state.movePointer(from: .degree(.I), to: nil)

        state.slide(on: .degree(.I), to: 0.8)
        state.movePointer(from: nil, to: .degree(.I))
        #expect(sink.playCalls.last?.notes == [39, 43, 46])   // D#, octave 2
        #expect(sink.playEvents.last?.context.octave == 2)
        #expect(state.playedKey == Key(root: .Ds, scale: .major))
        state.movePointer(from: .degree(.I), to: nil)

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

        state.slide(on: .degree(.I), to: 0.2)
        state.movePointer(from: nil, to: .degree(.I))
        #expect(sink.playCalls.last?.notes == [62, 66, 69])
        state.movePointer(from: .degree(.I), to: nil)

        state.slide(on: .degree(.I), to: 0.8)
        state.movePointer(from: nil, to: .degree(.I))
        #expect(sink.playCalls.last?.notes == [74, 78, 81])
    }

    @Test func slidingIntoAnotherZoneChangesTheHeldChord() {
        let (state, sink) = makeState()
        zoned(state)
        state.slide(on: .degree(.I), to: 0.2)
        state.movePointer(from: nil, to: .degree(.I))
        sink.reset()

        state.slide(on: .degree(.I), to: 0.3)                          // still the bottom zone
        #expect(sink.calls.isEmpty)

        state.slide(on: .degree(.I), to: 0.8)
        #expect(sink.playCalls.map(\.notes) == [[39, 43, 46]])
        #expect(state.heldKeys == [.degree(.I)])
    }

    /// A second finger's chord is in its own zone, and the first finger's
    /// chord is not played again on the way.
    @Test func eachFingerPlaysTheZoneItIsIn() {
        let (state, sink) = makeState()
        zoned(state)
        state.slide(on: .degree(.I), to: 0.2)
        state.movePointer(from: nil, to: .degree(.I))
        sink.reset()

        state.slide(on: .degree(.V), to: 0.8)
        state.movePointer(from: nil, to: .degree(.V))
        #expect(sink.playEvents.map(\.context.spec.degree) == [.V])
        #expect(sink.playEvents.last?.context.key == Key(root: .Ds, scale: .major))

        // Lifting it hands the chord back to the first finger, in its zone.
        state.movePointer(from: .degree(.V), to: nil)
        #expect(sink.playCalls.last?.notes == [60, 63, 67])
    }

    /// A latched chord stays in the key it was struck in when the finger lifts.
    @Test func aDroneKeepsItsZonesKeyOnceTheFingerIsUp() {
        let (state, sink) = makeState()
        zoned(state)
        state.selectMode(.drone)
        state.slide(on: .degree(.I), to: 0.8)
        state.movePointer(from: nil, to: .degree(.I))
        sink.reset()

        state.movePointer(from: .degree(.I), to: nil)
        #expect(sink.calls.isEmpty)
    }

    @Test func aLeadNoteIsInItsZonesKeyAndOctave() {
        let (state, sink) = makeState()
        zoned(state)
        state.selectMode(.lead)
        state.slide(on: .degree(.I), to: 0.8)
        state.movePointer(from: nil, to: .degree(.I))
        #expect(sink.playCalls.last?.notes == [39])
    }

    // MARK: – The octave's keys, each the root of a chord

    private let cMixolydian = Key(root: .C, scale: .mixolydian)

    @Test func aRootOfTheKeyPlaysItsDegreesChord() {
        let (state, sink) = makeState()
        state.press(.root(.D))

        #expect(sink.playCalls.last?.notes == [62, 65, 69])
        #expect(sink.playEvents.last?.context.key == state.key)
        #expect(state.activeDegree == .ii)
    }

    /// B♭ is not in C major: its chord is C Mixolydian's, a major one.
    @Test func aRootOutsideTheKeyPlaysABorrowedChord() {
        let (state, sink) = makeState()
        state.press(.root(.As))

        #expect(sink.playCalls.last?.notes == [70, 74, 77])
        #expect(sink.playEvents.last?.context.key == cMixolydian)
        #expect(state.playedKey == cMixolydian)
        // The keys are still in the key chosen.
        #expect(state.homeKey == state.key)

        state.release(.root(.As))
        #expect(state.playedKey == state.key)
    }

    /// In G major, C is the fourth degree, which the degrees' keys build
    /// above the tonic; the octave's keys go up from C as a piano's do.
    @Test func theOctavesChordsGoUpFromCToB() {
        let (state, sink) = makeState()
        state.key = Key(root: .G, scale: .major)

        state.press(.root(.C))
        #expect(sink.playCalls.last?.notes == [60, 64, 67])
        state.movePointer(from: .root(.C), to: .root(.Fs))
        #expect(sink.playCalls.last?.notes == [66, 69, 72])
        state.movePointer(from: .root(.Fs), to: .root(.G))
        #expect(sink.playCalls.last?.notes == [67, 71, 74])
        // The tonic's chord is where its degree's key has it.
        state.movePointer(from: .root(.G), to: .degree(.I))
        #expect(sink.playCalls.last?.notes == [67, 71, 74])
    }

    /// B and B♭ are both a seventh degree, of two keys: they are two keys,
    /// and lifting one hands the chord back to the other.
    @Test func twoRootsOfOneDegreeAreTwoKeys() {
        let (state, sink) = makeState()
        state.press(.root(.B))
        #expect(sink.playCalls.last?.notes == [71, 74, 77])
        state.press(.root(.As))
        #expect(sink.playCalls.last?.notes == [70, 74, 77])

        state.release(.root(.As))
        #expect(state.heldKeys == [.root(.B)])
        #expect(sink.playCalls.last?.notes == [71, 74, 77])
        #expect(sink.calls.last != .stop)
    }

    @Test func aColorChangePlaysTheBorrowedChordAgain() {
        let (state, sink) = makeState()
        state.press(.root(.As))
        state.joystickMoved(to: .right)

        #expect(sink.playCalls.last?.notes == [70, 74, 77, 81])
    }

    /// A latched chord is its key's, whichever key is down when it is
    /// played again.
    @Test func aDroneOnABorrowedRootStaysItsChord() {
        let (state, sink) = makeState()
        state.selectMode(.drone)
        state.press(.root(.As))
        state.release(.root(.As))
        state.joystickMoved(to: .right)

        #expect(sink.playCalls.last?.notes == [70, 74, 77, 81])
    }

    @Test func aLeadNoteIsTheRootItself() {
        let (state, sink) = makeState()
        state.selectMode(.lead)
        state.press(.root(.As))
        #expect(sink.playCalls.last?.notes == [70])
    }

    /// The octave's key for a note of the key is that degree's key, so it
    /// is divided by that degree's own zones; a root outside the key has
    /// every key's.
    @Test func aRootOfTheKeyHasItsDegreesZones() {
        let (state, sink) = makeState()
        state.effects.zones = KeyZoneSettings(isOn: true, zones: [KeyZone()])
        state.effects.keyZones[.ii] = KeyZoneSettings(isOn: true, zones: [KeyZone(octave: 5)])

        state.slide(on: .root(.D), to: 0.5)
        state.movePointer(from: nil, to: .root(.D))
        #expect(sink.playCalls.last?.notes == [74, 77, 81])
        state.slide(on: .root(.Cs), to: 0.5)
        state.movePointer(from: .root(.D), to: .root(.Cs))
        #expect(sink.playCalls.last?.notes == [61, 65, 68])
    }

    /// A zone's key is the key the keys are in, so a root is read in it.
    @Test func aRootIsReadInItsZonesKey() {
        let (state, sink) = makeState()
        state.effects.zones = KeyZoneSettings(isOn: true,
                                              zones: [KeyZone(key: Key(root: .C, scale: .naturalMinor))])
        state.slide(on: .root(.Ds), to: 0.5)
        state.movePointer(from: nil, to: .root(.Ds))

        #expect(sink.playCalls.last?.notes == [63, 67, 70])
        #expect(sink.playEvents.last?.context.key == Key(root: .C, scale: .naturalMinor))
    }

    @Test func aChordKeyKnowsItsDegreeInAKey() {
        let cMajor = Key(root: .C, scale: .major)
        #expect(ChordKey.degree(.V).degree(in: cMajor) == .V)
        #expect(ChordKey.root(.G).degree(in: cMajor) == .V)
        #expect(ChordKey.root(.Fs).degree(in: cMajor) == nil)
        #expect(ChordKey.root(.G).chord(in: cMajor) == ChordKey.degree(.V).chord(in: cMajor))
    }

    // MARK: – The key

    @Test func aChangeOfKeyIsLogged() {
        let logger = RecordingLogger()
        let state = PerformanceState(sink: RecordingSink(), clock: ManualClock(), logger: logger)
        state.key = Key(root: .D, scale: .dorian)
        state.key = Key(root: .D, scale: .dorian)

        let changes = logger.events.compactMap { if case let .key_changed(key) = $0 { key } else { nil } }
        #expect(changes == ["D Dorian"])
    }

    @Test func aChangeOfOctaveIsLogged() {
        let logger = RecordingLogger()
        let state = PerformanceState(sink: RecordingSink(), clock: ManualClock(), logger: logger)
        state.octave = 5
        state.octave = 5

        let changes = logger.events.compactMap { if case let .octave_changed(octave) = $0 { octave } else { nil } }
        #expect(changes == [5])
    }
}
