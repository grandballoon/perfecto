import Foundation
import Testing
@testable import Perfecto

/// The sequencer's edits as the screen makes them: on the notes of the layer
/// shown, through the steps selected.
@Suite("SequencerState editing")
@MainActor
struct SequencerEditingTests {

    private static let step = TimelineTime.ticksPerStep

    private func makeState(selecting steps: Set<Int> = []) -> SequencerState {
        let state = SequencerState(defaults: isolatedDefaults())
        state.selectedSteps = steps
        state.primaryStep = steps.max()
        return state
    }

    /// The layer shown, each note as (first step, steps drawn across, degree).
    private func drawn(_ state: SequencerState) -> [[Int]] {
        var notes: [[Int]] = []
        for chit in state.chits {
            if chit.isHead {
                notes.append([chit.steps.lowerBound, chit.steps.count, chit.note.chord.degree.rawValue])
            } else {
                notes[notes.count - 1][1] += chit.steps.count
            }
        }
        return notes
    }

    private func enter(_ degree: Degree, on steps: Set<Int>, in state: SequencerState) {
        state.selectedSteps = steps
        state.primaryStep = steps.max()
        state.editSelectedChords { ChordSpec(degree: degree, color: $0.color) }
    }

    // MARK: – Chords

    @Test func aChordGoesOnEverySelectedStepThatHasNone() {
        let state = makeState(selecting: [0, 1, 4])
        state.editSelectedChords { ChordSpec(degree: .V, color: $0.color) }
        #expect(drawn(state) == [[0, 1, 5], [1, 1, 5], [4, 1, 5]])
        #expect(state.primaryNote?.chord.degree == .V)
    }

    /// Any step of a held note selects it, and changing its chord leaves it
    /// held as it was.
    @Test func changingTheChordOfAHeldNoteKeepsItHeld() {
        let state = makeState()
        enter(.I, on: [0, 1, 2, 3], in: state)
        state.joinSelected()
        state.selectedSteps = [2]
        state.primaryStep = 2
        state.editSelectedChords { ChordSpec(degree: .IV, color: $0.color) }
        #expect(drawn(state) == [[0, 4, 4]])
        #expect(state.timeline.layers[0].notes[0].length == 4 * Self.step)
    }

    @Test func aColorEditKeepsTheDegree() {
        let state = makeState()
        enter(.vi, on: [3], in: state)
        state.editSelectedChords { ChordSpec(degree: $0.degree, color: .joystick(.default, .right)) }
        #expect(state.primaryNote?.chord == ChordSpec(degree: .vi, color: .joystick(.default, .right)))
    }

    // MARK: – Rest, join, split

    @Test func restEmptiesTheSelectedStepsAndIsOneUndoStep() {
        let state = makeState()
        enter(.I, on: [0, 1, 2], in: state)
        state.selectedSteps = [1]
        state.restSelected()
        #expect(drawn(state) == [[0, 1, 1], [2, 1, 1]])
        state.undo()
        #expect(drawn(state).count == 3)
    }

    @Test func joinAndSplitAreOfferedOnlyWhenTheyWouldChangeSomething() {
        let state = makeState()
        enter(.I, on: [0, 1, 2, 3], in: state)
        #expect(state.canJoin && !state.canSplit)
        state.joinSelected()
        #expect(drawn(state) == [[0, 4, 1]])
        #expect(!state.canJoin && state.canSplit)
        state.splitSelected()
        #expect(drawn(state) == [[0, 1, 1], [1, 1, 1], [2, 1, 1], [3, 1, 1]])

        state.selectedSteps = [8, 9]                  // nothing there to join
        #expect(!state.canJoin && !state.canSplit)
        state.selectedSteps = [0]                     // one step: nothing to join it to
        #expect(!state.canJoin)
    }

    // MARK: – Length

    @Test func aNoteIsMadeAStepLongerAndShorter() {
        let state = makeState()
        enter(.I, on: [0], in: state)
        state.lengthenSelected(bySteps: 2)
        #expect(state.timeline.layers[0].notes[0].length == 90 + 2 * Self.step)
        state.lengthenSelected(bySteps: -1)
        #expect(state.timeline.layers[0].notes[0].length == 90 + Self.step)
        #expect(state.primaryNote?.heldSteps == 2)
    }

