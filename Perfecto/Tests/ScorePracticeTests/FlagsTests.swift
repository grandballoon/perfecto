import Foundation
import Testing
@testable import ScorePractice

@Suite("Flags")
struct FlagsTests {

    @Test func aFlagIsAMomentWithAnOptionalNoteInTheOrderOfTheScore() {
        var flags = ScoreFlags()
        let late: FlagID, early: FlagID
        (flags, late) = flags.adding(at: 5, .right, note: "  the leap ")
        (flags, early) = flags.adding(at: 2, .both)
        #expect(flags.all.map(\.id) == [early, late])
        #expect(flags.flag(late)?.note == "the leap")
        #expect(flags.flag(early)?.note == nil)
        #expect(flags.flag(early)?.hands == .both)
        #expect(flags.adding(at: -1, .left).0.all.first?.time == 0)
    }

    @Test func aFlagOfTheSameHandsAtTheSameMomentIsThatFlag() {
        let (flags, id) = ScoreFlags().adding(at: 3, .right, note: "here")
        let (again, same) = flags.adding(at: 3, .right, note: "other")
        #expect(again == flags)
        #expect(same == id)
        // Another view's flag at that moment is a flag of its own.
        let (both, other) = flags.adding(at: 3, .left)
        #expect(other != id)
        #expect(both.all.count == 2)
    }

    @Test func aFlagsNoteIsChangedOrTakenAwayAndAFlagIsRemoved() {
        let (flags, id) = ScoreFlags().adding(at: 1, .right)
        let noted = flags.noting(id, " watch the thumb ")
        #expect(noted.flag(id)?.note == "watch the thumb")
        #expect(noted.noting(id, "   ").flag(id)?.note == nil)
        #expect(noted.removing(id).all.isEmpty)
        // An id taken away is never given again.
        let (_, next) = noted.removing(id).adding(at: 1, .right)
        #expect(next != id)
    }

    @Test func aFlagMarksTheStepOfAViewStruckAtItsMomentOrLastByThen() {
        let (flags, id) = ScoreFlags().adding(at: 2.5, .right)
        let flag = flags.flag(id)!
        #expect(ScoreFlags.step(flag, .right, in: scale) == 2)
        #expect(ScoreFlags.step(flag, .left, in: scale) == 0)
        // Seen at its step from anywhere in it, and nowhere else.
        #expect(flags.at(2, .right, in: scale) == [flag])
        #expect(flags.at(2.9, .right, in: scale) == [flag])
        #expect(flags.at(3, .right, in: scale).isEmpty)
        #expect(flags.at(3.9, .left, in: scale) == [flag])
        #expect(flags.at(4, .left, in: scale).isEmpty)
    }

    @Test func aRunsEdgesAreOnTheFlagsMarkingItsFirstAndLastSteps() {
        var flags = ScoreFlags()
        (flags, _) = flags.adding(at: 2, .right, note: "start")
        (flags, _) = flags.adding(at: 5.5, .both, note: "end")
        let edges = flags.edges(of: Passage(.right, from: 2, to: 5), in: scale)
        #expect(edges.start.map(\.note) == ["start"])
        #expect(edges.end.map(\.note) == ["end"])
        #expect(flags.edges(of: Passage(.right, from: 1, to: 4), in: scale).isEmpty)
        // A run of one step has the same flags at both edges.
        let one = flags.edges(of: Passage(.right, from: 2, to: 2), in: scale)
        #expect(one.start == one.end)
        // In the left hand both flags mark its steps 0 and 1.
        let left = flags.edges(of: Passage(.left, from: 0, to: 1), in: scale)
        #expect(left.start.map(\.note) == ["start"])
        #expect(left.end.map(\.note) == ["end"])
    }

    @Test func flagsAreKeptWithThePracticeAndReadWhereNoneWereKept() throws {
        var flags = ScoreFlags()
        (flags, _) = flags.adding(at: 1, .right, note: "a")
        let removed: FlagID
        (flags, removed) = flags.adding(at: 2, .left)
        flags = flags.removing(removed)
        let (practice, _) = Practice().with(flags).adding(Passage(.right, from: 0, to: 3))
        let read = try JSONDecoder().decode(Practice.self, from: JSONEncoder().encode(practice))
        #expect(read == practice)
        #expect(read.flags.adding(at: 9, .right).1 != removed)
        let old = try JSONDecoder().decode(Practice.self, from: Data(#"{"runs":[],"nextID":1}"#.utf8))
        #expect(old.flags.all.isEmpty)
    }

    @Test func aStepIsSteppedToFromAnyMomentAndHeardForAsLongAsTheScoreHoldsIt() {
        #expect(scale.step(.right, after: 2) == 3)
        #expect(scale.step(.right, after: 2.5) == 3)
        #expect(scale.step(.right, after: 7) == nil)
        #expect(scale.step(.right, before: 2) == 1)
        #expect(scale.step(.right, before: 2.5) == 2)
        #expect(scale.step(.right, before: 0) == nil)
        #expect(scale.step(.left, after: 0) == 1)
        #expect(scale.steps(.both)[0].sounded == [
            PassNote(pitch: 48, start: 0, end: 4), PassNote(pitch: 55, start: 0, end: 4),
            PassNote(pitch: 72, start: 0, end: 1),
        ])
    }
}
