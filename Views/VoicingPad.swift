import SwiftUI

/// Where the voicing pad's cells are: every voicing there is, a column to
/// each inversion from the furthest down to the furthest up and a row to
/// each octave with the highest at the top, with the inversions named along
/// the top and the octaves down the leading edge. A voicing field's finger
/// is read by the same cells (`VoicingSwipe`), so the place lit moves as
/// far as the finger does.
enum VoicingSpan {
    static let inversions = PerformanceState.inversions
    static let octaves = PerformanceState.octaves

    /// One voicing's cell, which is also a step of a finger's travel.
    static let cell = CGSize(width: 18, height: 26)
    /// The room round the cells: for the inversions' names at the top and
    /// the octaves' at the leading edge.
    static let top: CGFloat = 18
    static let leading: CGFloat = 20
    static let edge: CGFloat = 6
    /// How near the screen's edge the pad may come.
    static let margin: CGFloat = 8

    static var size: CGSize {
        CGSize(width: leading + CGFloat(inversions.count) * cell.width + edge,
               height: top + CGFloat(octaves.count) * cell.height + edge)
    }

    /// The cell of `voicing`, in the pad's own space. A voicing past the
    /// span has the nearest cell.
    static func frame(of voicing: KeyVoicing) -> CGRect {
        let column = voicing.inversion.steps.clamped(to: inversions) - inversions.lowerBound
        let row = octaves.upperBound - voicing.octave.clamped(to: octaves)
        return CGRect(origin: CGPoint(x: leading + CGFloat(column) * cell.width,
                                      y: top + CGFloat(row) * cell.height),
                      size: cell)
    }

    /// Where the pad goes on a screen of `screen`, for a field at `field`
    /// whose voicing was `pressed` when the finger came down: with that
    /// voicing's cell on the middle of the field, so the finger is on the
    /// place it moves, as near as the screen's edges let it be.
    static func frame(pressedAt pressed: KeyVoicing, on field: CGRect, in screen: CGSize) -> CGRect {
        let cell = frame(of: pressed)
        let x = field.midX - cell.midX
        let y = field.midY - cell.midY
        return CGRect(
            origin: CGPoint(x: max(margin, min(x, screen.width - size.width - margin)),
                            y: max(margin, min(y, screen.height - size.height - margin))),
            size: size)
    }
}

/// A voicing field with a finger on it: what the screen needs to draw its
/// pad.
struct VoicingPadPlace {
    /// The voicing when the finger came down.
    let pressed: KeyVoicing
    /// The voicing now.
    let voicing: KeyVoicing
    /// Where the field is.
    let field: Anchor<CGRect>
}

struct VoicingPadKey: PreferenceKey {
    static let defaultValue: VoicingPadPlace? = nil

    static func reduce(value: inout VoicingPadPlace?, nextValue: () -> VoicingPadPlace?) {
        value = value ?? nextValue()
    }
}

extension View {
    /// Draws the pad of whichever voicing field inside this view has a
    /// finger on it (`VoicingField`). It goes on the screen as a whole, so
    /// the pad lies over everything and no neighbour or clipped edge hides
    /// it. The pad takes no touches: the finger is still the field's.
    func showingVoicingPad() -> some View {
        overlayPreferenceValue(VoicingPadKey.self) { place in
            GeometryReader { geo in
                if let place {
                    let frame = VoicingSpan.frame(pressedAt: place.pressed, on: geo[place.field], in: geo.size)
                    VoicingPad(voicing: place.voicing)
                        .position(x: frame.midX, y: frame.midY)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.12), value: place != nil)
            .allowsHitTesting(false)
        }
    }
}

/// Every voicing there is, with the one chosen lit: the span a voicing
/// field's finger moves over (`VoicingSpan`). The row of the octave chosen
/// is the brighter one, a slider through the inversions, and the column of
/// root position is marked in every row.
private struct VoicingPad: View {
    let voicing: KeyVoicing

    private static let rowInset: CGFloat = 2

    var body: some View {
        let chosen = VoicingSpan.frame(of: voicing)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(white: 0.08))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(white: 0.4), lineWidth: 1))
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
        .shadow(color: .black.opacity(0.6), radius: 8, y: 2)
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
