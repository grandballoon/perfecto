/// Names one sounding note, from its start to its end. Whoever starts a note
/// chooses its id, so ending it never depends on what else is sounding, and
/// two notes of the same pitch (two layers playing middle C) stay two notes.
struct NoteID: Hashable, Sendable {
    private let serial: UInt64

    /// The id as a number, for a sink that names its notes by one.
    var number: UInt64 { serial }

    @MainActor private static var last: UInt64 = 0

    /// An id no note has had.
    @MainActor
    static func next() -> NoteID {
        last += 1
        return NoteID(serial: last)
    }
}

/// The sound a note is played with: which preset, and how much of each
/// sound effect. A note carries its own, so a loop keeps the sound it was
/// played with while the keys play another over it.
struct NoteSound: Equatable, Sendable {
    var preset = SynthPreset.initial
    var filter = FilterSettings()
    var chorus = ChorusSettings()
    var reverb = ReverbSettings()
}

extension NoteSound {
    init(preset: SynthPreset, effects: NoteEffects) {
        self.init(preset: preset, filter: effects.filter, chorus: effects.chorus, reverb: effects.reverb)
    }
}

/// A line of notes whose sound can be set: every note it starts takes the
/// sound, and a change reaches the notes it is holding.
@MainActor
protocol SoundControl: AnyObject {
    var sound: NoteSound { get set }
    /// Sets the sound for the notes started from now on. Notes being held
    /// keep theirs: for a new chord, whose sound is not the last one's.
    func startNotes(in sound: NoteSound)
}

/// Something that sounds notes: the audio engine, MIDI. Chords are turned
/// into notes before they get here (`NotePlayer`), so every note sink hears
/// the same notes and none of them knows what a chord or a strum is.
///
/// Contract:
/// - `noteOn` starts a note under an id that no sounding note has, in the
///   sound given. Notes already sounding carry on: nothing is replaced.
/// - `noteChange` changes the effects of a note being held (its preset is
///   fixed when it starts). A sink glides to them; one with no sound of its
///   own (MIDI) ignores them.
/// - `noteOff` ends that note and no other. An id that is unknown, or whose
///   note has already ended, is ignored.
/// - `note` is a MIDI note in `Voicing.midiRange`.
/// - A sink that cannot sound every note at once (a fixed number of voices)
///   chooses which to give up; the sender does not need to know.
@MainActor
protocol NoteSink: AnyObject {
    func noteOn(_ id: NoteID, note: Int, sound: NoteSound)
    func noteChange(_ id: NoteID, sound: NoteSound)
    func noteOff(_ id: NoteID)
}
