import Testing
@testable import Perfecto

/// The timeline's edits, as changes to plain values.
@Suite("Timeline edits")
struct TimelineEditTests {

    private static let step = TimelineTime.ticksPerStep
    private let I = ChordSpec(degree: .I, color: .base)
    private let IV = ChordSpec(degree: .IV, color: .base)
    private let V = ChordSpec(degree: .V, color: .base)

    private func note(_ chord: ChordSpec, step: Int, steps: Int = 1) -> TimelineNote {
        TimelineNote(start: step * Self.step, length: steps * Self.step, chord: chord)
    }

    /// Each note as (start step, length in steps, degree), for notes on the grid.
    private func shape(_ layer: Layer) -> [[Int]] {
        layer.notes.map { [$0.start / Self.step, $0.length / Self.step, $0.chord.degree.rawValue] }
    }

    /// A layer's rule: its notes are in order and none overlaps the next.
    private func isOrdered(_ layer: Layer) -> Bool {
        zip(layer.notes, layer.notes.dropFirst()).allSatisfy { $0.end <= $1.start } &&
            layer.notes.allSatisfy { $0.length >= 1 }
    }

    // MARK: – Time

    @Test func aStepIsASixteenthAndABarFollowsTheSignature() {
        #expect(TimelineTime.ticksPerStep == 120)
        #expect(TimeSignature.common.stepsPerBar == 16)
        #expect(TimeSignature(beats: 3, unit: .quarter).stepsPerBar == 12)
        #expect(TimeSignature(beats: 6, unit: .eighth).stepsPerBar == 12)
        #expect(TimeSignature(beats: 7, unit: .eighth).stepsPerBar == 14)
        #expect(TimeSignature(beats: 6, unit: .eighth).quarterBeatsPerBar == 3)
    }

    /// Each row of the grid is one felt beat.
    @Test func rowsFollowTheBeat() {
        #expect(TimeSignature.common.stepsPerRow == 4)
        #expect(TimeSignature(beats: 6, unit: .eighth).stepsPerRow == 6)
        #expect(TimeSignature(beats: 12, unit: .eighth).stepsPerRow == 6)
        #expect(TimeSignature(beats: 7, unit: .eighth).stepsPerRow == 4)
        for signature in TimeSignature.offered {
            #expect(signature.ticksPerBar.isMultiple(of: TimelineTime.ticksPerStep), "\(signature.label)")
        }
    }

    @Test func aTickBelongsToTheStepItFallsIn() {
        #expect(TimelineTime.step(at: 0) == 0)
        #expect(TimelineTime.step(at: 119) == 0)
        #expect(TimelineTime.step(at: 120) == 1)
        #expect(TimelineTime.nearestStepLine(to: 59) == 0)
        #expect(TimelineTime.nearestStepLine(to: 61) == 120)
    }

    // MARK: – Placing and resting

    @Test func placingPutsOneNoteOnEachStepWithAGapBeforeTheNext() {
        var layer = Layer()
        layer.place(I, onSteps: [0, 1, 4])
        #expect(layer.notes.map(\.start) == [0, 120, 480])
        #expect(layer.notes.allSatisfy { $0.length == 90 && $0.chord == I })
    }

    @Test func placingReplacesWhatWasOnTheStep() {
        var layer = Layer()
        layer.place(I, onSteps: [2])
        layer.place(IV, onSteps: [2])
        #expect(layer.notes.count == 1)
        #expect(layer.notes[0].chord == IV)
    }

    /// A new chord in the middle of a long one takes over from it there.
    @Test func placingInsideALongNoteCutsItShort() {
        var layer = Layer(notes: [note(I, step: 0, steps: 4)])
        layer.place(V, onSteps: [2], gate: 1)
        #expect(shape(layer) == [[0, 2, 1], [2, 1, 5]])
        #expect(isOrdered(layer))
    }

    @Test func restingEmptiesTheStepsAndEndsANoteSoundingIntoThem() {
        var layer = Layer(notes: [note(I, step: 0, steps: 3), note(IV, step: 3), note(V, step: 4)])
        layer.rest(onSteps: [2, 3])
        #expect(shape(layer) == [[0, 2, 1], [4, 1, 5]])
    }

