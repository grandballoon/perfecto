import Foundation
import Testing
@testable import ScorePractice

/// Eight right-hand steps a second apart from C5 up, and two left-hand
/// chords of four seconds.
let scale = Score(
    title: "Scale",
    notes: [72, 74, 76, 77, 79, 81, 83, 84].enumerated().map {
        ScoreNote(pitch: $1, onset: Double($0), duration: 1, hand: .right)
    } + [
        ScoreNote(pitch: 48, onset: 0, duration: 4, hand: .left),
        ScoreNote(pitch: 55, onset: 0, duration: 4, hand: .left),
        ScoreNote(pitch: 53, onset: 4, duration: 4, hand: .left),
    ])

@Suite("Practice")
struct PracticeTests {

    @Test func theStepsOfBothHandsAreBothHandsNotesStruckTogether() {
        #expect(scale.steps(.right).count == 8)
        #expect(scale.steps(.left).map(\.onset) == [0, 4])
        #expect(scale.steps(.both).map(\.onset) == [0, 1, 2, 3, 4, 5, 6, 7])
        #expect(scale.steps(.both)[4].notes.map(\.pitch) == [53, 79])
        #expect(scale.hands == [.right, .left, .both])
        let rightOnly = Score(title: "", notes: [ScoreNote(pitch: 60, onset: 0, duration: 1, hand: .right)])
        #expect(rightOnly.hands == [.right])
    }

    @Test func aRunIsAnyStretchOfAnyHandsAndBeginsAndEndsOnAnyStep() {
        let (practice, id) = Practice().adding(Passage(.left, from: 1, to: 1))
        #expect(practice.run(id)?.passage.span(in: scale) == 4...8)
        #expect(Passage(.right, from: 5, to: 2) == Passage(.right, from: 2, to: 5))
        #expect(Passage(.right, from: 2, to: 5).span(in: scale) == 2...6)
        #expect(Passage(.both, from: 3, to: 4).steps(in: scale).flatMap(\.notes).map(\.pitch) == [77, 53, 79])
        #expect(Passage.whole(.left, in: scale) == Passage(.left, from: 0, to: 1))
    }

    @Test func runsOverlapAndEachIsLeftAsItIsByTheOthers() {
        var practice = Practice()
        let a: RunID, b: RunID, c: RunID
        (practice, a) = practice.adding(Passage(.right, from: 0, to: 5))
        (practice, b) = practice.adding(Passage(.right, from: 2, to: 3))
        (practice, c) = practice.adding(Passage(.both, from: 4, to: 7))
        #expect(Set([a, b, c]).count == 3)
        let without = practice.removing(a)
        #expect(without.run(b) == practice.run(b))
        #expect(without.run(c) == practice.run(c))
        #expect(without.run(a) == nil)
        // A passage that is a run already is that run.
        let (again, same) = practice.adding(Passage(.right, from: 2, to: 3))
        #expect(again == practice)
        #expect(same == b)
    }

    @Test func aRemovedRunsIdIsNeverGivenAgain() {
        let (one, a) = Practice().adding(Passage(.right, from: 0, to: 1))
        let (_, b) = one.removing(a).adding(Passage(.right, from: 2, to: 3))
        #expect(a != b)
    }

    @Test func theRunsOfAHandAreInTheOrderOfTheScore() {
        var practice = Practice()
        for passage in [Passage(.right, from: 4, to: 5), Passage(.left, from: 0, to: 1),
                        Passage(.right, from: 0, to: 1), Passage(.right, from: 0, to: 6)] {
            practice = practice.adding(passage).0
        }
        #expect(practice.runs(of: .right, in: scale).map(\.passage.steps) == [0...6, 0...1, 4...5])
        #expect(practice.runs(of: .left, in: scale).count == 1)
        #expect(practice.runs(of: .both, in: scale).isEmpty)
    }

    @Test func aRunIsNamedAndSpacesAloneTakeTheNameAway() {
        let (practice, id) = Practice().adding(Passage(.right, from: 0, to: 3))
        let named = practice.naming(id, "  the climb ")
        #expect(named.run(id)?.name == "the climb")
        #expect(named.naming(id, "   ").run(id)?.name == nil)
        #expect(named.run(id)?.passage == practice.run(id)?.passage)
    }

    /// A new run of the right hand being made, from step `first` to `last`.
    private func draft(_ first: Int, _ last: Int) -> RunDraft {
        RunDraft(Passage(.right, from: first, to: last), room: 0...7)
    }

