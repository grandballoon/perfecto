import Foundation
import Testing
@testable import Perfecto

@Suite("GamepadState")
@MainActor
struct GamepadStateTests {

    // MARK: – Helpers

    /// A performance in C major, octave 4, played from a controller whose
    /// map is kept in a store of its own.
    private func makeState(defaults: UserDefaults = isolatedDefaults())
        -> (state: PerformanceState, keys: RecordingSink) {
        let keys = RecordingSink()
        let state = PerformanceState(sink: keys,
                                     sequencer: SequencerState(defaults: isolatedDefaults()),
                                     keyboard: KeyboardState(defaults: isolatedDefaults()),
                                     gamepad: GamepadState(defaults: defaults), clock: ManualClock())
        return (state, keys)
    }

    // MARK: – Buttons

    @Test func aButtonPlaysItsChordWhileItIsHeld() {
        let (state, keys) = makeState()
        state.gamepad.button(.a, isPressed: true)
        #expect(keys.playCalls.last?.notes == [60, 64, 67])
        #expect(state.heldKeys == [.degree(.I)])

        state.gamepad.button(.a, isPressed: false)
        #expect(state.heldKeys.isEmpty)
        #expect(keys.stopCount == 1)
    }

    @Test func theMostRecentButtonIsTheChordAndLiftingItHandsBack() {
        let (state, _) = makeState()
        state.gamepad.button(.a, isPressed: true)
        state.gamepad.button(.up, isPressed: true)
        #expect(state.activeDegree == .V)
        state.gamepad.button(.up, isPressed: false)
        #expect(state.activeDegree == .I)
    }

    @Test func aButtonAndAKeyOnOneChordAreTwoPressesOfIt() {
        let (state, _) = makeState()
        state.gamepad.button(.a, isPressed: true)
        state.keyboard.keyDown(KeyboardKey(code: 4, name: "A"))
        state.gamepad.button(.a, isPressed: false)
        #expect(state.heldKeys == [.degree(.I)])
        state.keyboard.keyUp(code: 4)
        #expect(state.heldKeys.isEmpty)
    }

    @Test func aButtonTapsAButtonOfTheScreen() {
        let (state, _) = makeState()
        state.gamepad.button(.leftShoulder, isPressed: true)
        state.gamepad.button(.leftShoulder, isPressed: false)
        #expect(state.solo.isOn)
    }

    @Test func aButtonThatPlaysNothingDoesNothing() {
        let (state, keys) = makeState()
        state.gamepad.button(.rightStick, isPressed: true)
        state.gamepad.button(.rightStick, isPressed: false)
        #expect(keys.calls.isEmpty)
    }

    // MARK: – The stick

    /// The stick plays the compass's first choices, and turned from one to
    /// the next it never passes through the plain chord.
    @Test func theStickPlaysTheCompass() {
        let (state, keys) = makeState()
        state.press(.degree(.I))
        state.gamepad.stickMoved(x: 0, y: 1)
        #expect(state.compassPlaces == [CompassPlace(.add, 1)])
        state.gamepad.stickMoved(x: 1, y: 0)
        #expect(state.compassPlaces == [CompassPlace(.raise, 1)])
        state.gamepad.stickMoved(x: 0, y: 0)
        #expect(state.compassPlaces.isEmpty)
        // C, Cmaj7, Csus4 and C again: no plain C between the two places.
        #expect(keys.playCalls.map(\.notes) == [[60, 64, 67], [60, 64, 67, 71], [60, 65, 67], [60, 64, 67]])
    }

    @Test func theStickPointsTheNearestOfTheFourKinds() {
        let ways: [(Double, Double, ColorStepKind)] = [
            (1, 0, .raise), (0, 1, .add), (-1, 0, .lower), (0, -1, .takeAway),
            (1, 0.9, .raise), (0.9, 1, .add), (-0.3, -1, .takeAway),
        ]
        for (x, y, kind) in ways {
            #expect(GamepadStick.kind(x: x, y: y, from: nil) == kind)
        }
    }

