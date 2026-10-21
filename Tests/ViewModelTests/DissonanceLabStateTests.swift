import Foundation
import Testing
@testable import Perfecto

@Suite("DissonanceLabState")
@MainActor
struct DissonanceLabStateTests {

    /// A performance whose lab sounds through a recording sink, with the
    /// lab on screen.
    @MainActor
    private struct Rig {
        let clock = ManualClock()
        let partials = RecordingPartialSink()
        let keys = RecordingSink()
        let logger = RecordingLogger()
        let state: PerformanceState

        init(shown: Bool = true) {
            state = PerformanceState(sink: keys, labSynth: DissonanceSynth(sink: partials, clock: clock),
                                     clock: clock, logger: logger)
            if shown { state.show(.lab) }
        }

        var lab: DissonanceLabState { state.lab }

        func midiDown(_ note: Int, velocity: Int = 100) {
            state.controller.hear(.noteOn(channel: 0, note: note, velocity: velocity))
        }

        func midiUp(_ note: Int) {
            state.controller.hear(.noteOff(channel: 0, note: note))
        }

        /// The MIDI notes the kernel is sounding, the lines as keyed among them.
        var sounding: [Int] { partials.sounding.values.sorted() }
    }

    // MARK: – A MIDI keyboard

    @Test func aMidiKeyboardPlaysTheLabWhileItIsShown() {
        let rig = Rig()
        rig.midiDown(57)
        rig.midiDown(64)
        #expect(rig.lab.held.map(\.note) == [57, 64])
        #expect(rig.lab.sounding?.interval == .perfectFifth)
        #expect(rig.keys.playCalls.isEmpty)
        rig.midiUp(64)
        #expect(rig.lab.sounding == nil)
        #expect(rig.lab.held.map(\.note) == [57])
    }

    @Test func offScreenTheLabHearsNothing() {
        let rig = Rig(shown: false)
        rig.midiDown(57)
        #expect(rig.lab.held.isEmpty)
        #expect(rig.partials.calls.isEmpty)
    }

    @Test func aThirdNoteTakesTheOldestsPlace() {
        let rig = Rig()
        rig.midiDown(57)
        rig.midiDown(64)
        rig.midiDown(60)
        #expect(rig.lab.held.map(\.note) == [64, 60])
        #expect(rig.lab.sounding?.interval == .majorThird)
        // Letting go of the note it replaced changes nothing.
        rig.midiUp(57)
        #expect(rig.lab.held.map(\.note) == [64, 60])
    }

    /// Velocity is how loud, and nothing of what the notes are found to be.
    @Test func velocityScalesTheGainAlone() {
        let soft = Rig(), hard = Rig()
        for (rig, velocity) in [(soft, 40), (hard, 120)] {
            rig.midiDown(57, velocity: velocity)
            rig.midiDown(64, velocity: velocity)
        }
        let velocities = { (rig: Rig) in
            rig.partials.calls.compactMap { if case let .on(_, _, _, _, velocity, _) = $0 { velocity } else { nil } }
        }
        #expect(velocities(soft).allSatisfy { abs($0 - 40.0 / 127) < 1e-6 })
        #expect(velocities(hard).allSatisfy { abs($0 - 120.0 / 127) < 1e-6 })
        #expect(soft.lab.sounding?.analysis == hard.lab.sounding?.analysis)
        #expect(soft.lab.sounding?.lowPartials == hard.lab.sounding?.lowPartials)
    }

    /// One note is played plainly, as keyed, with nothing to analyse.
    @Test func oneNoteIsPlayedPlainly() {
        let rig = Rig()
        rig.midiDown(45)
        #expect(rig.lab.sounding == nil)
        #expect(rig.sounding == [45])
    }

    /// Showing the lab at the desk lets go of what the Orchid held, so
    /// nothing is left sounding that the keyboard can no longer lift.
    @Test func showingTheLabLetsGoOfTheOrchid() {
        let rig = Rig(shown: false)
        rig.state.isAtDesk = true
        rig.midiDown(60)
        #expect(!rig.state.heldKeys.isEmpty)
        rig.state.deskPane = .lab
        #expect(rig.state.heldKeys.isEmpty)
        rig.midiDown(64)
        #expect(rig.lab.held.map(\.note) == [64])
    }

    @Test func leavingTheLabSilencesIt() {
        let rig = Rig()
        rig.midiDown(57)
        rig.midiDown(64)
        rig.state.show(.play)
        #expect(rig.lab.held.isEmpty)
        #expect(rig.partials.sounding.isEmpty)
    }

