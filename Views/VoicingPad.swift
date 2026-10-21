import SwiftUI

/// Where the voicing pad's cells are: every voicing there is, a column to
/// each inversion from the furthest down to the furthest up and a row to
/// each octave with the highest at the top, with the inversions named along
/// the top and the octaves down the leading edge. A voicing field's finger
/// is read by the same cells (`VoicingSwipe`), so the place lit moves as
/// far as the finger does.
enum VoicingSpan: PadMap {
    static let inversions = PerformanceState.inversions
    static let octaves = PerformanceState.octaves

    static let span = PadSpan(columns: inversions, rows: octaves,
                              cell: CGSize(width: 18, height: 26), top: 18, leading: 20)

    static func cell(of voicing: KeyVoicing) -> PadFieldCell {
        PadFieldCell(column: voicing.inversion.steps, row: voicing.octave)
    }

    static func value(at cell: PadFieldCell) -> KeyVoicing {
        KeyVoicing(octave: cell.row, inversion: Inversion(steps: cell.column))
    }

    /// One voicing's cell, which is also a step of a finger's travel.
    static var cell: CGSize { span.cell }
    static var top: CGFloat { span.top }
    static var leading: CGFloat { span.leading }
    static var edge: CGFloat { PadSpan.edge }
    static var margin: CGFloat { PadSpan.margin }
    static var size: CGSize { span.size }

    /// The cell of `voicing`, in the pad's own space. A voicing past the
    /// span has the nearest cell.
    static func frame(of voicing: KeyVoicing) -> CGRect {
        span.frame(of: cell(of: voicing))
    }

    /// Where the pad goes on a screen of `screen`, for a field at `field`
    /// whose voicing was `pressed` when the finger came down.
    static func frame(pressedAt pressed: KeyVoicing, on field: CGRect, in screen: CGSize) -> CGRect {
        span.frame(pressedAt: cell(of: pressed), on: field, in: screen)
    }
}

/// Every voicing there is, with the one chosen lit: the span a voicing
/// field's finger moves over (`VoicingSpan`). The row of the octave chosen
/// is the brighter one, a slider through the inversions, and the column of
/// root position is marked in every row.
struct VoicingPad: View {
    let voicing: KeyVoicing

    private static let rowInset: CGFloat = 2

    var body: some View {
        let chosen = VoicingSpan.frame(of: voicing)
        ZStack(alignment: .topLeading) {
            ForEach(Array(VoicingSpan.octaves), id: \.self) { octave in
                row(octave)
            }
            ForEach(Array(VoicingSpan.inversions), id: \.self) { steps in
                let isChosen = steps == voicing.inversion.steps
                let column = VoicingSpan.frame(of: KeyVoicing(octave: VoicingSpan.octaves.upperBound,
                                                              inversion: Inversion(steps: steps)))
                Text(Inversion(steps: steps).label)
                    .font(.system(size: 8, weight: isChosen ? .bold : .semibold, design: .monospaced))
                    .foregroundStyle(isChosen ? Color.orange : Color(white: steps == 0 ? 0.8 : 0.5))
                    .lineLimit(1)
                    .fixedSize()
                    .frame(width: column.width, height: VoicingSpan.top)
                    .offset(x: column.minX)
            }
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.orange)
                .frame(width: chosen.width, height: chosen.height - 2 * Self.rowInset)
                .offset(x: chosen.minX, y: chosen.minY + Self.rowInset)
        }
        .frame(width: VoicingSpan.size.width, height: VoicingSpan.size.height, alignment: .topLeading)
        .animation(.snappy(duration: 0.12), value: voicing)
    }

    /// One octave's row: its name, its track through the inversions, and
    /// the mark of root position.
    private func row(_ octave: Int) -> some View {
        let isChosen = octave == voicing.octave
        let first = VoicingSpan.frame(of: KeyVoicing(octave: octave,
                                                     inversion: Inversion(steps: VoicingSpan.inversions.lowerBound)))
        let root = VoicingSpan.frame(of: KeyVoicing(octave: octave, inversion: .root))
        let width = CGFloat(VoicingSpan.inversions.count) * first.width
        let height = first.height - 2 * Self.rowInset
        return ZStack(alignment: .topLeading) {
            Text("\(octave)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(isChosen ? Color.orange : Color(white: 0.5))
                .frame(width: VoicingSpan.leading, height: first.height)
                .offset(y: first.minY)
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(white: isChosen ? 0.24 : 0.14))
                .frame(width: width, height: height)
                .offset(x: first.minX, y: first.minY + Self.rowInset)
            Rectangle()
                .fill(Color(white: isChosen ? 0.5 : 0.3))
                .frame(width: 1, height: height)
                .offset(x: root.midX, y: root.minY + Self.rowInset)
        }
    }
}
