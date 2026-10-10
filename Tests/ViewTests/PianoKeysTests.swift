import CoreGraphics
import SwiftUI
import Testing
import UIKit
@testable import Perfecto

/// Where the piano's keys are drawn.
@Suite("Piano keys", .serialized)
@MainActor
struct PianoKeysTests {

    private let keys = PianoKeys(size: CGSize(width: 1040, height: 90))

    @Test func aPianoHas88KeysFromA0ToC8() {
        #expect(PianoKeys.notes.count == 88)
        #expect(PianoKeys.whites.count == 52)
        #expect(PianoKeys.blacks.count == 36)
        #expect(PianoKeys.whites.first == 21 && PianoKeys.whites.last == 108)
        #expect(PianoKeys.blacks.first == 22)   // A♯0
    }

    @Test func theWhiteKeysFillTheStripSideBySide() {
        let frames = PianoKeys.whites.map(keys.frame)
        #expect(frames.first?.minX == 0)
        #expect(abs(frames.last!.maxX - 1040) < 0.001)
        for (key, next) in zip(frames, frames.dropFirst()) {
            #expect(abs(key.maxX - next.minX) < 0.001)
            #expect(key.height == 90)
        }
    }

    @Test func aBlackKeyLiesOverTheLineBetweenItsWhiteKeys() {
        for note in PianoKeys.blacks {
            let black = keys.frame(of: note)
            #expect(abs(black.midX - keys.frame(of: note - 1).maxX) < 0.001)
            #expect(abs(black.midX - keys.frame(of: note + 1).minX) < 0.001)
            #expect(black.minY == 0 && black.height < 90)
            #expect(black.width < keys.whiteWidth)
        }
    }

    @Test func onlyACIsNamedAndMiddleCIsC4() {
        #expect(PianoKeys.octaveName(of: 60) == "C4")
        #expect(PianoKeys.octaveName(of: 108) == "C8")
        #expect(PianoKeys.octaveName(of: 62) == nil)
    }

    @Test func theStripIsTallerInAWiderScreenWithinLimits() {
        #expect(PianoKeys.height(forWidth: 393) == 44)
        #expect(PianoKeys.height(forWidth: 1500) == 104)
        let onItsSide = PianoKeys.height(forWidth: 852)
        #expect(onItsSide > 44 && onItsSide < 104)
    }

    // MARK: – On the play screen

    /// Whether a window of `size` whose piano is on is laid out for the
    /// desk, which says so by leaving the sequencer's mode for the keys'.
    private func isDesk(_ size: CGSize) throws -> Bool {
        let state = PerformanceState(sink: RecordingSink(),
                                     sequencer: SequencerState(defaults: isolatedDefaults()),
                                     keyboard: KeyboardState(defaults: isolatedDefaults()),
                                     clock: ManualClock())
        state.selectMode(.sequencer)
        state.piano.isOn = true
        let window = try show(PerformanceView()
            .environment(state)
            .environment(state.sequencerState), size: size)
        defer { window.isHidden = true }
        return state.mode.kind == .play
    }

    /// The screen is laid out in what the piano leaves of the window.
    @Test func theScreenIsLaidOutAboveThePiano() throws {
        #expect(try isDesk(CGSize(width: 1500, height: 950)))
        // A desk without the piano, and too low for one with it.
        let low = CGSize(width: 1500, height: DeskLayout.minimumSize.height + 40)
        #expect(DeskLayout.fits(low))
        #expect(try !isDesk(low))
    }
}