    @Test func aRunIsMovedAlongThePartKeepingItsLength() {
        let run = draft(1, 3)
        #expect(run.moved(toStartAt: 4.4, in: scale).passage == Passage(.right, from: 4, to: 6))
        #expect(run.moved(toStartAt: -2, in: scale).passage == Passage(.right, from: 0, to: 2))
        // Never past the part's end.
        #expect(run.moved(toStartAt: 7.5, in: scale).passage == Passage(.right, from: 5, to: 7))
        let left = RunDraft(Passage(.left, from: 0, to: 0), room: 0...1)
        #expect(left.moved(toStartAt: 5, in: scale).passage == Passage(.left, from: 1, to: 1))
    }

    @Test func aRunTakesInOneMoreNoteAtATimeAtEitherEnd() {
        let run = draft(2, 3)
        #expect(run.extendingStart().passage == Passage(.right, from: 1, to: 3))
        #expect(run.extendingEnd().passage == Passage(.right, from: 2, to: 4))
        let whole = draft(0, 7)
        #expect(!whole.canExtendStart && !whole.canExtendEnd)
        #expect(whole.extendingStart() == whole)
        #expect(whole.extendingEnd() == whole)
    }

    @Test func aRunGivesUpOneNoteAtATimeAtEitherEndButNeverItsLast() {
        let run = draft(2, 4)
        #expect(run.shrinkingStart().passage == Passage(.right, from: 3, to: 4))
        #expect(run.shrinkingEnd().passage == Passage(.right, from: 2, to: 3))
        let one = draft(5, 5)
        #expect(!one.canShrinkStart && !one.canShrinkEnd)
        #expect(one.shrinkingStart() == one)
        #expect(one.shrinkingEnd() == one)
    }

    @Test func aNewRunIsTheNoteAtThePlayhead() {
        #expect(Practice().newRun(.right, at: 2.5, in: scale) == RunDraft(Passage(.right, from: 2, to: 2), room: 0...7))
        #expect(Practice().newRun(.left, at: 0, in: Score(title: "", notes: [])) == nil)
        #expect(Passage.step(.right, at: 2.5, in: scale) == Passage(.right, from: 2, to: 2))
        #expect(Passage.step(.left, at: 3.9, in: scale) == Passage(.left, from: 0, to: 0))
        #expect(Passage.step(.both, at: 7, in: scale) == Passage(.both, from: 7, to: 7))
        #expect(Passage.step(.left, at: 0, in: Score(title: "", notes: [])) == nil)
    }

    @Test func aRunIsReplacedKeepingItsIdAndName() {
        let (practice, id) = Practice().adding(Passage(.right, from: 0, to: 1), name: "start")
        let (both, other) = practice.adding(Passage(.left, from: 0, to: 1))
        let moved = both.replacing(id, with: Passage(.right, from: 4, to: 6))
        #expect(moved.run(id) == PracticeRun(id: id, passage: Passage(.right, from: 4, to: 6), name: "start"))
        #expect(moved.run(other) == both.run(other))
    }

    @Test func aDraftKeptIsANewRunOrTheRunEdited() {
        let (practice, id) = Practice().keeping(draft(2, 4))
        #expect(practice.run(id)?.passage == Passage(.right, from: 2, to: 4))
        let edit = try! #require(practice.editing(id, in: scale))
        #expect(edit.room == 0...7)
        let (edited, same) = practice.keeping(edit.moved(toStartAt: 5, in: scale))
        #expect(same == id)
        #expect(edited.runs.map(\.passage) == [Passage(.right, from: 5, to: 7)])
    }

    @Test func aRunGoesByItsBars() {
        let score = Score(title: "", notes: scale.notes, barlines: [0, 2, 4, 6, 8])
        #expect(score.bars(of: Passage(.right, from: 0, to: 1).span(in: score)) == "Bar 1")
        #expect(score.bars(of: Passage(.right, from: 1, to: 4).span(in: score)) == "Bars 1–3")
        #expect(score.bars(of: Passage(.right, from: 6, to: 7).span(in: score)) == "Bar 4")
    }

    @Test func runsThatOverlapAreDrawnInLanesApart() {
        #expect(Practice.lanes(of: [0...4, 2...3, 4...6, 3...8, 7...9]) == [0, 1, 0, 1, 0])
        #expect(Practice.lanes(of: [0...4, 1...5, 2...6]) == [0, 1, 2])
        #expect(Practice.lanes(of: []) == [])
    }

    @Test func practiceIsSavedAndReadAsItIs() throws {
        let practice = Practice().adding(Passage(.both, from: 1, to: 3), name: "both").0
            .adding(Passage(.left, from: 0, to: 0)).0
        let data = try JSONEncoder().encode(practice)
        let read = try JSONDecoder().decode(Practice.self, from: data)
        #expect(read == practice)
        #expect(read.adding(Passage(.right, from: 0, to: 0)).1 == RunID(rawValue: 3))
    }
}

