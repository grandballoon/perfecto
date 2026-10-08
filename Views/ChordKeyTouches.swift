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

/// The chord keys' fingers, changes and slides; the solo strip's cells are
/// tracked by the same rules (`SoloStripView`).
typealias ChordKeyTouches<Touch: Hashable> = KeyTouches<Touch, Degree>
typealias ChordKeyChange = KeyChange<Degree>
typealias ChordKeySlide = KeySlide<Degree>

/// Which finger is on which key, for a surface whose keys sit at `frames`.
/// This is the one place fingers become keys: every chord layout gets
/// several fingers and sliding from it, and `PerformanceState` only ever
/// hears about keys, and about where on its key a finger is (`slide`).
///
/// A finger plays the key it is on, or the nearest key within `reach` of it.
/// Further out it keeps the key it had, so sliding across the space between
/// two keys never drops the chord.
struct KeyTouches<Touch: Hashable, PlayedKey: Hashable> {
    /// How far outside a key a finger still plays it. Covers the gaps between
    /// adjacent keys in the row and grid layouts.
    static var reach: CGFloat { 8 }

    var frames: [PlayedKey: CGRect] = [:]
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
        guard let key = keys[touch], let frame = frames[key], frame.height > 0 else { return nil }
        let up = (frame.maxY - point.y) / frame.height
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
        let nearest = frames
            .map { (key: $0.key, distance: point.distance(to: $0.value)) }
            .min { $0.distance < $1.distance }
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
}
