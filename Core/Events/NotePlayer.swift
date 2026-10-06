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
/// A player has a sound, which every note it starts takes. The keys' player
/// follows the effects as they are played (it is an `EffectsControl`); a
/// layer's is given the sound of each of its chords.
@MainActor
final class NotePlayer: ChordEventSink, SoundControl, EffectsControl {

    var sound = NoteSound() {
        didSet {
            guard sound != oldValue, !isStartingAfresh else { return }
            for id in sounding {
                for sink in sinks { sink.noteChange(id, sound: sound) }
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
    /// The notes started and not yet ended, in the order they started.
    private var sounding: [NoteID] = []
    /// The notes of a strum still to come.
    private var strum: [ClockCall] = []

    init(_ sinks: [any NoteSink], clock: any ClockTickable) {
        self.sinks = sinks
        self.clock = clock
    }

    func playChord(_ event: ChordEvent) {
        stopChord()
        for (i, note) in event.voicing.notes.enumerated() {
            let onset = event.articulation.onset(ofNote: i)
            if onset > 0 {
                strum.append(clock.after(seconds: onset) { [weak self] in self?.start(note) })
            } else {
                start(note)
            }
        }
    }

    func stopChord() {
        for call in strum { call.cancel() }
        strum = []
        for id in sounding {
            for sink in sinks { sink.noteOff(id) }
        }
        sounding = []
    }

    private func start(_ note: Int) {
        let id = NoteID.next()
        sounding.append(id)
        for sink in sinks { sink.noteOn(id, note: note, sound: sound) }
    }

    func setFilter(_ played: FilterSettings) { sound.filter = played }
    func setChorus(_ played: ChorusSettings) { sound.chorus = played }
    func setReverb(_ played: ReverbSettings) { sound.reverb = played }
}
