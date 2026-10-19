import CoreGraphics
import Foundation
import Testing
@testable import Perfecto

@Suite("PadsState")
@MainActor
struct PadsStateTests {

    // MARK: – Helpers

    /// What the keys would give a pad, said by the test.
    @MainActor
    private final class Host: PadsHost {
        var padSound = PadsStateTests.sound(.I)
        private(set) var changes = 0
        func padsChanged() { changes += 1 }
    }

    /// Pads whose voices are recorded: one for each pad played, in the
    /// order they were first played, and the sequence's.
    @MainActor
    private final class Rig {
        let clock = ManualClock()
        let host = Host()
        let sequence = RecordingVoice()
        private(set) var voices: [RecordingVoice] = []
        private(set) var pads: PadsState!

        init(defaults: UserDefaults? = nil) {
            pads = PadsState(makeVoice: { [unowned self] in
                let voice = RecordingVoice()
                voices.append(voice)
                return voice
            }, sequenceVoice: sequence, clock: clock, defaults: defaults)
            pads.host = host
        }

        /// Gives the pad at `row`, `column` a sound.
        func assign(_ sound: PadSound, row: Int, column: Int) {
            pads.select(PadPlace(row: row, column: column))
            pads.edit { $0 = sound }
        }
    }

    private static func sound(_ degree: Degree, preset: SynthPreset = .initial,
                              effects: NoteEffects = NoteEffects()) -> PadSound {
        PadSound(chord: ChordSpec(degree: degree, color: .base), key: Key(root: .C, scale: .major),
                 octave: 4, preset: preset, effects: effects)
    }

    private func place(_ row: Int, _ column: Int) -> PadPlace { PadPlace(row: row, column: column) }

    // MARK: – The grid

    @Test func theGridIsFourByFourToStartWithAndPlayedRowByRow() {
        let grid = PadGrid()
        #expect(grid.places.count == 16)
        #expect(Array(grid.places.prefix(5)) == [place(0, 0), place(0, 1), place(0, 2), place(0, 3), place(1, 0)])
    }

    @Test func rowsAndColumnsAreSetApartAndKeptBetweenFourAndEight() {
        var grid = PadGrid()
        grid.resize(rows: 6, columns: 8)
        #expect(grid.rows == 6)
        #expect(grid.columns == 8)
        #expect(grid.places.count == 48)

        grid.resize(rows: 2, columns: 12)
        #expect(grid.rows == 4)
        #expect(grid.columns == 8)
    }

    @Test func aPadLeftOutsideASmallerGridComesBackWithALargerOne() {
        var grid = PadGrid()
        grid.resize(rows: 8, columns: 8)
        grid[place(7, 7)] = Self.sound(.V)
        grid[place(1, 2)] = Self.sound(.ii)

        grid.resize(rows: 4, columns: 4)
        #expect(grid[place(7, 7)] == nil)
        // The pad that is still there has kept its place.
        #expect(grid[place(1, 2)] == Self.sound(.ii))

        grid.resize(rows: 8, columns: 8)
        #expect(grid[place(7, 7)] == Self.sound(.V))
    }

    @Test func theSequenceGoesFromTheLastPadToTheFirst() {
        let grid = PadGrid()
        #expect(grid.place(after: nil) == place(0, 0))
        #expect(grid.place(after: place(0, 3)) == place(1, 0))
        #expect(grid.place(after: place(3, 3)) == place(0, 0))
        // A place the grid no longer has.
        #expect(grid.place(after: place(6, 6)) == place(0, 0))
    }

    // MARK: – Playing

    @Test func aPadSoundsItsChordInItsOwnSoundWhileItIsHeld() {
        let rig = Rig()
        var effects = NoteEffects()
        effects.vocoder.isOn = true
        let sound = Self.sound(.V, preset: .strings, effects: effects)
        rig.assign(sound, row: 0, column: 1)

        rig.pads.press(place(0, 1))
        #expect(rig.voices.count == 1)
        let played = rig.voices[0].sounding
        #expect(played?.event.voicing.notes == [67, 71, 74])   // G major
        #expect(played?.preset == .strings)
        #expect(played?.effects == effects)

        rig.pads.release([place(0, 1)])
        #expect(rig.voices[0].calls.last == .stop)
        #expect(rig.pads.held.isEmpty)
    }

