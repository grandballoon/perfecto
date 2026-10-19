import CoreGraphics
import Testing
@testable import Perfecto

/// A finger on the voicing field moves the voicing: along through the
/// inversions, across through the octaves.
@Suite("Voicing swipe")
struct VoicingSwipeTests {
    private let cell = VoicingSpan.cell
    private let start = KeyVoicing(octave: 4, inversion: .root)

    @Test func alongIsTheInversion() {
        var swipe = VoicingSwipe(from: start)
        swipe.moved(to: CGSize(width: cell.width * 2, height: 0))
        #expect(swipe.voicing == KeyVoicing(octave: 4, inversion: .second))

        swipe.moved(to: CGSize(width: -cell.width, height: 0))
        #expect(swipe.voicing == KeyVoicing(octave: 4, inversion: Inversion(steps: -1)))
    }

    /// Up the screen is up in pitch.
    @Test func acrossIsTheOctave() {
        var swipe = VoicingSwipe(from: start)
        swipe.moved(to: CGSize(width: 0, height: -cell.height))
        #expect(swipe.voicing == KeyVoicing(octave: 5, inversion: .root))

        swipe.moved(to: CGSize(width: 0, height: cell.height * 2))
        #expect(swipe.voicing == KeyVoicing(octave: 2, inversion: .root))
    }

    /// A finger that only goes up or down, as nearly as a finger does,
    /// changes only the octave.
    @Test func aFingerThatStraysLessThanACellKeepsTheOtherSetting() {
        var swipe = VoicingSwipe(from: start)
        swipe.moved(to: CGSize(width: cell.width - 1, height: -cell.height * 2))
        #expect(swipe.voicing == KeyVoicing(octave: 6, inversion: .root))
    }

    @Test func oneMoveChangesBoth() {
        var swipe = VoicingSwipe(from: start)
        swipe.moved(to: CGSize(width: -cell.width * 3, height: -cell.height))
        #expect(swipe.voicing == KeyVoicing(octave: 5, inversion: Inversion(steps: -3)))
    }

    @Test func itStopsAtTheEndsOfTheSpan() {
        var swipe = VoicingSwipe(from: start)
        swipe.moved(to: CGSize(width: cell.width * 40, height: -cell.height * 40))
        #expect(swipe.voicing == KeyVoicing(octave: VoicingSpan.octaves.upperBound,
                                            inversion: Inversion(steps: VoicingSpan.inversions.upperBound)))
    }

    // MARK: – The span

    @Test func theSpanHasACellForEveryVoicingWithTheHighestOctaveAtTheTop() {
        let low = VoicingSpan.frame(of: KeyVoicing(octave: 2, inversion: Inversion(steps: -8)))
        let high = VoicingSpan.frame(of: KeyVoicing(octave: 7, inversion: Inversion(steps: 8)))
        #expect(low.minX == VoicingSpan.leading)
        #expect(high.minY == VoicingSpan.top)
        #expect(high.maxX == VoicingSpan.size.width - VoicingSpan.edge)
        #expect(low.maxY == VoicingSpan.size.height - VoicingSpan.edge)
    }

    /// A step of the finger is a cell, so the place lit moves as it does.
    @Test func aStepOfTheFingerIsACell() {
        var swipe = VoicingSwipe(from: start)
        swipe.moved(to: CGSize(width: cell.width, height: -cell.height))
        let from = VoicingSpan.frame(of: start)
        let to = VoicingSpan.frame(of: swipe.voicing)
        #expect(to.minX - from.minX == cell.width)
        #expect(to.minY - from.minY == -cell.height)
    }

    @Test func thePadIsLaidOutWithTheVoicingUnderTheFinger() {
        let screen = CGSize(width: 1200, height: 800)
        let field = CGRect(x: 500, y: 400, width: 78, height: 34)
        let pad = VoicingSpan.frame(pressedAt: start, on: field, in: screen)
        let cell = VoicingSpan.frame(of: start).offsetBy(dx: pad.minX, dy: pad.minY)
        #expect(cell.midX == field.midX)
        #expect(cell.midY == field.midY)
    }

    @Test func thePadStaysOnTheScreen() {
        let screen = CGSize(width: 393, height: 852)
        let field = CGRect(x: 20, y: 120, width: 78, height: 34)
        for pressed in [KeyVoicing(octave: 2, inversion: Inversion(steps: 8)),
                        KeyVoicing(octave: 7, inversion: Inversion(steps: -8))] {
            let pad = VoicingSpan.frame(pressedAt: pressed, on: field, in: screen)
            #expect(pad.minX >= VoicingSpan.margin)
            #expect(pad.maxX <= screen.width - VoicingSpan.margin)
            #expect(pad.minY >= VoicingSpan.margin)
            #expect(pad.maxY <= screen.height - VoicingSpan.margin)
        }
    }
}
