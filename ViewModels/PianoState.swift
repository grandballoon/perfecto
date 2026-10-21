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
    /// The pads, played or in sequence.
    case pads
    /// The Trautonium's bars.
    case trautonium
    /// The chord–scale tree.
    case tree
    /// The Dissonance Lab's two notes, at the nearest key.
    case lab

    var displayName: String {
        switch self {
        case .keys:    return "Chord keys"
        case .layers:  return "Loops and sequence"
        case .solo:    return "Solo strip"
        case .tonnetz: return "Tonnetz"
        case .pads:    return "Pads"
        case .trautonium: return "Trautonium"
        case .tree:       return "Chord–scale tree"
        case .lab:        return "Dissonance Lab"
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
/// that are sounded, a note that slides on the key it has slid to. A line
/// of notes that should be seen on it is given one more sink where its
/// `NotePlayer` is made.
///
/// It is also what of it is in view (`span`, zoomed by a pinch and moved
/// by a drag) and whether it has the whole screen (`isExpanded`), so the
/// strip and the whole screen show the same keys.
@Observable
@MainActor
final class PianoState {

    var isOn = false {
        didSet {
            guard isOn != oldValue else { return }
            logger?.log(.piano_switched(isOn: isOn))
            if !isOn { isExpanded = false }
        }
    }

    /// Whether the piano has the whole screen, over whatever is on it,
    /// rather than the strip along its bottom.
    var isExpanded = false {
        didSet {
            guard isExpanded != oldValue else { return }
            logger?.log(.piano_expanded(isExpanded: isExpanded))
        }
    }

    /// The white keys in view.
    var span = PianoSpan.whole

    /// The sources whose notes are lit.
    private(set) var lit = Set(PianoSource.allCases)

    func light(_ source: PianoSource, _ isLit: Bool) {
        if isLit { lit.insert(source) } else { lit.remove(source) }
    }

    private struct Sounding {
        let source: PianoSource
        /// The note as it was started, and the key it is at now: a note
        /// that is bent is shown on the key nearest where it has got to.
        let struck: Int
        var note: Int
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

    fileprivate func started(_ id: NoteID, note: Int, bend: Float, by source: PianoSource) {
        sounding[id] = Sounding(source: source, struck: note, note: note + Int(bend.rounded()))
    }

    fileprivate func bent(_ id: NoteID, by bend: Float) {
        guard let held = sounding[id] else { return }
        let note = held.struck + Int(bend.rounded())
        if note != held.note { sounding[id]?.note = note }
    }

    fileprivate func ended(_ id: NoteID) {
        sounding[id] = nil
    }
}

/// The part of the piano in view, in white keys: `count` of them across,
/// from `start` white keys above A0 (a fraction cuts a key at the edge).
/// It is always within the piano's 52 white keys, and never closer than
/// `fewest` of them, about an octave's.
struct PianoSpan: Equatable, Sendable {
    /// A piano's white keys, A0 to C8.
    static let whites = 52.0
    static let fewest = 7.0
    static let whole = PianoSpan(start: 0, count: whites)

    let start: Double
    let count: Double

    init(start: Double, count: Double) {
        self.count = count.clamped(to: Self.fewest...Self.whites)
        self.start = start.clamped(to: 0...(Self.whites - self.count))
    }

    /// This span `scale` times closer (2 shows half as many keys), moved so
    /// that what was at `from` is at `to`, each a share of the width from
    /// the low end: a pinch, whose fingers move as they spread, or with a
    /// scale of 1 a drag.
    func moved(by scale: Double = 1, from: Double, to: Double) -> PianoSpan {
        let held = start + from * count
        let count = PianoSpan(start: 0, count: count / scale).count
        return PianoSpan(start: held - to * count, count: count)
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
        piano.started(id, note: note, bend: sound.bend, by: source)
    }

    func noteChange(_ id: NoteID, sound: NoteSound, at time: TimeInterval) {
        piano.bent(id, by: sound.bend)
    }

    func noteOff(_ id: NoteID, at time: TimeInterval) {
        piano.ended(id)
    }
}
