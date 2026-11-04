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

    @Test func aRunKeptStaysWhereItIsWhileARunInsideItIsMatched() {
        let halves = practice.cutting(right.id, before: 4)
        let first = halves.root(.right)!.children[0]
        let shifted = halves.settingStart(of: right.id, to: 2, in: scale)
        let kept = shifted.keeping(right.id, in: scale)
        #expect(kept.span(of: right.id, in: scale) == 2...10)
        #expect(kept.settingEnd(of: first.id, to: 4, in: scale).span(of: right.id, in: scale) == 2...10)
        // Without it, one anchor only moves the whole part.
        #expect(halves.settingEnd(of: first.id, to: 6, in: scale).span(of: right.id, in: scale) == 2...10)
        #expect(kept.keeping(right.id, in: scale) == kept)
    }

    @Test func practiceIsSavedAndReadAsItIs() throws {
        let diced = practice.cutting(right.id, before: 4).settingStart(of: right.id, to: 2, in: scale)
        let data = try JSONEncoder().encode(diced)
        #expect(try JSONDecoder().decode(Practice.self, from: data) == diced)
    }
}

import Foundation
