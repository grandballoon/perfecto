import Foundation
import Testing
@testable import Perfecto

@Suite("OrchidState")
@MainActor
struct OrchidStateTests {

    // MARK: – Helpers

    /// A performance in C major, octave 4, at the desk, played from an
    /// Alesis V61 as an Orchid, each with a store of its own.
    private func makeState(defaults: UserDefaults = isolatedDefaults(), isAtDesk: Bool = true)
        -> (state: PerformanceState, keys: RecordingSink, logger: RecordingLogger) {
        let keys = RecordingSink(), logger = RecordingLogger()
        let state = PerformanceState(sink: keys,
                                     sequencer: SequencerState(defaults: isolatedDefaults()),
                                     controller: ControllerState(defaults: isolatedDefaults()),
                                     orchid: OrchidState(defaults: defaults, logger: logger),
                                     clock: ManualClock())
        state.isAtDesk = isAtDesk
        return (state, keys, logger)
    }

    // The V61's pads, by what they are on the Orchid: the top row (5 to 8)
    // the types, the bottom (1 to 4) the extensions. They are notes on
    // channel 10.
    private enum Pad: Int {
        case sixth = 36, minorSeventh, majorSeventh, ninth, dim, min, maj, sus
    }

    private func press(_ pad: Pad, on state: PerformanceState) {
        state.controller.hear(.noteOn(channel: 9, note: pad.rawValue, velocity: 100))
    }

    private func lift(_ pad: Pad, on state: PerformanceState) {
        state.controller.hear(.noteOff(channel: 9, note: pad.rawValue))
    }

    private func keyDown(_ note: Int, on state: PerformanceState) {
        state.controller.hear(.noteOn(channel: 0, note: note, velocity: 90))
    }

    private func keyUp(_ note: Int, on state: PerformanceState) {
        state.controller.hear(.noteOff(channel: 0, note: note))
    }

    /// The V61's first button, the key button.
    private func keyButton(_ isDown: Bool, on state: PerformanceState) {
        state.controller.hear(.controlChange(channel: 0, controller: 48, value: isDown ? 127 : 0))
    }

    /// The V61's second button, the key change button.
    private func tapKeyChangeButton(on state: PerformanceState) {
        state.controller.hear(.controlChange(channel: 0, controller: 49, value: 127))
        state.controller.hear(.controlChange(channel: 0, controller: 49, value: 0))
    }

    private func tapKeyButton(on state: PerformanceState) {
        keyButton(true, on: state)
        keyButton(false, on: state)
    }

    // MARK: – The chord buttons

    @Test func aTypeHeldBuildsItsTriadOnTheRootStruck() {
        let (state, keys, _) = makeState()
        press(.min, on: state)
        keyDown(62, on: state)       // D
        #expect(keys.lastPlay?.notes == [62, 65, 69])
        #expect(state.activeVoicingText == "D min")
        keyUp(62, on: state)
        #expect(state.heldKeys.isEmpty)

        press(.maj, on: state)       // Min is still held, and Maj is the last
        keyDown(62, on: state)
        #expect(keys.lastPlay?.notes == [62, 66, 69])
    }

    @Test func theExtensionsHeldAreAddedToTheTriad() {
        let (state, keys, _) = makeState()
        press(.maj, on: state)
        press(.minorSeventh, on: state)
        press(.ninth, on: state)
        keyDown(67, on: state)       // G
        #expect(keys.lastPlay?.notes == [67, 71, 74, 77, 81])
        #expect(state.activeVoicingText == "G 9")
    }

    @Test func aButtonPressedWhileARootIsHeldChangesItsChord() {
        let (state, keys, _) = makeState()
        press(.maj, on: state)
        keyDown(60, on: state)
        press(.majorSeventh, on: state)
        #expect(keys.lastPlay?.notes == [60, 64, 67, 71])
        lift(.majorSeventh, on: state)
        #expect(keys.lastPlay?.notes == [60, 64, 67])
    }

    @Test func outOfKeyModeARootWithNoTypeIsTheNoteAlone() {
        let (state, keys, _) = makeState()
        tapKeyButton(on: state)
        #expect(!state.orchid.isKeyMode)
        press(.minorSeventh, on: state)
        keyDown(64, on: state)       // E
        #expect(keys.lastPlay?.notes == [64])
        #expect(state.activeVoicingText == "E")
    }

