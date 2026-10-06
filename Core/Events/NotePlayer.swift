/// Plays chords as notes: the one place a `ChordEvent` becomes note-ons and
/// note-offs, for every `NoteSink` alike. It keeps the chord-level contract
/// (`playChord` replaces what is sounding) on behalf of the note sinks, and
/// realizes the articulation, so they all strum alike.
///
/// One player is one line of chords. Players are independent: each ends only
/// the notes it started, so several can sound at once through the same sinks.
@MainActor
final class NotePlayer: ChordEventSink {

    private let sinks: [any NoteSink]
    /// The notes started and not yet ended, in the order they started.
    private var sounding: [NoteID] = []
    /// The rest of a strum still to come.
    private var strum: Task<Void, Never>?

    init(_ sinks: [any NoteSink]) {
        self.sinks = sinks
    }

    func playChord(_ event: ChordEvent) {
        stopChord()
        let notes = event.voicing.notes
        let articulation = event.articulation
        guard case .strum = articulation, notes.count > 1 else {
            for note in notes { start(note) }
            return
        }
        strum = Task { @MainActor [weak self] in
            for (i, note) in notes.enumerated() {
                let wait = articulation.onset(ofNote: i) - articulation.onset(ofNote: max(i - 1, 0))
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                guard !Task.isCancelled else { return }
                self?.start(note)
            }
        }
    }

    func stopChord() {
        strum?.cancel()
        strum = nil
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