    @Test func theStickHasAMiddleItStaysOutOfUntilItIsWellIn() {
        #expect(GamepadStick.kind(x: 0.45, y: 0, from: nil) == nil)
        #expect(GamepadStick.kind(x: 0.55, y: 0, from: nil) == .raise)
        // Once out, it is out until it is further in than it came out.
        #expect(GamepadStick.kind(x: 0.45, y: 0, from: .raise) == .raise)
        #expect(GamepadStick.kind(x: 0.3, y: 0, from: .raise) == nil)
    }

    @Test func theStickKeepsItsKindALittlePastTheNext() {
        // 48° is add's from the middle, and still raise's from raise.
        let (x, y) = (cos(48 * Double.pi / 180), sin(48 * Double.pi / 180))
        #expect(GamepadStick.kind(x: x, y: y, from: nil) == .add)
        #expect(GamepadStick.kind(x: x, y: y, from: .raise) == .raise)
        #expect(GamepadStick.kind(x: x, y: y, from: .lower) == .add)
        // Across the line where the angle wraps round.
        #expect(GamepadStick.kind(x: -1, y: -0.01, from: .lower) == .lower)
    }

    /// A stick at rest is reported over and over, and must not take the
    /// compass back from whatever else is playing it.
    @Test func aStickAtRestLeavesTheCompassToTheKeyboard() {
        let (state, _) = makeState()
        state.keyboard.keyDown(KeyboardKey(code: 82, name: "↑"))
        state.gamepad.stickMoved(x: 0.02, y: -0.01)
        #expect(state.compassPlaces == [CompassPlace(.add, 1)])
    }

    // MARK: – The controller

    @Test func aControllerThatGoesLetsGoOfWhatItHeld() {
        let (state, _) = makeState()
        state.gamepad.connected(to: "Pad")
        #expect(state.gamepad.controller == "Pad")
        state.gamepad.button(.a, isPressed: true)
        state.gamepad.stickMoved(x: 1, y: 0)

        state.gamepad.connected(to: nil)
        #expect(state.gamepad.controller == nil)
        #expect(state.heldKeys.isEmpty)
        #expect(state.compassPlaces.isEmpty)
        // The button was let go, so its lifting later is nothing.
        state.gamepad.button(.a, isPressed: false)
        #expect(state.heldKeys.isEmpty)
    }

    // MARK: – The map

    @Test func theStandardMapIsTheFaceButtonsAndTheDPad() {
        let map = KeyboardMap.gamepad
        #expect(Degree.allCases.map { map.key(for: .chord($0))?.name } == ["A", "B", "X", "Y", "↑", "→", "↓"])
        #expect(map.key(for: .button(.loop))?.name == "R1")
        #expect(map.key(for: .button(.solo))?.name == "L1")
        #expect(map.key(for: .button(.playStop))?.name == "Menu")
    }

    /// The keyboard's Escape and Delete end the choosing of a key, so no
    /// button may be taken for either.
    @Test func noButtonIsTakenForEscapeOrDelete() {
        let codes = GamepadButton.allCases.map(\.rawValue)
        #expect(!codes.contains(KeyboardKey.escapeCode))
        #expect(!codes.contains(KeyboardKey.deleteCode))
        #expect(Set(codes).count == codes.count)
    }

    @Test func theNextButtonPressedBecomesTheChosenActionsButton() {
        let (state, keys) = makeState()
        state.gamepad.buttons.choosing = .chord(.I)
        state.gamepad.button(.leftTrigger, isPressed: true)
        state.gamepad.button(.leftTrigger, isPressed: false)
        #expect(keys.playCalls.isEmpty, "choosing a button plays nothing")
        #expect(state.gamepad.buttons.map.key(for: .chord(.I))?.name == "L2")

        state.gamepad.button(.leftTrigger, isPressed: true)
        #expect(state.heldKeys == [.degree(.I)])
    }

    @Test func theMapIsRememberedApartFromTheKeyboards() {
        let defaults = isolatedDefaults()
        let (state, _) = makeState(defaults: defaults)
        state.gamepad.buttons.choosing = .chord(.I)
        state.gamepad.button(.leftTrigger, isPressed: true)

        #expect(GamepadState(defaults: defaults).buttons.map.key(for: .chord(.I))?.name == "L2")
        #expect(KeyboardState(defaults: defaults).map == .standard)
        state.gamepad.buttons.reset()
        #expect(GamepadState(defaults: defaults).buttons.map == .gamepad)
    }
}