@Suite("Sub-runs")
struct SubRunTests {

    /// A run of the right hand's steps 1 to 6, with a sub-run of 2 to 3.
    private func nested() -> (Practice, parent: RunID, child: RunID) {
        let (one, parent) = Practice().adding(Passage(.right, from: 1, to: 6))
        let (two, child) = one.adding(Passage(.right, from: 2, to: 3), under: parent)
        return (two, parent, child)
    }

    @Test func aSubRunIsARunOfItsOwnLeavingItsParentWhole() {
        let (practice, parent, child) = nested()
        #expect(practice.run(parent)?.passage == Passage(.right, from: 1, to: 6))
        #expect(practice.run(child) == PracticeRun(id: child, passage: Passage(.right, from: 2, to: 3), parent: parent))
        #expect(practice.subRuns(of: parent, in: scale).map(\.id) == [child])
        #expect(practice.runs(of: .right, in: scale).count == 2)
    }

    @Test func aSubRunIsKeptWithinItsParentAndOfItsHands() {
        let (practice, parent, _) = nested()
        let (fitted, id) = practice.adding(Passage(.both, from: 0, to: 4), under: parent)
        #expect(fitted.run(id)?.passage == Passage(.right, from: 1, to: 4))
        // The whole parent again is the parent.
        #expect(practice.adding(Passage(.right, from: 1, to: 6), under: parent).1 == parent)
        // The same steps beside it are that sub-run; elsewhere they are a run of their own.
        let (again, same) = practice.adding(Passage(.right, from: 2, to: 3), under: parent)
        #expect(again == practice)
        #expect(same == nested().child)
        let (other, top) = practice.adding(Passage(.right, from: 2, to: 3))
        #expect(top != same)
        #expect(other.run(top)?.parent == nil)
    }

    @Test func runsAreOutlinedEachFollowedByItsSubRuns() {
        var (practice, parent, child) = nested()
        let grandchild: RunID, later: RunID, before: RunID, first: RunID
        (practice, later) = practice.adding(Passage(.right, from: 4, to: 5), under: parent)
        (practice, grandchild) = practice.adding(Passage(.right, from: 3, to: 3), under: child)
        (practice, before) = practice.adding(Passage(.right, from: 0, to: 1))
        (practice, first) = practice.adding(Passage(.left, from: 0, to: 1))
        #expect(practice.outline(of: .right, in: scale).map { [$0.id.rawValue, $0.depth] }
                == [[before.rawValue, 0], [parent.rawValue, 0], [child.rawValue, 1],
                    [grandchild.rawValue, 2], [later.rawValue, 1]])
        #expect(practice.outline(of: .left, in: scale).map(\.id) == [first])
    }

    @Test func aRunGoesWithItsSubRuns() {
        var (practice, parent, child) = nested()
        let grandchild: RunID
        (practice, grandchild) = practice.adding(Passage(.right, from: 3, to: 3), under: child)
        let (beside, other) = practice.adding(Passage(.right, from: 0, to: 7))
        #expect(beside.removing(parent).runs.map(\.id) == [other])
        #expect(practice.removing(child).runs.map(\.id) == [parent])
        #expect(practice.descendants(of: parent) == [child, grandchild])
    }

    @Test func aSubRunIsMadeWithinItsParentFromTheStepNearestThePlayhead() throws {
        let (practice, parent, _) = nested()
        let draft = try #require(practice.newRun(.left, at: 7.5, in: scale, under: parent))
        #expect(draft.passage == Passage(.right, from: 6, to: 6))
        #expect(draft.room == 1...6)
        #expect(!draft.canExtendEnd)
        #expect(draft.moved(toStartAt: 0, in: scale).passage == Passage(.right, from: 1, to: 1))
        let (kept, id) = practice.keeping(draft.extendingStart())
        #expect(kept.run(id) == PracticeRun(id: id, passage: Passage(.right, from: 5, to: 6), parent: parent))
    }

    @Test func aRunCannotGiveUpTheStepsOfItsSubRuns() throws {
        let (practice, parent, _) = nested()
        var edit = try #require(practice.editing(parent, in: scale))
        #expect(edit.keeps == 2...3)
        edit = edit.shrinkingStart().shrinkingStart().shrinkingEnd().shrinkingEnd().shrinkingEnd().shrinkingEnd()
        #expect(edit.passage == Passage(.right, from: 2, to: 3))
        #expect(!edit.canShrinkStart && !edit.canShrinkEnd)
    }

    @Test func aRunMovedTakesItsSubRunsWithIt() throws {
        var (practice, parent, child) = nested()
        let grandchild: RunID
        (practice, grandchild) = practice.adding(Passage(.right, from: 3, to: 3), under: child)
        let edit = try #require(practice.editing(parent, in: scale)).shrinkingEnd().moved(toStartAt: 3, in: scale)
        #expect(edit.passage == Passage(.right, from: 3, to: 7))
        #expect(edit.keeps == 4...5)
        let (moved, _) = practice.keeping(edit.extendingStart())
        #expect(moved.run(parent)?.passage == Passage(.right, from: 2, to: 7))
        #expect(moved.run(child)?.passage == Passage(.right, from: 4, to: 5))
        #expect(moved.run(grandchild)?.passage == Passage(.right, from: 5, to: 5))
    }

    @Test func aSubRunIsEditedWithinItsParent() throws {
        let (practice, parent, child) = nested()
        let edit = try #require(practice.editing(child, in: scale))
        #expect(edit.room == 1...6)
        #expect(edit.moved(toStartAt: 7, in: scale).passage == Passage(.right, from: 5, to: 6))
        let (kept, _) = practice.keeping(edit.extendingStart().extendingStart())
        #expect(kept.run(child)?.passage == Passage(.right, from: 1, to: 3))
        #expect(kept.run(child)?.parent == parent)
    }

    @Test func subRunsAreSavedAndReadAsTheyAre() throws {
        let (practice, _, _) = nested()
        let read = try JSONDecoder().decode(Practice.self, from: try JSONEncoder().encode(practice))
        #expect(read == practice)
        // A sub-run whose parent is gone is read as a run of the score.
        let orphan = #"{"runs":[{"id":2,"passage":{"hands":"right","first":0,"last":1},"parent":9}],"nextID":3}"#
        let lone = try JSONDecoder().decode(Practice.self, from: Data(orphan.utf8))
        #expect(lone.runs.map(\.parent) == [nil])
    }
}

