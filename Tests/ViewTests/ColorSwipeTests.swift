import CoreGraphics
import Testing
@testable import Perfecto

/// A finger on the color field moves the color: along through the
/// joystick's directions, across through its modes.
@Suite("Color swipe")
struct ColorSwipeTests {
    private let cell = ColorSpan.span.cell

    @Test func alongIsTheDirectionRoundFromUp() {
        var swipe = PadSwipe<ColorSpan>(from: .base)
        swipe.moved(to: CGSize(width: cell.width, height: 0))
        #expect(swipe.value == KeyColor(mode: .default, direction: .up))

        swipe.moved(to: CGSize(width: cell.width * 3, height: 0))
        #expect(swipe.value == KeyColor(mode: .default, direction: .right))
    }

    /// Up the screen is the next mode, away from the plainest.
    @Test func acrossIsTheMode() {
        var swipe = PadSwipe<ColorSpan>(from: KeyColor(mode: .default, direction: .upRight))
        swipe.moved(to: CGSize(width: 0, height: -cell.height))
        #expect(swipe.value == KeyColor(mode: .extended, direction: .upRight))

        swipe.moved(to: CGSize(width: 0, height: -cell.height * 2))
        #expect(swipe.value == KeyColor(mode: .chromatic, direction: .upRight))
    }

    @Test func itStopsAtTheEndsOfTheSpan() {
        var swipe = PadSwipe<ColorSpan>(from: .base)
        swipe.moved(to: CGSize(width: cell.width * 40, height: -cell.height * 40))
        #expect(swipe.value == KeyColor(mode: .chromatic, direction: .upLeft))

        swipe.moved(to: CGSize(width: -cell.width * 80, height: cell.height * 80))
        #expect(swipe.value == .base)
    }

    @Test func everyColorHasItsOwnCell() {
        let colors = ColorSpan.modes.flatMap { mode in
            ColorSpan.directions.map { KeyColor(mode: mode, direction: $0) }
        }
        let cells = colors.map(ColorSpan.cell(of:))
        #expect(Set(cells.map { "\($0.column),\($0.row)" }).count == colors.count)
        #expect(colors.allSatisfy { ColorSpan.value(at: ColorSpan.cell(of: $0)) == $0 })
    }

    /// The pad fits across the narrowest phone, inside its margins.
    @Test func thePadFitsAPhone() {
        let screen = CGSize(width: 375, height: 667)
        let field = CGRect(x: 280, y: 200, width: 78, height: 34)
        for pressed in [KeyColor.base, KeyColor(mode: .chromatic, direction: .upLeft)] {
            let pad = ColorSpan.span.frame(pressedAt: ColorSpan.cell(of: pressed), on: field, in: screen)
            #expect(pad.minX >= PadSpan.margin)
            #expect(pad.maxX <= screen.width - PadSpan.margin)
        }
    }
}
