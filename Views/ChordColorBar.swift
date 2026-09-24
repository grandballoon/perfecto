import SwiftUI

/// The 8-section chord-coloration strip shared by Play mode (`ChordBarView`)
/// and the Sequencer step editor.
///
/// It renders the joystick directions as a vertical or horizontal bar and
/// reports selection changes through closures — it owns no state of its own,
/// so callers decide what "selected" means (global performance direction in
/// Play mode; the selected step's direction in the sequencer).
struct ChordColorBar: View {

    let axis: Axis
    /// Drives the per-section labels (Maj7, Dom7, …) which vary by mode.
    let mode: JoystickMode
    /// The currently highlighted direction.
    let selected: JoystickDirection
    /// Called as the drag crosses into a new section.
    let onChange: (JoystickDirection) -> Void
    /// Called when the drag ends. Play mode resets to `.center`; the sequencer
    /// leaves the chosen direction in place, so it passes `nil`.
    var onEnd: (() -> Void)? = nil

    private let haptic = UIImpactFeedbackGenerator(style: .rigid)

    private let directions: [JoystickDirection] = [
        .up, .upRight, .right, .downRight,
        .down, .downLeft, .left, .upLeft,
    ]

    var body: some View {
        GeometryReader { geo in
            Group {
                if axis == .vertical {
                    VStack(spacing: 0) { sections }
                } else {
                    HStack(spacing: 0) { sections }
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        let index = sectionIndex(at: value.location, in: geo.size)
                        let direction = directions[index]
                        guard selected != direction else { return }
                        haptic.impactOccurred()
                        onChange(direction)
                    }
                    .onEnded { _ in onEnd?() }
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(white: 0.25), lineWidth: 1))
    }

    @ViewBuilder
    private var sections: some View {
        ForEach(Array(directions.enumerated()), id: \.offset) { index, direction in
            sectionView(direction)
            if index < directions.count - 1 {
                divider
            }
        }
    }

    private func sectionView(_ direction: JoystickDirection) -> some View {
        let active = selected == direction
        return ZStack {
            (active ? Color.orange.opacity(0.85) : Color(white: 0.08))
            VStack(spacing: 2) {
                // The arrows map to 2-D joystick directions; laid out along a
                // single horizontal row their positions carry no meaning, so
                // show them only in the vertical bar.
                if axis == .vertical {
                    Text(symbol(for: direction))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(active ? .black : Color(white: 0.45))
                }
                Text(joystickActionLabel(mode: mode, direction: direction))
                    .font(.system(size: axis == .vertical ? 11 : 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(active ? .black.opacity(0.8) : Color(white: 0.5))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.6)
            }
            .padding(4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var divider: some View {
        Group {
            if axis == .vertical {
                Rectangle().fill(Color(white: 0.2)).frame(height: 1)
            } else {
                Rectangle().fill(Color(white: 0.2)).frame(width: 1)
            }
        }
    }

    // MARK: – Gesture helpers

    private func sectionIndex(at point: CGPoint, in size: CGSize) -> Int {
        let count = directions.count
        let raw = axis == .vertical
            ? Int(point.y / size.height * CGFloat(count))
            : Int(point.x / size.width * CGFloat(count))
        return max(0, min(count - 1, raw))
    }

    // MARK: – Labels

    private func symbol(for direction: JoystickDirection) -> String {
        switch direction {
        case .up:        return "↑"
        case .upRight:   return "↗"
        case .right:     return "→"
        case .downRight: return "↘"
        case .down:      return "↓"
        case .downLeft:  return "↙"
        case .left:      return "←"
        case .upLeft:    return "↖"
        case .center:    return "·"
        }
    }
}
