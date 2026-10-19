import CoreGraphics
import Testing
@testable import Perfecto

@Suite("ChordKeyTouches")
struct ChordKeyTouchesTests {

    /// Three keys in a row, 100 wide with a 10 gap: I at 0, IV at 110, V at 220.
    private func makeTouches() -> KeyTouches<Int, Degree> {
        var touches = KeyTouches<Int, Degree>()
        touches.frames = [
            .I:  CGRect(x: 0,   y: 0, width: 100, height: 100),
            .IV: CGRect(x: 110, y: 0, width: 100, height: 100),
            .V:  CGRect(x: 220, y: 0, width: 100, height: 100),
        ]
        return touches
    }

    private let onI  = CGPoint(x: 50,  y: 50)
    private let onIV = CGPoint(x: 160, y: 50)
    private let onV  = CGPoint(x: 270, y: 50)

    /// A place on the slide and its place on the key are each other's inverse,
    /// so the zone edges drawn on a key are where the zones change.
    @Test func aSlidesPlaceOnTheKeyReadsAsThatSlide() {
        for height: Float in [0, 0.25, 0.5, 1] {
            #expect(abs(ChordKeySlide.height(at: ChordKeySlide.share(at: height)) - height) < 0.0001)
        }
        #expect(ChordKeySlide.share(at: 0) == ChordKeySlide.margin)
        #expect(ChordKeySlide.height(at: 0) == 0 && ChordKeySlide.height(at: 1) == 1)
    }

    @Test func aFingerPressesTheKeyItLandsOn() {
        var touches = makeTouches()
        #expect(touches.touch(1, at: onI) == KeyChange<Degree>(pressed: .I))
        #expect(touches.lift([1]) == [.I])
    }

    @Test func twoFingersHoldTwoKeysIndependently() {
        var touches = makeTouches()
        _ = touches.touch(1, at: onI)
        #expect(touches.touch(2, at: onIV) == KeyChange<Degree>(pressed: .IV))
        #expect(touches.lift([2]) == [.IV])
        #expect(touches.lift([1]) == [.I])
    }

    @Test func slidingReleasesTheOldKeyAndPressesTheNew() {
        var touches = makeTouches()
        _ = touches.touch(1, at: onI)
        #expect(touches.touch(1, at: onIV) == KeyChange<Degree>(released: .I, pressed: .IV))
    }

    /// One finger holds I; a second slides IV → V. Only the sliding finger's keys change.
    @Test func oneFingerSlidesWhileAnotherHolds() {
        var touches = makeTouches()
        _ = touches.touch(1, at: onI)
        _ = touches.touch(2, at: onIV)
        #expect(touches.touch(2, at: onV) == KeyChange<Degree>(released: .IV, pressed: .V))
        #expect(touches.lift([2]) == [.V])
        #expect(touches.lift([1]) == [.I])
    }

    @Test func movingWithinAKeyChangesNothing() {
        var touches = makeTouches()
        _ = touches.touch(1, at: onI)
        #expect(touches.touch(1, at: CGPoint(x: 60, y: 70)) == KeyChange<Degree>())
    }

    /// Past the reach of every key, a finger keeps the key it had.
    @Test func aFingerKeepsItsKeyAcrossEmptySpace() {
        var touches = makeTouches()
        _ = touches.touch(1, at: onI)
        #expect(touches.touch(1, at: CGPoint(x: 50, y: 300)) == KeyChange<Degree>())
        #expect(touches.lift([1]) == [.I])
    }

    @Test func aFingerLandingInEmptySpacePlaysNothingUntilItReachesAKey() {
        var touches = makeTouches()
        #expect(touches.touch(1, at: CGPoint(x: 50, y: 300)) == KeyChange<Degree>())
        #expect(touches.touch(1, at: onI) == KeyChange<Degree>(pressed: .I))
    }

    /// The gap between two keys belongs to the nearer one.
    @Test func theGapBetweenKeysPlaysTheNearerKey() {
        var touches = makeTouches()
        #expect(touches.touch(1, at: CGPoint(x: 103, y: 50)) == KeyChange<Degree>(pressed: .I))
        #expect(touches.touch(1, at: CGPoint(x: 107, y: 50)) == KeyChange<Degree>(released: .I, pressed: .IV))
    }

