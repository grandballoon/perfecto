import DeskCore
import SwiftUI

/// A point at `bearing` (degrees clockwise from up), `distance` from `centre`.
func point(_ centre: CGPoint, bearing: Double, distance: CGFloat) -> CGPoint {
    let radians = bearing * .pi / 180
    return CGPoint(x: centre.x + distance * CGFloat(sin(radians)), y: centre.y - distance * CGFloat(cos(radians)))
}

/// A stick's pie: its targets round a circle, each named by what it would
/// sound, and the stick's own place as a dot, so where the thumb is and
/// where it would land are both seen before anything sounds.
struct PieView: View {
    let targets: [Target?]
    let stick: Stick
    var accent: Color = Theme.chord
    /// What the middle says: the chord there, and a line under it.
    var centre: (title: String, detail: String)?
    var compact = false

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let middle = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let radius = size / 2
            ZStack {
                Circle()
                    .fill(Theme.raised.opacity(0.5))
                    .frame(width: size, height: size)
                Circle()
                    .strokeBorder(Theme.rule, lineWidth: 1)
                    .frame(width: size * 0.36, height: size * 0.36)
                ForEach(Array(targets.enumerated()), id: \.offset) { _, target in
                    if let target {
                        Path { path in
                            path.move(to: point(middle, bearing: target.bearing, distance: radius * 0.2))
                            path.addLine(to: point(middle, bearing: target.bearing, distance: radius * 0.5))
                        }
                        .stroke(target.isAimed ? accent : Theme.rule, lineWidth: target.isAimed ? 2 : 1)
                    }
                }
                StickDot(stick: stick, middle: middle, radius: radius, accent: accent)
                if let centre {
                    VStack(spacing: 2) {
                        Text(centre.title)
                            .font(.system(size: compact ? 15 : 20, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.text)
                        Text(centre.detail)
                            .font(.system(size: compact ? 10 : 11, weight: .medium))
                            .foregroundStyle(Theme.secondary)
                    }
                    .position(middle)
                }
                ForEach(Array(targets.enumerated()), id: \.offset) { _, target in
                    if let target {
                        TargetLabel(target: target, accent: accent, compact: compact)
                            .position(point(middle, bearing: target.bearing, distance: radius * 0.72))
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// Where a stick is, as a dot inside its pie.
struct StickDot: View {
    let stick: Stick
    let middle: CGPoint
    let radius: CGFloat
    let accent: Color

    var body: some View {
        let at = CGPoint(x: middle.x + CGFloat(stick.x) * radius * 0.94, y: middle.y - CGFloat(stick.y) * radius * 0.94)
        ZStack {
            Path { path in
                path.move(to: middle)
                path.addLine(to: at)
            }
            .stroke(accent.opacity(0.35), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            Circle()
                .fill(accent.opacity(stick.radius > 0.05 ? 0.9 : 0.25))
                .frame(width: 12, height: 12)
                .position(at)
        }
        .allowsHitTesting(false)
    }
}

/// A target's label: its chord, and what it is.
struct TargetLabel: View {
    let target: Target
    let accent: Color
    var compact = false

    var body: some View {
        VStack(spacing: 1) {
            Text(target.name)
                .font(.system(size: compact ? 12 : 14, weight: .semibold, design: .rounded))
                .foregroundStyle(target.isAimed ? Color.black : Theme.text)
                .italic(target.fit == .borrowed)
            if !target.detail.isEmpty {
                Text(target.detail)
                    .font(.system(size: compact ? 9 : 10, weight: .medium))
                    .foregroundStyle(target.isAimed ? Color.black.opacity(0.65) : Theme.secondary)
            }
        }
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(background, in: Capsule())
        .overlay(Capsule().strokeBorder(border, style: StrokeStyle(lineWidth: target.isKept ? 2 : 1,
                                                                   dash: target.fit == .borrowed ? [3, 2] : [])))
        .opacity(target.fit == .tense && !target.isAimed ? 0.75 : 1)
    }

    private var background: Color {
        if target.isAimed { return accent }
        if target.isNear { return Theme.near.opacity(0.18) }
        return Theme.panel
    }

    private var border: Color {
        if target.isKept { return accent }
        if target.fit == .borrowed { return Theme.borrowed }
        if target.isNear { return Theme.near.opacity(0.7) }
        return Theme.rule
    }
}

/// The color ring on the right stick: three bands of seven sectors, darker
/// anticlockwise and brighter clockwise, turned as its arrangement says.
/// Each mode is named round the outside, the key's own marked, and the gap
/// where the darkest and brightest would meet says so.
struct RingView: View {
    /// Inside out, each darkest first, as `pie.sectors` are.
    let rings: [[Target]]
    let pie: RingPie
    let stick: Stick
    /// The chord in the middle: the plain triad, or what is kept.
    let centre: (title: String, detail: String)

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let middle = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            // Room round the outside for the modes' names.
            let outer = size / 2 - 26
            let inner = outer * 0.3
            let band = (outer - inner) / CGFloat(max(1, rings.count))
            ZStack {
                ForEach(Array(rings.enumerated()), id: \.offset) { ring, cells in
                    ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                        let from = inner + band * CGFloat(ring)
                        RingSector(bearing: cell.bearing, span: RingPie.sectorSpan, inner: from + 1, outer: from + band - 1)
                            .fill(fill(cell))
                        RingSector(bearing: cell.bearing, span: RingPie.sectorSpan, inner: from + 1, outer: from + band - 1)
                            .stroke(stroke(cell), style: StrokeStyle(lineWidth: cell.isKept ? 2.5 : 1,
                                                                     dash: cell.fit == .borrowed ? [3, 2] : []))
                    }
                }
                // The key's own mode: its sector edged on the outside.
                ForEach(pie.sectors.filter(\.isOwn), id: \.bearing) { sector in
                    RingSector(bearing: sector.bearing, span: RingPie.sectorSpan - 2, inner: outer + 2, outer: outer + 5)
                        .fill(Theme.chord)
                }
                Circle()
                    .fill(Theme.raised.opacity(0.6))
                    .frame(width: inner * 2 - 4, height: inner * 2 - 4)
                    .position(middle)
                StickDot(stick: stick, middle: middle, radius: outer, accent: Theme.chord)
                VStack(spacing: 1) {
                    Text(centre.title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Text(centre.detail)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.secondary)
                }
                .foregroundStyle(Theme.text)
                .position(middle)
                ForEach(Array(rings.enumerated()), id: \.offset) { ring, cells in
                    ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                        Text(cell.name)
                            .font(.system(size: ring == 0 ? 11 : 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(cell.isAimed ? Color.black : Theme.text)
                            .italic(cell.fit == .borrowed)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .frame(width: band * 1.6)
                            .position(point(middle, bearing: cell.bearing,
                                            distance: inner + band * (CGFloat(ring) + 0.5)))
                    }
                }
                // The modes, named round the outside.
                ForEach(pie.sectors, id: \.bearing) { sector in
                    VStack(spacing: 0) {
                        Text(sector.mode.displayName)
                            .font(.system(size: 10, weight: sector.isOwn ? .bold : .medium))
                        if sector.isOwn {
                            Text("key's own")
                                .font(.system(size: 8, weight: .semibold))
                        }
                    }
                    .foregroundStyle(sector.isOwn ? Theme.chord : Theme.secondary)
                    .lineLimit(1)
                    .fixedSize()
                    .position(point(middle, bearing: sector.bearing, distance: outer + 16))
                }
                // The gap: where the ring ends, brightest on one side, darkest on the other.
                VStack(spacing: 1) {
                    Text("ring ends")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                    Text("\(pie.sectors.last!.mode.displayName) | \(pie.sectors.first!.mode.displayName)")
                        .font(.system(size: 8, weight: .medium))
                }
                .foregroundStyle(Theme.faint)
                .fixedSize()
                .position(point(middle, bearing: pie.gap, distance: inner + (outer - inner) * 0.55))
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func fill(_ cell: Target) -> Color {
        if cell.isAimed { return Theme.chord }
        if cell.isNear { return Theme.near.opacity(0.22) }
        if cell.fit == .borrowed { return Theme.borrowed.opacity(0.1) }
        return Theme.panel
    }

    private func stroke(_ cell: Target) -> Color {
        if cell.isKept { return Theme.chord }
        if cell.fit == .borrowed { return Theme.borrowed.opacity(0.7) }
        return Theme.rule
    }
}

/// A sector of a ring, centred on `bearing`.
struct RingSector: Shape {
    let bearing: Double
    let span: Double
    let inner: CGFloat
    let outer: CGFloat

    func path(in rect: CGRect) -> Path {
        let middle = CGPoint(x: rect.midX, y: rect.midY)
        // SwiftUI's angles start at the right and turn clockwise; a bearing
        // starts at the top.
        let start = Angle(degrees: bearing - span / 2 - 90)
        let end = Angle(degrees: bearing + span / 2 - 90)
        var path = Path()
        path.addArc(center: middle, radius: outer, startAngle: start, endAngle: end, clockwise: false)
        path.addArc(center: middle, radius: inner, startAngle: end, endAngle: start, clockwise: true)
        path.closeSubpath()
        return path
    }
}
