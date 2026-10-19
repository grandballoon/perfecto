import CoreGraphics
import Testing
@testable import Perfecto

/// A swipe along a field (the key's, the octave's, the sound's) moves its
/// value a step at a time.
@Suite("Swipe steps")
struct SwipeStepsTests {
    private let step = SwipeSteps.step
    private let octaves = PerformanceState.octaves
    private let roots = 0...11

    @Test func aSwipeToTheRightIsAStepUpAndToTheLeftOneDown() {
        var up = SwipeSteps(from: 4, in: octaves)
        up.moved(to: step)
        #expect(up.value == 5)

        var down = SwipeSteps(from: 4, in: octaves)
        down.moved(to: -step)
        #expect(down.value == 3)
    }

    @Test func aFingerThatHasNotGoneAStepChangesNothing() {
        var swipe = SwipeSteps(from: 4, in: octaves)
        swipe.moved(to: step - 1)
        #expect(swipe.value == 4)
        swipe.moved(to: -(step - 1))
        #expect(swipe.value == 4)
    }

    @Test func aLongSwipeCrossesSeveralSteps() {
        var swipe = SwipeSteps(from: 4, in: octaves)
        swipe.moved(to: step * 2.5)
        #expect(swipe.value == 6)
        // However the travel is divided into readings.
        var slow = SwipeSteps(from: 4, in: octaves)
        for travel in stride(from: CGFloat(0), through: step * 2.5, by: 1) { slow.moved(to: travel) }
        #expect(slow.value == 6)
    }

    @Test func aFingerThatGoesBackTakesTheValueBack() {
        var swipe = SwipeSteps(from: 4, in: octaves)
        swipe.moved(to: step * 2)
        swipe.moved(to: step)
        #expect(swipe.value == 5)
        swipe.moved(to: 0)
        #expect(swipe.value == 4)
    }

    @Test func theValueStopsAtTheLastOne() {
        var swipe = SwipeSteps(from: 6, in: octaves)
        swipe.moved(to: step * 10)
        #expect(swipe.value == octaves.upperBound)

        var down = SwipeSteps(from: 3, in: octaves)
        down.moved(to: -step * 10)
        #expect(down.value == octaves.lowerBound)
    }

    @Test func travelPastTheLastValueIsNotOwedBack() {
        var swipe = SwipeSteps(from: 6, in: octaves)
        swipe.moved(to: step * 10)
        swipe.moved(to: step * 9)
        #expect(swipe.value == octaves.upperBound - 1)
    }

    @Test func aRangeThatWrapsGoesRoundAtItsEnds() {
        var up = SwipeSteps(from: 11, in: roots, wraps: true)
        up.moved(to: step)
        #expect(up.value == 0)

        var down = SwipeSteps(from: 0, in: roots, wraps: true)
        down.moved(to: -step)
        #expect(down.value == 11)
    }

    @Test func aSwipeRoundARangeThatWrapsOwesItsTravelBack() {
        var swipe = SwipeSteps(from: 10, in: roots, wraps: true)
        swipe.moved(to: step * 4)
        #expect(swipe.value == 2)
        swipe.moved(to: step * 3)
        #expect(swipe.value == 1)
        swipe.moved(to: 0)
        #expect(swipe.value == 10)
        // More than once round.
        swipe.moved(to: -step * 25)
        #expect(swipe.value == 9)
    }

    @Test func theStepPastTheEndIsTheOtherEndOnlyIfTheRangeWraps() {
        #expect(SwipeSteps.value(1, from: 11, in: roots, wraps: true) == 0)
        #expect(SwipeSteps.value(-1, from: 0, in: roots, wraps: true) == 11)
        #expect(SwipeSteps.value(1, from: 11, in: roots, wraps: false) == nil)
        #expect(SwipeSteps.value(1, from: 4, in: roots, wraps: false) == 5)
    }
}