    /// A key is down while any finger is on it: the second finger does not
    /// press it again, and it is released only when the last finger leaves.
    @Test func twoFingersOnOneKeyAreOnePress() {
        var touches = makeTouches()
        _ = touches.touch(1, at: onI)
        #expect(touches.touch(2, at: onI) == KeyChange<Degree>())
        #expect(touches.lift([1]) == [])
        #expect(touches.lift([2]) == [.I])
    }

    @Test func slidingOntoAHeldKeyOnlyReleasesTheOldOne() {
        var touches = makeTouches()
        _ = touches.touch(1, at: onI)
        _ = touches.touch(2, at: onIV)
        #expect(touches.touch(1, at: onIV) == KeyChange<Degree>(released: .I))
    }

    @Test func fingersLiftedTogetherReleaseTheirKeysTogether() {
        var touches = makeTouches()
        _ = touches.touch(1, at: onI)
        _ = touches.touch(2, at: onIV)
        #expect(Set(touches.lift([1, 2])) == [.I, .IV])
    }

    @Test func liftAllReleasesEveryKeyThatWasDown() {
        var touches = makeTouches()
        _ = touches.touch(1, at: onI)
        _ = touches.touch(2, at: onIV)
        #expect(Set(touches.liftAll()) == [.I, .IV])
        #expect(touches.liftAll().isEmpty)
    }

    // MARK: – Slide

    /// The slide is how far up its key a finger is. The key's top and bottom
    /// margins already read as all the way.
    @Test func theSlideIsHowFarUpTheKeyTheFingerIs() {
        var touches = makeTouches()
        _ = touches.touch(1, at: onI)
        #expect(touches.slide(of: 1, at: onI) == KeySlide<Degree>(key: .I, height: 0.5))
        #expect(touches.slide(of: 1, at: CGPoint(x: 50, y: 10))?.height == 1)
        #expect(touches.slide(of: 1, at: CGPoint(x: 50, y: 90))?.height == 0)
        let upper = touches.slide(of: 1, at: CGPoint(x: 50, y: 32.5))?.height ?? 0
        #expect(abs(upper - 0.75) < 1e-5)
    }

    @Test func aFingerPastItsKeysEdgeSlidesNoFurther() {
        var touches = makeTouches()
        _ = touches.touch(1, at: onI)
        _ = touches.touch(1, at: CGPoint(x: 50, y: 300))
        #expect(touches.slide(of: 1, at: CGPoint(x: 50, y: 300)) == KeySlide<Degree>(key: .I, height: 0))
        #expect(touches.slide(of: 1, at: CGPoint(x: 50, y: -300)) == KeySlide<Degree>(key: .I, height: 1))
    }

    /// Each finger slides on its own key.
    @Test func theSlideBelongsToTheKeyTheFingerPlays() {
        var touches = makeTouches()
        _ = touches.touch(1, at: onI)
        _ = touches.touch(2, at: CGPoint(x: 160, y: 5))
        #expect(touches.slide(of: 1, at: onI)?.key == .I)
        #expect(touches.slide(of: 2, at: CGPoint(x: 160, y: 5)) == KeySlide<Degree>(key: .IV, height: 1))
    }

    /// A piano's black key lies over the white keys beside it.
    @Test func ofKeysThatOverlapTheSmallerIsPlayed() {
        var touches = KeyTouches<Int, Degree>()
        touches.frames = [
            .I:  CGRect(x: 0,   y: 0, width: 100, height: 100),
            .ii: CGRect(x: 80,  y: 0, width: 40,  height: 60),
            .IV: CGRect(x: 104, y: 0, width: 100, height: 100),
        ]
        #expect(touches.touch(1, at: CGPoint(x: 90, y: 30)) == KeyChange<Degree>(pressed: .ii))
        #expect(touches.touch(2, at: CGPoint(x: 110, y: 30)) == KeyChange<Degree>())
        // Below the smaller key, the key under it.
        #expect(touches.touch(3, at: CGPoint(x: 90, y: 80)) == KeyChange<Degree>(pressed: .I))
    }

    @Test func aFingerOnNoKeyHasNoSlide() {
        var touches = makeTouches()
        _ = touches.touch(1, at: CGPoint(x: 50, y: 300))
        #expect(touches.slide(of: 1, at: CGPoint(x: 50, y: 300)) == nil)
        #expect(touches.slide(of: 2, at: onI) == nil)
    }

