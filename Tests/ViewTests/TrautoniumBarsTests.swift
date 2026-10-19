import CoreGraphics
import SwiftUI
import Testing
@testable import Perfecto

/// Where the Trautonium's bars are, where a point is on one, and which
/// finger plays each.
@Suite("Trautonium bars")
struct TrautoniumBarsTests {

    private let flat = CGSize(width: 800, height: 212)
    private let upright = CGSize(width: 312, height: 500)

    // MARK: – The bars

    @Test func theBarsLieAlongTheLongerSide() {
        #expect(TrautoniumBars.axis(in: flat) == .horizontal)
        #expect(TrautoniumBars.frames(in: flat) == [.high: CGRect(x: 0, y: 0, width: 800, height: 100),
                                                    .low: CGRect(x: 0, y: 112, width: 800, height: 100)])
        #expect(TrautoniumBars.axis(in: upright) == .vertical)
        #expect(TrautoniumBars.frames(in: upright) == [.low: CGRect(x: 0, y: 0, width: 150, height: 500),
                                                       .high: CGRect(x: 162, y: 0, width: 150, height: 500)])
        #expect(TrautoniumBars.frames(in: .zero).isEmpty)
    }

    @Test func aBarLyingFlatGoesUpToTheRightAndIsLoudAtItsTop() {
        let frame = CGRect(x: 0, y: 112, width: 800, height: 100)
        #expect(TrautoniumBars.place(of: CGPoint(x: 200, y: 137), in: frame, axis: .horizontal)
                == BarPlace(along: 0.25, across: 0.75))
        // Off the bar is the nearest place on it.
        #expect(TrautoniumBars.place(of: CGPoint(x: 900, y: 300), in: frame, axis: .horizontal)
                == BarPlace(along: 1, across: 0))
    }

    @Test func anUprightBarGoesUpTheScreenAndIsLoudAtItsTrailingEdge() {
        let frame = CGRect(x: 162, y: 0, width: 150, height: 500)
        #expect(TrautoniumBars.place(of: CGPoint(x: 162, y: 125), in: frame, axis: .vertical)
                == BarPlace(along: 0.75, across: 0))
    }

    @Test(arguments: [Axis.horizontal, .vertical])
    func aPlacesPointIsReadAsThatPlace(_ axis: Axis) {
        let frame = CGRect(x: 20, y: 30, width: 400, height: 240)
        let place = BarPlace(along: 0.3, across: 0.8)
        let read = TrautoniumBars.place(of: TrautoniumBars.point(of: place, in: frame, axis: axis),
                                        in: frame, axis: axis)
        #expect(abs(read.along - place.along) < 1e-9 && abs(read.across - place.across) < 1e-9)
    }

    // MARK: – The pitches along a bar

    @Test func everyNoteOfABarHasAsMuchOfItsLength() {
        let range = BarRange(lowest: 60)
        for note in 60...84 {
            #expect(abs(range.pitch(at: range.place(of: Double(note))) - Double(note)) < 1e-9)
        }
        #expect(abs(range.place(of: 61) - range.place(of: 60) - 1.0 / 25) < 1e-9)
        // The ends are the lowest and the highest note, and no further.
        #expect(range.pitch(at: 0) == 60)
        #expect(range.pitch(at: 1) == 84)
    }

    // MARK: – Fingers

    private func touches() -> BarTouches<Int> {
        var touches = BarTouches<Int>()
        touches.frames = TrautoniumBars.frames(in: flat)
        touches.axis = .horizontal
        return touches
    }

    @Test func aFingerPlaysTheBarItComesDownOnWhereverItGoes() {
        var touches = touches()
        #expect(touches.down(1, at: CGPoint(x: 400, y: 162)) == .pressed(.low, BarPlace(along: 0.5, across: 0.5)))
        #expect(touches.move(1, to: CGPoint(x: 600, y: 112)) == .moved(.low, BarPlace(along: 0.75, across: 1)))
        // Over the other bar it still plays its own, at its loud edge.
        #expect(touches.move(1, to: CGPoint(x: 600, y: 40)) == .moved(.low, BarPlace(along: 0.75, across: 1)))
        #expect(touches.lift(1) == .released(.low))
    }

    @Test func aFingerBetweenTheBarsPlaysNothing() {
        var touches = touches()
        #expect(touches.down(1, at: CGPoint(x: 400, y: 106)) == nil)
        #expect(touches.move(1, to: CGPoint(x: 400, y: 150)) == nil)
        #expect(touches.lift(1) == nil)
    }

    @Test func theLastFingerDownPlaysABarAndLiftingItHandsTheBarBack() {
        var touches = touches()
        _ = touches.down(1, at: CGPoint(x: 200, y: 162))
        #expect(touches.down(2, at: CGPoint(x: 600, y: 162)) == .pressed(.low, BarPlace(along: 0.75, across: 0.5)))
        // The finger beneath moves unheard, and is where it got to when
        // the bar comes back to it.
        #expect(touches.move(1, to: CGPoint(x: 400, y: 162)) == nil)
        #expect(touches.lift(2) == .pressed(.low, BarPlace(along: 0.5, across: 0.5)))
        #expect(touches.lift(1) == .released(.low))
    }

    @Test func aFingerBeneathThatLiftsChangesNothing() {
        var touches = touches()
        _ = touches.down(1, at: CGPoint(x: 200, y: 162))
        _ = touches.down(2, at: CGPoint(x: 600, y: 162))
        #expect(touches.lift(1) == nil)
        #expect(touches.lift(2) == .released(.low))
    }

    @Test func eachBarHasItsOwnFinger() {
        var touches = touches()
        #expect(touches.down(1, at: CGPoint(x: 0, y: 162)) == .pressed(.low, BarPlace(along: 0, across: 0.5)))
        #expect(touches.down(2, at: CGPoint(x: 400, y: 0)) == .pressed(.high, BarPlace(along: 0.5, across: 1)))
        #expect(Set(touches.liftAll()) == [.low, .high])
        #expect(touches.liftAll().isEmpty)
    }
}
