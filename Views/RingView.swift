import SwiftUI

struct RingView: View {

    var outerRadius: CGFloat = 72

    @Environment(PerformanceState.self) private var state
    @State private var lastZone: JoystickDirection = .center

    private var innerRadius: CGFloat { outerRadius * 2 / 3 }
    private let deadbandFraction: CGFloat = 0.22
    private let directionHaptic = UIImpactFeedbackGenerator(style: .rigid)
    private let centerHaptic    = UIImpactFeedbackGenerator(style: .soft)

    // (direction, startDeg, endDeg) — angles increase clockwise, 0° = right
    private let segments: [(JoystickDirection, Double, Double)] = [
        (.right,     -22.5,   22.5),
        (.downRight,  22.5,   67.5),
        (.down,       67.5,  112.5),
        (.downLeft,  112.5,  157.5),
        (.left,      157.5,  202.5),
        (.upLeft,    202.5,  247.5),
        (.up,        247.5,  292.5),
        (.upRight,   292.5,  337.5),
    ]

    var body: some View {
        ZStack {
            // Outer ring track
            Circle()
                .fill(Color(white: 0.08))
                .overlay(Circle().stroke(Color(white: 0.25), lineWidth: 1.5))
                .frame(width: outerRadius * 2, height: outerRadius * 2)

            // Sector fills and dividers
            ForEach(segments.indices, id: \.self) { i in
                let (direction, start, end) = segments[i]
                let active = state.joystickDirection == direction
                sectorPath(startDeg: start, endDeg: end)
                    .fill(active ? Color.orange.opacity(0.85) : Color.clear)
                sectorPath(startDeg: start, endDeg: end)
                    .stroke(Color(white: 0.22), lineWidth: 0.75)
            }

            // Center circle (deadband area)
            Circle()
                .fill(Color(white: 0.04))
                .overlay(Circle().stroke(Color(white: 0.18), lineWidth: 0.75))
                .frame(width: innerRadius * 2, height: innerRadius * 2)

            // Labels
            ForEach(segments.indices, id: \.self) { i in
                let (direction, start, end) = segments[i]
                let active = state.joystickDirection == direction
                sectorLabel(direction: direction, startDeg: start, endDeg: end, active: active)
            }
        }
        .frame(width: outerRadius * 2, height: outerRadius * 2)
        .contentShape(Circle().size(CGSize(width: outerRadius * 2, height: outerRadius * 2)))
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    let offset = CGSize(
                        width:  value.location.x - outerRadius,
                        height: value.location.y - outerRadius
                    )
                    let zone = zoneFor(offset)
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
                }
        )
    }

    // MARK: – Path

    private func sectorPath(startDeg: Double, endDeg: Double) -> Path {
        let center = CGPoint(x: outerRadius, y: outerRadius)
        var path = Path()
        // Outer arc (clockwise on screen = clockwise: false in SwiftUI's flipped convention)
        path.addArc(center: center, radius: outerRadius - 1,
                    startAngle: .degrees(startDeg), endAngle: .degrees(endDeg),
                    clockwise: false)
        // Inner arc reversed
        path.addArc(center: center, radius: innerRadius,
                    startAngle: .degrees(endDeg), endAngle: .degrees(startDeg),
                    clockwise: true)
        path.closeSubpath()
        return path
    }

    // MARK: – Label

    private func sectorLabel(direction: JoystickDirection,
                              startDeg: Double, endDeg: Double,
                              active: Bool) -> some View {
        let midDeg    = (startDeg + endDeg) / 2
        let midRadius = (innerRadius + outerRadius) / 2
        let radians   = midDeg * .pi / 180
        let x         = outerRadius + midRadius * CGFloat(cos(radians))
        let y         = outerRadius + midRadius * CGFloat(sin(radians))
        let labelW    = outerRadius * 0.62

        return VStack(spacing: 1) {
            Text(symbol(for: direction))
                .font(.system(size: max(9, outerRadius * 0.13),
                              weight: .medium, design: .monospaced))
            Text(qualityLabel(for: direction))
                .font(.system(size: max(7, outerRadius * 0.10),
                              weight: .regular, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.4)
        }
        .foregroundStyle(active ? Color.black : Color(white: 0.55))
        .frame(width: labelW)
        .position(x: x, y: y)
    }

    // MARK: – Zone detection (same logic as JoystickView)

    private func zoneFor(_ offset: CGSize) -> JoystickDirection {
        let d = hypot(offset.width, offset.height)
        guard d > outerRadius * deadbandFraction else { return .center }
        let deg = atan2(Double(offset.height), Double(offset.width)) * 180 / .pi
        switch deg {
        case -22.5  ..<  22.5:   return .right
        case  22.5  ..<  67.5:   return .downRight
        case  67.5  ..< 112.5:   return .down
        case  112.5 ..< 157.5:   return .downLeft
        case  157.5 ... 180,
             -180.0 ..< -157.5:  return .left
        case -157.5 ..< -112.5:  return .upLeft
        case -112.5 ..< -67.5:   return .up
        default:                  return .upRight
        }
    }

    // MARK: – Labels (mirrors ChordBarView)

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

    private func qualityLabel(for direction: JoystickDirection) -> String {
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