    @Test func padsHeldTogetherSoundTogetherEachThroughItsOwnVoice() {
        let rig = Rig()
        rig.assign(Self.sound(.I), row: 0, column: 0)
        rig.assign(Self.sound(.IV), row: 0, column: 1)
        rig.assign(Self.sound(.V), row: 0, column: 2)

        for column in 0..<3 { rig.pads.press(place(0, column)) }
        #expect(rig.voices.map(\.degrees) == [[.I], [.IV], [.V]])
        #expect(rig.voices.allSatisfy { $0.stopCount == 0 })

        // Lifting one ends that pad alone.
        rig.pads.release([place(0, 1)])
        #expect(rig.voices.map(\.stopCount) == [0, 1, 0])
        #expect(rig.pads.held == [place(0, 0), place(0, 2)])
    }

    @Test func aPadWithNoSoundIsSilent() {
        let rig = Rig()
        rig.pads.press(place(2, 2))
        #expect(rig.voices.isEmpty)
        #expect(rig.pads.held == [place(2, 2)])
    }

    @Test func aPadIsPlayedAgainThroughTheVoiceItHad() {
        let rig = Rig()
        rig.assign(Self.sound(.I), row: 0, column: 0)
        for _ in 0..<2 {
            rig.pads.press(place(0, 0))
            rig.pads.release([place(0, 0)])
        }
        #expect(rig.voices.count == 1)
        #expect(rig.voices[0].degrees == [.I, .I])
    }

    @Test func aFingerSlidingAcrossThePadsLeavesNoGap() {
        let rig = Rig()
        rig.assign(Self.sound(.I), row: 0, column: 0)
        rig.assign(Self.sound(.ii), row: 0, column: 1)

        rig.pads.movePointer(from: nil, to: place(0, 0))
        rig.pads.movePointer(from: place(0, 0), to: place(0, 1))

        // The second pad started before the first ended.
        #expect(rig.voices[1].sounding != nil)
        #expect(rig.voices[0].calls.last == .stop)
    }

    // MARK: – The sequence

    @Test func theSequencePlaysThePadsInOrderOneToAStep() {
        let rig = Rig()
        rig.assign(Self.sound(.I), row: 0, column: 0)
        rig.assign(Self.sound(.IV), row: 0, column: 1)
        rig.assign(Self.sound(.V), row: 0, column: 3)

        rig.pads.isRunning = true
        #expect(rig.pads.step == place(0, 0))
        #expect(rig.sequence.degrees == [.I])

        rig.clock.advance(beats: 1)
        #expect(rig.pads.step == place(0, 1))
        #expect(rig.sequence.degrees == [.I, .IV])

        // A pad with no sound is a rest.
        rig.clock.advance(beats: 1)
        #expect(rig.pads.step == place(0, 2))
        #expect(rig.sequence.sounding == nil)

        rig.clock.advance(beats: 1)
        #expect(rig.sequence.degrees == [.I, .IV, .V])
        // No pad's own voice was used.
        #expect(rig.voices.isEmpty)
    }

    @Test func theSequenceStartsAgainFromTheFirstPadAfterTheLast() {
        let rig = Rig()
        rig.assign(Self.sound(.I), row: 0, column: 0)
        rig.pads.isRunning = true
        rig.clock.advance(beats: 16.1)
        #expect(rig.pads.step == place(0, 0))
        #expect(rig.sequence.degrees == [.I, .I])
    }

    @Test func aStepSoundsForAShareOfItsLength() {
        let rig = Rig()
        rig.assign(Self.sound(.I), row: 0, column: 0)
        rig.assign(Self.sound(.I), row: 0, column: 1)
        rig.pads.isRunning = true

        rig.clock.advance(beats: 0.7)
        #expect(rig.sequence.sounding != nil)
        rig.clock.advance(beats: 0.1)
        #expect(rig.sequence.sounding == nil)
    }

