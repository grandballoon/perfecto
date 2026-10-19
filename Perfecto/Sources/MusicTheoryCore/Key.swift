public struct Key: Equatable, Hashable, Codable, Sendable {
    public let root: PitchClass
    public let scale: ScaleType

    public init(root: PitchClass, scale: ScaleType) {
        self.root = root
        self.scale = scale
    }
}

extension Key {
    /// Whether `note`, a MIDI note, is a note of the key.
    public func has(_ note: Int) -> Bool {
        scale.intervals.contains(((note - root.rawValue) % 12 + 12) % 12)
    }

    /// The note of the key nearest `pitch`, a MIDI note and any part of a
    /// semitone past it; of two as near, the lower. It is where a pitch
    /// that can be anywhere is in tune.
    public func note(nearest pitch: Double) -> Int {
        let middle = Int(pitch.rounded(.down))
        // No scale has a gap of more than three semitones.
        let near = (middle - 3...middle + 4).filter(has)
        return near.min { abs(Double($0) - pitch) < abs(Double($1) - pitch) } ?? middle
    }
}
