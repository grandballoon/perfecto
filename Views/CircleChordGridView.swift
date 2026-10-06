import SwiftUI

/// Seven scale-degree chord buttons in a circular layout.
/// The root chord (I) sits in a large circle at the centre.
/// The remaining six chords are arranged clockwise around the outer ring:
/// ii (upper-right), iii (right), IV (lower-right),
/// V (lower-left), vi (left), vii° (upper-left).
///
/// Visual only: the `ChordKeySurface` owns the touches.
struct CircleChordGridView: View {
    @Environment(PerformanceState.self) private var state

    private struct RingChord: Identifiable {
        let degree: Degree
        let color: Color
        let angleDeg: Double
        var id: Int { degree.rawValue }
    }

    private let ringChords: [RingChord] = [
        RingChord(degree: .ii,     color: .orange, angleDeg: 30),
        RingChord(degree: .iii,    color: .orange, angleDeg: 90),
        RingChord(degree: .IV,     color: .orange, angleDeg: 150),
        RingChord(degree: .V,      color: .orange, angleDeg: 210),
        RingChord(degree: .vi,     color: .orange, angleDeg: 270),
        RingChord(degree: .viiDim, color: .orange, angleDeg: 330),
    ]

    var body: some View {
        GeometryReader { geo in
            let size     = min(geo.size.width, geo.size.height)
            let cx       = geo.size.width  / 2
            let cy       = geo.size.height / 2
            let ringR    = size * 0.38
            let centerSz = size * 0.27
            let outerSz  = size * 0.22

            ChordKeySurface {
                ZStack {
                    // Faint guide ring
                    Circle()
                        .stroke(Color(white: 0.18), lineWidth: 1)
                        .frame(width: ringR * 2, height: ringR * 2)
                        .position(x: cx, y: cy)

                    // Outer chord buttons
                    ForEach(ringChords) { chord in
                        let rad = chord.angleDeg * .pi / 180
                        CircleChordButton(
                            label:     degreeNumeral(key: state.key, degree: chord.degree),
                            color:     chord.color,
                            isPressed: state.heldDegrees.contains(chord.degree),
                            fontSize:  outerSz * 0.30
                        )
                        .frame(width: outerSz, height: outerSz)
                        .chordKey(chord.degree)
                        .position(
                            x: cx + ringR * CGFloat(sin(rad)),
                            y: cy - ringR * CGFloat(cos(rad))
                        )
                    }

                    // Centre: root chord I
                    CircleChordButton(
                        label:     degreeNumeral(key: state.key, degree: .I),
                        color:     .orange,
                        isPressed: state.heldDegrees.contains(.I),
                        fontSize:  centerSz * 0.34
                    )
                    .frame(width: centerSz, height: centerSz)
                    .chordKey(.I)
                    .position(x: cx, y: cy)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: – Visual-only circle button (no gesture — the surface owns interaction)

/// Circular chord button drawn by `CircleChordGridView`. Visual only; the
/// enclosing `ChordKeySurface` owns the touches.
struct CircleChordButton: View {
    let label:     String
    let color:     Color
    let isPressed: Bool
    let fontSize:  CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(isPressed ? color.opacity(0.9) : color.opacity(0.55))
                .overlay(Circle().stroke(color, lineWidth: 2))
            Text(label)
                .font(.system(size: fontSize, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .scaleEffect(isPressed ? 0.93 : 1.0)
        .animation(.easeInOut(duration: 0.06), value: isPressed)
    }
}
