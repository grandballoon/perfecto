/// The slide divided into equal bands, counted from the bottom of the key:
/// how a finger's place on a key is read as one of several things.
enum SlideBands {
    /// How far past the edge of its band a finger must go to leave it, as a
    /// share of the slide. A finger resting on an edge would otherwise go
    /// back and forth between the two bands.
    static var hold: Float { 0.04 }

    /// The band of `count` a finger at `slide` is in, given the band it was
    /// in before (`current`).
    static func band(at slide: Float, of count: Int, from current: Int?) -> Int {
        let place = slide.clamped(to: 0...1) * Float(count)
        if let current, (0..<count).contains(current) {
            let reach = hold * Float(count)
            if place >= Float(current) - reach, place <= Float(current + 1) + reach { return current }
        }
        return min(Int(place), count - 1)
    }
}

/// The slide as it plays a chord's inversion: the middle of the key is the
/// inversion as set, and each band above it rolls the chord a step further
/// up (`Inversion`), each band below it a step further down. So where a key
/// is struck is how its chord is rolled, and a finger sliding up a held key
/// rolls the chord up through its inversions.
enum InversionSlide {
    /// The steps a finger at the top of a key rolls the chord up, and one
    /// at the bottom down: an octave of a four-note chord.
    static let reach = 4

    /// The steps a finger at `slide` rolls the chord, given the steps it
    /// did before (`current`); 0 for a key with no place on it.
    static func steps(at slide: Float?, from current: Int?) -> Int {
        guard let slide else { return 0 }
        return SlideBands.band(at: slide, of: 2 * reach + 1, from: current.map { $0 + reach }) - reach
    }
}