@Suite("Practice kept as it once was")
struct OldPracticeTests {

    @Test func aTreeOfCutsIsReadAsItsRunsEachItsOwn() throws {
        let old = #"""
        {"right":{"id":1,"first":0,"last":7,"children":[
            {"id":3,"first":0,"last":3,"name":"climb","children":[
                {"id":5,"first":0,"last":1,"children":[]},{"id":6,"first":2,"last":3,"children":[]}]},
            {"id":4,"first":4,"last":7,"children":[]}]},
         "left":{"id":2,"first":0,"last":1,"children":[]},"nextID":7}
        """#
        let practice = try JSONDecoder().decode(Practice.self, from: Data(old.utf8))
        // Each hand's whole part is the whole piece, not a run.
        #expect(practice.runs.map(\.id.rawValue) == [3, 5, 6, 4])
        #expect(practice.runs.map(\.passage) == [Passage(.right, from: 0, to: 3), Passage(.right, from: 0, to: 1),
                                                  Passage(.right, from: 2, to: 3), Passage(.right, from: 4, to: 7)])
        #expect(practice.runs.map(\.name) == ["climb", nil, nil, nil])
        #expect(practice.adding(Passage(.left, from: 0, to: 0)).1 == RunID(rawValue: 7))
    }

    @Test func aPracticeSavedWithARecordingsMatchIsReadAsItsRuns() throws {
        let old = #"{"right":{"id":1,"first":0,"last":3,"children":[{"id":2,"first":0,"last":1,"children":[]},{"id":3,"first":2,"last":3,"children":[]}]},"anchors":[{"score":0,"recording":47}],"matched":[],"unsure":[3.5],"nudges":[47.2],"nextID":4}"#
        let practice = try JSONDecoder().decode(Practice.self, from: Data(old.utf8))
        #expect(practice.runs.map(\.passage.steps) == [0...1, 2...3])
    }
}

@Suite("Undo")
struct HistoryTests {

    @Test func aChangeIsUndoneAndRedone() {
        let history = History(1).doing(2).doing(3)
        #expect(history.present == 3)
        #expect(history.undoing().present == 2)
        #expect(history.undoing().undoing().present == 1)
        #expect(!history.undoing().undoing().canUndo)
        #expect(history.undoing().undoing().undoing().present == 1)
        #expect(history.undoing().redoing().present == 3)
        #expect(!history.canRedo)
    }

    @Test func aChangeAfterAnUndoLeavesNothingToRedo() {
        let history = History(1).doing(2).undoing().doing(5)
        #expect(history.present == 5)
        #expect(!history.canRedo)
        #expect(history.undoing().present == 1)
    }

    @Test func theSameValueAgainIsNoChange() {
        #expect(!History(1).doing(1).canUndo)
    }
}
