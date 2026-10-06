import Foundation

/// Plays chords as notes: the one place a `ChordEvent` becomes note-ons and
/// note-offs, for every `NoteSink` alike. It keeps the chord-level contract
/// (`playChord` replaces what is sounding) on behalf of the note sinks, and
/// realizes the articulation, so they all strum alike.
///
/// A strum's later notes are the clock's to start, each at its own time
/// after the first, so a strum is as even as the clock is.
///
/// One player is one line of chords. Players are independent: each ends only
/// the notes it started, so several can sound at once through the same sinks.
///
/// Every note is stamped with the clock's time when it is started or ended,
/// plus the player's `lead`. A note started from a call of the clock's is
/// stamped with the moment that call was due, so with a lead longer than the
/// clock is ever late, a sink that keeps time (the audio kernel, MIDI) sounds
/// it at exactly that moment and the clock's lateness is never heard. That is
/// for what the clock plays (a layer of the timeline): everything it plays
/// is heard the same short time late and so stays exactly in step. The keys'
/// player has no lead, since a key must sound at once.
///
/// A player has a sound, which every note it starts takes. The keys' player
/// follows the effects as they are played (it is an `EffectsControl`); a
/// layer's is given the sound of each of its chords.
@MainActor
final class NotePlayer: ChordEventSink, SoundControl, EffectsControl {

    var sound = NoteSound() {
        didSet {
            guard sound != oldValue, !isStartingAfresh else { return }
            for note in sounding {
                for sink in sinks { sink.noteChange(note.id, sound: sound(at: note.pan), at: now) }
            }
        }
    }

    /// While set, a change of sound is for the notes to come only.
    private var isStartingAfresh = false

    func startNotes(in sound: NoteSound) {
        isStartingAfresh = true
        self.sound = sound
        isStartingAfresh = false
    }

    private let sinks: [any NoteSink]
    private let clock: any ClockTickable
    /// The notes started and not yet ended, in the order they started,
    /// each with where it sits between left and right.
    private var sounding: [(id: NoteID, pan: Float)] = []

    /// How far to either side a chord's lowest and highest notes sit: low
    /// to the left and high to the right, as at a keyboard, and little
    /// enough that the chord is still one thing in the middle.
    static let spread: Float = 0.3
    /// The notes of a strum still to come.
    private var strum: [ClockCall] = []

    /// How long after the clock's time notes are sounded.
    private let lead: TimeInterval

    /// The lead for what the clock plays: longer than the main thread is
    /// held up in ordinary use, short enough not to be noticed between
    /// pressing Play and hearing the first chord.
    static let sequencedLead: TimeInterval = 0.05

    init(_ sinks: [any NoteSink], clock: any ClockTickable, lead: TimeInterval = 0) {
        self.sinks = sinks
        self.clock = clock
        self.lead = lead
    }

    private var now: TimeInterval { clock.time + lead }

    func playChord(_ event: ChordEvent) {
        stopChord()
        let notes = event.voicing.notes
        for (i, note) in notes.enumerated() {
            // A note alone is in the middle.
            let pan = notes.count > 1 ? Self.spread * (2 * Float(i) / Float(notes.count - 1) - 1) : 0
            let onset = event.articulation.onset(ofNote: i)
            if onset > 0 {
                strum.append(clock.after(seconds: onset) { [weak self] in self?.start(note, pan: pan) })
            } else {
                start(note, pan: pan)
            }
        }
    }

    func stopChord() {
        for call in strum { call.cancel() }
        strum = []
        for note in sounding {
            for sink in sinks { sink.noteOff(note.id, at: now) }
        }
        sounding = []
    }

    private func start(_ note: Int, pan: Float) {
        let id = NoteID.next()
        sounding.append((id, pan))
        for sink in sinks { sink.noteOn(id, note: note, sound: sound(at: pan), at: now) }
    }

    /// The player's sound, for a note at `pan`.
    private func sound(at pan: Float) -> NoteSound {
        var sound = sound
        sound.pan = pan
        return sound
    }

    func setFilter(_ played: FilterSettings) { sound.filter = played }
    func setChorus(_ played: ChorusSettings) { sound.chorus = played }
    func setReverb(_ played: ReverbSettings) { sound.reverb = played }
    func setVocoder(_ played: VocoderSettings) { sound.vocoder = played }
}
