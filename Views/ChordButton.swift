import SwiftUI

struct ChordButton: View {
    let degree: Degree
    let label: String
    let color: Color

    @Environment(PerformanceState.self) private var state
    @State private var isPressed = false

    private let haptic = UIImpactFeedbackGenerator(style: .medium)

    var body: some View {
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
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 0.06), value: isPressed)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isPressed else { return }
                    isPressed = true
                    haptic.impactOccurred()
                    state.press(degree: degree)
                }
                .onEnded { _ in
                    isPressed = false
                    state.release(degree: degree)
                }
        )
    }
}
