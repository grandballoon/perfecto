import CoreGraphics
import SwiftUI
import Testing
@testable import Perfecto

@Suite("SoloState")
@MainActor
struct SoloStateTests {

    // MARK: – Helpers

    /// A performance in C major, octave 4, whose solo strip sounds through
    /// a sink of its own.
    private func makeState() -> (state: PerformanceState, keys: RecordingSink, solo: RecordingSink) {
        let keys = RecordingSink(), solo = RecordingSink()
        let state = PerformanceState(sink: keys, soloSink: solo, clock: ManualClock())
        return (state, keys, solo)
    }

    private func pitches(_ state: PerformanceState, _ count: Int) -> [Int] {
        state.solo.notes(count).map(\.note)
    }

    // MARK: – The notes on the strip

    @Test func theStripOffersTheNotesThatFitTheChordHeld() {
        let (state, _, _) = makeState()
        state.press(degree: .I)
        #expect(pitches(state, 6) == [60, 62, 64, 67, 69, 72])   // C major pentatonic

        state.movePointer(from: .I, to: .ii)
        #expect(pitches(state, 5) == [60, 62, 65, 67, 69])       // D minor pentatonic, from C up
    }

    @Test func theStripFollowsTheChordsColor() {
        let (state, _, _) = makeState()
        state.joystickMoved(to: .up)   // Flip 3rd: C minor
        state.press(degree: .I)
        #expect(pitches(state, 5) == [60, 63, 65, 67, 69])
    }

    @Test func beforeAnyChordTheStripIsTheTonics() {
        let (state, _, _) = makeState()
        #expect(pitches(state, 5) == [60, 62, 64, 67, 69])
    }

    @Test func aChordLetGoIsStillPlayedOverInTheKeySetNow() {
        let (state, _, _) = makeState()
        state.press(degree: .V)
        state.release(degree: .V)
        #expect(pitches(state, 5) == [62, 65, 67, 69, 71])       // G: G A B D F, from C up

        state.key = Key(root: .D, scale: .major)
        state.octave = 3
        // The same degree in D major, an octave lower: A B C# E G, from D up.
        #expect(pitches(state, 5) == [52, 55, 57, 59, 61])
    }

    // MARK: – Playing

    @Test func aCellSoundsItsNoteBesideTheKeysChord() {
        let (state, keys, solo) = makeState()
        state.press(degree: .I)
        keys.reset()

        state.solo.press(cell: 3)

        #expect(solo.playCalls == [Voicing(notes: [67])])
        #expect(solo.playEvents.first?.context == state.soloChord)
        #expect(keys.calls.isEmpty)
    }

    @Test func aFingerSlidingAlongTheStripPlaysARunWithNoGaps() {
        let (state, _, solo) = makeState()
        state.solo.movePointer(from: nil, to: 0)
        state.solo.movePointer(from: 0, to: 1)
        state.solo.movePointer(from: 1, to: 2)

        // Each note replaces the last; nothing is stopped in between.
        #expect(solo.calls == [60, 62, 64].map { .play(event(state, $0)) })
        #expect(state.solo.held == [2])
    }

    @Test func liftingTheNewestFingerHandsTheNoteBackToTheOneBeneath() {
        let (state, _, solo) = makeState()
        state.solo.press(cell: 0)
        state.solo.press(cell: 2)
        solo.reset()

        state.solo.release([2])
        #expect(solo.playCalls == [Voicing(notes: [60])])

        // Lifting a finger that is not the one sounding changes nothing.
        state.solo.press(cell: 2)
        solo.reset()
        state.solo.release([0])
        #expect(solo.calls.isEmpty)
        #expect(state.solo.held == [2])
    }

    @Test func theLastFingerUpEndsTheNote() {
        let (state, _, solo) = makeState()
        state.solo.press(cell: 0)
        state.solo.press(cell: 1)
        solo.reset()

        state.solo.release([0, 1])

        #expect(solo.calls == [.stop])
        #expect(state.solo.held.isEmpty)
    }

