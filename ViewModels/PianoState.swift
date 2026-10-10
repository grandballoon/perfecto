import Foundation
import Observation

/// A part of the app that sounds notes, as the piano tells them apart: each
/// has a color of its own there.
enum PianoSource: CaseIterable, Sendable {
    /// The chord keys, as their notes are sounded (one at a time under the
    /// arpeggiator).
    case keys
    /// The timeline's layers: the loops and the sequence.
    case layers
    /// The solo strip.
    case solo
    /// The Tonnetz.
    case tonnetz

    var displayName: String {
        switch self {
        case .keys:    return "Chord keys"
        case .layers:  return "Loops and sequence"
        case .solo:    return "Solo strip"
        case .tonnetz: return "Tonnetz"
        }
    }
}

/// The piano: the 88 keys along the bottom of the screen, which light up
/// with the notes the rest of the app is sounding, each source in its own
/// color, so that whatever is played can be read as a pianist would play it.
///
/// It is a display, not an instrument. It hears notes the way the audio
/// and MIDI do, as a `NoteSink` on each line of notes (`line(_:)`), so it
/// knows nothing of chords, modes or effects and shows exactly the notes
/// that are sounded. A line of notes that should be seen on it is given one
/// more sink where its `NotePlayer` is made.
@Observable
@MainActor
final class PianoState {

    var isOn = false {
        didSet {
            guard isOn != oldValue else { return }
            logger?.log(.piano_switched(isOn: isOn))
        }
    }

    /// The sources whose notes are lit.
    private(set) var lit = Set(PianoSource.allCases)

    func light(_ source: PianoSource, _ isLit: Bool) {
        if isLit { lit.insert(source) } else { lit.remove(source) }
    }

    private struct Sounding {
        let source: PianoSource
        let note: Int
    }

    /// The notes started and not yet ended, whether or not they are lit.
    private var sounding: [NoteID: Sounding] = [:]

    private let logger: (any Logger)?

    init(logger: (any Logger)? = nil) {
        self.logger = logger
    }

    /// The sources sounding each note that is lit, in `PianoSource`'s
    /// order. A note no lit source is sounding has no entry.
    var lights: [Int: [PianoSource]] {
        var sources: [Int: Set<PianoSource>] = [:]
        for held in sounding.values where lit.contains(held.source) {
            sources[held.note, default: []].insert(held.source)
        }
        return sources.mapValues { held in PianoSource.allCases.filter(held.contains) }
    }

    /// The sink that shows `source`'s notes on the piano, to put beside the
    /// sinks that sound them.
    ///
    /// A note is lit when it is sent, not at the moment it is stamped with:
    /// what the clock plays is seen its lead (`NotePlayer.sequencedLead`)
    /// before it is heard, which is too little to see.
    func line(_ source: PianoSource) -> any NoteSink {
        PianoLine(piano: self, source: source)
    }

    fileprivate func started(_ id: NoteID, note: Int, by source: PianoSource) {
        sounding[id] = Sounding(source: source, note: note)
    }

    fileprivate func ended(_ id: NoteID) {
        sounding[id] = nil
    }
}

/// One source's notes on their way to the piano.
@MainActor
private final class PianoLine: NoteSink {
    private let piano: PianoState
    private let source: PianoSource

    init(piano: PianoState, source: PianoSource) {
        self.piano = piano
        self.source = source
    }

    func noteOn(_ id: NoteID, note: Int, sound: NoteSound, at time: TimeInterval) {
        piano.started(id, note: note, by: source)
    }

    func noteChange(_ id: NoteID, sound: NoteSound, at time: TimeInterval) {}

    func noteOff(_ id: NoteID, at time: TimeInterval) {
        piano.ended(id)
    }
}
