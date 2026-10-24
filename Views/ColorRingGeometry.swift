import CoreGraphics
import SwiftUI

/// Where the color ring's cells are in a frame: a band to each stack height
/// out from the hub, and a sector to each of `ColorRing.modes` clockwise from
/// the darkest at the lower left, the gap between the darkest and the
/// brightest at the bottom of a ring that is not turned. The ring draws its
/// cells by it and reads its finger by it (`ColorRingPad`), so the two
/// cannot disagree. Angles are in degrees clockwise from the top.
struct ColorRingGeometry {
    let center: CGPoint
    /// The hub's radius; inside it is not a cell.
    let hub: CGFloat
    /// The outer edge of the outermost band.
    let outer: CGFloat
    /// Sectors the ring is turned clockwise (`ColorRing.turn`).
    let turn: Int

    /// The sectors take this much of the circle; the rest is the gap.
    static let arc: CGFloat = 300
    static let sectorAngle = arc / CGFloat(ColorRing.modes.count)
    /// Where the darkest sector starts on a ring that is not turned.
    static let start: CGFloat = 180 + (360 - arc) / 2
    /// Room kept round the outside for the modes' names: above and below
    /// them, and beside them, where a name is wider than it is tall.
    static let labelMargin: CGFloat = 12
    static let sideMargin: CGFloat = 16

    static let heights = StackHeight.allCases

    /// How far below the centre a ring that is not turned reaches, in outer
    /// radii: the bottom corners of its first and last sectors, beside the
    /// gap. Its modes' names are higher.
    static let depthBelow = cos((360 - arc) / 2 * .pi / 180)

    /// The ring as large as `size` allows. A ring that is not turned draws
    /// nothing in its gap at the bottom, so it is fitted to what it draws,
    /// its lowest cells on the bottom edge (`fitsGap`); a ring that turns
    /// can have its gap anywhere, so it is fitted as a whole circle.
    init(size: CGSize, turn: Int, fitsGap: Bool = false) {
        if fitsGap {
            let byHeight = (size.height - Self.labelMargin) / (1 + Self.depthBelow)
            outer = max(min(size.width / 2 - Self.sideMargin, byHeight), 1)
            let drawn = (outer + Self.labelMargin) + outer * Self.depthBelow
            center = CGPoint(x: size.width / 2, y: size.height - drawn + Self.labelMargin + outer)
        } else {
            outer = max(min(size.width / 2 - Self.sideMargin, size.height / 2 - Self.labelMargin), 1)
            center = CGPoint(x: size.width / 2, y: size.height / 2)
        }
        hub = outer * 0.17
        self.turn = turn
    }

    var band: CGFloat { (outer - hub) / CGFloat(Self.heights.count) }

    /// Where sector `sector` starts.
    func startAngle(of sector: Int) -> CGFloat {
        Self.start + CGFloat(sector + turn) * Self.sectorAngle
    }

    /// The radii a height's band runs between.
    func radii(of height: StackHeight) -> (inner: CGFloat, outer: CGFloat) {
        let index = CGFloat(Self.heights.firstIndex(of: height)!)
        return (hub + index * band, hub + (index + 1) * band)
    }

    func point(radius: CGFloat, angle: CGFloat) -> CGPoint {
        let t = angle * .pi / 180
        return CGPoint(x: center.x + radius * sin(t), y: center.y - radius * cos(t))
    }

    /// The cell under `point`: its height and sector, or nil in the hub, the
    /// gap or outside the ring.
    func cell(at point: CGPoint) -> (height: StackHeight, sector: Int)? {
        let dx = point.x - center.x, dy = point.y - center.y
        let r = (dx * dx + dy * dy).squareRoot()
        guard r >= hub, r < outer else { return nil }
        let angle = (atan2(dx, -dy) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
        let along = (angle - startAngle(of: 0)).truncatingRemainder(dividingBy: 360)
        let fromStart = along < 0 ? along + 360 : along
        guard fromStart < Self.arc else { return nil }
        let sector = min(Int(fromStart / Self.sectorAngle), ColorRing.modes.count - 1)
        let index = min(Int((r - hub) / band), Self.heights.count - 1)
        return (Self.heights[index], sector)
    }

    /// A cell's outline, its arcs drawn as short straight runs.
    func path(height: StackHeight, sector: Int) -> Path {
        let (r0, r1) = radii(of: height)
        let a0 = startAngle(of: sector), a1 = a0 + Self.sectorAngle
        let runs = 10
        var path = Path()
        path.move(to: point(radius: r1, angle: a0))
        for i in 1...runs { path.addLine(to: point(radius: r1, angle: a0 + (a1 - a0) * CGFloat(i) / CGFloat(runs))) }
        for i in (0...runs).reversed() { path.addLine(to: point(radius: r0, angle: a0 + (a1 - a0) * CGFloat(i) / CGFloat(runs))) }
        path.closeSubpath()
        return path
    }

    /// The middle of a cell, where its name goes.
    func middle(height: StackHeight, sector: Int) -> CGPoint {
        let (r0, r1) = radii(of: height)
        return point(radius: (r0 + r1) / 2, angle: startAngle(of: sector) + Self.sectorAngle / 2)
    }

    /// Outside a sector, where its mode's name goes.
    func modeLabel(sector: Int) -> CGPoint {
        point(radius: outer + Self.labelMargin / 2 + 1, angle: startAngle(of: sector) + Self.sectorAngle / 2)
    }

    /// The two edges of the gap.
    var seam: Path {
        var path = Path()
        for angle in [startAngle(of: 0), startAngle(of: 0) + Self.arc] {
            path.move(to: point(radius: hub, angle: angle))
            path.addLine(to: point(radius: outer, angle: angle))
        }
        return path
    }
}
