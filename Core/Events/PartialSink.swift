import Foundation

/// How one partial of a note is to sound: how strong (a share of its sound's
/// level, as a sawtooth's nth is 1/n), how far from its place in the
/// harmonic series in Hz, and how it swings in strength: by `depth`, from 0
/// (steady) to 1 (down to silence and back), `rate` times a second.
struct PartialSetting: Equatable, Sendable {
    var strength: Float
    var offset: Float = 0
    var depth: Float = 0
    var rate: Float = 0

    static let silent = PartialSetting(strength: 0)
}

/// The sounds made of partials that a `PartialSink` has: each its own
/// envelope, the partials being set note by note.
enum PartialSound: CaseIterable, Sendable {
    /// An organ's: up in 30 ms, full while held, gone 150 ms after, with no
    /// decay, so a beat has all the time it needs to be heard.
    case held
    /// A piano's, near enough: struck, and dying away while held.
    case struck
}

/// Something that sounds notes whose partials are set one by one: the
/// audio kernel. It is the Dissonance Lab's way to the sound, beside the
/// `NoteSink`s, which know nothing of partials.
///
/// Contract:
/// - `partialNoteOn` starts a note under an id no sounding note has, its
///   partials as its sound starts them, `bend` semitones from `note` (a MIDI
///   note), `velocity` (0...1) strong and at `pan` (-1 left, 1 right).
/// - `partialChange` sets one partial of a note being held, numbered from 0
///   (the fundamental); one sent at a note's start sets it from its first
///   sound. A change is glided to, never jumped to.
/// - `partialBend` glides a note being held to `bend` semitones from its note.
/// - `partialNoteOff` ends that note and no other.
/// - Each call says when it takes effect, as `NoteSink`'s do.
@MainActor
protocol PartialSink: AnyObject {
    /// The most partials a note has.
    var partialCount: Int { get }
    func partialNoteOn(_ id: NoteID, note: Int, bend: Float, sound: PartialSound, velocity: Float,
                       pan: Float, at time: TimeInterval)
    func partialChange(_ id: NoteID, partial: Int, to setting: PartialSetting, at time: TimeInterval)
    func partialBend(_ id: NoteID, to bend: Float, at time: TimeInterval)
    func partialNoteOff(_ id: NoteID, at time: TimeInterval)
}