    @Test func inKeyModeARootWithNoTypeIsItsChordInTheKey() {
        let (state, keys, _) = makeState()
        #expect(state.orchid.isKeyMode)
        keyDown(64, on: state)       // E: iii of C major
        #expect(keys.lastPlay?.notes == [64, 67, 71])
        press(.minorSeventh, on: state)
        #expect(keys.lastPlay?.notes == [64, 67, 71, 74])
        keyUp(64, on: state)

        keyDown(70, on: state)       // B♭, borrowed from C Mixolydian
        #expect(keys.lastPlay?.notes.first.map { $0 % 12 } == 10)
    }

    @Test func theButtonsBuildNothingWhileNothingIsHeld() {
        let (state, _, _) = makeState()
        tapKeyButton(on: state)
        keyDown(60, on: state)
        #expect(state.chordButtons == ChordBuild(type: .note))
        keyUp(60, on: state)
        #expect(state.chordButtons == nil)
        // The screen's keys are colored as the screen colors them.
        state.press(.degree(.ii))
        #expect(state.activeVoicingText == "D min")
    }

    @Test func aTypeHeldAlsoBuildsTheChordsTheScreenPlays() {
        let (state, keys, _) = makeState()
        press(.sus, on: state)
        state.press(.degree(.I))
        #expect(keys.lastPlay?.notes == [60, 65, 67])
    }

    // MARK: – The octave

    @Test func everyKeyIsARootOnThatKey() {
        let (state, keys, _) = makeState()
        press(.maj, on: state)
        keyDown(36, on: state)       // C2
        #expect(keys.lastPlay?.notes == [36, 40, 43])
        keyUp(36, on: state)
        keyDown(95, on: state)       // B6
        #expect(keys.lastPlay?.notes == [95, 99, 102])
        #expect(state.heldKeys == [.root(.B)])
    }

    @Test func inKeyModeAChordIsOnTheKeyStruckWhateverOctaveIsChosen() {
        let (state, keys, _) = makeState()
        state.octave = 6
        keyDown(45, on: state)       // A2: vi of C major
        #expect(keys.lastPlay?.notes == [45, 48, 52])
        keyUp(45, on: state)
        keyDown(70, on: state)       // B♭4, borrowed from C Mixolydian
        #expect(keys.lastPlay?.notes == [70, 74, 77])
    }

    @Test func theVoicingDialRollsTheChordFromTheKeyStruck() {
        let (state, keys, _) = makeState()
        keyDown(48, on: state)       // C3
        state.inversion = .first
        #expect(keys.lastPlay?.notes == [52, 55, 60])
    }

    @Test func liftingOneOfTwoOfTheSameNoteHandsTheChordToTheOther() {
        let (state, keys, _) = makeState()
        keyDown(48, on: state)
        keyDown(60, on: state)
        #expect(keys.lastPlay?.notes == [60, 64, 67])
        keyUp(60, on: state)
        #expect(keys.lastPlay?.notes == [48, 52, 55])
        #expect(state.heldKeys == [.root(.C)])
        keyUp(48, on: state)
        #expect(state.heldKeys.isEmpty)
    }

    @Test func aDroneStaysInTheOctaveItWasStruckIn() {
        let (state, keys, _) = makeState()
        state.setMode(DroneMode())
        keyDown(48, on: state)
        keyUp(48, on: state)
        state.inversion = .first
        #expect(keys.lastPlay?.notes == [52, 55, 60])
    }

    @Test func theScreensKeysAreStillInTheOctaveChosen() {
        let (state, keys, _) = makeState()
        keyDown(36, on: state)
        keyUp(36, on: state)
        state.press(.degree(.I))
        #expect(keys.lastPlay?.notes == [60, 64, 67])
    }

    @Test func nothingIsPlayedAwayFromTheDesk() {
        let (state, keys, _) = makeState(isAtDesk: false)
        press(.maj, on: state)
        keyDown(60, on: state)
        #expect(keys.playCalls.isEmpty)
        #expect(state.chordButtons == nil)
    }

