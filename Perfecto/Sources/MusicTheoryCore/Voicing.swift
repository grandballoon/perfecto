public struct Voicing: Equatable, Sendable {
    /// MIDI note numbers, sorted low to high, without duplicates, all within
    /// `midiRange`, so every consumer can send them as MIDI data bytes.
    public let notes: [Int]
    public let bassNote: Int?    // optional slash-chord bass, also within `midiRange`

    /// The notes MIDI can carry.
    public static let midiRange = 0...127

    /// Notes outside `midiRange` are moved by octaves into it, keeping their
    /// pitch class: a chord voiced near the top of the range folds its highest
    /// notes down rather than losing them.
    public init(notes: [Int], bassNote: Int? = nil) {
        self.notes = Set(notes.map(Self.fold)).sorted()
        self.bassNote = bassNote.map(Self.fold)
    }

    private static func fold(_ note: Int) -> Int {
        var note = note
        while note > midiRange.upperBound { note -= 12 }
        while note < midiRange.lowerBound { note += 12 }
        return note
    }
}