    @Test func theStepsLengthIsTheRateSet() {
        let rig = Rig()
        rig.pads.setRate(.sixteenth)
        rig.pads.isRunning = true
        rig.clock.advance(beats: 1)
        #expect(rig.pads.step == place(1, 0))

        // A new rate is taken up from where the sequence is.
        rig.pads.setRate(.half)
        #expect(rig.pads.step == place(1, 0))
        rig.clock.advance(beats: 2)
        #expect(rig.pads.step == place(1, 1))
    }

    @Test func stoppingTheSequenceSilencesItAndForgetsItsPlace() {
        let rig = Rig()
        rig.assign(Self.sound(.I), row: 0, column: 0)
        rig.pads.isRunning = true
        rig.pads.isRunning = false

        #expect(rig.pads.step == nil)
        #expect(rig.sequence.sounding == nil)
        rig.clock.advance(beats: 4)
        #expect(rig.sequence.degrees == [.I])
    }

    @Test func padsArePlayedOverTheSequence() {
        let rig = Rig()
        rig.assign(Self.sound(.I), row: 0, column: 0)
        rig.pads.isRunning = true

        rig.pads.press(place(0, 0))
        #expect(rig.voices.map(\.degrees) == [[.I]])
        #expect(rig.sequence.sounding != nil)

        // The sequence goes on while the pads are not on screen.
        rig.pads.isShown = true
        rig.pads.isShown = false
        #expect(rig.pads.held.isEmpty)
        #expect(rig.pads.isRunning)
    }

    // MARK: – Editing

    @Test func whileEditingAPressChoosesThePad() {
        let rig = Rig()
        rig.pads.isShown = true
        rig.pads.isEditing = true
        #expect(rig.pads.edited == place(0, 0))

        rig.pads.press(place(2, 1))
        #expect(rig.pads.edited == place(2, 1))

        rig.pads.isEditing = false
        #expect(rig.pads.edited == nil)
    }

    @Test func aPadWithNoSoundIsGivenWhatTheKeysPlay() {
        let rig = Rig()
        rig.host.padSound = Self.sound(.vi, preset: .organ)
        rig.pads.select(place(1, 1))

        rig.pads.edit { $0.octave = 3 }

        var expected = Self.sound(.vi, preset: .organ)
        expected.octave = 3
        #expect(rig.pads.grid[place(1, 1)] == expected)
    }

    @Test func takingFromTheKeysReplacesThePadsSound() {
        let rig = Rig()
        rig.assign(Self.sound(.I), row: 0, column: 0)
        rig.host.padSound = Self.sound(.V, preset: .bell)

        rig.pads.takeFromKeys()
        #expect(rig.pads.grid[place(0, 0)] == Self.sound(.V, preset: .bell))

        rig.pads.clearSelected()
        #expect(rig.pads.grid[place(0, 0)] == nil)
    }

    @Test func aNewChordIsHeardAtOnceInAPadThatIsHeld() {
        let rig = Rig()
        rig.assign(Self.sound(.I), row: 0, column: 0)
        rig.pads.audition()

        rig.pads.edit { $0.chord = ChordSpec(degree: .IV, color: .base) }
        #expect(rig.voices[0].degrees == [.I, .IV])

        rig.pads.endAudition()
        #expect(rig.voices[0].calls.last == .stop)
        #expect(rig.pads.held.isEmpty)
    }

    @Test func newEffectsReachAHeldPadWithoutStrikingItAgain() {
        let rig = Rig()
        rig.assign(Self.sound(.I), row: 0, column: 0)
        rig.pads.press(place(0, 0))

        rig.pads.edit { $0.effects.reverb.isOn = true }

        #expect(rig.voices[0].degrees == [.I])
        guard case let .change(chord) = rig.voices[0].calls.last else {
            Issue.record("the pad's effects were not changed under it")
            return
        }
        #expect(chord.effects.reverb.isOn)
    }

