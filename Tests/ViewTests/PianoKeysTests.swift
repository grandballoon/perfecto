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

    // MARK: – Zoomed

    /// An octave from middle C, C4 to B4.
    private let octave = PianoSpan(start: Double(PianoKeys.whitesBelow(60)), count: 7)

    @Test func aZoomedPianoShowsItsSpanAcrossTheStrip() {
        let keys = PianoKeys(size: CGSize(width: 700, height: 90), span: octave)
        #expect(keys.whiteWidth == 100)
        #expect(keys.frame(of: 60).minX == 0)
        #expect(abs(keys.frame(of: 71).maxX - 700) < 0.001)
        #expect(keys.shows(60) && keys.shows(71))
        #expect(!keys.shows(59) && !keys.shows(72))
        // C♯4 is over the line between C4 and D4, as it always is.
        #expect(abs(keys.frame(of: 61).midX - 100) < 0.001)
    }

    @Test func aSpanIsAlwaysWithinThePianoAndNoCloserThanAnOctave() {
        #expect(PianoSpan(start: -5, count: 100) == .whole)
        #expect(PianoSpan(start: 0, count: 2).count == PianoSpan.fewest)
        #expect(PianoSpan(start: 50, count: 10).start == 42)
        #expect(Double(PianoKeys.whites.count) == PianoSpan.whites)
    }

    @Test func aPinchKeepsTheKeyBetweenTheFingersWhereItIs() {
        let closer = PianoSpan.whole.moved(by: 2, from: 0.75, to: 0.75)
        #expect(closer.count == 26)
        #expect(closer.start + 0.75 * closer.count == 39)
        // Pinched back out, it is the whole piano again, not more.
        #expect(closer.moved(by: 0.1, from: 0.5, to: 0.5) == .whole)
        #expect(closer.moved(by: 100, from: 0.5, to: 0.5).count == PianoSpan.fewest)
    }

    @Test func aDragMovesTheKeysWithTheFingerAndStopsAtTheEnds() {
        // A finger moved a quarter of the way toward the high end brings
        // the lower keys into view.
        let dragged = octave.moved(from: 0, to: 0.25)
        #expect(dragged.count == 7)
        #expect(dragged.start == octave.start - 1.75)
        #expect(octave.moved(from: 0, to: 10).start == 0)
        #expect(octave.moved(from: 0, to: -10).start == PianoSpan.whites - 7)
    }

    /// With the whole screen, the keys keep a piano's proportions, however
    /// high the screen is, and stand on its bottom.
    @Test func theWholeScreensKeysAreAPianosShape() {
        let upright = PianoKeys.standing(in: CGSize(width: 390, height: 844), above: 34, span: .whole)
        #expect(abs(upright.height - 390 / 52 * PianoKeys.whiteLength) < 0.001)
        #expect(upright.maxY == 810 && upright.width == 390)

        // An octave on a phone on its side is longer than the screen is
        // high, and reaches past its top.
        let close = PianoKeys.standing(in: CGSize(width: 844, height: 390), above: 21, span: octave)
        #expect(abs(close.height - 844 / 7 * PianoKeys.whiteLength) < 0.001)
        #expect(close.maxY == 369 && close.minY < 0)
    }
}
