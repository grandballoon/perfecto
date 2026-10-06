import CoreGraphics

/// What one finger's movement did to the chord keys. A key is pressed when
/// its first finger arrives and released when its last finger leaves, so a
/// second finger on a key that is already down changes nothing.
struct ChordKeyChange: Equatable {
    var released: Degree? = nil
    var pressed: Degree? = nil
}

/// Where a finger is on the key it plays.
struct ChordKeySlide: Equatable {
    /// The share of a key's height, at its top and at its bottom, where a
    /// finger already reads as all the way up or down. A fingertip cannot
    /// reach a key's very edge without leaving it.
    static var margin: CGFloat { 0.15 }

    var key: Degree
    /// How far up the key the finger is: 0 at the bottom, 1 at the top.
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

/// Which finger is on which chord key, for a surface whose keys sit at
/// `frames`. This is the one place fingers become keys: every chord layout
/// gets several fingers and sliding from it, and `PerformanceState` only ever
/// hears about keys, and about where on its key a finger is (`slide`).
///
/// A finger plays the key it is on, or the nearest key within `reach` of it.
/// Further out it keeps the key it had, so sliding across the space between
/// two keys never drops the chord.
struct ChordKeyTouches<Touch: Hashable> {
    /// How far outside a key a finger still plays it. Covers the gaps between
    /// adjacent keys in the row and grid layouts.
    static var reach: CGFloat { 8 }

    var frames: [Degree: CGRect] = [:]
    private var keys: [Touch: Degree] = [:]

    /// A finger landed at, or moved to, `point`.
    mutating func touch(_ touch: Touch, at point: CGPoint) -> ChordKeyChange {
        let old = keys[touch]
        let new = key(at: point) ?? old
        guard old != new else { return ChordKeyChange() }
        keys[touch] = new
        return ChordKeyChange(released: old.flatMap { isDown($0) ? nil : $0 },
                              pressed: new.flatMap { fingers(on: $0) == 1 ? $0 : nil })
    }

    /// Where on its key the finger `touch` is, now that it is at `point`; nil
    /// while it plays no key. A finger that has left its key and kept it
    /// reads as at the edge it left by.
    func slide(of touch: Touch, at point: CGPoint) -> ChordKeySlide? {
        guard let key = keys[touch], let frame = frames[key], frame.height > 0 else { return nil }
        let up = (frame.maxY - point.y) / frame.height
        return ChordKeySlide(key: key, height: ChordKeySlide.height(at: up))
    }

    /// Fingers lifted together. Returns the keys that no finger holds any more.
    mutating func lift(_ touches: some Sequence<Touch>) -> [Degree] {
        let lifted = Set(touches.compactMap { keys.removeValue(forKey: $0) })
        return lifted.filter { !isDown($0) }
    }

    /// Every finger is gone (the surface went away). Returns the keys that were down.
    mutating func liftAll() -> [Degree] {
        lift(Array(keys.keys))
    }

    private func isDown(_ degree: Degree) -> Bool { fingers(on: degree) > 0 }

    private func fingers(on degree: Degree) -> Int {
        keys.values.count { $0 == degree }
    }

    private func key(at point: CGPoint) -> Degree? {
        let nearest = frames
            .map { (degree: $0.key, distance: Self.distance(from: point, to: $0.value)) }
            .min { $0.distance < $1.distance }
        guard let nearest, nearest.distance <= Self.reach else { return nil }
        return nearest.degree
    }

    /// Distance from `point` to the nearest edge of `rect`; zero inside it.
    private static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }
}
