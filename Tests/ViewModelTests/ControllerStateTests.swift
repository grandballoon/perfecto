import Foundation
import Testing
@testable import Perfecto

@Suite("ControllerState")
@MainActor
struct ControllerStateTests {

    /// An Alesis V61 whose learned bindings are kept in a store of its own.
    private func makeController(defaults: UserDefaults = isolatedDefaults(),
                                logger: RecordingLogger? = nil) -> ControllerState {
        ControllerState(layout: .alesisV61, defaults: defaults, logger: logger)
    }

    // MARK: – The device

    @Test func theV61IsRecognizedByItsNameAndNotItsSuccessor() {
        let layout = ControllerLayout.alesisV61
        #expect(layout.recognizes("V61"))
        #expect(layout.recognizes("Alesis V61"))
        #expect(!layout.recognizes("V61 MKII"))
        #expect(!layout.recognizes("Launchkey 61"))
    }

    @Test func theDeviceIsTheSourceThatIsAV61() {
        let controller = makeController()
        controller.connected(to: ["IAC Driver Bus 1", "V61"])
        #expect(controller.device == "V61")
        controller.connected(to: ["IAC Driver Bus 1"])
        #expect(controller.device == nil)
    }

    @Test func aSourceThatGoesLetsItsKeysGo() {
        let controller = makeController()
        controller.connected(to: ["V61"])
        controller.hear(.noteOn(channel: 0, note: 60, velocity: 90))
        controller.connected(to: [])
        #expect(controller.heldNotes.isEmpty)
    }

    // MARK: – Hearing

    @Test func theKnobsAreWhereTheirControllersSay() {
        let controller = makeController()
        controller.hear(.controlChange(channel: 0, controller: 21, value: 127))
        #expect(controller.values["knob2"] == 1)
        #expect(controller.heard?.target == .control("knob2"))
    }

    @Test func theWheelsAreReadAsTheyAreSent() {
        let controller = makeController()
        controller.hear(.pitchBend(channel: 0, value: -8192))
        controller.hear(.controlChange(channel: 0, controller: 1, value: 0))
        #expect(controller.values["pitch"] == -1)
        #expect(controller.values["mod"] == 0)
        controller.hear(.pitchBend(channel: 0, value: 8191))
        #expect(controller.values["pitch"] == 1)
    }

    @Test func aPadIsLitAsHardAsItIsStruckWhileItIsHeld() {
        let controller = makeController()
        controller.hear(.noteOn(channel: 9, note: 38, velocity: 127))
        #expect(controller.values["pad3"] == 1)
        #expect(controller.heldNotes.isEmpty)
        controller.hear(.noteOff(channel: 9, note: 38))
        #expect(controller.values["pad3"] == 0)
    }

    @Test func aNoteNoControlHasIsAKey() {
        let controller = makeController()
        controller.hear(.noteOn(channel: 0, note: 36, velocity: 64))
        #expect(controller.velocity(ofKey: 0) == 64)
        #expect(controller.heard?.target == .key(0))
        controller.hear(.noteOff(channel: 0, note: 36))
        #expect(controller.velocity(ofKey: 0) == nil)
    }

    @Test func aMessageNothingSendsIsHeardAsNothing() {
        let controller = makeController()
        controller.hear(.controlChange(channel: 0, controller: 99, value: 1))
        #expect(controller.heard?.target == ControllerState.Target.none)
    }

    // MARK: – The octave shift

    @Test func theShiftIsReadFromTheNotes() {
        var keys = ControllerKeys(ControllerLayout.alesisV61.keyboard)
        #expect(keys.key(of: 36) == 0)
        #expect(keys.key(of: 96) == 60)
        // A note above the keys: they were shifted up an octave.
        #expect(keys.key(of: 100) == 52)
        #expect(keys.shift == 1)
        // And a note they still send keeps it.
        #expect(keys.key(of: 60) == 12)
        #expect(keys.shift == 1)
        // A note below them shifts them down as far as it takes.
        #expect(keys.key(of: 10) == 10)
        #expect(keys.shift == -3)
    }

