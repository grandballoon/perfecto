/// Names one sounding note, from its start to its end. Whoever starts a note
/// chooses its id, so ending it never depends on what else is sounding, and
/// two notes of the same pitch (two layers playing middle C) stay two notes.
struct NoteID: Hashable, Sendable {
    private let serial: UInt64

    @MainActor private static var last: UInt64 = 0

    /// An id no note has had.
    @MainActor
    static func next() -> NoteID {
        last += 1
        return NoteID(serial: last)
    }
}

/// Something that sounds notes: the audio engine, MIDI. Chords are turned
/// into notes before they get here (`NotePlayer`), so every note sink hears
/// the same notes and none of them knows what a chord or a strum is.
///
/// Contract:
/// - `noteOn` starts a note under an id that no sounding note has. Notes
///   already sounding carry on: nothing is replaced.
/// - `noteOff` ends that note and no other. An id that is unknown, or whose
///   note has already ended, is ignored.
/// - `note` is a MIDI note in `Voicing.midiRange`.
/// - A sink that cannot sound every note at once (a fixed number of voices)
///   chooses which to give up; the sender does not need to know.
@MainActor
protocol NoteSink: AnyObject {
    func noteOn(_ id: NoteID, note: Int)
    func noteOff(_ id: NoteID)
}
