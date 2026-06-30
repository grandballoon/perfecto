import SwiftUI

struct ChordBarView: View {

    let axis: Axis

    @Environment(PerformanceState.self) private var state

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
                        guard state.joystickDirection != direction else { return }
                        haptic.impactOccurred()
                        state.joystickMoved(to: direction)
                    }
                    .onEnded { _ in
                        state.joystickMoved(to: .center)
                    }
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(white: 0.25), lineWidth: 1))
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
        let active = state.joystickDirection == direction
        return ZStack {
            (active ? Color.orange.opacity(0.85) : Color(white: 0.08))
            VStack(spacing: 2) {
                Text(symbol(for: direction))
                    .font(.system(size: axis == .vertical ? 11 : 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(active ? .black : Color(white: 0.45))
                Text(label(for: direction))
                    .font(.system(size: axis == .vertical ? 9 : 8, weight: .regular, design: .monospaced))
                    .foregroundStyle(active ? .black.opacity(0.7) : Color(white: 0.35))
                    .lineLimit(1)
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

    private func label(for direction: JoystickDirection) -> String {
        switch state.joystickMode {
        case .default:
            switch direction {
            case .up:        return "Flip 3rd"
            case .upRight:   return "Dom 7"
            case .right:     return "Maj 7"
            case .downRight: return "Add 9"
            case .down:      return "Sus 4"
            case .downLeft:  return "6/Sus2"
            case .left:      return "Dim"
            case .upLeft:    return "Aug"
            case .center:    return "Base"
            }
        case .extended:
            switch direction {
            case .up:        return "Flip 3rd"
            case .upRight:   return "Dom 9"
            case .right:     return "Add 11"
            case .downRight: return "Min 11"
            case .down:      return "7♯9"
            case .downLeft:  return "Add 9"
            case .left:      return "Sus4 7"
            case .upLeft:    return "½dim 7"
            case .center:    return "Base"
            }
        case .chromatic:
            switch direction {
            case .up:        return "MinMaj 7"
            case .upRight:   return "Dom 13"
            case .right:     return "6/9"
            case .downRight: return "7alt"
            case .down:      return "Maj 13"
            case .downLeft:  return "7♭9"
            case .left:      return "½dim 7"
            case .upLeft:    return "Maj7♯11"
            case .center:    return "Base"
            }
        }
    }
}
