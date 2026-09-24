import SwiftUI

/// The seven scale-degree chord buttons laid out in a single tall, uniform-width
/// horizontal row. A single container-level drag gesture lets the player slide a
/// finger across buttons — the next chord replaces the previous without a gap —
/// instead of having to lift and re-tap. Used in landscape when the horizontal
/// chord-row layout is enabled in Settings.
struct ChordRowView: View {
    @Environment(PerformanceState.self) private var state

    private let haptic = UIImpactFeedbackGenerator(style: .medium)

    private let chords: [(degree: Degree, color: Color)] = [
        (.I, .orange),
        (.ii, .orange),
        (.iii, .orange),
        (.IV, .orange),
        (.V, .orange),
        (.vi, .orange),
        (.viiDim, .orange),
    ]

    @State private var pressedIndex: Int? = nil

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 8) {
                ForEach(Array(chords.enumerated()), id: \.offset) { index, chord in
                    button(chord, active: pressedIndex == index)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        let index = buttonIndex(at: value.location.x, in: geo.size.width)
                        guard pressedIndex != index else { return }
                        haptic.impactOccurred()
                        state.movePointer(from: pressedIndex.map { chords[$0].degree },
                                          to: chords[index].degree)
                        pressedIndex = index
                    }
                    .onEnded { _ in
                        state.movePointer(from: pressedIndex.map { chords[$0].degree }, to: nil)
                        pressedIndex = nil
                    }
            )
        }
    }

    private func button(_ chord: (degree: Degree, color: Color),
                        active: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(active ? chord.color.opacity(0.9) : chord.color.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(chord.color, lineWidth: 2)
                )
            Text(degreeNumeral(key: state.key, degree: chord.degree))
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scaleEffect(active ? 0.96 : 1.0)
        .animation(.easeInOut(duration: 0.06), value: active)
    }

    /// Maps an x-coordinate to a button index by even division. Inter-button
    /// spacing is ignored (as elsewhere in the app) — the small boundary slop is
    /// imperceptible and the active highlight gives immediate feedback.
    private func buttonIndex(at x: CGFloat, in width: CGFloat) -> Int {
        guard width > 0 else { return 0 }
        let count = chords.count
        let raw = Int(x / width * CGFloat(count))
        return max(0, min(count - 1, raw))
    }
}
