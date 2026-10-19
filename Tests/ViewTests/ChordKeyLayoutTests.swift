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

    @Test func aFingerChoosesTheKeyItIsNearest() {
        let frames: [Degree: KeyShape] = [
            .I: .rect(CGRect(x: 0, y: 0, width: 40, height: 80)),
            .ii: .rect(CGRect(x: 48, y: 0, width: 40, height: 80)),
        ]
        #expect(DegreeSelector.nearest(to: CGPoint(x: 20, y: 40), in: frames) == .I)
        #expect(DegreeSelector.nearest(to: CGPoint(x: 46, y: 40), in: frames) == .ii)
        // Well outside every key, it is still the nearest one's.
        #expect(DegreeSelector.nearest(to: CGPoint(x: 300, y: 200), in: frames) == .ii)
        #expect(DegreeSelector.nearest(to: CGPoint(x: 20, y: 40), in: [:]) == nil)
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

    /// A phone upright and on its side.
    nonisolated static let screens = [CGSize(width: 393, height: 660), CGSize(width: 852, height: 393)]

    @Test(.serialized, arguments: ChordGridLayout.allCases, screens)
    func theSequencerDrawsItsDegreeKeysInEveryLayout(_ layout: ChordGridLayout, screen: CGSize) throws {
        let seq = SequencerState(defaults: isolatedDefaults())
        seq.selectedSteps = [0]
        seq.primaryStep = 0
        seq.editSelectedChords { ChordSpec(degree: .V, color: $0.color) }

        let perf = PerformanceState(sink: RecordingSink(), clock: ManualClock())
        perf.chordGridLayout = layout
        let window = try show(SequencerView().environment(perf).environment(seq)
            .frame(width: screen.width, height: screen.height))
        defer { window.isHidden = true }

        for other in ChordGridLayout.allCases {
            perf.chordGridLayout = other
            redraw(window)
        }
        #expect(seq.primaryNote?.chord.degree == .V)
    }
}
