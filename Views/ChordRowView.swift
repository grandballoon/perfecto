import SwiftUI

/// The seven scale-degree chord buttons laid out in a single tall, uniform-width
/// horizontal row. Visual only: the `ChordKeySurface` owns the touches. Used in
/// landscape when the horizontal chord-row layout is enabled in Settings.
struct ChordRowView: View {
    @Environment(PerformanceState.self) private var state

    private let chords: [(degree: Degree, color: Color)] = [
        (.I, .orange),
        (.ii, .orange),
        (.iii, .orange),
        (.IV, .orange),
        (.V, .orange),
        (.vi, .orange),
        (.viiDim, .orange),
    ]

    var body: some View {
        ChordKeySurface {
            HStack(spacing: 8) {
                ForEach(chords, id: \.degree) { chord in
                    button(chord, active: state.heldDegrees.contains(chord.degree))
                        .chordKey(chord.degree)
                }
            }
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
}