    /// A note held across more steps than are rested keeps the others.
    @Test func restingTheMiddleOfALongNoteLeavesItsEnds() {
        var layer = Layer(notes: [note(I, step: 0, steps: 4)])
        layer.rest(onSteps: [1])
        #expect(shape(layer) == [[0, 1, 1], [2, 2, 1]])
    }

    // MARK: – Notes off the grid

    /// A chord played a little early or late is on the step it was meant
    /// for: the one whose line its start is nearest.
    @Test func aNoteBelongsToTheStepItsStartIsNearest() {
        let early = TimelineNote(start: 110, length: 100, chord: I)       // just before step 1
        let late = TimelineNote(start: 130, length: 200, chord: I)        // just after it
        #expect(early.step == 1 && late.step == 1)
        #expect(early.steps == 1..<2)
        #expect(late.steps == 1..<3)                                      // ends at 330, nearest line 360
        #expect(!late.isOnGrid)

        let layer = Layer(notes: [early])
        #expect(layer.note(on: 1) == early)
        #expect(layer.note(on: 0) == nil)
        #expect(layer.indicesOfNotes(on: [0]).isEmpty)
    }

    /// A long note is on every step it is drawn across, so any of them selects it.
    @Test func aLongNoteIsOnEveryStepItIsHeldAcross() {
        let layer = Layer(notes: [note(I, step: 2, steps: 3), note(IV, step: 6)])
        #expect(layer.indicesOfNotes(on: [4]) == [0])
        #expect(layer.indicesOfNotes(on: [5]).isEmpty)
        #expect(layer.indicesOfNotes(on: [3, 6]) == [0, 1])
    }

    @Test func aChordEnteredOnAStepIsOnThatStepHoweverCrisp() {
        var layer = Layer()
        layer.place(I, onSteps: [3], gate: 0.1)
        #expect(layer.notes[0].steps == 3..<4)
        #expect(layer.notes[0].heldSteps == 1)
        #expect(layer.notes[0].gate == 0.1)
    }

    /// Placing on a step replaces the note that is its, even one that
    /// starts a little before the step's line, and leaves the next step's
    /// note alone though it starts inside this step.
    @Test func placingOnAStepLeavesTheNeighboursPlayedEarly() {
        var layer = Layer(notes: [TimelineNote(start: 110, length: 60, chord: I),      // step 1's, early
                                  TimelineNote(start: 200, length: 100, chord: IV)])   // step 2's, early
        layer.place(V, onSteps: [1], gate: 1)
        #expect(layer.notes.map(\.chord) == [V, IV])
        #expect(layer.notes[0].start == 120 && layer.notes[0].end == 200)
        #expect(isOrdered(layer))
    }

    @Test func restingRemovesANotePlayedOffTheGrid() {
        var layer = Layer(notes: [TimelineNote(start: 110, length: 100, chord: I)])
        layer.rest(onSteps: [0])
        #expect(layer.notes.count == 1)
        layer.rest(onSteps: [1])
        #expect(layer.notes.isEmpty)
    }

    // MARK: – Joining and splitting

    @Test func joiningMakesARunOfStepsOneLongNote() {
        var layer = Layer()
        layer.place(I, onSteps: [0, 1, 2, 3])
        layer.join(steps: [0, 1, 2])
        #expect(layer.notes.count == 2)
        #expect(layer.notes[0].start == 0 && layer.notes[0].length == 3 * Self.step)
        #expect(layer.notes[1].start == 3 * Self.step)
    }

    /// Each run is joined on its own, and takes the chord of its first note.
    @Test func separateRunsAreJoinedSeparately() {
        var layer = Layer(notes: [note(I, step: 0), note(IV, step: 1), note(V, step: 4), note(I, step: 5)])
        layer.join(steps: [0, 1, 4, 5])
        #expect(shape(layer) == [[0, 2, 1], [4, 2, 5]])
    }

    @Test func joiningStepsThatStartWithARestHoldsTheFirstNoteToTheEnd() {
        var layer = Layer(notes: [note(IV, step: 1)])
        layer.join(steps: [0, 1, 2, 3])
        #expect(shape(layer) == [[1, 3, 4]])
        layer.join(steps: [8, 9])                       // nothing there: nothing happens
        #expect(shape(layer) == [[1, 3, 4]])
    }