    @Test func aNoteHeldRingsOnWhenTheChordChanges() {
        let (state, _, solo) = makeState()
        state.press(degree: .I)
        state.solo.press(cell: 2)   // E
        solo.reset()

        state.movePointer(from: .I, to: .ii)

        #expect(solo.calls.isEmpty)
        // The next cell pressed is the new chord's.
        state.solo.movePointer(from: 2, to: 3)
        #expect(solo.playCalls == [Voicing(notes: [67])])
    }

    @Test func switchingTheStripOffEndsItsNote() {
        let (state, _, solo) = makeState()
        state.solo.isOn = true
        state.solo.press(cell: 0)
        solo.reset()

        state.solo.isOn = false

        #expect(solo.calls == [.stop])
        #expect(state.solo.held.isEmpty)
    }

    @Test func aNoteTakesTheKeysPresetAndTheEffectsAsSet() {
        let notes = RecordingNoteSink()
        let clock = ManualClock()
        let state = PerformanceState(sink: RecordingSink(), soloSink: NotePlayer([notes], clock: clock), clock: clock)
        state.effects.reverb.isOn = true
        state.effects.filter.isOn = true
        state.effects.filter.followsSlide = true
        // A slide on the chord key plays the chord's filter, not the run's.
        state.slide(on: .I, to: 1)
        state.press(degree: .I)

        state.solo.press(cell: 1)

        #expect(notes.started == [62])
        #expect(notes.sounds.first == NoteSound(preset: state.synthPreset, effects: state.effects.asSet))
    }

    // MARK: – Where the strip is

    @Test func theStripInTheColorsPlaceIsABarAndLeavesTheColorNeutral() {
        let (state, _, _) = makeState()
        state.colorSurface = .grid
        state.gridMoved(to: GridPosition(height: .seventh, row: 0))
        state.solo.placement = .colors
        #expect(state.surfaceShape == .grid)

        state.solo.isOn = true

        #expect(state.solo.takesColorsPlace && state.solo.placementByKeys == nil)
        #expect(state.surfaceShape == .bar)
        #expect(state.gridPosition == nil)

        state.solo.placement = .underKeys
        #expect(state.solo.placementByKeys == .underKeys)
        #expect(state.surfaceShape == .grid)
    }

    @Test func theKeysGiveUpNoMoreThanTheStripMayTake() {
        let (state, _, _) = makeState()
        state.solo.resize(to: 0.9)
        #expect(state.solo.share == SoloState.shareRange.upperBound)
        state.solo.resize(to: 0)
        #expect(state.solo.share == SoloState.shareRange.lowerBound)
    }

    // MARK: – Cells

    /// The strip's sizes on the play screen, and the cells each has.
    @Test(arguments: [
        (CGSize(width: 362, height: 88), Axis.horizontal, 8),     // in the colors' place
        (CGSize(width: 362, height: 192), Axis.horizontal, 16),   // under the keys, upright
        (CGSize(width: 614, height: 88), Axis.horizontal, 14),    // under the row of keys
        (CGSize(width: 343, height: 224), Axis.horizontal, 16),   // beside the keys, on its side
        (CGSize(width: 88, height: 328), Axis.vertical, 8),       // the upright bar
    ])
    func cellsFillTheStripLowToHigh(_ size: CGSize, axis: Axis, count: Int) {
        let frames = SoloStripCells.frames(in: size, axis: axis)
        #expect(frames.count == count)

        // The lowest note is at the bottom, at the leading edge.
        #expect(frames.first?.minX == 0)
        #expect(abs((frames.first?.maxY ?? 0) - size.height) < 0.001)
        // Cells do not overlap, and none leaves the strip.
        let bounds = CGRect(origin: .zero, size: size).insetBy(dx: -0.001, dy: -0.001)
        for (index, frame) in frames.enumerated() {
            #expect(bounds.contains(frame))
            for other in frames[(index + 1)...] {
                #expect(frame.intersection(other).isEmpty)
            }
        }
        #expect(SoloStripCells.frames(in: .zero, axis: axis).isEmpty)
    }

    private func event(_ state: PerformanceState, _ note: Int) -> ChordEvent {
        ChordEvent(voicing: Voicing(notes: [note]), articulation: .block, context: state.soloChord)
    }
}
