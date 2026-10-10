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
    private let one = KeyboardKey(code: 30, name: "1")
    private let right = KeyboardKey(code: 79, name: "→")
    private let up = KeyboardKey(code: 82, name: "↑")
    private let escape = KeyboardKey(code: KeyboardKey.escapeCode, name: "Escape")
    private let delete = KeyboardKey(code: KeyboardKey.deleteCode, name: "Delete")

    /// A performance in C major, octave 4, played from a keyboard whose map
    /// is kept in a store of its own, as the loops it records are.
    private func makeState(defaults: UserDefaults = isolatedDefaults(), clock: ManualClock = ManualClock())
        -> (state: PerformanceState, keys: RecordingSink, solo: RecordingSink) {
        let keys = RecordingSink(), solo = RecordingSink()
        let state = PerformanceState(sink: keys, soloSink: solo,
                                     sequencer: SequencerState(defaults: isolatedDefaults()),
                                     keyboard: KeyboardState(defaults: defaults), clock: clock)
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
        #expect(!state.keyboard.keyDown(x))
        #expect(!state.keyboard.keyUp(code: x.code))
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

    // MARK: – Buttons

    private let space = KeyboardKey(code: 44, name: "Space")
    private let enter = KeyboardKey(code: 40, name: "Return")
    private let o = KeyboardKey(code: 18, name: "O")
    private let m = KeyboardKey(code: 16, name: "M")

    @Test func aButtonsKeyTapsItOnceHoweverLongItIsHeld() {
        let (state, _, _) = makeState()
        state.keyboard.keyDown(o)
        state.keyboard.keyDown(o)   // the system's repeat
        #expect(state.solo.isOn)
        state.keyboard.keyUp(code: o.code)
        #expect(state.solo.isOn)
        state.keyboard.keyDown(o)
        #expect(!state.solo.isOn)

        state.keyboard.keyDown(m)
        #expect(state.isExternalSynth)
    }

    private let k = KeyboardKey(code: 14, name: "K")
    private let n = KeyboardKey(code: 17, name: "N")
    private let t = KeyboardKey(code: 23, name: "T")
    private let q = KeyboardKey(code: 20, name: "Q")
    private let z = KeyboardKey(code: 29, name: "Z")

    /// On a phone the sequencer is a mode; the Tonnetz lies over whichever is on.
    @Test func keysShowTheSequencerAndTheTonnetzOnAPhone() {
        let (state, _, _) = makeState()
        state.keyboard.keyDown(q)
        #expect(state.phoneScreen == .sequencer)
        state.keyboard.keyDown(z)
        #expect(state.phoneScreen == .tonnetz)
        #expect(state.tonnetz.isShown)
    }

    /// At the desk the two are panes beside the keys, which stay played.
    @Test func keysChooseTheDesksPaneAndLeaveTheKeysPlayed() {
        let (state, _, _) = makeState()
        state.isAtDesk = true
        state.keyboard.keyDown(z)
        #expect(state.deskPane == .tonnetz)
        state.keyboard.keyDown(q)
        #expect(state.deskPane == .sequencer)
        #expect(state.mode.kind == .play)
    }

    @Test func theTonnetzsButtonsAreTappedByTheirKeysWhileItIsOnScreen() {
        let (state, _, _) = makeState()
        for key in [t, k] { state.keyboard.keyDown(key); state.keyboard.keyUp(code: key.code) }
        #expect(state.tonnetz.view == .net)
        #expect(!state.tonnetz.holds)

        state.deskPane = .tonnetz
        for key in [t, k] { state.keyboard.keyDown(key); state.keyboard.keyUp(code: key.code) }
        #expect(state.tonnetz.view == .triad)
        #expect(state.tonnetz.holds)
        for key in [n, k] { state.keyboard.keyDown(key); state.keyboard.keyUp(code: key.code) }
        #expect(state.tonnetz.view == .net)
        #expect(!state.tonnetz.holds)
    }

    /// The key a pointer over a button is shown follows the map.
    @Test func aButtonsTipIsTheKeyThatTapsIt() {
        let (state, _, _) = makeState()
        #expect(state.keyboard.keyName(for: .hold) == "K")
        #expect(state.keyboard.keyName(for: .loop) == "Return")
        state.keyboard.choosing = .button(.hold)
        state.keyboard.keyDown(x)
        #expect(state.keyboard.keyName(for: .hold) == "X")
        state.keyboard.choosing = .button(.hold)
        state.keyboard.keyDown(delete)
        #expect(state.keyboard.keyName(for: .hold) == nil)
    }

    /// A map saved before a button could be given a key gets the key it
    /// starts with, unless that key was given to something else, and a
    /// button left with no key on purpose stays without one.
    @Test func aMapSavedBeforeAButtonHadAKeyGetsItsStandardOne() throws {
        struct Saved: Encodable { var keys: [KeyboardAction: KeyboardKey] }
        var old = KeyboardMap.standard.keys
        for button in [KeyboardButton.sequencer, .tonnetz, .net, .triad, .hold] { old[.button(button)] = nil }
        old[.chord(.I)] = n                                   // N already plays a chord
        let defaults = isolatedDefaults()
        defaults.set(try JSONEncoder().encode(Saved(keys: old)), forKey: "keyboardMap")

        let (state, _, _) = makeState(defaults: defaults)
        #expect(state.keyboard.map.key(for: .button(.hold)) == k)
        #expect(state.keyboard.map.key(for: .button(.sequencer)) == q)
        #expect(state.keyboard.map.key(for: .button(.net)) == nil)
        #expect(state.keyboard.map.key(for: .chord(.I)) == n)

        state.keyboard.choosing = .button(.hold)
        state.keyboard.keyDown(delete)
        #expect(makeState(defaults: defaults).state.keyboard.map.key(for: .button(.hold)) == nil)
    }

    @Test func returnRecordsALoopAndSpaceStopsAndStartsIt() {
        let clock = ManualClock()
        let (state, _, _) = makeState(clock: clock)
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

    // MARK: – The Tonnetz

    private let p = KeyboardKey(code: 19, name: "P")
    private let l = KeyboardKey(code: 15, name: "L")
    private let r = KeyboardKey(code: 21, name: "R")

    /// A performance whose Tonnetz is on screen, at C major, and sounds
    /// through a sink of its own.
    private func makeTonnetz() -> (state: PerformanceState, tonnetz: RecordingSink) {
        let sink = RecordingSink()
        let state = PerformanceState(sink: RecordingSink(), tonnetzSink: sink,
                                     sequencer: SequencerState(defaults: isolatedDefaults()),
                                     keyboard: KeyboardState(defaults: isolatedDefaults()), clock: ManualClock())
        state.tonnetz.isShown = true
        return (state, sink)
    }

    @Test func aMovesKeyMakesTheMoveAndSoundsItsTriadWhileHeld() {
        let (state, sink) = makeTonnetz()
        #expect(state.keyboard.keyDown(r))
        state.keyboard.keyDown(r)   // the system's repeat
        #expect(state.tonnetz.cell.triad == Triad(root: .A, quality: .minor))
        #expect(sink.playCalls.count == 1)
        #expect(state.tonnetz.isSounding)

        state.keyboard.keyUp(code: r.code)
        #expect(!state.tonnetz.isSounding)
        #expect(sink.calls.last == .stop)
    }

    @Test func movesPlayedOverOneAnotherSoundUntilTheLastKeyIsUp() {
        let (state, sink) = makeTonnetz()
        state.keyboard.keyDown(p)
        state.keyboard.keyDown(l)   // C minor to A♭ major
        #expect(state.tonnetz.cell.triad == Triad(root: .Gs, quality: .major))

        state.keyboard.keyUp(code: p.code)
        #expect(state.tonnetz.isSounding)
        #expect(sink.stopCount == 0)

        state.keyboard.keyUp(code: l.code)
        #expect(!state.tonnetz.isSounding)
    }

    @Test func theMovesAreNotMadeWhileTheTonnetzIsOffScreen() {
        let (state, sink) = makeTonnetz()
        state.tonnetz.isShown = false
        // The key is still the Tonnetz's, so it is taken.
        #expect(state.keyboard.keyDown(p))
        state.keyboard.keyUp(code: p.code)
        #expect(state.tonnetz.cell == .home)
        #expect(sink.calls.isEmpty)
    }

    @Test func theTonnetzGoingOffScreenEndsItsTriad() {
        let (state, sink) = makeTonnetz()
        state.keyboard.keyDown(p)
        state.tonnetz.isShown = false
        #expect(!state.tonnetz.isSounding)
        #expect(sink.calls.last == .stop)
    }

    @Test func lettingEveryKeyGoEndsTheTriad() {
        let (state, _) = makeTonnetz()
        state.keyboard.keyDown(p)
        state.keyboard.releaseAll()
        #expect(!state.tonnetz.isSounding)
    }

    // MARK: – The map

    @Test func theNextKeyPressedBecomesTheChosenActionsKey() {
        let (state, keys, _) = makeState()
        state.keyboard.choosing = .chord(.I)
        #expect(state.keyboard.keyDown(x))
        #expect(state.keyboard.choosing == nil)
        #expect(keys.playCalls.isEmpty, "choosing a key plays nothing")
        #expect(state.keyboard.map.key(for: .chord(.I)) == x)

        state.keyboard.keyDown(x)
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
        state.keyboard.keyDown(x)

        let (again, _, _) = makeState(defaults: defaults)
        #expect(again.keyboard.map.key(for: .chord(.I)) == x)
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
        #expect(KeyboardButton.allCases.map { map.key(for: .button($0))?.name } == ["Return", "O", "M", "Space", "Q", "Z", "N", "T", "K"])
        #expect(TonnetzMove.allCases.map { map.key(for: .tonnetz($0))?.name } == ["P", "L", "R"])
    }
}