    @Test func splittingCutsALongNoteAtTheSelectedStepLines() {
        var layer = Layer(notes: [note(I, step: 0, steps: 4)])
        layer.split(steps: [1])
        #expect(shape(layer) == [[0, 1, 1], [1, 1, 1], [2, 2, 1]])
        layer.split(steps: [2, 3])
        #expect(shape(layer) == [[0, 1, 1], [1, 1, 1], [2, 1, 1], [3, 1, 1]])
        #expect(isOrdered(layer))
    }

    /// A note that only just sounds into the next step is not drawn on it,
    /// and is not cut there: the cut would leave a sliver.
    @Test func splittingLeavesANoteThatIsOnOneStepWhole() {
        let whole = Layer(notes: [TimelineNote(start: 0, length: 150, chord: I)])
        var layer = whole
        layer.split(steps: [0, 1])
        #expect(layer == whole)
    }

    /// A slide played across a cut carries on in the second note.
    @Test func splittingKeepsASlideOnBothSidesOfTheCut() {
        var bright = NoteEffects()
        bright.reverb.mix = 0.9
        var brighter = bright
        brighter.reverb.mix = 1
        var held = note(I, step: 0, steps: 4)
        held.changes = [SoundChange(offset: 60, effects: bright), SoundChange(offset: 300, effects: brighter)]
        var layer = Layer(notes: [held])
        layer.split(steps: [2])                                           // cuts at 240 and 360
        #expect(layer.notes.map(\.start) == [0, 240, 360])
        #expect(layer.notes[0].changes == [SoundChange(offset: 60, effects: bright)])
        #expect(layer.notes[1].playing.effects == bright)
        #expect(layer.notes[1].changes == [SoundChange(offset: 60, effects: brighter)])
        #expect(layer.notes[2].playing.effects == brighter)
        #expect(layer.notes[2].changes.isEmpty)
    }

    /// Joining inside a note already held past the selection does not shorten it.
    @Test func joiningNeverShortensANote() {
        var layer = Layer(notes: [note(I, step: 0, steps: 4)])
        layer.join(steps: [0, 1])
        #expect(shape(layer) == [[0, 4, 1]])
    }

    /// A long note reaching into the run is the one held on.
    @Test func joiningHoldsANoteThatReachesIntoTheRun() {
        var layer = Layer(notes: [note(I, step: 0, steps: 3), note(IV, step: 3), note(V, step: 5)])
        layer.join(steps: [2, 3, 4])
        #expect(shape(layer) == [[0, 5, 1], [5, 1, 5]])
        #expect(isOrdered(layer))
    }

    @Test func splittingThenJoiningGivesBackTheNote() {
        let whole = Layer(notes: [note(I, step: 0, steps: 4)])
        var layer = whole
        layer.split(steps: [1, 2, 3])
        layer.join(steps: [0, 1, 2, 3])
        #expect(layer.notes == whole.notes)
    }

    // MARK: – Length

    @Test func aNoteIsLengthenedUpToTheNextNoteAndNoFurther() {
        var layer = Layer(notes: [note(I, step: 0), note(IV, step: 3)])
        layer.lengthen(notesOn: [0], by: Self.step, limit: 1920)
        #expect(layer.notes[0].length == 2 * Self.step)
        layer.lengthen(notesOn: [0], by: 10 * Self.step, limit: 1920)
        #expect(layer.notes[0].length == 3 * Self.step)
        #expect(isOrdered(layer))
    }

    @Test func theLastNoteStopsAtTheEndOfTheTimeline() {
        var layer = Layer(notes: [note(I, step: 14)])
        layer.lengthen(notesOn: [14], by: 100 * Self.step, limit: 1920)
        #expect(layer.notes[0].end == 1920)
    }

    @Test func aNoteKeepsAtLeastATick() {
        var layer = Layer(notes: [note(I, step: 0)])
        layer.lengthen(notesOn: [0], by: -10_000, limit: 1920)
        #expect(layer.notes[0].length == 1)
    }

