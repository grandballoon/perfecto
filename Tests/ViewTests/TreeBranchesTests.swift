import CoreGraphics
import Testing
@testable import Perfecto

@Suite("TreeBranches")
@MainActor
struct TreeBranchesTests {

    private let c = TreeChord(root: NoteName.roots[0], quality: .major)
    private let phone = CGSize(width: 353, height: 400)

    @Test func theChordTheTreeIsAtIsOverABranchForEachStep() {
        let branches = TreeBranches(size: phone, position: c)
        #expect(branches.labels.count == 6)
        #expect(branches.steps.map(\.count) == [5, 2, 3, 4, 2, 6])
        for (label, frames) in zip(branches.labels, branches.steps) {
            #expect(label.minY > branches.here.maxY)
            #expect(frames.allSatisfy { $0.minY == label.minY && $0.minX > label.maxX })
        }
    }

    @Test func theBranchesFitTheBoard() {
        let branches = TreeBranches(size: phone, position: c)
        let all = branches.steps.joined() + branches.labels + [branches.here]
        #expect(all.allSatisfy { CGRect(origin: .zero, size: phone).contains($0) })
    }

    @Test func aChordIsNoLargerThanItsLargestHoweverMuchRoomThereIs() {
        let branches = TreeBranches(size: CGSize(width: 2000, height: 2000), position: c)
        #expect(branches.steps.joined().allSatisfy {
            $0.width <= TreeBranches.largest.width && $0.height <= TreeBranches.largest.height
        })
    }

    @Test func aPointIsOnTheChordDrawnThere() {
        let branches = TreeBranches(size: phone, position: c)
        let center = { (frame: CGRect) in CGPoint(x: frame.midX, y: frame.midY) }
        #expect(branches.spot(at: center(branches.here), tier: 2) == TreeSpot(tier: 2, from: c, step: nil))
        #expect(branches.spot(at: center(branches.steps[0][2]), tier: 2)?.chord.label == "Dm")
        #expect(branches.spot(at: center(branches.labels[0]), tier: 2) == nil)
    }

    @Test func theTreeIsLaidOutForTheRoomItHas() {
        #expect(TreeArrangement.of(CGSize(width: 900, height: 860)) == .wide)
        #expect(TreeArrangement.of(CGSize(width: 353, height: 620)) == .stacked)
        #expect(TreeArrangement.of(CGSize(width: 800, height: 300)) == .beside)
    }

    // MARK: – The tiers

    @Test func aPhoneShowsOneTierAtATimeAndADeskMore() {
        let one = TreeTiers(size: phone, count: 3)
        #expect(one.width == phone.width)
        #expect(one.stops == [0, phone.width + TreeTiers.gap, 2 * (phone.width + TreeTiers.gap)])
        let desk = TreeTiers(size: CGSize(width: 2000, height: 600), count: 3)
        #expect(desk.width == TreeTiers.widest)
        #expect(desk.isWhole(0, scrolled: 0) && desk.isWhole(1, scrolled: 0))
    }

    @Test func theLastTierComesToRestAtTheTrailingEdge() {
        let desk = TreeTiers(size: CGSize(width: 1400, height: 600), count: 3)
        #expect(desk.stops.last == desk.farthest)
        #expect(desk.minX(of: 2) + desk.width - desk.farthest == 1400)
        #expect(TreeTiers(size: CGSize(width: 2000, height: 600), count: 1).farthest == 0)
    }

    @Test func aPointIsOnTheTierDrawnThere() {
        let tiers = TreeTiers(size: phone, count: 3)
        let stride = phone.width + TreeTiers.gap
        let found = tiers.tier(at: CGPoint(x: 10, y: 20), scrolled: stride)
        #expect(found?.tier == 1)
        #expect(found?.point == CGPoint(x: 10, y: 20))
        // The gap between two tiers is on neither.
        #expect(tiers.tier(at: CGPoint(x: phone.width - 10, y: 20), scrolled: 20) == nil)
        #expect(tiers.tier(at: CGPoint(x: 10, y: 20), scrolled: 3 * stride) == nil)
    }

    @Test func scrollingComesToRestAtTheNearestStopOrOnInTheDirectionOfAFlick() {
        let tiers = TreeTiers(size: phone, count: 3)
        let stride = phone.width + TreeTiers.gap
        #expect(tiers.settled(stride * 0.4, velocity: 0) == 0)
        #expect(tiers.settled(stride * 0.6, velocity: 0) == stride)
        #expect(tiers.settled(stride * 0.1, velocity: TreeTiers.flick + 1) == stride)
        #expect(tiers.settled(stride * 1.9, velocity: -TreeTiers.flick - 1) == stride)
        #expect(tiers.settled(stride * 2, velocity: TreeTiers.flick + 1) == stride * 2)
    }

    @Test func theTierTheTreeGoesToIsBroughtIntoViewMovingAsLittleAsThereIsTo() {
        let phoneTiers = TreeTiers(size: phone, count: 3)
        let stride = phone.width + TreeTiers.gap
        #expect(phoneTiers.revealing(2, from: 0) == 2 * stride)
        #expect(phoneTiers.revealing(0, from: 2 * stride) == 0)
        let desk = TreeTiers(size: CGSize(width: 2000, height: 600), count: 4)
        #expect(desk.revealing(1, from: 0) == 0)
        #expect(desk.revealing(3, from: 0) == desk.farthest)
        #expect(desk.nearestWhole(to: 0, scrolled: desk.farthest) == 2)
    }
}
