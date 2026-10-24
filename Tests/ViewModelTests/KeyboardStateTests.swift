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
    private let x = KeyboardKey(code: 27, name: "X")
    private let right = KeyboardKey(code: 79, name: "→")
    private let up = KeyboardKey(code: 82, name: "↑")
    private let escape = KeyboardKey(code: KeyboardKey.escapeCode, name: "Escape")
    private let delete = KeyboardKey(code: KeyboardKey.deleteCode, name: "Delete")

    /// A performance in C major, octave 4, played from a keyboard whose map
    /// is kept in a store of its own, as the loops it records are.
    private func makeState(defaults: UserDefaults = isolatedDefaults(), clock: ManualClock = ManualClock())
        -> (state: PerformanceState, keys: RecordingSink) {
        let keys = RecordingSink()
        let state = PerformanceState(sink: keys,
                                     sequencer: SequencerState(defaults: isolatedDefaults()),
                                     keyboard: KeyboardState(defaults: defaults), clock: clock)
        return (state, keys)
    }

    // MARK: – Playing

    @Test func aKeyPlaysItsChordWhileItIsHeld() {
        let (state, keys) = makeState()
        #expect(state.keyboard.keyDown(a))
        #expect(keys.playCalls.last?.notes == [60, 64, 67])
        #expect(state.heldKeys == [.degree(.I)])

        #expect(state.keyboard.keyUp(code: a.code))
        #expect(state.heldKeys.isEmpty)
        #expect(keys.stopCount == 1)
    }

    @Test func theMostRecentKeyIsTheChordAndLiftingItHandsBack() {
        let (state, keys) = makeState()
        state.keyboard.keyDown(a)
        state.keyboard.keyDown(s)
        #expect(state.activeDegree == .ii)
        state.keyboard.keyUp(code: s.code)
        #expect(state.activeDegree == .I)
        #expect(keys.playCalls.last?.notes == [60, 64, 67])
    }

    @Test func aKeyHeldDownIsOnePress() {
        let (state, keys) = makeState()
        state.keyboard.keyDown(a)
        #expect(state.keyboard.keyDown(a))   // the system's repeat
        #expect(state.heldKeys == [.degree(.I)])
        #expect(keys.playCalls.count == 1)
    }

    @Test func aKeyThatPlaysNothingIsNotTaken() {
        let (state, keys) = makeState()
        #expect(!state.keyboard.keyDown(x))
        #expect(!state.keyboard.keyUp(code: x.code))
        #expect(keys.playCalls.isEmpty)
    }

    /// The arrows are the compass's first choices, each held as a finger
    /// on it is: the latest plays, and lifting it is the plain chord.
    @Test func theArrowsPlayTheCompass() {
        let (state, _) = makeState()
        state.keyboard.keyDown(up)
        #expect(state.compassPlaces == [CompassPlace(.add, 1)])
        state.keyboard.keyDown(right)
        #expect(state.compassPlaces == [CompassPlace(.raise, 1)])
        state.keyboard.keyUp(code: up.code)
        #expect(state.compassPlaces == [CompassPlace(.raise, 1)])
        state.keyboard.keyUp(code: right.code)
        #expect(state.compassPlaces.isEmpty)
    }

    /// While the compass keeps its color, each arrow is a step of the walk.
    @Test func theArrowsWalkTheCompassWhileItKeeps() {
        let (state, _) = makeState()
        state.keepsCompassColor = true
        state.keyboard.keyDown(up)
        state.keyboard.keyUp(code: up.code)
        state.keyboard.keyDown(up)
        state.keyboard.keyUp(code: up.code)
        #expect(state.compassPlaces == [CompassPlace(.add, 1), CompassPlace(.add, 1)])
    }

    @Test func lettingEveryKeyGoEndsWhatTheyPlayed() {
        let (state, _) = makeState()
        state.keyboard.keyDown(a)
        state.keyboard.keyDown(up)
        state.keyboard.releaseAll()
        #expect(state.heldKeys.isEmpty)
        #expect(state.compassPlaces.isEmpty)
        // The keys were let go, so their lifting later is nothing.
        #expect(!state.keyboard.keyUp(code: a.code))
    }

    // MARK: – Buttons

    private let space = KeyboardKey(code: 44, name: "Space")
    private let enter = KeyboardKey(code: 40, name: "Return")
    private let m = KeyboardKey(code: 16, name: "M")

    @Test func aButtonsKeyTapsItOnceHoweverLongItIsHeld() {
        let (state, _) = makeState()
        state.keyboard.keyDown(m)
        state.keyboard.keyDown(m)   // the system's repeat
        #expect(state.isExternalSynth)
        state.keyboard.keyUp(code: m.code)
        #expect(state.isExternalSynth)
        state.keyboard.keyDown(m)
        #expect(!state.isExternalSynth)
    }

    /// The key a pointer over a button is shown follows the map.
    @Test func aButtonsTipIsTheKeyThatTapsIt() {
        let (state, _) = makeState()
        #expect(state.keyboard.keyName(for: .midi) == "M")
        #expect(state.keyboard.keyName(for: .loop) == "Return")
        state.keyboard.choosing = .button(.midi)
        state.keyboard.keyDown(x)
        #expect(state.keyboard.keyName(for: .midi) == "X")
        state.keyboard.choosing = .button(.midi)
        state.keyboard.keyDown(delete)
        #expect(state.keyboard.keyName(for: .midi) == nil)
    }

    /// A map saved before a button could be given a key gets the key it
    /// starts with, unless that key was given to something else, and a
    /// button left with no key on purpose stays without one.
    @Test func aMapSavedBeforeAButtonHadAKeyGetsItsStandardOne() throws {
        struct Saved: Encodable { var keys: [KeyboardAction: KeyboardKey] }
        var old = KeyboardMap.standard.keys
        for button in [KeyboardButton.midi, .playStop] { old[.button(button)] = nil }
        old[.chord(.I)] = m                                   // M already plays a chord
        let defaults = isolatedDefaults()
        defaults.set(try JSONEncoder().encode(Saved(keys: old)), forKey: "keyboardMap")

        let (state, _) = makeState(defaults: defaults)
        #expect(state.keyboard.map.key(for: .button(.playStop)) == space)
        #expect(state.keyboard.map.key(for: .button(.midi)) == nil)
        #expect(state.keyboard.map.key(for: .chord(.I)) == m)

        state.keyboard.choosing = .button(.playStop)
        state.keyboard.keyDown(delete)
        #expect(makeState(defaults: defaults).state.keyboard.map.key(for: .button(.playStop)) == nil)
    }

    @Test func returnRecordsALoopAndSpaceStopsAndStartsIt() {
        let clock = ManualClock()
        let (state, _) = makeState(clock: clock)
        let loops = state.quickLoopState
        state.keyboard.keyDown(enter)
        state.keyboard.keyUp(code: enter.code)
        #expect(loops.phase == .recording)
        // A bar of the I chord.
        state.keyboard.keyDown(a)
        clock.advance(beats: 4)
        state.keyboard.keyUp(code: a.code)
        state.keyboard.keyDown(enter)
        state.keyboard.keyUp(code: enter.code)
        #expect(loops.phase == .idle)
        #expect(loops.loops.count == 1)
        #expect(loops.isRunning)

        state.keyboard.keyDown(space)
        state.keyboard.keyUp(code: space.code)
        #expect(!loops.isRunning)
        state.keyboard.keyDown(space)
        #expect(loops.isRunning)
    }

    // MARK: – The map

    @Test func theNextKeyPressedBecomesTheChosenActionsKey() {
        let (state, keys) = makeState()
        state.keyboard.choosing = .chord(.I)
        #expect(state.keyboard.keyDown(x))
        #expect(state.keyboard.choosing == nil)
        #expect(keys.playCalls.isEmpty, "choosing a key plays nothing")
        #expect(state.keyboard.map.key(for: .chord(.I)) == x)

        state.keyboard.keyDown(x)
        #expect(state.heldKeys == [.degree(.I)])
        // The key it had plays nothing now.
        #expect(!state.keyboard.keyDown(a))
    }

    @Test func aKeyGivenToAnotherActionLeavesTheOneItHad() {
        let (state, _) = makeState()
        state.keyboard.choosing = .chord(.ii)
        state.keyboard.keyDown(a)
        #expect(state.keyboard.map.key(for: .chord(.ii)) == a)
        #expect(state.keyboard.map.key(for: .chord(.I)) == nil)
    }

    @Test func escapeLeavesTheActionAsItWasAndDeleteLeavesItNoKey() {
        let (state, _) = makeState()
        state.keyboard.choosing = .chord(.I)
        state.keyboard.keyDown(escape)
        #expect(state.keyboard.choosing == nil)
        #expect(state.keyboard.map.key(for: .chord(.I)) == a)

        state.keyboard.choosing = .chord(.I)
        state.keyboard.keyDown(delete)
        #expect(state.keyboard.map.key(for: .chord(.I)) == nil)
    }

    @Test func aKeyLiftedEndsWhatItStartedWhateverTheMapSaysByThen() {
        let (state, _) = makeState()
        state.keyboard.keyDown(a)
        state.keyboard.choosing = .chord(.ii)
        state.keyboard.keyDown(a)   // A is now ii's key, and still down as I
        state.keyboard.keyUp(code: a.code)
        #expect(state.heldKeys.isEmpty)
    }

    @Test func theMapIsRememberedAndCanBeReset() {
        let defaults = isolatedDefaults()
        let (state, _) = makeState(defaults: defaults)
        state.keyboard.choosing = .chord(.I)
        state.keyboard.keyDown(x)

        let (again, _) = makeState(defaults: defaults)
        #expect(again.keyboard.map.key(for: .chord(.I)) == x)
        again.keyboard.reset()
        #expect(again.keyboard.map == .standard)
        #expect(makeState(defaults: defaults).state.keyboard.map == .standard)
    }

    @Test func theStandardMapIsTheHomeRowAndTheArrows() {
        let map = KeyboardMap.standard
        #expect(Degree.allCases.map { map.key(for: .chord($0))?.name } == ["A", "S", "D", "F", "G", "H", "J"])
        #expect(map.key(for: .compass(CompassPlace(.add, 1)))?.name == "↑")
        #expect(map.key(for: .compass(CompassPlace(.raise, 1)))?.name == "→")
        #expect(map.key(for: .compass(CompassPlace(.add, 2))) == nil)
        #expect(KeyboardButton.allCases.map { map.key(for: .button($0))?.name } == ["Return", "M", "Space"])
    }
}