    @Test func leavingTheDeskLetsEverythingGo() {
        let (state, _, _) = makeState()
        press(.maj, on: state)
        keyDown(60, on: state)
        state.isAtDesk = false
        #expect(state.heldKeys.isEmpty)
        #expect(state.chordButtons == nil)
    }

    @Test func aSourceThatGoesLetsItsRootsGo() {
        let (state, _, _) = makeState()
        state.controller.connected(to: ["V61"])
        keyDown(60, on: state)
        state.controller.connected(to: [])
        #expect(state.heldKeys.isEmpty)
    }

    // MARK: – The voicing dial

    @Test func theVoicingDialRollsTheChordHeld() {
        let (state, keys, _) = makeState()
        press(.maj, on: state)
        keyDown(60, on: state)
        // Its middle is root position, and each step a note further.
        state.controller.hear(.controlChange(channel: 0, controller: 20, value: 64))
        #expect(state.inversion == .root)
        state.controller.hear(.controlChange(channel: 0, controller: 20, value: 72))
        #expect(state.inversion == .first)
        #expect(keys.lastPlay?.notes == [64, 67, 72])
        state.controller.hear(.controlChange(channel: 0, controller: 20, value: 0))
        #expect(state.inversion == Inversion(steps: PerformanceState.inversions.lowerBound))
        state.controller.hear(.controlChange(channel: 0, controller: 20, value: 127))
        #expect(state.inversion == Inversion(steps: PerformanceState.inversions.upperBound))
    }

    // MARK: – Key mode and the key

    @Test func keyModeIsOnToStartWithSoAKeyAlonePlaysAChord() {
        let (state, keys, _) = makeState()
        #expect(state.orchid.isKeyMode)
        keyDown(62, on: state)       // D: ii of C major
        #expect(keys.lastPlay?.notes == [62, 65, 69])
    }

    @Test func theKeyButtonSwitchesKeyModeAndItIsRemembered() {
        let defaults = isolatedDefaults()
        let (state, _, logger) = makeState(defaults: defaults)
        tapKeyButton(on: state)
        #expect(!state.orchid.isKeyMode)
        let switches = logger.events.compactMap {
            if case let .orchid_key_mode_switched(isOn) = $0 { isOn } else { nil }
        }
        #expect(switches == [false])
        #expect(!makeState(defaults: defaults).state.orchid.isKeyMode)
        tapKeyButton(on: state)
        #expect(state.orchid.isKeyMode)
    }

    @Test func aRootStruckWithTheKeyButtonHeldIsTheKey() {
        let (state, keys, logger) = makeState()
        tapKeyButton(on: state)      // key mode off, to see choosing a key switch it on
        keyButton(true, on: state)
        keyDown(62, on: state)
        #expect(state.key == Key(root: .D, scale: .major))
        #expect(keys.playCalls.isEmpty)
        keyUp(62, on: state)
        keyButton(false, on: state)
        // Choosing a key is key mode, and the button lifting leaves it on.
        #expect(state.orchid.isKeyMode)
        let chosen = logger.events.compactMap { if case let .orchid_key_chosen(key) = $0 { key } else { nil } }
        #expect(chosen == ["D Major"])

        keyButton(true, on: state)
        press(.min, on: state)
        keyDown(69, on: state)
        #expect(state.key == Key(root: .A, scale: .naturalMinor))
    }

    @Test func aRootStruckAfterTheKeyChangeButtonIsTheKey() {
        let (state, keys, logger) = makeState()
        tapKeyButton(on: state)      // key mode off, to see choosing a key switch it on
        tapKeyChangeButton(on: state)
        #expect(state.orchid.isChoosingKey)
        keyDown(38, on: state)       // D2: the octave is no matter
        #expect(state.key == Key(root: .D, scale: .major))
        #expect(keys.playCalls.isEmpty)
        #expect(state.orchid.isKeyMode)
        keyUp(38, on: state)

        // It chooses one key: the next is played.
        #expect(!state.orchid.isChoosingKey)
        keyDown(64, on: state)
        #expect(keys.lastPlay?.notes == [64, 67, 71])   // E: ii of D major
        keyUp(64, on: state)

        press(.min, on: state)
        tapKeyChangeButton(on: state)
        keyDown(81, on: state)
        #expect(state.key == Key(root: .A, scale: .naturalMinor))
        let waits = logger.events.compactMap {
            if case let .orchid_key_change_switched(isWaiting) = $0 { isWaiting } else { nil }
        }
        #expect(waits == [true, false, true, false])
    }

