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

    private let practice = Practice(score: scale)

    private var right: Run { practice.root(.right)! }

    @Test func eachHandIsARunOfAllItsSteps() {
        #expect(right.steps == 0...7)
        #expect(practice.root(.left)!.steps == 0...1)
        #expect(Practice(score: Score(title: "", notes: [ScoreNote(pitch: 60, onset: 0, duration: 1, hand: .right)])).root(.left) == nil)
    }

    @Test func aCutMakesTwoRunsAndMoreCutsMore() {
        let once = practice.cutting(right.id, before: 4)
        #expect(once.root(.right)!.children.map(\.steps) == [0...3, 4...7])
        let twice = once.cutting(right.id, before: 2)
        #expect(twice.root(.right)!.children.map(\.steps) == [0...1, 2...3, 4...7])
        #expect(twice.cuts(of: right.id) == [2, 4])
    }

    @Test func aCutWhereThereIsOneOrAtTheStartChangesNothing() {
        let once = practice.cutting(right.id, before: 4)
        #expect(once.cutting(right.id, before: 4) == once)
        #expect(once.cutting(right.id, before: 0) == once)
        #expect(once.cutting(right.id, before: 8) == once)
    }

    @Test func aRunIsCutIntoRunsOfItsOwn() {
        let halves = practice.cutting(right.id, before: 4)
        let second = halves.root(.right)!.children[1]
        let diced = halves.cutting(second.id, before: 6)
        #expect(diced.find(second.id)!.run.children.map(\.steps) == [4...5, 6...7])
        #expect(diced.path(to: diced.find(second.id)!.run.children[1].id).map(\.steps) == [0...7, 4...7, 6...7])
        // The run above is still cut in two.
        #expect(diced.root(.right)!.children.map(\.steps) == [0...3, 4...7])
    }

    @Test func cuttingARunThatHasRunsCutsThemToo() {
        let halves = practice.cutting(right.id, before: 4)
        let first = halves.root(.right)!.children[0]
        let diced = halves.cutting(first.id, before: 2)
        // A cut of the whole part's through the first half's runs.
        let recut = diced.cutting(right.id, before: 3)
        let children = recut.root(.right)!.children
        #expect(children.map(\.steps) == [0...2, 3...3, 4...7])
        #expect(children[0].children.map(\.steps) == [0...1, 2...2])
        #expect(children[1].isLeaf)
    }

    @Test func joiningUndoesACut() {
        let once = practice.cutting(right.id, before: 4)
        #expect(once.joining(right.id, before: 4).root(.right)!.isLeaf)
        let twice = once.cutting(right.id, before: 2)
        #expect(twice.joining(right.id, before: 2).root(.right)!.children.map(\.steps) == [0...3, 4...7])
    }

    @Test func joinedRunsKeepTheirRuns() {
        let thirds = practice.cutting(right.id, before: 4).cutting(right.id, before: 6)
        let middle = thirds.root(.right)!.children[1]
        let diced = thirds.cutting(middle.id, before: 5)
        let joined = diced.joining(right.id, before: 6)
        let children = joined.root(.right)!.children
        #expect(children.map(\.steps) == [0...3, 4...7])
        #expect(children[1].children.map(\.steps) == [4...4, 5...5, 6...7])
    }

    @Test func runsKeepTheirIdsAndNewOnesAreUnique() {
        let diced = practice.cutting(right.id, before: 4).cutting(right.id, before: 2).cutting(right.id, before: 6)
        let ids = diced.root(.right)!.children.map(\.id) + [right.id, practice.root(.left)!.id]
        #expect(Set(ids).count == ids.count)
    }

    @Test func aRunIsHeardWhereTheScoreHasItUntilItIsMatched() {
        let halves = practice.cutting(right.id, before: 4)
        let second = halves.root(.right)!.children[1]
        #expect(halves.span(of: second.id, in: scale) == 4...8)
    }

    @Test func matchingARunMovesTheRunsInIt() {
        let halves = practice.cutting(right.id, before: 4)
        let second = halves.root(.right)!.children[1]
        let matched = halves
            .settingStart(of: right.id, to: 10, in: scale)
            .settingEnd(of: right.id, to: 26, in: scale)
        // Twice as slow, ten seconds in.
        #expect(matched.span(of: second.id, in: scale) == 18...26)
        // The left hand is heard in the same recording.
        #expect(matched.span(of: matched.root(.left)!.id, in: scale) == 10...26)
    }

    @Test func matchingAnInnerRunKeepsTheOutsideWhereItWas() {
        let halves = practice.cutting(right.id, before: 4)
        let first = halves.root(.right)!.children[0]
        let matched = halves
            .settingStart(of: right.id, to: 0, in: scale)
            .settingEnd(of: right.id, to: 8, in: scale)
            .settingEnd(of: first.id, to: 5, in: scale)
        #expect(matched.span(of: first.id, in: scale) == 0...5)
        #expect(matched.span(of: right.id, in: scale) == 0...8)
    }

    @Test func practiceIsSavedAndReadAsItIs() throws {
        let diced = practice.cutting(right.id, before: 4).settingStart(of: right.id, to: 2, in: scale)
        let data = try JSONEncoder().encode(diced)
        #expect(try JSONDecoder().decode(Practice.self, from: data) == diced)
    }
}

import Foundation

@Suite("Run names")
struct RunNameTests {
    let score = Score(title: "", notes: (0..<8).map {
        ScoreNote(pitch: 60 + $0, onset: Double($0), duration: 1, hand: .right)
    })

    @Test func aRunIsNamedAndTheNameKeptThroughCutsAndJoins() throws {
        var practice = Practice(score: score)
        let root = try #require(practice.root(.right))
        practice = practice.cutting(root.id, before: 4)
        let first = practice.root(.right)!.children[0].id
        practice = practice.naming(first, "  the climb ")
        #expect(practice.find(first)?.run.name == "the climb")
        // Cut again inside it: the first part keeps the name.
        practice = practice.cutting(root.id, before: 2)
        #expect(practice.root(.right)!.children.map(\.name) == ["the climb", nil, nil])
        // Joined again: the name stays.
        practice = practice.joining(root.id, before: 2)
        #expect(practice.root(.right)!.children.map(\.name) == ["the climb", nil])
        // Spaces alone take it away.
        #expect(practice.naming(first, "   ").find(first)?.run.name == nil)
    }

    @Test func theOutlineIsEveryRunInOrderWithItsDepth() {
        var practice = Practice(score: score)
        let root = practice.root(.right)!
        practice = practice.cutting(root.id, before: 4)
        let second = practice.root(.right)!.children[1].id
        practice = practice.cutting(second, before: 6)
        let outline = practice.outline(.right)
        #expect(outline.map(\.depth) == [0, 1, 1, 2, 2])
        #expect(outline.map(\.run.steps) == [0...7, 0...3, 4...7, 4...5, 6...7])
        #expect(practice.outline(.left).isEmpty)
    }

    @Test func aPracticeSavedBeforeNamesIsReadWithNone() throws {
        let practice = Practice(score: score).naming(Practice(score: score).root(.right)!.id, "all")
        let again = try JSONDecoder().decode(Practice.self, from: JSONEncoder().encode(practice))
        #expect(again.root(.right)?.name == "all")
        let old = #"{"right":{"id":1,"first":0,"last":3,"children":[]},"anchors":[],"nextID":2}"#
        #expect(try JSONDecoder().decode(Practice.self, from: Data(old.utf8)).root(.right)?.name == nil)
    }
}