    @Test func theGateSlidesTheEndOfTheLastStep() {
        let state = makeState()
        enter(.I, on: [0, 1], in: state)
        state.joinSelected()
        state.snapshot()
        state.setGateOfSelected(0.25)
        state.setGateOfSelected(0.5)
        #expect(state.primaryNote?.length == Self.step + 60)
        state.undo()                                  // the whole drag
        #expect(state.primaryNote?.length == 2 * Self.step)
    }

    // MARK: – Notes played off the grid

    private func loose() -> [TimelineNote] {
        [TimelineNote(start: 110, length: 200, chord: ChordSpec(degree: .I, color: .base)),     // step 1, early
         TimelineNote(start: 1900, length: 20, chord: ChordSpec(degree: .V, color: .base))]     // nearest the end
    }

    @Test func aLooselyPlayedNoteIsSnappedOntoTheGrid() {
        let state = makeState()
        state.startLoop(loose(), bars: 1)
        #expect(drawn(state) == [[1, 2, 1], [15, 1, 5]])
        state.selectedSteps = [2]
        #expect(state.canSnap)
        state.snapSelected()
        #expect(state.timeline.layers[0].notes[0].start == 120)
        #expect(state.timeline.layers[0].notes[0].isOnGrid)
        #expect(!state.canSnap)
    }

    /// The note drawn on the last step, though nearest the line after it,
    /// is selected and edited through that step.
    @Test func theLastStepSelectsANoteNearestTheEnd() {
        let state = makeState()
        state.startLoop(loose(), bars: 1)
        state.selectedSteps = [15]
        state.primaryStep = 15
        #expect(state.primaryNote?.chord.degree == .V)
        state.editSelectedChords { ChordSpec(degree: .ii, color: $0.color) }
        #expect(state.timeline.layers[0].notes.map(\.chord.degree) == [.I, .ii])   // changed, not added to
        state.snapSelected()
        #expect(state.timeline.layers[0].notes[1].start == 15 * Self.step)
        state.restSelected()
        #expect(state.timeline.layers[0].notes.count == 1)
    }

    // MARK: – A note's own key and octave

    @Test func aNoteKeepsAKeyOfItsOwnUntilToldToFollowAgain() {
        let state = makeState()
        enter(.I, on: [0, 1], in: state)
        state.selectedSteps = [1]
        state.primaryStep = 1
        let d = Key(root: .D, scale: .major)
        state.editSelectedPlaying { $0.key = d }
        #expect(state.timeline.layers[0].notes.map(\.playing.key) == [nil, d])
        #expect(state.primaryNote?.playing.hasOwn == true)

        // It plays in its own key whatever is chosen, and the other note follows.
        let live = LiveSettings(key: Key(root: .C, scale: .major), octave: 4, preset: .allCases[0], effects: NoteEffects())
        let chords = state.timeline.compile(layer: state.layerID, live: live)
        #expect(chords.map(\.event.context.key) == [live.key, d])

        state.editSelectedPlaying { $0.key = nil }
        #expect(state.primaryNote?.playing.hasOwn == false)
        state.undo()
        #expect(state.primaryNote?.playing.key == d)
    }

    @Test func anOctaveOfItsOwnIsSetOnEverySelectedNote() {
        let state = makeState()
        enter(.I, on: [0, 1, 2], in: state)
        state.selectedSteps = [0, 2]
        state.editSelectedPlaying { $0.octave = 5 }
        #expect(state.timeline.layers[0].notes.map(\.playing.octave) == [5, nil, 5])
    }

    // MARK: – Step entry

    /// A progression is entered by choosing its chords in order: each goes
    /// on the selected step and the selection moves to the next.
    @Test func enteringChordsInOrderFillsStepAfterStep() {
        let state = makeState(selecting: [14])
        for degree in [Degree.I, .IV, .V] {
            state.snapshot()
            state.editSelectedChords { ChordSpec(degree: degree, color: $0.color) }
            state.advanceSelection()
        }
        // Round the end of the bar to its first step.
        #expect(drawn(state) == [[0, 1, 5], [14, 1, 1], [15, 1, 4]])
        #expect(state.selectedSteps == [1] && state.primaryStep == 1)
        state.undo()                                  // the last chord and its move
        #expect(drawn(state) == [[14, 1, 1], [15, 1, 4]])
        #expect(state.selectedSteps == [0])
    }