    @Test func theKeyChangeButtonPressedAgainChoosesNone() {
        let (state, keys, _) = makeState()
        tapKeyChangeButton(on: state)
        tapKeyChangeButton(on: state)
        #expect(!state.orchid.isChoosingKey)
        keyDown(62, on: state)
        #expect(state.key == Key(root: .C, scale: .major))
        #expect(keys.lastPlay?.notes == [62, 65, 69])
    }

    @Test func whileLearningTheControlsPlayNothing() {
        let (state, _, _) = makeState()
        state.controller.isLearning = true
        press(.maj, on: state)
        #expect(state.orchid.heldTypes.isEmpty)
    }

    // MARK: – The arpeggio wheel

    /// The pitch wheel pushed `push` of the way up (below 0, down).
    private func bend(_ push: Double, on state: PerformanceState) {
        state.controller.hear(.pitchBend(channel: 0, value: Int((push * 8191).rounded())))
    }

    private func give(_ part: OrchidPart, to id: ControllerControl.ID?, on state: PerformanceState) {
        state.orchid.give(part, to: state.orchid.map.turned(id))
    }

    @Test func noControlPlaysTheArpeggioToStartWith() {
        let (state, _, _) = makeState()
        #expect(state.orchid.controls[.arpeggio] == nil)
        bend(1, on: state)
        #expect(!state.effects.asPlayed.arpeggiator.isOn)
    }

    @Test func thePitchWheelPushedUpArpeggiatesFromTheLowestNoteUp() {
        let (state, keys, _) = makeState()
        give(.arpeggio, to: "pitch", on: state)
        keyDown(60, on: state)
        bend(1, on: state)
        let played = state.effects.asPlayed.arpeggiator
        #expect(played.isOn && played.pattern == .up && played.cycle == .halfBeat)
        // The chord is played a note at a time, the lowest first.
        #expect(keys.lastPlay?.notes == [60])
        // The arpeggiator as set is as it was.
        #expect(!state.effects.arpeggiator.isOn)
    }

    @Test func pushedDownItGoesFromTheHighestNoteDown() {
        let (state, keys, _) = makeState()
        give(.arpeggio, to: "pitch", on: state)
        keyDown(60, on: state)
        bend(-1, on: state)
        #expect(state.effects.asPlayed.arpeggiator.pattern == .down)
        #expect(keys.lastPlay?.notes == [67])
    }

    @Test func theFurtherItIsPushedTheFasterThroughTheCycles() {
        let (state, _, _) = makeState()
        give(.arpeggio, to: "pitch", on: state)
        var cycles: [ArpeggioCycle] = []
        for push in [0.2, 0.4, 0.7, 0.95] {
            bend(-push, on: state)
            cycles.append(state.effects.asPlayed.arpeggiator.cycle)
        }
        #expect(cycles == [.bar, .twoBeats, .beat, .halfBeat])
    }

    @Test func itsMiddleAndALittleEitherWayPlayNoArpeggio() {
        let (state, keys, _) = makeState()
        give(.arpeggio, to: "pitch", on: state)
        keyDown(60, on: state)
        bend(0.5, on: state)
        bend(0.05, on: state)
        #expect(state.orchid.heldArpeggio == nil)
        #expect(!state.effects.asPlayed.arpeggiator.isOn)
        // The chord sounds whole again.
        #expect(keys.lastPlay?.notes == [60, 64, 67])
    }

    @Test func theModWheelIsReadFromItsMiddle() {
        let (state, _, _) = makeState()
        give(.arpeggio, to: "mod", on: state)
        state.controller.hear(.controlChange(channel: 0, controller: 1, value: 64))
        #expect(state.orchid.heldArpeggio == nil)
        state.controller.hear(.controlChange(channel: 0, controller: 1, value: 0))
        #expect(state.orchid.heldArpeggio == HeldArpeggio(pattern: .down, cycle: .halfBeat))
        state.controller.hear(.controlChange(channel: 0, controller: 1, value: 127))
        #expect(state.orchid.heldArpeggio == HeldArpeggio(pattern: .up, cycle: .halfBeat))
    }

