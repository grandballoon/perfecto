import CoreGraphics
import Testing
@testable import Perfecto

@Suite("ChordKeyTouches")
struct ChordKeyTouchesTests {

    /// Three keys in a row, 100 wide with a 10 gap: I at 0, IV at 110, V at 220.
    private func makeTouches() -> ChordKeyTouches<Int> {
        var touches = ChordKeyTouches<Int>()
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
        #expect(touches.touch(1, at: onI) == ChordKeyChange(pressed: .I))
        #expect(touches.lift([1]) == [.I])
    }

    @Test func twoFingersHoldTwoKeysIndependently() {
        var touches = makeTouches()
        _ = touches.touch(1, at: onI)
        #expect(touches.touch(2, at: onIV) == ChordKeyChange(pressed: .IV))
        #expect(touches.lift([2]) == [.IV])
        #expect(touches.lift([1]) == [.I])
    }

    @Test func slidingReleasesTheOldKeyAndPressesTheNew() {
        var touches = makeTouches()
        _ = touches.touch(1, at: onI)
        #expect(touches.touch(1, at: onIV) == ChordKeyChange(released: .I, pressed: .IV))
    }

    /// One finger holds I; a second slides IV → V. Only the sliding finger's keys change.
    @Test func oneFingerSlidesWhileAnotherHolds() {
        var touches = makeTouches()
        _ = touches.touch(1, at: onI)
        _ = touches.touch(2, at: onIV)
        #expect(touches.touch(2, at: onV) == ChordKeyChange(released: .IV, pressed: .V))
        #expect(touches.lift([2]) == [.V])
        #expect(touches.lift([1]) == [.I])
    }

    @Test func movingWithinAKeyChangesNothing() {
        var touches = makeTouches()
        _ = touches.touch(1, at: onI)
        #expect(touches.touch(1, at: CGPoint(x: 60, y: 70)) == ChordKeyChange())
    }

    /// Past the reach of every key, a finger keeps the key it had.
    @Test func aFingerKeepsItsKeyAcrossEmptySpace() {
        var touches = makeTouches()
        _ = touches.touch(1, at: onI)
        #expect(touches.touch(1, at: CGPoint(x: 50, y: 300)) == ChordKeyChange())
        #expect(touches.lift([1]) == [.I])
    }

    @Test func aFingerLandingInEmptySpacePlaysNothingUntilItReachesAKey() {
        var touches = makeTouches()
        #expect(touches.touch(1, at: CGPoint(x: 50, y: 300)) == ChordKeyChange())
        #expect(touches.touch(1, at: onI) == ChordKeyChange(pressed: .I))
    }

    /// The gap between two keys belongs to the nearer one.
    @Test func theGapBetweenKeysPlaysTheNearerKey() {
        var touches = makeTouches()
        #expect(touches.touch(1, at: CGPoint(x: 103, y: 50)) == ChordKeyChange(pressed: .I))
        #expect(touches.touch(1, at: CGPoint(x: 107, y: 50)) == ChordKeyChange(released: .I, pressed: .IV))
    }

    /// A key is down while any finger is on it: the second finger does not
    /// press it again, and it is released only when the last finger leaves.
    @Test func twoFingersOnOneKeyAreOnePress() {
        var touches = makeTouches()
        _ = touches.touch(1, at: onI)
        #expect(touches.touch(2, at: onI) == ChordKeyChange())
        #expect(touches.lift([1]) == [])
        #expect(touches.lift([2]) == [.I])
    }

    @Test func slidingOntoAHeldKeyOnlyReleasesTheOldOne() {
        var touches = makeTouches()
        _ = touches.touch(1, at: onI)
        _ = touches.touch(2, at: onIV)
        #expect(touches.touch(1, at: onIV) == ChordKeyChange(released: .I))
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
        #expect(touches.slide(of: 1, at: onI) == ChordKeySlide(key: .I, height: 0.5))
        #expect(touches.slide(of: 1, at: CGPoint(x: 50, y: 10))?.height == 1)
        #expect(touches.slide(of: 1, at: CGPoint(x: 50, y: 90))?.height == 0)
        let upper = touches.slide(of: 1, at: CGPoint(x: 50, y: 32.5))?.height ?? 0
        #expect(abs(upper - 0.75) < 1e-5)
    }

    @Test func aFingerPastItsKeysEdgeSlidesNoFurther() {
        var touches = makeTouches()
        _ = touches.touch(1, at: onI)
        _ = touches.touch(1, at: CGPoint(x: 50, y: 300))
        #expect(touches.slide(of: 1, at: CGPoint(x: 50, y: 300)) == ChordKeySlide(key: .I, height: 0))
        #expect(touches.slide(of: 1, at: CGPoint(x: 50, y: -300)) == ChordKeySlide(key: .I, height: 1))
    }

    /// Each finger slides on its own key.
    @Test func theSlideBelongsToTheKeyTheFingerPlays() {
        var touches = makeTouches()
        _ = touches.touch(1, at: onI)
        _ = touches.touch(2, at: CGPoint(x: 160, y: 5))
        #expect(touches.slide(of: 1, at: onI)?.key == .I)
        #expect(touches.slide(of: 2, at: CGPoint(x: 160, y: 5)) == ChordKeySlide(key: .IV, height: 1))
    }

    @Test func aFingerOnNoKeyHasNoSlide() {
        var touches = makeTouches()
        _ = touches.touch(1, at: CGPoint(x: 50, y: 300))
        #expect(touches.slide(of: 1, at: CGPoint(x: 50, y: 300)) == nil)
        #expect(touches.slide(of: 2, at: onI) == nil)
    }
}
