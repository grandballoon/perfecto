import SwiftUI

/// The seven scale-degree chord keys, drawn in one of their arrangements
/// (`ChordKeyArrangement`). Visual only: each key is marked with
/// `chordKey(_:)` and the surface around it owns the touches, so the same
/// keys are played in Play mode (`ChordKeySurface`) and chosen from in the
/// Sequencer (`DegreeSelector`).
struct ChordKeysView: View {
    let arrangement: ChordKeyArrangement
    /// The key, which decides each degree's numeral (e.g. "ii" vs "ii°").
    let key: Key
    /// The keys drawn as down.
    let lit: [Degree]

    private static let color = Color.orange

    var body: some View {
        switch arrangement {
        case .grid:   grid
        case .circle: circle
        case .row:    row
        }
    }

    // MARK: – Grid: the staggered Nashville grid, four keys over three

    private var grid: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                ForEach([Degree.I, .ii, .iii, .IV]) { barKey($0, pressedScale: 0.95) }
            }
            HStack(spacing: 10) {
                ForEach([Degree.V, .vi, .viiDim]) { barKey($0, pressedScale: 0.95) }
                // The fourth place, so the rows' keys line up.
                Color.clear
            }
        }
    }

    // MARK: – Row: all seven in one line, as tall as there is room for

    private var row: some View {
        HStack(spacing: 8) {
            ForEach(Degree.allCases) { barKey($0, pressedScale: 0.96) }
        }
    }

    private func barKey(_ degree: Degree, pressedScale: CGFloat) -> some View {
        let isPressed = lit.contains(degree)
        return ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Self.color.opacity(isPressed ? 0.9 : 0.6))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Self.color, lineWidth: 2))
            Text(degreeNumeral(key: key, degree: degree))
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .chordKey(degree)
        .scaleEffect(isPressed ? pressedScale : 1.0)
        .animation(.easeInOut(duration: 0.06), value: isPressed)
    }

    // MARK: – Circle: the root in the centre, the other six clockwise around it

    /// The ring's keys and where each sits, in degrees clockwise from the top:
    /// ii (upper-right), iii (right), IV (lower-right), V (lower-left),
    /// vi (left), vii° (upper-left).
    private static let ring: [(degree: Degree, angle: Double)] = [
        (.ii, 30), (.iii, 90), (.IV, 150), (.V, 210), (.vi, 270), (.viiDim, 330),
    ]

    private var circle: some View {
        GeometryReader { geo in
            let size     = min(geo.size.width, geo.size.height)
            let cx       = geo.size.width  / 2
            let cy       = geo.size.height / 2
            let ringR    = size * 0.38
            let centerSz = size * 0.27
            let outerSz  = size * 0.22

            ZStack {
                // Faint guide ring
                Circle()
                    .stroke(Color(white: 0.18), lineWidth: 1)
                    .frame(width: ringR * 2, height: ringR * 2)
                    .position(x: cx, y: cy)

                ForEach(Self.ring, id: \.degree) { chord in
                    let rad = chord.angle * .pi / 180
                    circleKey(chord.degree, size: outerSz, fontSize: outerSz * 0.30)
                        .position(
                            x: cx + ringR * CGFloat(sin(rad)),
                            y: cy - ringR * CGFloat(cos(rad))
                        )
                }

                circleKey(.I, size: centerSz, fontSize: centerSz * 0.34)
                    .position(x: cx, y: cy)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func circleKey(_ degree: Degree, size: CGFloat, fontSize: CGFloat) -> some View {
        let isPressed = lit.contains(degree)
        return ZStack {
            Circle()
                .fill(Self.color.opacity(isPressed ? 0.9 : 0.55))
                .overlay(Circle().stroke(Self.color, lineWidth: 2))
            Text(degreeNumeral(key: key, degree: degree))
                .font(.system(size: fontSize, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .scaleEffect(isPressed ? 0.93 : 1.0)
        .animation(.easeInOut(duration: 0.06), value: isPressed)
        .frame(width: size, height: size)
        .chordKey(degree)
    }
}