    // MARK: – The ring

    /// The circle's keys: I a disc of radius 40 at (100, 100), and round it
    /// a ring from 50 out to 100, ii its first sixth from the top and iii
    /// its second.
    private func makeRing() -> KeyTouches<Int, Degree> {
        let center = CGPoint(x: 100, y: 100)
        var touches = KeyTouches<Int, Degree>()
        touches.shapes = [
            .I: .disc(CGRect(x: 60, y: 60, width: 80, height: 80)),
            .ii: .segment(RingSegment(center: center, radii: 50...100, angles: 0...(.pi / 3))),
            .iii: .segment(RingSegment(center: center, radii: 50...100, angles: .pi / 3...2 * .pi / 3)),
        ]
        return touches
    }

    /// A place on the ring: `angle` in degrees clockwise from the top.
    private func onRing(_ angle: CGFloat, radius: CGFloat) -> CGPoint {
        CGPoint(x: 100 + radius * sin(angle * .pi / 180), y: 100 - radius * cos(angle * .pi / 180))
    }

    /// The squares round two segments of a ring overlap, so a segment is
    /// played by its own shape.
    @Test func aSegmentOfTheRingIsPlayedWhereItIsDrawn() {
        var touches = makeRing()
        #expect(touches.touch(1, at: onRing(55, radius: 75)) == KeyChange<Degree>(pressed: .ii))
        #expect(touches.touch(1, at: onRing(65, radius: 75)) == KeyChange<Degree>(released: .ii, pressed: .iii))
        #expect(touches.touch(1, at: CGPoint(x: 100, y: 100)) == KeyChange<Degree>(released: .iii, pressed: .I))
        // In the disc's square, but past its edge and nearer the ring.
        #expect(touches.touch(1, at: onRing(45, radius: 47)) == KeyChange<Degree>(released: .I, pressed: .ii))
    }

    @Test func aFingerBesideTheRingKeepsItsKey() {
        var touches = makeRing()
        _ = touches.touch(1, at: onRing(30, radius: 75))
        #expect(touches.touch(1, at: onRing(30, radius: 105)) == KeyChange<Degree>())
        #expect(touches.touch(1, at: onRing(30, radius: 200)) == KeyChange<Degree>())
        // Round the ring where it has no key.
        #expect(touches.touch(1, at: onRing(270, radius: 75)) == KeyChange<Degree>())
        #expect(touches.lift([1]) == [.ii])
    }

    @Test func aSegmentsDistanceIsToItsNearestEdge() {
        let segment = RingSegment(center: CGPoint(x: 100, y: 100), radii: 50...100, angles: 0...(.pi / 3))
        #expect(segment.distance(from: onRing(30, radius: 75)) == 0)
        #expect(abs(segment.distance(from: onRing(30, radius: 120)) - 20) < 0.001)
        #expect(abs(segment.distance(from: onRing(30, radius: 44)) - 6) < 0.001)
        // Beside its straight side, which runs up from the centre.
        #expect(abs(segment.distance(from: CGPoint(x: 93, y: 25)) - 7) < 0.001)
    }

    /// A segment is slid outwards, wherever round the ring it is.
    @Test func theSlideOnASegmentIsHowFarOutTheFingerIs() {
        var touches = makeRing()
        _ = touches.touch(1, at: onRing(30, radius: 75))
        _ = touches.touch(2, at: onRing(90, radius: 75))
        for (finger, angle) in [(1, CGFloat(30)), (2, 90)] {
            #expect(abs((touches.slide(of: finger, at: onRing(angle, radius: 75))?.height ?? 0) - 0.5) < 1e-5)
            #expect(touches.slide(of: finger, at: onRing(angle, radius: 95))?.height == 1)
            #expect(touches.slide(of: finger, at: onRing(angle, radius: 55))?.height == 0)
        }
    }

    /// The disc in the middle is slid up and down, as a key of any other layout.
    @Test func theSlideOnTheDiscIsHowFarUpTheFingerIs() {
        var touches = makeRing()
        _ = touches.touch(1, at: CGPoint(x: 100, y: 100))
        #expect(touches.slide(of: 1, at: CGPoint(x: 100, y: 100)) == KeySlide<Degree>(key: .I, height: 0.5))
        #expect(touches.slide(of: 1, at: CGPoint(x: 100, y: 64))?.height == 1)
    }
}
