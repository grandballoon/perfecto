import SwiftUI

struct JoystickView: View {

    var outerRadius: CGFloat = 72
    private var thumbRadius: CGFloat { outerRadius * (22.0 / 72.0) }
    private let deadbandFraction: CGFloat = 0.22

    @Environment(PerformanceState.self) private var state
    @State private var thumbOffset: CGSize = .zero
    @State private var lastZone: JoystickDirection = .center

    private let directionHaptic = UIImpactFeedbackGenerator(style: .rigid)
    private let centerHaptic    = UIImpactFeedbackGenerator(style: .soft)

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(white: 0.08))
                .overlay(Circle().stroke(Color(white: 0.25), lineWidth: 1.5))
                .frame(width: outerRadius * 2, height: outerRadius * 2)

            Circle()
                .fill(state.joystickDirection == .center
                      ? Color(white: 0.55)
                      : Color.orange)
                .frame(width: thumbRadius * 2, height: thumbRadius * 2)
                .shadow(color: .orange.opacity(state.joystickDirection == .center ? 0 : 0.5),
                        radius: 6)
                .offset(thumbOffset)
        }
        .contentShape(Circle()
            .size(CGSize(width: outerRadius * 2, height: outerRadius * 2)))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    thumbOffset = clamped(value.translation, to: outerRadius - thumbRadius)
                    let zone = zoneFor(thumbOffset)
                    if zone != lastZone {
                        lastZone = zone
                        if zone == .center {
                            centerHaptic.impactOccurred(intensity: 0.5)
                        } else {
                            directionHaptic.impactOccurred()
                        }
                    }
                    state.joystickMoved(to: zone)
                }
                .onEnded { _ in
                    if lastZone != .center {
                        centerHaptic.impactOccurred(intensity: 0.5)
                        lastZone = .center
                    }
                    state.joystickMoved(to: .center)
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.65)) {
                        thumbOffset = .zero
                    }
                }
        )
    }

    // MARK: – Helpers

    private func clamped(_ size: CGSize, to radius: CGFloat) -> CGSize {
        let d = hypot(size.width, size.height)
        guard d > radius else { return size }
        let s = radius / d
        return CGSize(width: size.width * s, height: size.height * s)
    }

    private func zoneFor(_ offset: CGSize) -> JoystickDirection {
        let d = hypot(offset.width, offset.height)
        guard d > outerRadius * deadbandFraction else { return .center }

        let deg = atan2(Double(offset.height), Double(offset.width)) * 180 / .pi

        switch deg {
        case -22.5 ..< 22.5:    return .right
        case  22.5 ..< 67.5:    return .downRight
        case  67.5 ..< 112.5:   return .down
        case  112.5 ..< 157.5:  return .downLeft
        case  157.5 ... 180,
             -180.0 ..< -157.5: return .left
        case -157.5 ..< -112.5: return .upLeft
        case -112.5 ..< -67.5:  return .up
        default:                 return .upRight
        }
    }
}
