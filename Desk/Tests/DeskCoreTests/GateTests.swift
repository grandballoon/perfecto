import Testing
@testable import DeskCore

@Suite("Gates")
struct GateTests {

    @Test func aPieChoosesTheNearestTarget() {
        let pie = PieGate.even(7)
        #expect(pie.select(lean(0), from: nil) == 0)
        #expect(pie.select(lean(52), from: nil) == 1)
        #expect(pie.select(lean(350), from: nil) == 0)
        #expect(pie.select(lean(180), from: nil) == 3 || pie.select(lean(180), from: nil) == 4)
    }

    @Test func aPieChoosesNothingInTheMiddle() {
        let pie = PieGate.even(4)
        #expect(pie.select(lean(0, 0.4), from: nil) == nil)
        // Once chosen, it holds until the stick is further in.
        #expect(pie.select(lean(0, 0.4), from: 0) == 0)
        #expect(pie.select(lean(0, 0.3), from: 0) == nil)
    }

    @Test func aPieHoldsOnPastItsEdge() {
        let pie = PieGate.even(4)
        // 45° is the edge between up and right.
        #expect(pie.select(lean(48), from: 0) == 0)
        #expect(pie.select(lean(48), from: nil) == 1)
        #expect(pie.select(lean(55), from: 0) == 1)
    }

    @Test func aPieWithAGapChoosesNothingThere() {
        let pie = PieGate(bearings: [-30, 0, 30], width: 15)
        #expect(pie.select(lean(180), from: nil) == nil)
        #expect(pie.select(lean(40), from: nil) == 2)
    }

    @Test func bandsAreReadOutwardsAndHold() {
        let bands = RadialBands.three
        #expect(bands.band(0.6, from: nil) == 0)
        #expect(bands.band(0.8, from: nil) == 1)
        #expect(bands.band(0.95, from: nil) == 2)
        #expect(bands.band(0.69, from: 1) == 1)
        #expect(bands.band(0.6, from: 1) == 0)
    }

    @Test func aFastPullStrikesLouderThanASlowOne() {
        var fast = TriggerStrike()
        let result1 = fast.step(0.1, at: 0)
        #expect(result1 == [])
        let loud = fast.step(0.7, at: 0.016)
        var slow = TriggerStrike()
        _ = slow.step(0.1, at: 0)
        let soft = slow.step(0.15, at: 0.016)
        guard case let .strike(high)? = loud.first, case let .strike(low)? = soft.first else {
            Issue.record("both strike")
            return
        }
        #expect(high > low)
        #expect(low >= TriggerStrike.softest)
    }

    @Test func aStrikeIsHeldAndLetGo() {
        var trigger = TriggerStrike()
        _ = trigger.step(1, at: 0)
        #expect(trigger.isHeld)
        let result2 = trigger.step(0.5, at: 0.1)
        #expect(result2 == [.depth(0.5)])
        let result3 = trigger.step(0.02, at: 0.2)
        #expect(result3 == [.release])
        #expect(!trigger.isHeld)
    }

    @Test func triggerStepsHoldAtTheirEdges() {
        let steps = TriggerSteps.three
        #expect(steps.step(0.1, from: 0) == 0)
        #expect(steps.step(0.2, from: 0) == 1)
        #expect(steps.step(0.12, from: 1) == 1)
        #expect(steps.step(0.05, from: 1) == 0)
        #expect(steps.step(0.9, from: 0) == 3)
    }

    @Test func aFlickKeepsAndAHoldLetsGo() {
        let pie = PieGate.even(8)
        var flick = StickGesture()
        let result4 = flick.step(lean(90), gate: pie, at: 0)
        #expect(result4 == [.aim(2)])
        let result5 = flick.step(.rest, gate: pie, at: 0.1)
        #expect(result5 == [.flick(2)])

        var hold = StickGesture()
        _ = hold.step(lean(90), gate: pie, at: 0)
        let result6 = hold.step(lean(90), gate: pie, at: 0.5)
        #expect(result6 == [])
        let result7 = hold.step(.rest, gate: pie, at: 0.6)
        #expect(result7 == [.lift(2)])
    }

    @Test func aTapIsQuickAndUnused() {
        var tap = TapOrHold()
        tap.press(at: 0)
        let result8 = tap.release(at: 0.2)
        #expect(result8)
        tap.press(at: 1)
        tap.use()
        let result9 = tap.release(at: 1.1)
        #expect(!result9)
        tap.press(at: 2)
        let result10 = tap.release(at: 3)
        #expect(!result10)
    }
}
