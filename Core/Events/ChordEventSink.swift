/// The inputs that fully determine a chord's notes (given the previous
/// voicing): what was asked for, in which key, and how it was voiced. Carried
/// on every `ChordEvent` so a sink that needs the chord's meaning (ChordLink)
/// reads it from the event instead of reconstructing it from app state.
struct ChordContext: Equatable {
    let key: Key
    let spec: ChordSpec
    let octave: Int
    let inversion: Inversion
    let voiceLeading: Bool

    /// The notes this context produces, voice-led from `previous` when enabled.
    func voicing(after previous: Voicing?) -> Voicing {
        computeVoicing(key: key, spec: spec, inversion: inversion, octave: octave,
                       voiceLeading: voiceLeading, previousVoicing: previous)
    }
}

/// How a chord's notes are started.
enum Articulation: Equatable {
    /// All notes at once.
    case block
    /// One note at a time, low to high, `interval` seconds apart.
    case strum(interval: Double)

    /// Seconds after the event at which the note at `index` (low to high) starts.
    func onset(ofNote index: Int) -> Double {
        switch self {
        case .block:               return 0
        case let .strum(interval): return Double(index) * interval
        }
    }
}

/// One thing to sound: the notes, how to start them, and the chord they came
/// from. Single notes (a lead note, one arpeggio step) carry the context of
/// the chord they belong to.
struct ChordEvent: Equatable {
    let voicing: Voicing
    let articulation: Articulation
    let context: ChordContext
}

/// Decouples chord-event producers (performance modes) from consumers (audio,
/// MIDI, ChordLink). Every sink receives the same events and knows nothing
/// about the others or about app state.
///
/// Contract:
/// - `playChord` replaces whatever the sink is sounding: the sink ends its
///   previous notes before starting the new ones, so a producer may send
///   `playChord` twice in a row without `stopChord` in between.
/// - `stopChord` ends the current notes, including any not yet started by a
///   strum. It may be called when nothing is sounding.
/// - All notes are in `Voicing.midiRange` (the `Voicing` invariant).
@MainActor
protocol ChordEventSink: AnyObject {
    func playChord(_ event: ChordEvent)
    func stopChord()
}

/// Starts `notes` at their `articulation` onsets, calling `noteOn(index, note)`
/// for each. Block chords start synchronously and return nil; a strum returns
/// the task driving it, which the caller cancels when the chord is replaced or
/// stopped. Shared by every sink that sounds notes, so they all strum alike.
@MainActor
func startNotes(_ notes: [Int], _ articulation: Articulation,
                noteOn: @escaping @MainActor (Int, Int) -> Void) -> Task<Void, Never>? {
    guard case .strum = articulation, notes.count > 1 else {
        for (i, note) in notes.enumerated() { noteOn(i, note) }
        return nil
    }
    return Task { @MainActor in
        for (i, note) in notes.enumerated() {
            let wait = articulation.onset(ofNote: i) - articulation.onset(ofNote: max(i - 1, 0))
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard !Task.isCancelled else { return }
            noteOn(i, note)
        }
    }
}