    @Test func aPadTheGridNoLongerHasIsLetGo() {
        let rig = Rig()
        rig.pads.setRows(8)
        rig.pads.setColumns(8)
        rig.assign(Self.sound(.I), row: 7, column: 7)
        rig.pads.press(place(7, 7))

        rig.pads.setRows(4)

        #expect(rig.pads.held.isEmpty)
        #expect(rig.voices[0].calls.last == .stop)
        #expect(rig.pads.selected == place(0, 0))
    }

    // MARK: – The mic

    @Test func aPadWithTheVocoderOnNeedsTheMicWhileItCanSound() {
        let rig = Rig()
        var effects = NoteEffects()
        effects.vocoder.isOn = true
        rig.assign(Self.sound(.I, effects: effects), row: 0, column: 0)
        #expect(!rig.pads.hearsTheMic)

        rig.pads.isShown = true
        #expect(rig.pads.hearsTheMic)

        rig.pads.isShown = false
        rig.pads.isRunning = true
        #expect(rig.pads.hearsTheMic)

        rig.pads.clearSelected()
        #expect(!rig.pads.hearsTheMic)
        #expect(rig.host.changes > 0)
    }

    // MARK: – Saving

    @Test func theGridIsSaved() {
        let defaults = isolatedDefaults()
        let rig = Rig(defaults: defaults)
        rig.pads.setColumns(6)
        rig.pads.setRate(.eighth)
        rig.assign(Self.sound(.ii, preset: .kalimba), row: 3, column: 5)

        let restored = Rig(defaults: defaults).pads!
        #expect(restored.grid == rig.pads.grid)
        #expect(restored.grid[place(3, 5)] == Self.sound(.ii, preset: .kalimba))
    }

    // MARK: – In the performance

    @Test func aPadTakesTheChordTheKeysPlayedLastAsTheyAreSetNow() {
        let padSink = RecordingSink()
        let state = PerformanceState(sink: RecordingSink(), padSink: { padSink }, clock: ManualClock())
        state.key = Key(root: .D, scale: .major)
        state.joystickMoved(to: .right)
        state.press(.degree(.V))
        state.release(.degree(.V))
        state.joystickMoved(to: .center)
        state.setSynthPreset(.brass)
        state.effects.chorus.isOn = true

        state.pads.select(PadPlace(row: 0, column: 0))
        state.pads.takeFromKeys()

        let sound = state.pads.grid[PadPlace(row: 0, column: 0)]
        #expect(sound?.chord == ChordSpec(degree: .V, color: .joystick(.default, .right)))
        #expect(sound?.key == Key(root: .D, scale: .major))
        #expect(sound?.preset == .brass)
        #expect(sound?.effects.chorus.isOn == true)

        // What is chosen for the keys afterwards does not reach the pad.
        state.key = Key(root: .C, scale: .major)
        state.pads.press(PadPlace(row: 0, column: 0))
        #expect(padSink.playEvents.first?.context.key == Key(root: .D, scale: .major))
    }

    @Test func thePadsTakeThePhonesScreenAndLeaveTheModeAsItIs() {
        let state = PerformanceState(sink: RecordingSink(), clock: ManualClock())
        state.show(.pads)
        #expect(state.phoneScreen == .pads)
        #expect(state.pads.isShown)
        #expect(state.mode.kind == .play)

        state.show(.play)
        #expect(state.phoneScreen == .play)
        #expect(!state.pads.isShown)
    }

    // MARK: – Where the pads are

    @Test func theBoardIsDividedEvenlyIntoThePads() {
        var grid = PadGrid()
        grid.resize(rows: 4, columns: 5)
        let frames = PadCells.frames(in: CGSize(width: 5 * 60 + 4 * PadCells.gap, height: 4 * 40 + 3 * PadCells.gap),
                                     grid: grid)

        #expect(frames.count == 20)
        #expect(frames[place(0, 0)] == CGRect(x: 0, y: 0, width: 60, height: 40))
        #expect(frames[place(3, 4)] == CGRect(x: 4 * (60 + PadCells.gap), y: 3 * (40 + PadCells.gap),
                                              width: 60, height: 40))
    }
}