    /// The gate is how much of its last step a note sounds for; setting it
    /// keeps the steps the note is held across.
    @Test func theGateChangesOnlyTheLastStepOfANote() {
        var layer = Layer(notes: [note(I, step: 0, steps: 3), note(IV, step: 4)])
        layer.hold(notesOn: [1, 4], forGate: 0.5, limit: 1920)
        #expect(layer.notes.map(\.length) == [300, 60])
        #expect(layer.notes.map(\.heldSteps) == [3, 1])
        #expect(layer.notes.map(\.gate) == [0.5, 0.5])
        layer.hold(notesOn: [0], forGate: 1, limit: 1920)
        #expect(layer.notes[0].length == 360 && layer.notes[0].gate == 1)
    }

    // MARK: – Snapping

    /// A loop played a little early and late lands on the grid.
    @Test func snappingMovesStartsAndEndsToTheNearestStepLines() {
        var layer = Layer(notes: [
            TimelineNote(start: 10, length: 220, chord: I),          // 10...230 → 0...240
            TimelineNote(start: 470, length: 130, chord: IV),        // 470...600 → 480...600
        ])
        layer.snap(notesOn: [0, 4], limit: 1920)
        #expect(layer.notes.map(\.start) == [0, 480])
        #expect(layer.notes.map(\.length) == [240, 120])
        #expect(layer.notes.allSatisfy { $0.isOnGrid })
    }

    @Test func aVeryShortNoteSnapsToAWholeStep() {
        var layer = Layer(notes: [TimelineNote(start: 125, length: 5, chord: I)])
        layer.snap(notesOn: [1], limit: 1920)
        #expect(layer.notes[0].start == 120 && layer.notes[0].length == 120)
    }

    @Test func snappingKeepsNotesInOrderAndInsideTheTimeline() {
        var layer = Layer(notes: [
            TimelineNote(start: 100, length: 30, chord: I),
            TimelineNote(start: 135, length: 60, chord: IV),          // both nearest to step line 120
            TimelineNote(start: 1900, length: 15, chord: V),          // nearest line is the very end
        ])
        layer.snap(notesOn: [1, 16], limit: 1920)
        #expect(isOrdered(layer))
        #expect(layer.notes.allSatisfy { $0.end <= 1920 })
        #expect(layer.notes.map(\.chord) == [IV, V])
    }

    @Test func notesThatAreNotSelectedAreNotSnapped() {
        var layer = Layer(notes: [TimelineNote(start: 10, length: 100, chord: I),
                                  TimelineNote(start: 490, length: 100, chord: IV)])
        layer.snap(notesOn: [0], limit: 1920)
        #expect(layer.notes.map(\.start) == [0, 490])
    }

    // MARK: – A note's own settings

    @Test func aNotesOwnKeyIsSetWithoutMovingOrChangingItsChord() {
        var layer = Layer(notes: [note(I, step: 0), note(IV, step: 1)])
        let key = Key(root: .D, scale: .major)
        layer.edit(notesOn: [1]) {
            $0.playing.key = key
            $0.start = 999                               // not this edit's to change
        }
        #expect(layer.notes[0].playing.key == nil)
        #expect(layer.notes[1].playing.key == key)
        #expect(layer.notes[1].playing.hasOwn)
        #expect(layer.notes[1].start == Self.step && layer.notes[1].chord == IV)
    }

    // MARK: – Bars

    @Test func removingABarMovesLaterNotesUp() {
        var timeline = Timeline(barCount: 3)
        timeline.layers[0].notes = [note(I, step: 0), note(IV, step: 16), note(V, step: 32)]
        timeline.removeBar(1)
        #expect(timeline.barCount == 2)
        #expect(shape(timeline.layers[0]) == [[0, 1, 1], [16, 1, 5]])
    }

    @Test func aNoteHeldIntoARemovedBarEndsWhereTheBarBegan() {
        var timeline = Timeline(barCount: 2)
        timeline.layers[0].notes = [note(I, step: 14, steps: 6)]
        timeline.removeBar(1)
        #expect(shape(timeline.layers[0]) == [[14, 2, 1]])
    }

    @Test func theLastBarStays() {
        var timeline = Timeline()
        timeline.removeBar(0)
        #expect(timeline.barCount == 1)
    }

    @Test func aLoopMovesWithItsBarsAndGoesWithABarItLayInside() {
        var timeline = Timeline(barCount: 3)
        timeline.setLoop(steps: Set(32..<40))
        timeline.removeBar(0)
        #expect(timeline.loop == 16 * Self.step ..< 24 * Self.step)
        timeline.removeBar(1)
        #expect(timeline.loop == nil)
    }

