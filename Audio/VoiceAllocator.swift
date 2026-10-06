/// Decides which voice plays each note, for a sink with a fixed number of
/// voices. It only keeps the books: the caller starts and releases the
/// voices it names.
///
/// A new note takes the voice that has been free longest, so the voices
/// released most recently are left to ring out; a chord change overlaps the
/// old chord's release with the new chord's attack, as on an instrument.
/// With every voice held, the note takes over the one held longest.
struct VoiceAllocator {

    private struct Voice {
        /// The note the voice is holding; nil once released (or never used).
        var note: NoteID?
        /// When the voice last started or was released, as a count of such
        /// changes; 0 for a voice never used.
        var changed = 0
    }

    private var voices: [Voice]
    private var changes = 0

    init(voices count: Int) {
        voices = Array(repeating: Voice(), count: count)
    }

    /// The voice to start `id` on. `stolen` is true when every voice was
    /// held, and the note that had this one is forgotten: ending it later
    /// does nothing.
    mutating func start(_ id: NoteID) -> (voice: Int, stolen: Bool) {
        let free = voices.indices.filter { voices[$0].note == nil }
        let candidates = free.isEmpty ? Array(voices.indices) : free
        let voice = candidates.min { voices[$0].changed < voices[$1].changed }!
        changes += 1
        voices[voice] = Voice(note: id, changed: changes)
        return (voice, free.isEmpty)
    }

    /// The voice to release for `id`; nil if the note is not sounding.
    mutating func end(_ id: NoteID) -> Int? {
        guard let voice = voices.firstIndex(where: { $0.note == id }) else { return nil }
        changes += 1
        voices[voice] = Voice(note: nil, changed: changes)
        return voice
    }

    /// Forgets every note, returning the voices to release.
    mutating func endAll() -> [Int] {
        let held = voices.indices.filter { voices[$0].note != nil }
        for voice in held {
            changes += 1
            voices[voice] = Voice(note: nil, changed: changes)
        }
        return held
    }
}
