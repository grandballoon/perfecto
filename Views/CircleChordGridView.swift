import SwiftUI

/// Seven scale-degree chord buttons in a circular layout.
/// The root chord (I) sits in a large circle at the centre.
/// The remaining six chords are arranged clockwise around the outer ring:
/// ii (upper-right), iii (right), IV (lower-right),
/// V (lower-left), vi (left), vii° (upper-left).
///
/// A single container-level drag gesture enables sliding between buttons.
/// @GestureState guarantees the pressed degree resets to nil whenever the
/// gesture ends or is cancelled — including multi-touch interference — so
/// chords can never get stuck in the "on" position.
struct CircleChordGridView: View {
    @Environment(PerformanceState.self) private var state

    // GestureState resets automatically on gesture end/cancel — no manual
    // cleanup needed and no stuck-chord possible.
    @GestureState private var pressingDegree: Degree? = nil

    private let haptic = UIImpactFeedbackGenerator(style: .medium)

    private struct RingChord: Identifiable {
        let degree: Degree
        let label: String
        let color: Color
        let angleDeg: Double
        var id: Int { degree.rawValue }
    }

    private let ringChords: [RingChord] = [
        RingChord(degree: .ii,     label: "ii",   color: .blue,   angleDeg: 30),
        RingChord(degree: .iii,    label: "iii",  color: .indigo, angleDeg: 90),
        RingChord(degree: .IV,     label: "IV",   color: .orange, angleDeg: 150),
        RingChord(degree: .V,      label: "V",    color: .orange, angleDeg: 210),
        RingChord(degree: .vi,     label: "vi",   color: .blue,   angleDeg: 270),
        RingChord(degree: .viiDim, label: "vii°", color: .purple, angleDeg: 330),
    ]

    var body: some View {
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

                // Outer chord buttons (visual only — gesture is on the container)
                ForEach(ringChords) { chord in
                    let rad = chord.angleDeg * .pi / 180
                    CircleChordButton(
                        label:     chord.label,
                        color:     chord.color,
                        isPressed: pressingDegree == chord.degree,
                        fontSize:  outerSz * 0.30
                    )
                    .frame(width: outerSz, height: outerSz)
                    .position(
                        x: cx + ringR * CGFloat(sin(rad)),
                        y: cy - ringR * CGFloat(cos(rad))
                    )
                }

                // Centre: root chord I (visual only)
                CircleChordButton(
                    label:     "I",
                    color:     .orange,
                    isPressed: pressingDegree == .I,
                    fontSize:  centerSz * 0.34
                )
                .frame(width: centerSz, height: centerSz)
                .position(x: cx, y: cy)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .updating($pressingDegree) { value, degree, _ in
                        degree = nearest(to: value.location, cx: cx, cy: cy, ringR: ringR)
                    }
            )
        }
        .aspectRatio(1, contentMode: .fit)
        .onChange(of: pressingDegree) { oldDegree, newDegree in
            if let new = newDegree {
                // playChord() calls stopChord() internally, so no explicit release
                // needed when sliding between degrees — avoiding a double-stop that
                // races with voice release envelopes and silences the new chord.
                haptic.impactOccurred()
                state.press(degree: new)
            } else if let old = oldDegree {
                // All fingers lifted — release cleanly.
                state.release(degree: old)
            }
        }
    }

    /// Returns the degree whose button centre is closest to `point`.
    private func nearest(to point: CGPoint, cx: CGFloat, cy: CGFloat, ringR: CGFloat) -> Degree {
        var best: Degree = .I
        var bestDist = hypot(point.x - cx, point.y - cy)
        for chord in ringChords {
            let rad = chord.angleDeg * .pi / 180
            let bx = cx + ringR * CGFloat(sin(rad))
            let by = cy - ringR * CGFloat(cos(rad))
            let d = hypot(point.x - bx, point.y - by)
            if d < bestDist {
                bestDist = d
                best = chord.degree
            }
        }
        return best
    }
}

// MARK: – Visual-only circle button (no gesture — parent owns interaction)

private struct CircleChordButton: View {
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