    /// What cuts the silence off a loop that was closed late.
    @Test func trimmingDropsTheEmptyBarsAtTheEnd() {
        var timeline = Timeline(barCount: 4)
        timeline.layers[0].notes = [note(I, step: 0), note(IV, step: 17)]
        timeline.trimEmptyBars()
        #expect(timeline.barCount == 2)

        var empty = Timeline(barCount: 4)
        empty.trimEmptyBars()
        #expect(empty.barCount == 1)
    }

    @Test func doublingAndHalvingReadTheSameNotesAsMoreOrFewerBars() {
        var timeline = Timeline(barCount: 1)
        timeline.layers[0].notes = [note(I, step: 0, steps: 2), note(IV, step: 8, steps: 4)]
        let original = timeline

        timeline.doubleBars()
        #expect(timeline.barCount == 2)
        #expect(shape(timeline.layers[0]) == [[0, 4, 1], [16, 8, 4]])

        timeline.halveBars()
        #expect(timeline == original)
        #expect(!timeline.canHalveBars)
        timeline.halveBars()
        #expect(timeline == original)
    }

    /// Nothing moves in time, and nothing is lost off the end.
    @Test func changingTheSignatureKeepsEveryNoteWhereItIs() {
        var timeline = Timeline(barCount: 2)                     // 32 steps of 4/4
        timeline.layers[0].notes = [note(I, step: 0), note(V, step: 30)]
        timeline.setSignature(TimeSignature(beats: 3, unit: .quarter))
        #expect(timeline.barCount == 3)                          // 36 steps hold all 32
        #expect(shape(timeline.layers[0]) == [[0, 1, 1], [30, 1, 5]])
    }

    // MARK: – A layer's effects

    /// An edit changes every note of the layer, and every point of a slide
    /// recorded in one, and leaves what it does not name as it was played.
    @Test func editingALayersEffectsChangesEveryNoteAndKeepsTheRest() {
        var dark = NoteEffects()
        dark.filter = FilterSettings(isOn: true, brightness: 0.2)
        var bright = dark
        bright.filter.brightness = 0.8
        var slid = note(I, step: 0, steps: 4)
        slid.playing.effects = dark
        slid.changes = [SoundChange(offset: 240, effects: bright)]
        var layer = Layer(notes: [slid, note(V, step: 4)])
        #expect(layer.effects == dark)

        var live = NoteEffects()
        live.chorus.isOn = true
        layer.editEffects(following: live) { $0.reverb = ReverbSettings(isOn: true, mix: 0.7) }

        #expect(layer.notes.allSatisfy { $0.playing.effects?.reverb == ReverbSettings(isOn: true, mix: 0.7) })
        #expect(layer.notes[0].playing.effects?.filter.brightness == 0.2)
        #expect(layer.notes[0].changes.map(\.effects.filter.brightness) == [0.8])
        #expect(layer.notes[0].changes.allSatisfy { $0.effects.reverb.isOn })
        // A note that followed the keys' effects starts from them, and is its own now.
        #expect(layer.notes[1].playing.effects?.chorus.isOn == true)
        #expect(layer.notes[0].playing.effects?.chorus.isOn == false)
    }

    // MARK: – Loop and layers

    @Test func theLoopIsOneStretchFromTheFirstSelectedStepToTheLast() {
        var timeline = Timeline(barCount: 2)
        timeline.setLoop(steps: [4, 9, 6])
        #expect(timeline.playedRange == 4 * Self.step ..< 10 * Self.step)
        timeline.setLoop(steps: [])
        #expect(timeline.playedRange == 0..<timeline.length)
    }

    @Test func aTimelineAlwaysHasALayer() {
        var timeline = Timeline()
        let second = timeline.addLayer()
        timeline.edit(layer: second) { $0.place(I, onSteps: [0]) }
        let copy = timeline.duplicateLayer(second)
        #expect(timeline.layers.count == 3)
        #expect(timeline.layer(copy!)?.notes == timeline.layer(second)?.notes)
        #expect(copy != second)

        for layer in timeline.layers { timeline.removeLayer(layer.id) }
        #expect(timeline.layers.count == 1)
        #expect(timeline.isEmpty)
    }
}
