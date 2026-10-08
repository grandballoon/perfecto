import SwiftUI
import Testing
import UIKit
@testable import Perfecto

/// The sequencer screen itself, on screen in a window, while bars are removed
/// from under it. The state tests cover what a removal leaves behind; these
/// cover the redraw that follows, where a cell drawn for a step that no longer
/// exists traps.
@Suite("SequencerView bar removal")
@MainActor
struct SequencerViewBarRemovalTests {

    /// What was on screen, and which bar was removed.
    struct Removal: CustomTestStringConvertible, Sendable {
        var layout: SequencerLayout
        var bars: Int
        var focusedBar: Int
        var removedBar: Int
        var isPlaying = false

        var testDescription: String {
            "\(layout.rawValue): bar \(removedBar + 1) of \(bars), showing bar \(focusedBar + 1)"
                + (isPlaying ? ", playing" : "")
        }
    }

    nonisolated static let removals: [Removal] = SequencerLayout.allCases.flatMap { layout in
        [
            Removal(layout: layout, bars: 2, focusedBar: 1, removedBar: 1),
            Removal(layout: layout, bars: 3, focusedBar: 2, removedBar: 2),
            Removal(layout: layout, bars: 3, focusedBar: 1, removedBar: 1),
            Removal(layout: layout, bars: 3, focusedBar: 2, removedBar: 0),
            Removal(layout: layout, bars: 2, focusedBar: 1, removedBar: 1, isPlaying: true),
        ]
    }

    @Test(.serialized, arguments: removals)
    func theScreenRedrawsAfterABarIsRemoved(_ removal: Removal) throws {
        let seq = SequencerState(defaults: isolatedDefaults())
        for _ in 1..<removal.bars { seq.addBar() }
        seq.layout = removal.layout
        seq.focusedBar = removal.focusedBar
        // A selection, loop and playhead in the bar that goes, as when the
        // bar being worked on is the one removed.
        let lastStep = (removal.removedBar + 1) * seq.stepsPerBar - 1
        seq.selectedSteps = [lastStep]
        seq.primaryStep = lastStep
        seq.loopSelection()
        if removal.isPlaying {
            seq.isPlaying = true
            seq.currentStep = lastStep
        }

        let perf = PerformanceState(sink: RecordingSink(), clock: ManualClock())
        let window = try show(SequencerView().environment(perf).environment(seq))
        defer { window.isHidden = true }

        seq.removeBar(removal.removedBar)
        redraw(window)
        #expect(seq.barCount == removal.bars - 1)

        seq.undo()
        redraw(window)
        #expect(seq.barCount == removal.bars)
    }

    /// Every signature draws, in both layouts, with a note held across
    /// rows and bars, a note played off the grid, and a second layer.
    @Test(.serialized, arguments: TimeSignature.offered)
    func theScreenDrawsInEverySignature(_ signature: TimeSignature) throws {
        let seq = SequencerState(defaults: isolatedDefaults())
        seq.addBar()
        seq.setSignature(signature)
        seq.selectedSteps = Set(2..<seq.stepsPerBar + 3)
        seq.primaryStep = 2
        seq.editSelectedChords { ChordSpec(degree: .V, color: $0.color) }
        seq.joinSelected()
        seq.addLayer()
        seq.startLoop([TimelineNote(start: 110, length: 300, chord: ChordSpec(degree: .ii, color: .base)),
                       TimelineNote(start: seq.timeline.length - 10, length: 10,
                                    chord: ChordSpec(degree: .I, color: .base))],
                      bars: seq.barCount)
        seq.undo()                                    // back to the two layers

        let perf = PerformanceState(sink: RecordingSink(), clock: ManualClock())
        let window = try show(SequencerView().environment(perf).environment(seq))
        defer { window.isHidden = true }

        for layout in SequencerLayout.allCases {
            seq.layout = layout
            for layer in seq.layers {
                seq.showLayer(layer.id)
                redraw(window)
            }
            seq.focusedBar = seq.barCount - 1
            redraw(window)
        }
        #expect(seq.shape.rowsPerBar * seq.shape.columns >= seq.stepsPerBar)
    }
}
