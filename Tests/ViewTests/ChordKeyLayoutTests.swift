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
        #expect(ChordGridLayout.grid.arrangement(isLandscape: false) == .grid)
        #expect(ChordGridLayout.grid.arrangement(isLandscape: true) == .grid)
        #expect(ChordGridLayout.circle.arrangement(isLandscape: false) == .circle)
        #expect(ChordGridLayout.circle.arrangement(isLandscape: true) == .circle)
        // The row needs the width of a phone on its side.
        #expect(ChordGridLayout.horizontalBar.arrangement(isLandscape: false) == .grid)
        #expect(ChordGridLayout.horizontalBar.arrangement(isLandscape: true) == .row)
        #expect(ChordGridLayout.octave.arrangement(isLandscape: false) == .octave)
        #expect(ChordGridLayout.octave.arrangement(isLandscape: true) == .octave)
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
