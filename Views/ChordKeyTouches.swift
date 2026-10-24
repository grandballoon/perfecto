import CoreGraphics

/// What one finger's movement did to the keys of a surface. A key is pressed
/// when its first finger arrives and released when its last finger leaves,
/// so a second finger on a key that is already down changes nothing.
struct KeyChange<PlayedKey: Hashable>: Equatable {
    var released: PlayedKey? = nil
    var pressed: PlayedKey? = nil
}

/// Where a finger is on the key it plays.
struct KeySlide<PlayedKey: Hashable>: Equatable {
    /// The share of a key's height, at its top and at its bottom, where a
    /// finger already reads as all the way up or down. A fingertip cannot
    /// reach a key's very edge without leaving it.
    static var margin: CGFloat { 0.15 }

    var key: PlayedKey
    /// How far up the key the finger is: 0 at the bottom, 1 at the top. On a
    /// segment of a ring, up is outwards (`KeyShape.height`).
    var height: Float

    /// The slide of a finger `share` of the way up its key's height.
    static func height(at share: CGFloat) -> Float {
        Float(((share - margin) / (1 - 2 * margin)).clamped(to: 0...1))
    }

    /// The share of a key's height at which a finger reads as `height`.
    static func share(at height: Float) -> CGFloat {
        margin + CGFloat(height) * (1 - 2 * margin)
    }
}

/// The chord keys' fingers, changes and slides; the pads are tracked by
/// the same rules (`PadsView`).
typealias ChordKeyTouches<Touch: Hashable> = KeyTouches<Touch, ChordKey>
typealias ChordKeyChange = KeyChange<ChordKey>
typealias ChordKeySlide = KeySlide<ChordKey>

/// A piece of a ring: what lies between two radii and two angles.
struct RingSegment: Equatable {
    var center: CGPoint
    var radii: ClosedRange<CGFloat>
    /// Where it starts and where it ends, in radians clockwise from the top.
    var angles: ClosedRange<CGFloat>

    /// The point at `angle`, `radius` from the centre.
    func point(at angle: CGFloat, radius: CGFloat) -> CGPoint {
        CGPoint(x: center.x + radius * sin(angle), y: center.y - radius * cos(angle))
    }

    /// Distance from `point` to the segment; zero inside it.
    func distance(from point: CGPoint) -> CGFloat {
        let radius = hypot(point.x - center.x, point.y - center.y)
        var angle = (atan2(point.x - center.x, center.y - point.y) - angles.lowerBound)
            .truncatingRemainder(dividingBy: 2 * .pi)
        if angle < 0 { angle += 2 * .pi }
        if angle <= angles.upperBound - angles.lowerBound {
            return max(radii.lowerBound - radius, 0, radius - radii.upperBound)
        }
        // Beside it, so the nearest of it is on one of its two straight sides.
        return [angles.lowerBound, angles.upperBound]
            .map { point.distance(toLineFrom: self.point(at: $0, radius: radii.lowerBound),
                                  to: self.point(at: $0, radius: radii.upperBound)) }
            .min() ?? .infinity
    }
}

/// Where a key is and what shape it has. Fingers are read against it, so a
/// key is played where it is drawn whatever its shape.
enum KeyShape: Equatable {
    case rect(CGRect)
    /// The circle that fills a square.
    case disc(CGRect)
    case segment(RingSegment)

    /// Distance from `point` to the key; zero on it.
    func distance(from point: CGPoint) -> CGFloat {
        switch self {
        case .rect(let frame): return point.distance(to: frame)
        case .disc(let frame):
            return max(hypot(point.x - frame.midX, point.y - frame.midY) - frame.width / 2, 0)
        case .segment(let segment): return segment.distance(from: point)
        }
    }

    var area: CGFloat {
        switch self {
        case .rect(let frame): return frame.width * frame.height
        case .disc(let frame): return .pi * frame.width * frame.width / 4
        case .segment(let segment):
            let (inner, outer) = (segment.radii.lowerBound, segment.radii.upperBound)
            return (segment.angles.upperBound - segment.angles.lowerBound) / 2 * (outer * outer - inner * inner)
        }
    }