    @Test func theControlGivenIsRememberedAndGivingNoneStopsTheArpeggio() {
        let defaults = isolatedDefaults()
        let (state, _, logger) = makeState(defaults: defaults)
        give(.arpeggio, to: "pitch", on: state)
        #expect(makeState(defaults: defaults).state.orchid.controls[.arpeggio]?.id == "pitch")
        bend(1, on: state)
        give(.arpeggio, to: nil, on: state)
        #expect(!state.effects.asPlayed.arpeggiator.isOn)
        let given: [String?] = logger.events.compactMap {
            if case let .orchid_part_given("arpeggio", control) = $0 { .some(control) } else { nil }
        }
        #expect(given == ["pitch", nil])
    }

    @Test func leavingTheDeskStopsTheArpeggio() {
        let (state, _, _) = makeState()
        give(.arpeggio, to: "pitch", on: state)
        bend(1, on: state)
        state.isAtDesk = false
        #expect(!state.effects.asPlayed.arpeggiator.isOn)
        bend(0.9, on: state)
        #expect(state.orchid.heldArpeggio == nil)
    }

    // MARK: – The velocity's arpeggio

    private func strike(_ note: Int, velocity: Int, on state: PerformanceState) {
        state.controller.hear(.noteOn(channel: 0, note: note, velocity: velocity))
    }

    @Test func theVelocityPlaysNoArpeggioToStartWith() {
        let (state, keys, _) = makeState()
        #expect(!state.orchid.velocityPlaysArpeggio)
        strike(60, velocity: 20, on: state)
        #expect(!state.effects.asPlayed.arpeggiator.isOn)
        #expect(keys.lastPlay?.notes == [60, 64, 67])
    }

    @Test func aKeyStruckSoftArpeggiatesUpAndOneStruckHardDown() {
        let (state, keys, _) = makeState()
        state.orchid.switchVelocityArpeggio()
        strike(60, velocity: OrchidState.hardVelocity - 1, on: state)
        #expect(state.effects.asPlayed.arpeggiator.pattern == .up)
        // The chord starts arpeggiated, from its lowest note.
        #expect(keys.playCalls.map(\.notes) == [[60]])
        keyUp(60, on: state)
        keys.reset()
        strike(60, velocity: OrchidState.hardVelocity, on: state)
        #expect(state.effects.asPlayed.arpeggiator.pattern == .down)
        #expect(keys.playCalls.map(\.notes) == [[67]])
        // It is played, not set.
        #expect(!state.effects.arpeggiator.isOn)
    }

    @Test func itIsAsFastAsTheArpeggiatorIsSet() {
        let (state, _, _) = makeState()
        state.effects.arpeggiator.cycle = .bar
        state.orchid.switchVelocityArpeggio()
        strike(60, velocity: 100, on: state)
        let played = state.effects.asPlayed.arpeggiator
        #expect(played.isOn && played.cycle == .bar)
    }

    @Test func theArpeggiosControlSaysHowFastAndTheVelocityWhichWay() {
        let (state, _, _) = makeState()
        give(.arpeggio, to: "pitch", on: state)
        state.orchid.switchVelocityArpeggio()
        bend(1, on: state)
        strike(60, velocity: 120, on: state)
        #expect(state.orchid.heldArpeggio == HeldArpeggio(pattern: .down, cycle: .halfBeat))
        // Let go of, the control leaves the velocity's arpeggio as set.
        bend(0, on: state)
        #expect(state.orchid.heldArpeggio == HeldArpeggio(pattern: .down))
    }

    @Test func aKeyHeldBeneathTakesItsOwnOrderBack() {
        let (state, keys, _) = makeState()
        state.orchid.switchVelocityArpeggio()
        strike(60, velocity: 120, on: state)
        strike(62, velocity: 20, on: state)
        #expect(state.effects.asPlayed.arpeggiator.pattern == .up)
        #expect(keys.lastPlay?.notes == [62])
        keyUp(62, on: state)
        #expect(state.effects.asPlayed.arpeggiator.pattern == .down)
        // C major again, from its highest note.
        #expect(keys.lastPlay?.notes == [67])
    }

