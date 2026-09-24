import SwiftUI

/// Selectable seven-degree chord ring — the same circular layout as the
/// Play-mode `CircleChordGridView` (root `I` in a large centre circle, the
/// remaining six degrees clockwise around the outer ring), but driven by a
/// selection instead of live performance.
///
/// Used by the Sequencer step editor to pick a step's scale degree. Like
/// `ChordColorBar`, it owns no persistent state: the caller decides what
/// "selected" means and records undo. A drag slides the highlight between
/// degrees (a plain tap is included, since `minimumDistance` is 0).
struct DegreeRingView: View {
    /// The highlighted degree, or `nil` when the step is a rest (nothing lit).
    let selected: Degree?
    /// Called as the finger crosses into a new degree.
    let onChange: (Degree) -> Void
    /// Called when the gesture ends (lets the caller close its undo group).
    var onEnd: (() -> Void)? = nil

    @State private var lastDegree: Degree? = nil
    private let haptic = UIImpactFeedbackGenerator(style: .medium)

    private struct RingChord: Identifiable {
        let degree: Degree
        let label: String
        let angleDeg: Double
        var id: Int { degree.rawValue }
    }

    private let ringChords: [RingChord] = [
        RingChord(degree: .ii,     label: "ii",   angleDeg: 30),
        RingChord(degree: .iii,    label: "iii",  angleDeg: 90),
        RingChord(degree: .IV,     label: "IV",   angleDeg: 150),
        RingChord(degree: .V,      label: "V",    angleDeg: 210),
        RingChord(degree: .vi,     label: "vi",   angleDeg: 270),
        RingChord(degree: .viiDim, label: "vii°", angleDeg: 330),
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

                // Outer degree buttons (visual only — gesture is on the container)
                ForEach(ringChords) { chord in
                    let rad = chord.angleDeg * .pi / 180
                    CircleChordButton(
                        label:     chord.label,
                        color:     .orange,
                        isPressed: selected == chord.degree,
                        fontSize:  outerSz * 0.30
                    )
                    .frame(width: outerSz, height: outerSz)
                    .position(
                        x: cx + ringR * CGFloat(sin(rad)),
                        y: cy - ringR * CGFloat(cos(rad))
                    )
                }

                // Centre: root degree I
                CircleChordButton(
                    label:     "I",
                    color:     .orange,
                    isPressed: selected == .I,
                    fontSize:  centerSz * 0.34
                )
                .frame(width: centerSz, height: centerSz)
                .position(x: cx, y: cy)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        let degree = nearest(to: value.location, cx: cx, cy: cy, ringR: ringR)
                        guard degree != lastDegree else { return }
                        lastDegree = degree
                        haptic.impactOccurred()
                        onChange(degree)
                    }
                    .onEnded { _ in
                        lastDegree = nil
                        onEnd?()
                    }
            )
        }
        .aspectRatio(1, contentMode: .fit)
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