    /// The share of the way up the key that `point` is: from its bottom to
    /// its top, or from the inside of a ring to the outside. Nil for a key
    /// with no height.
    func height(of point: CGPoint) -> CGFloat? {
        switch self {
        case .rect(let frame), .disc(let frame):
            guard frame.height > 0 else { return nil }
            return (frame.maxY - point.y) / frame.height
        case .segment(let segment):
            let depth = segment.radii.upperBound - segment.radii.lowerBound
            guard depth > 0 else { return nil }
            let radius = hypot(point.x - segment.center.x, point.y - segment.center.y)
            return (radius - segment.radii.lowerBound) / depth
        }
    }
}

/// Which finger is on which key, for a surface whose keys sit at `shapes`.
/// This is the one place fingers become keys: every chord layout gets
/// several fingers and sliding from it, and `PerformanceState` only ever
/// hears about keys, and about where on its key a finger is (`slide`).
///
/// A finger plays the key it is on, or the nearest key within `reach` of it.
/// Further out it keeps the key it had, so sliding across the space between
/// two keys never drops the chord. Where keys overlap (a piano's black keys
/// lie over its white ones) it plays the smaller, which is the one on top.
struct KeyTouches<Touch: Hashable, PlayedKey: Hashable> {
    /// How far outside a key a finger still plays it. Covers the gaps between
    /// adjacent keys in the row and grid layouts.
    static var reach: CGFloat { 8 }

    var shapes: [PlayedKey: KeyShape] = [:]
    /// The keys' places on a surface whose keys are all rectangles.
    var frames: [PlayedKey: CGRect] {
        get { shapes.compactMapValues { if case .rect(let frame) = $0 { frame } else { nil } } }
        set { shapes = newValue.mapValues(KeyShape.rect) }
    }
    private var keys: [Touch: PlayedKey] = [:]

    /// A finger landed at, or moved to, `point`.
    mutating func touch(_ touch: Touch, at point: CGPoint) -> KeyChange<PlayedKey> {
        let old = keys[touch]
        let new = key(at: point) ?? old
        guard old != new else { return KeyChange() }
        keys[touch] = new
        return KeyChange(released: old.flatMap { isDown($0) ? nil : $0 },
                         pressed: new.flatMap { fingers(on: $0) == 1 ? $0 : nil })
    }

    /// Where on its key the finger `touch` is, now that it is at `point`; nil
    /// while it plays no key. A finger that has left its key and kept it
    /// reads as at the edge it left by.
    func slide(of touch: Touch, at point: CGPoint) -> KeySlide<PlayedKey>? {
        guard let key = keys[touch], let up = shapes[key]?.height(of: point) else { return nil }
        return KeySlide(key: key, height: KeySlide<PlayedKey>.height(at: up))
    }

    /// Fingers lifted together. Returns the keys that no finger holds any more.
    mutating func lift(_ touches: some Sequence<Touch>) -> [PlayedKey] {
        let lifted = Set(touches.compactMap { keys.removeValue(forKey: $0) })
        return lifted.filter { !isDown($0) }
    }

    /// Every finger is gone (the surface went away). Returns the keys that were down.
    mutating func liftAll() -> [PlayedKey] {
        lift(Array(keys.keys))
    }

    private func isDown(_ key: PlayedKey) -> Bool { fingers(on: key) > 0 }

    private func fingers(on key: PlayedKey) -> Int {
        keys.values.count { $0 == key }
    }

    private func key(at point: CGPoint) -> PlayedKey? {
        let nearest = shapes
            .map { (key: $0.key, distance: $0.value.distance(from: point), area: $0.value.area) }
            .min { ($0.distance, $0.area) < ($1.distance, $1.area) }
        guard let nearest, nearest.distance <= Self.reach else { return nil }
        return nearest.key
    }
}

extension CGPoint {
    /// Distance from this point to the nearest edge of `rect`; zero inside it.
    func distance(to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - x, 0, x - rect.maxX)
        let dy = max(rect.minY - y, 0, y - rect.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }

    /// Distance from this point to the nearest point of the line from
    /// `start` to `end`.
    func distance(toLineFrom start: CGPoint, to end: CGPoint) -> CGFloat {
        let (dx, dy) = (end.x - start.x, end.y - start.y)
        let length = dx * dx + dy * dy
        let along = length > 0 ? (((x - start.x) * dx + (y - start.y) * dy) / length).clamped(to: 0...1) : 0
        return hypot(x - (start.x + along * dx), y - (start.y + along * dy))
    }
}
