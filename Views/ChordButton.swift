import SwiftUI

/// One key of the chord grid. Visual only: the enclosing `ChordKeySurface`
/// owns the touches.
struct ChordButton: View {
    let degree: Degree
    let label: String
    let color: Color

    @Environment(PerformanceState.self) private var state

    var body: some View {
        let isPressed = state.heldDegrees.contains(degree)
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(isPressed ? color.opacity(0.9) : color.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(color, lineWidth: 2)
                )

            Text(label)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
        }
        .frame(minWidth: 60, minHeight: 60)
        .chordKey(degree)
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 0.06), value: isPressed)
    }
}
