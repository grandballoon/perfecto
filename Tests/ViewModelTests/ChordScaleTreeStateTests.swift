import Testing
@testable import Perfecto

@Suite("ChordScaleTreeState")
@MainActor
struct ChordScaleTreeStateTests {

    // MARK: – Helpers

    /// A performance in C major with the tree on screen, sounding through
    /// a player of its own on one note sink.
    @MainActor
    private struct Rig {
        let notes: RecordingNoteSink
        let state: PerformanceState

        init() {
            let (clock, notes) = (ManualClock(), RecordingNoteSink())
            self.notes = notes
            state = PerformanceState(sink: RecordingSink(), treeSink: NotePlayer([notes], clock: clock),
                                     clock: clock)
            state.show(.tree)
        }

        var tree: ChordScaleTreeState { state.tree }

        /// The chord labelled `label` that the tree can go to from the tier it is at.
        func next(_ label: String) -> TreeSpot {
            tree.spots(on: tree.tier).next.joined().first { $0.chord.label == label }!
        }

        /// The chord the tier the tree is at grows from.
        var here: TreeSpot { tree.spots(on: tree.tier).here }

        /// Presses and lets go of each of `labels` in turn, from where the tree is.
        func walk(_ labels: [String]) {
            for label in labels {
                let spot = next(label)
                tree.press(spot)
                tree.release(spot)
            }
        }
    }

    // MARK: – Where it is

    @Test func theTreeComesOnAtTheTonicChordOfTheKeysKey() {
        let rig = Rig()
        #expect(rig.tree.position.label == "C")
        rig.state.show(.play)
        rig.state.key = Key(root: .D, scale: .dorian)
        rig.state.show(.tree)
        #expect(rig.tree.position.label == "Dm")
    }

    @Test func aChordPressedSoundsWhileHeldAndOpensATierOnFromIt() {
        let rig = Rig()
        let am = rig.next("Am")
        rig.tree.press(am)
        #expect(rig.notes.sounding == [57, 60, 64])
        #expect(rig.tree.tiers.map(\.label) == ["C", "Am"])
        #expect(rig.tree.tier == 1)
        rig.tree.release(am)
        #expect(rig.notes.sounding.isEmpty)
        // The tree stays where it went, and grows on from there.
        #expect(rig.tree.position == am.chord)
        #expect(rig.tree.position.next.joined().contains { $0.chord.label == "Dm" })
    }

    @Test func pressingTheChordATierGrowsFromSoundsItWithoutGoingAnywhere() {
        let rig = Rig()
        rig.tree.press(rig.here)
        #expect(rig.notes.sounding == [48, 52, 55])
        #expect(rig.tree.tiers.count == 1)
    }

    @Test func liftingTheChordSoundingHandsTheSoundBackToTheOneBeneath() {
        let rig = Rig()
        let f = rig.next("F")
        rig.tree.press(f)
        let g = rig.next("G")
        rig.tree.press(g)
        #expect(rig.notes.sounding == [55, 59, 62])
        rig.tree.release(g)
        #expect(rig.notes.sounding == [53, 57, 60])
        #expect(rig.tree.position == g.chord)
        rig.tree.release(f)
        #expect(rig.notes.sounding.isEmpty)
    }

    @Test func liftingAChordHeldBeneathLeavesTheOneSounding() {
        let rig = Rig()
        let (f, g) = (rig.next("F"), rig.next("G"))
        rig.tree.press(f)
        rig.tree.press(g)
        rig.tree.release(f)
        #expect(rig.notes.sounding == [55, 59, 62])
    }

    // MARK: – The tiers

    @Test func movingBetweenTiersKeepsThemAll() {
        let rig = Rig()
        rig.walk(["Am", "Dm", "G"])
        #expect(rig.tree.tiers.map(\.label) == ["C", "Am", "Dm", "G"])
        rig.tree.show(tier: 1)
        #expect(rig.tree.position.label == "Am")
        #expect(rig.tree.tiers.map(\.label) == ["C", "Am", "Dm", "G"])
        #expect(rig.tree.opened(on: 1)?.label == "Dm")
        rig.tree.show(tier: 3)
        #expect(rig.tree.position.label == "G")
    }

    @Test func pressingTheChordTheNextTierGrowsFromKeepsTheWayOn() {
        let rig = Rig()
        rig.walk(["Am", "Dm", "G"])
        rig.tree.show(tier: 0)
        rig.walk(["Am"])
        #expect(rig.tree.tier == 1)
        #expect(rig.tree.tiers.map(\.label) == ["C", "Am", "Dm", "G"])
    }

    @Test func pressingAnotherChordOnATierTakesANewWayOnFromIt() {
        let rig = Rig()
        rig.walk(["Am", "Dm", "G"])
        rig.tree.show(tier: 1)
        rig.walk(["F"])
        #expect(rig.tree.tier == 2)
        #expect(rig.tree.tiers.map(\.label) == ["C", "Am", "F"])
    }

    @Test func aChordOnAnEarlierTierIsPlayedWhereverTheTreeIs() {
        let rig = Rig()
        rig.walk(["Am", "Dm"])
        let fFromC = rig.tree.spots(on: 0).next.joined().first { $0.chord.label == "F" }!
        rig.tree.press(fFromC)
        #expect(rig.notes.sounding == [53, 57, 60])
        #expect(rig.tree.tiers.map(\.label) == ["C", "F"])
        #expect(rig.tree.tier == 1)
    }

    @Test func aChordFromAWayLetGoOfIsNotPlayed() {
        let rig = Rig()
        rig.walk(["Am"])
        let stale = rig.next("Dm")
        rig.tree.show(tier: 0)
        rig.walk(["F"])
        rig.tree.press(stale)
        #expect(rig.notes.sounding.isEmpty)
    }

    @Test func homeIsTheTonicChordWithNoWayOn() {
        let rig = Rig()
        rig.walk(["Am"])
        rig.tree.goHome()
        #expect(rig.tree.tiers.map(\.label) == ["C"])
        #expect(rig.tree.tier == 0)
    }

    @Test func aChangeOfSizeTakesEveryTierToTheNewSize() {
        let rig = Rig()
        rig.walk(["G"])
        rig.tree.size = .sevenths
        #expect(rig.tree.position.label == "Gmaj7")
        #expect(rig.tree.tiers.map(\.label) == ["Cmaj7", "Gmaj7"])
    }

    // MARK: – Looking

    @Test func whatIsShownIsUnderThePointerElseSoundingElseWhereTheTreeIs() {
        let rig = Rig()
        let (dm, em) = (rig.next("Dm"), rig.next("Em"))
        rig.tree.hover(dm)
        #expect(rig.tree.focus == dm.chord)
        #expect(rig.tree.focusSpot?.step?.numeral == "ii")
        rig.tree.hover(nil)
        #expect(rig.tree.focus.label == "C")
        #expect(rig.tree.focusSpot == nil)
        rig.tree.press(em)
        #expect(rig.tree.focus == em.chord)
        #expect(rig.notes.started.count == 3)
    }

    // MARK: – Off screen

    @Test func offScreenTheTreeIsSilentAndLeavingItEndsWhatSounds() {
        let rig = Rig()
        rig.tree.press(rig.next("Am"))
        rig.state.show(.play)
        #expect(rig.notes.sounding.isEmpty)
        rig.tree.press(rig.here)
        #expect(rig.notes.sounding.isEmpty)
    }
}
