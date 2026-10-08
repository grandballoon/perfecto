import Foundation
import Testing
@testable import Perfecto

@Suite("KeyboardState")
@MainActor
struct KeyboardStateTests {

    // MARK: – Helpers

    // Where the keys are (their HID usages).
    private let a = KeyboardKey(code: 4, name: "A")
    private let s = KeyboardKey(code: 22, name: "S")
    private let q = KeyboardKey(code: 20, name: "Q")
    private let one = KeyboardKey(code: 30, name: "1")
    private let right = KeyboardKey(code: 79, name: "→")
    private let up = KeyboardKey(code: 82, name: "↑")
    private let escape = KeyboardKey(code: KeyboardKey.escapeCode, name: "Escape")
    private let delete = KeyboardKey(code: KeyboardKey.deleteCode, name: "Delete")

    /// A performance in C major, octave 4, played from a keyboard whose map
    /// is kept in a store of its own.
    private func makeState(defaults: UserDefaults = isolatedDefaults())
        -> (state: PerformanceState, keys: RecordingSink, solo: RecordingSink) {
        let keys = RecordingSink(), solo = RecordingSink()
        let state = PerformanceState(sink: keys, soloSink: solo,
                                     keyboard: KeyboardState(defaults: defaults), clock: ManualClock())
        return (state, keys, solo)
    }

    // MARK: – Playing

    @Test func aKeyPlaysItsChordWhileItIsHeld() {
        let (state, keys, _) = makeState()
        #expect(state.keyboard.keyDown(a))
        #expect(keys.playCalls.last?.notes == [60, 64, 67])
        #expect(state.heldDegrees == [.I])

        #expect(state.keyboard.keyUp(code: a.code))
        #expect(state.heldDegrees.isEmpty)
        #expect(keys.stopCount == 1)
    }

    @Test func theMostRecentKeyIsTheChordAndLiftingItHandsBack() {
        let (state, keys, _) = makeState()
        state.keyboard.keyDown(a)
        state.keyboard.keyDown(s)
        #expect(state.activeDegree == .ii)
        state.keyboard.keyUp(code: s.code)
        #expect(state.activeDegree == .I)
        #expect(keys.playCalls.last?.notes == [60, 64, 67])
    }

    @Test func aKeyHeldDownIsOnePress() {
        let (state, keys, _) = makeState()
        state.keyboard.keyDown(a)
        #expect(state.keyboard.keyDown(a))   // the system's repeat
        #expect(state.heldDegrees == [.I])
        #expect(keys.playCalls.count == 1)
    }

    @Test func aKeyThatPlaysNothingIsNotTaken() {
        let (state, keys, _) = makeState()
        #expect(!state.keyboard.keyDown(q))
        #expect(!state.keyboard.keyUp(code: q.code))
        #expect(keys.playCalls.isEmpty)
    }

    @Test func colorKeysHeldTogetherAddUp() {
        let (state, _, _) = makeState()
        state.keyboard.keyDown(up)
        #expect(state.joystickDirection == .up)
        state.keyboard.keyDown(right)
        #expect(state.joystickDirection == .upRight)
        state.keyboard.keyUp(code: up.code)
        #expect(state.joystickDirection == .right)
        state.keyboard.keyUp(code: right.code)
        #expect(state.joystickDirection == .center)
    }

    @Test func theNumberRowPlaysTheSoloStripWhileItIsOn() {
        let (state, _, solo) = makeState()
        state.keyboard.keyDown(one)
        state.keyboard.keyUp(code: one.code)
        #expect(solo.playCalls.isEmpty)

        state.solo.isOn = true
        state.keyboard.keyDown(one)
        #expect(solo.playCalls.last?.notes == [60])
        #expect(state.solo.held == [0])
        state.keyboard.keyUp(code: one.code)
        #expect(state.solo.held.isEmpty)
    }

    @Test func lettingEveryKeyGoEndsWhatTheyPlayed() {
        let (state, _, _) = makeState()
        state.keyboard.keyDown(a)
        state.keyboard.keyDown(up)
        state.keyboard.releaseAll()
        #expect(state.heldDegrees.isEmpty)
        #expect(state.joystickDirection == .center)
        // The keys were let go, so their lifting later is nothing.
        #expect(!state.keyboard.keyUp(code: a.code))
    }

    // MARK: – The map

    @Test func theNextKeyPressedBecomesTheChosenActionsKey() {
        let (state, keys, _) = makeState()
        state.keyboard.choosing = .chord(.I)
        #expect(state.keyboard.keyDown(q))
        #expect(state.keyboard.choosing == nil)
        #expect(keys.playCalls.isEmpty, "choosing a key plays nothing")
        #expect(state.keyboard.map.key(for: .chord(.I)) == q)

        state.keyboard.keyDown(q)
        #expect(state.heldDegrees == [.I])
        // The key it had plays nothing now.
        #expect(!state.keyboard.keyDown(a))
    }

    @Test func aKeyGivenToAnotherActionLeavesTheOneItHad() {
        let (state, _, _) = makeState()
        state.keyboard.choosing = .chord(.ii)
        state.keyboard.keyDown(a)
        #expect(state.keyboard.map.key(for: .chord(.ii)) == a)
        #expect(state.keyboard.map.key(for: .chord(.I)) == nil)
    }

    @Test func escapeLeavesTheActionAsItWasAndDeleteLeavesItNoKey() {
        let (state, _, _) = makeState()
        state.keyboard.choosing = .chord(.I)
        state.keyboard.keyDown(escape)
        #expect(state.keyboard.choosing == nil)
        #expect(state.keyboard.map.key(for: .chord(.I)) == a)

        state.keyboard.choosing = .chord(.I)
        state.keyboard.keyDown(delete)
        #expect(state.keyboard.map.key(for: .chord(.I)) == nil)
    }

    @Test func aKeyLiftedEndsWhatItStartedWhateverTheMapSaysByThen() {
        let (state, _, _) = makeState()
        state.keyboard.keyDown(a)
        state.keyboard.choosing = .chord(.ii)
        state.keyboard.keyDown(a)   // A is now ii's key, and still down as I
        state.keyboard.keyUp(code: a.code)
        #expect(state.heldDegrees.isEmpty)
    }

    @Test func theMapIsRememberedAndCanBeReset() {
        let defaults = isolatedDefaults()
        let (state, _, _) = makeState(defaults: defaults)
        state.keyboard.choosing = .chord(.I)
        state.keyboard.keyDown(q)

        let (again, _, _) = makeState(defaults: defaults)
        #expect(again.keyboard.map.key(for: .chord(.I)) == q)
        again.keyboard.reset()
        #expect(again.keyboard.map == .standard)
        #expect(makeState(defaults: defaults).state.keyboard.map == .standard)
    }

    @Test func theStandardMapIsTheHomeRowTheArrowsAndTheNumberRow() {
        let map = KeyboardMap.standard
        #expect(Degree.allCases.map { map.key(for: .chord($0))?.name } == ["A", "S", "D", "F", "G", "H", "J"])
        #expect(map.key(for: .color(.up))?.name == "↑")
        #expect(map.key(for: .color(.upRight)) == nil)
        #expect((0..<KeyboardMap.soloCells).map { map.key(for: .solo(cell: $0))?.name }
                == ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"])
    }
}