    @Test func theLastKeyUpEndsItsChordWithoutSoundingItAgain() {
        let (state, keys, _) = makeState()
        state.orchid.switchVelocityArpeggio()
        strike(60, velocity: 100, on: state)
        keys.reset()
        keyUp(60, on: state)
        #expect(keys.calls == [.stop])
        #expect(state.orchid.heldArpeggio == nil)
        #expect(!state.effects.asPlayed.arpeggiator.isOn)
    }

    @Test func switchedOnItArpeggiatesTheChordHeldAtOnce() {
        let (state, keys, _) = makeState()
        strike(60, velocity: 20, on: state)
        state.orchid.switchVelocityArpeggio()
        #expect(keys.lastPlay?.notes == [60])
        state.orchid.switchVelocityArpeggio()
        #expect(keys.lastPlay?.notes == [60, 64, 67])
    }

    @Test func theSwitchIsRememberedAndLogged() {
        let defaults = isolatedDefaults()
        let (state, _, logger) = makeState(defaults: defaults)
        state.orchid.switchVelocityArpeggio()
        #expect(makeState(defaults: defaults).state.orchid.velocityPlaysArpeggio)
        #expect(logger.events.contains {
            if case .orchid_velocity_arpeggio_switched(isOn: true) = $0 { true } else { false }
        })
    }

    @Test func theVelocitysMiddleDividesSoftFromHard() {
        #expect(OrchidState.pattern(struckAt: 1) == .up)
        #expect(OrchidState.pattern(struckAt: 63) == .up)
        #expect(OrchidState.pattern(struckAt: 64) == .down)
        #expect(OrchidState.pattern(struckAt: 127) == .down)
    }

    // MARK: – Giving the parts to controls

    @Test func theVoicingIsOnTheFirstKnobToStartWith() {
        let (state, _, _) = makeState()
        #expect(state.orchid.controls[.voicing]?.id == "knob1")
        #expect(state.orchid.part(of: "knob1") == .voicing)
    }

    @Test func theVoicingCanBeGivenToAWheel() {
        let (state, _, _) = makeState()
        give(.voicing, to: "pitch", on: state)
        bend(1, on: state)
        #expect(state.inversion == Inversion(steps: PerformanceState.inversions.upperBound))
        bend(0, on: state)
        #expect(state.inversion == .root)
        // The first knob no longer plays it.
        state.controller.hear(.controlChange(channel: 0, controller: 20, value: 0))
        #expect(state.inversion == .root)
    }

    @Test func theArpeggioCanBeGivenToAKnobReadFromItsMiddle() {
        let (state, _, _) = makeState()
        give(.arpeggio, to: "knob3", on: state)
        state.controller.hear(.controlChange(channel: 0, controller: 22, value: 64))
        #expect(state.orchid.heldArpeggio == nil)
        state.controller.hear(.controlChange(channel: 0, controller: 22, value: 127))
        #expect(state.orchid.heldArpeggio == HeldArpeggio(pattern: .up, cycle: .halfBeat))
        #expect(state.orchid.part(of: "knob3") == .arpeggio)
    }

    @Test func aControlPlaysOnePartSoGivingItTakesItFromTheOther() {
        let (state, _, _) = makeState()
        give(.arpeggio, to: "pitch", on: state)
        bend(1, on: state)
        give(.voicing, to: "pitch", on: state)
        #expect(state.orchid.controls[.arpeggio] == nil)
        #expect(state.orchid.controls[.voicing]?.id == "pitch")
        #expect(!state.effects.asPlayed.arpeggiator.isOn)
    }

    @Test func aPartGivenNoControlIsRememberedSo() {
        let defaults = isolatedDefaults()
        let (state, _, _) = makeState(defaults: defaults)
        give(.voicing, to: nil, on: state)
        #expect(makeState(defaults: defaults).state.orchid.controls[.voicing] == nil)
        state.controller.hear(.controlChange(channel: 0, controller: 20, value: 0))
        #expect(state.inversion == .root)
    }
}
