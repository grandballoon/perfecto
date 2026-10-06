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
@MainActor
final class NotePlayer: ChordEventSink {

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
        for sink in sinks { sink.noteOn(id, note: note) }
    }
}