    // MARK: – The pads

    @Test func aPadSoundsItsIntervalOverTheRootWhileHeld() {
        let rig = Rig()
        rig.lab.setPadRoot(60)
        rig.lab.pressPad(.minorThird)
        #expect(rig.lab.held.map(\.note) == [60, 63])
        #expect(rig.lab.sounding?.interval == .minorThird)
        rig.lab.releasePad()
        #expect(rig.lab.held.isEmpty && rig.partials.sounding.isEmpty)
    }

    /// A key struck while a pad is held takes the oldest note's place, and
    /// lifting the pad after leaves what the keys hold.
    @Test func aKeyStruckOverAPadIsANoteLikeAnyOther() {
        let rig = Rig()
        rig.lab.setPadRoot(60)
        rig.lab.pressPad(.perfectFifth)
        rig.midiDown(64)
        #expect(rig.lab.held.map(\.note) == [67, 64])
        rig.lab.releasePad()
        #expect(rig.lab.held.map(\.note) == [67, 64])
        rig.midiUp(64)
        #expect(rig.lab.held.map(\.note) == [67])
    }

    @Test func movingTheRootUnderAHeldPadMovesTheInterval() {
        let rig = Rig()
        rig.lab.pressPad(.perfectFifth)
        rig.lab.setPadRoot(50)
        #expect(rig.lab.held.map(\.note) == [50, 57])
        rig.lab.setPadRoot(200)
        #expect(rig.lab.padRoot == DissonanceLabState.padRoots.upperBound)
    }

    // MARK: – Levels and A/B

    @Test func aLevelSetsEveryControlAndAChangeAfterIsAnAdjustment() {
        let rig = Rig()
        rig.lab.choose(.three)
        #expect(rig.lab.settings == LabLevel.three.settings && !rig.lab.isAdjusted)
        rig.lab.settings.rootTone = false
        #expect(rig.lab.isAdjusted && rig.lab.level == .three)
        #expect(rig.logger.events.contains { if case .lab_level_chosen(3) = $0 { true } else { false } })
    }

    /// A change of a control while the notes sound is glided to, not struck.
    @Test func aChangeOfAControlIsHeardWithoutStrikingAgain() {
        let rig = Rig()
        rig.lab.choose(.three)
        rig.midiDown(57)
        rig.midiDown(64)
        rig.partials.clear()
        rig.lab.settings.spotlightBoost = 6
        #expect(!rig.partials.calls.isEmpty)
        #expect(rig.partials.calls.allSatisfy { if case .partial = $0 { true } else { false } })
    }

    /// The A/B button: a just fifth goes to equal temperament by a bend,
    /// and the root tone ends.
    @Test func holdingABPlaysThePlainSound() {
        let rig = Rig()
        rig.midiDown(57)
        rig.midiDown(64)
        #expect(rig.lab.sounding?.isJust == true)
        #expect(rig.sounding.count == 3)                          // the root tone too
        rig.partials.clear()
        rig.lab.isPlain = true
        #expect(rig.lab.sounding?.isJust == false)
        #expect(rig.partials.calls.contains { if case .bend = $0 { true } else { false } })
        #expect(rig.sounding.count == 2)
        rig.lab.isPlain = false
        #expect(rig.sounding.count == 3)
        #expect(rig.logger.events.contains { if case .lab_bypassed(true) = $0 { true } else { false } })
    }

    /// What a quiz would drive the lab by.
    @Test func anIntervalCanBePlayedAtALevel() {
        let rig = Rig()
        rig.lab.play(.tritone, above: 62, level: .two)
        #expect(rig.lab.level == .two && rig.lab.settings == LabLevel.two.settings)
        #expect(rig.lab.held.map(\.note) == [62, 68])
        #expect(rig.logger.events.contains {
            if case .lab_interval_played(62, 68, 6, false) = $0 { true } else { false }
        })
        rig.lab.stop()
        #expect(rig.partials.sounding.isEmpty)
    }

    @Test func theLabsNotesAreShownOnThePiano() {
        let piano = RecordingNoteSink()
        let clock = ManualClock()
        let state = PerformanceState(sink: RecordingSink(),
                                     labSynth: DissonanceSynth(sink: RecordingPartialSink(), display: [piano],
                                                               clock: clock),
                                     clock: clock)
        state.show(.lab)
        state.lab.pressPad(.majorThird)
        #expect(piano.sounding.sorted() == [57, 61])
    }
}