    /// Past a held note, the next place is the step after its end.
    @Test func theSelectionMovesPastAHeldNote() {
        let state = makeState()
        enter(.I, on: [4, 5, 6], in: state)
        state.joinSelected()
        state.selectedSteps = [4]
        state.primaryStep = 4
        state.advanceSelection()
        #expect(state.selectedSteps == [7])
    }

    @Test func theSelectionMovesOnToTheNextBarAndShowsIt() {
        let state = makeState(selecting: [15])
        state.addBar()
        state.focusedBar = 0
        state.advanceSelection()
        #expect(state.selectedSteps == [16])
        #expect(state.focusedBar == 1)
    }

    // MARK: – Layers

    @Test func aNewLayerIsShownAndEditedOnItsOwn() {
        let state = makeState()
        enter(.I, on: [0], in: state)
        let first = state.layerID
        state.addLayer()
        #expect(state.layers.count == 2)
        #expect(state.layerID != first)
        #expect(state.chits.isEmpty)
        enter(.V, on: [4], in: state)
        #expect(state.timeline.layer(first)?.notes.count == 1)
        state.showLayer(first)
        #expect(drawn(state) == [[0, 1, 1]])
    }

    @Test func aLayerIsDuplicatedAndTheCopyShown() {
        let state = makeState()
        enter(.IV, on: [2], in: state)
        let first = state.layerID
        state.duplicateLayer()
        #expect(state.layers.count == 2)
        #expect(state.layerID != first)
        #expect(drawn(state) == [[2, 1, 4]])
        state.undo()
        #expect(state.layers.count == 1 && state.layerID == first)
    }

    @Test func thereAreNoMoreLayersThanTheLoopBarHolds() {
        let state = makeState()
        for _ in 0..<10 { state.addLayer() }
        #expect(state.layers.count == Timeline.maxLayers)
        #expect(!state.canAddLayer)
    }

    @Test func removingTheLayerShownShowsAnother() {
        let state = makeState()
        let first = state.layerID
        state.addLayer()
        state.removeLayer(state.layerID)
        #expect(state.layerID == first)
        state.removeLayer(first)                      // the last one: an empty layer takes its place
        #expect(state.layers.count == 1)
        #expect(state.timeline.layer(state.layerID) != nil)
    }

    // MARK: – Signature and bars

    @Test func theSignatureChangesTheBarsAndNotTheNotes() {
        let logger = RecordingLogger()
        let state = SequencerState(defaults: isolatedDefaults(), logger: logger)
        state.selectedSteps = [13]
        state.primaryStep = 13
        state.editSelectedChords { ChordSpec(degree: .V, color: $0.color) }
        state.setSignature(TimeSignature(beats: 6, unit: .eighth))
        #expect(state.stepsPerBar == 12)
        #expect(state.barCount == 2)                  // 16 steps need two bars of 12
        #expect(state.shape.columns == 6)
        #expect(state.timeline.layers[0].notes[0].start == 13 * Self.step)
        #expect(state.selectedSteps == [13])
        #expect(logger.events.contains {
            if case .sequencer_signature_changed(signature: "6/8") = $0 { return true }
            return false
        })
        state.undo()
        #expect(state.stepsPerBar == 16 && state.barCount == 1)
    }

    @Test func removingABarFollowsTheSignature() {
        let state = makeState()
        state.setSignature(TimeSignature(beats: 3, unit: .quarter))
        state.addBar()
        enter(.V, on: [14], in: state)                // bar 2, third step
        state.removeBar(0)
        #expect(drawn(state) == [[2, 1, 5]])
        #expect(state.selectedSteps == [2])
    }

    @Test func doublingAndHalvingReadTheNotesAsMoreOrFewerBars() {
        let state = makeState()
        enter(.I, on: [0, 4], in: state)
        #expect(!state.canHalveBars)
        state.doubleBars()
        #expect(state.barCount == 2)
        #expect(drawn(state).map { $0[0] } == [0, 8])
        #expect(state.selectedSteps.isEmpty)
        #expect(state.canHalveBars)
        state.halveBars()
        #expect(state.barCount == 1)
        #expect(drawn(state).map { $0[0] } == [0, 4])
    }

    @Test func emptyBarsAtTheEndAreTrimmed() {
        let state = makeState()
        enter(.I, on: [3], in: state)
        #expect(!state.canTrimBars)
        state.addBar()
        state.addBar()
        #expect(state.canTrimBars)
        state.trimEmptyBars()
        #expect(state.barCount == 1)
    }
}
