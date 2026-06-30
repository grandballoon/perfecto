public struct Voicing: Equatable, Sendable {
    public let notes: [Int]      // MIDI note numbers, sorted low to high
    public let bassNote: Int?    // optional slash-chord bass

    public init(notes: [Int], bassNote: Int? = nil) {
        self.notes = notes.sorted()
        self.bassNote = bassNote
    }
}
