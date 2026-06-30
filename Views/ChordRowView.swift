import SwiftUI

/// The seven scale-degree chord buttons laid out in a single tall, uniform-width
/// horizontal row. A single container-level drag gesture lets the player slide a
/// finger across buttons — releasing the previous chord and pressing the next —
/// instead of having to lift and re-tap. Used in landscape when the horizontal
/// chord-row layout is enabled in Settings.
struct ChordRowView: View {
    @Environment(PerformanceState.self) private var state

    private let haptic = UIImpactFeedbackGenerator(style: .medium)

    private let chords: [(degree: Degree, label: String, color: Color)] = [
        (.I,      "I",    .orange),
        (.ii,     "ii",   .blue),
        (.iii,    "iii",  .indigo),
        (.IV,     "IV",   .orange),
        (.V,      "V",    .orange),
        (.vi,     "vi",   .blue),
        (.viiDim, "vii°", .purple),
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
                        if let prev = pressedIndex {
                            state.release(degree: chords[prev].degree)
                        }
                        pressedIndex = index
                        haptic.impactOccurred()
                        state.press(degree: chords[index].degree)
                    }
                    .onEnded { _ in
                        if let prev = pressedIndex {
                            state.release(degree: chords[prev].degree)
                        }
                        pressedIndex = nil
                    }
            )
        }
    }

    private func button(_ chord: (degree: Degree, label: String, color: Color),
                        active: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(active ? chord.color.opacity(0.9) : chord.color.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(chord.color, lineWidth: 2)
                )
            Text(chord.label)
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
