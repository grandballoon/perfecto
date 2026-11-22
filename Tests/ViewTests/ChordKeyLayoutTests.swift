import SwiftUI
import Testing
import UIKit
@testable import Perfecto

/// The chord layout chosen in Setup is the one every screen with chord keys
/// shows: Play mode plays them, and the sequencer chooses a step's degree
/// from them.
@Suite("Chord key layout")
@MainActor
struct ChordKeyLayoutTests {

    @Test func aLayoutIsArrangedTheSameOnEveryScreen() {
        func arrangement(_ layout: ChordGridLayout, isLandscape: Bool,
                         handedness: Handedness = .right) -> ChordKeyArrangement {
            layout.arrangement(isLandscape: isLandscape, handedness: handedness)
        }
        #expect(arrangement(.grid, isLandscape: false) == .grid)
        #expect(arrangement(.grid, isLandscape: true) == .grid)
        #expect(arrangement(.circle, isLandscape: false) == .circle)
        #expect(arrangement(.circle, isLandscape: true) == .circle)
        // The row needs the width of a phone on its side.
        #expect(arrangement(.horizontalBar, isLandscape: false) == .grid)
        #expect(arrangement(.horizontalBar, isLandscape: true) == .row)
        #expect(arrangement(.octave, isLandscape: false) == .octave)
        #expect(arrangement(.octave, isLandscape: true) == .octave)
        // The edge needs a phone on its side too, and follows the hand.
        #expect(arrangement(.edge, isLandscape: false) == .circle)
        #expect(arrangement(.edge, isLandscape: true) == .edge(.right))
        #expect(arrangement(.edge, isLandscape: true, handedness: .left) == .edge(.left))
        #expect(arrangement(.grid, isLandscape: true, handedness: .left) == .grid)
    }

    /// A key's outline is a shape in its view's frame, which is what it is
    /// drawn as and what fingers are read against.
    @Test func aSegmentIsOfTheRingThatFillsItsView() {
        let frame = CGRect(x: 10, y: 20, width: 200, height: 240)
        let outline = KeyOutline.segment(angles: 0...1, inner: 0.5)
        #expect(outline.shape(in: frame)
                == .segment(RingSegment(center: CGPoint(x: 110, y: 140), radii: 50...100, angles: 0...1)))
        #expect(KeyOutline.rect.shape(in: frame) == .rect(frame))
        #expect(KeyOutline.disc.shape(in: frame) == .disc(frame))
    }
}