    @Test func aKeyIsLitWhereItIsAsTheKeysAreShifted() {
        let controller = makeController()
        controller.hear(.noteOn(channel: 0, note: 110, velocity: 100))
        #expect(controller.keys.shift == 2)
        #expect(controller.velocity(ofKey: 110 - 60) == 100)
    }

    // MARK: – Learning

    @Test func aControlChosenWhileLearningTakesTheNextMessage() {
        let logger = RecordingLogger()
        let controller = makeController(logger: logger)
        controller.isLearning = true
        controller.choose("pad1")
        #expect(controller.learning == "pad1")
        controller.hear(.noteOn(channel: 0, note: 49, velocity: 100))
        #expect(controller.learning == nil)
        #expect(controller.address(of: "pad1") == .note(49, channel: 0))
        #expect(controller.hasLearned("pad1"))
        // What it learned is heard as it, and lights it.
        #expect(controller.values["pad1"] == 100.0 / 127)
        #expect(controller.heard?.target == .control("pad1"))
        #expect(logger.events.contains {
            if case let .controller_control_learned(control, address) = $0 {
                return control == "pad1" && address == "Note 49 · ch 1"
            }
            return false
        })
    }

    @Test func nothingIsChosenWhileNotLearning() {
        let controller = makeController()
        controller.choose("pad1")
        #expect(controller.learning == nil)
    }

    @Test func aControlThatSendsNothingHasNothingToLearn() {
        let controller = makeController()
        controller.isLearning = true
        controller.choose("octaveUp")
        #expect(controller.learning == nil)
    }

    @Test func choosingTheControlAgainStopsItLearning() {
        let controller = makeController()
        controller.isLearning = true
        controller.choose("knob1")
        controller.choose("knob1")
        #expect(controller.learning == nil)
    }

    @Test func aMessageIsOneControls() {
        let controller = makeController()
        controller.isLearning = true
        controller.choose("button1")
        // Knob 1's own controller.
        controller.hear(.controlChange(channel: 0, controller: 20, value: 127))
        #expect(controller.address(of: "button1") == .controller(20, channel: 0))
        #expect(controller.address(of: "knob1") == nil)
        controller.hear(.controlChange(channel: 0, controller: 20, value: 0))
        #expect(controller.heard?.target == .control("button1"))
    }

    @Test func theLearnedBindingsAreKeptAndCanBeForgotten() {
        let defaults = isolatedDefaults()
        let controller = makeController(defaults: defaults)
        controller.isLearning = true
        controller.choose("knob1")
        controller.hear(.controlChange(channel: 0, controller: 74, value: 1))

        let reopened = makeController(defaults: defaults)
        #expect(reopened.address(of: "knob1") == .controller(74, channel: 0))
        reopened.forgetLearned()
        #expect(reopened.address(of: "knob1") == .controller(20))
        #expect(!reopened.hasLearnedAny)
        #expect(makeController(defaults: defaults).address(of: "knob1") == .controller(20))
    }

    @Test func aControlThatGaveItsMessageUpIsKeptSo() {
        let defaults = isolatedDefaults()
        let controller = makeController(defaults: defaults)
        controller.isLearning = true
        controller.choose("button1")
        controller.hear(.controlChange(channel: 0, controller: 20, value: 1))
        #expect(makeController(defaults: defaults).address(of: "knob1") == nil)
    }

    @Test func learningTheFactorysMessageAgainIsNotALearnedOne() {
        let controller = makeController()
        controller.isLearning = true
        controller.choose("pad1")
        controller.hear(.noteOn(channel: 9, note: 36, velocity: 1))
        #expect(!controller.hasLearned("pad1"))
    }

    @Test func stoppingLearningForgetsTheControlChosen() {
        let controller = makeController()
        controller.isLearning = true
        controller.choose("knob1")
        controller.isLearning = false
        controller.hear(.controlChange(channel: 0, controller: 74, value: 1))
        #expect(controller.address(of: "knob1") == .controller(20))
    }
}
