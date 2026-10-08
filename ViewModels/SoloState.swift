import CoreGraphics
import Observation

/// Where the solo strip sits on the play screen.
enum SoloPlacement: CaseIterable {
    /// Under the chord keys, which give up some of their height to it.
    /// Where the screen has room to spare beside the keys (a phone on its
    /// side, with the keys in half of it), the strip takes that instead.
    case underKeys
    /// Upright along the trailing edge of the chord keys, which give up
    /// some of their width.
    case besideKeys
    /// In the chord colors' place, so the two cannot be played together.
    case colors

    var displayName: String {
        switch self {
        case .underKeys:  return "Under"
        case .besideKeys: return "Beside"
        case .colors:     return "Colors"
        }
    }
}

/// What the solo strip needs from whatever plays the chords.
@MainActor
protocol SoloHost: AnyObject {
    /// The chord the strip is played over.
    var soloChord: ChordContext { get }
    /// The sound a note of the strip is played with.
    var soloSound: NoteSound { get }
}

/// The solo strip: a line of cells beside the chord keys, each a note that
/// fits the chord being played, for runs on top of it with no wrong notes.
///
/// The cells are the solo scale of the host's chord (`soloNotes`), ascending
/// from the key's tonic in the octave the chords are built in, so a cell
/// stays about where it was when the chord changes. The strip is one voice:
/// it sounds through a sink of its own, beside the keys' chord, and by the
/// keys' own contract (the most recent press sounds; lifting it hands the
/// note back to the cell held beneath it). A note being held rings on when
/// the chord changes under it.
@Observable
@MainActor
final class SoloState {

    var isOn = false {
        didSet {
            guard isOn != oldValue else { return }
            if !isOn { release(held) }
            logger?.log(.solo_switched(isOn: isOn))
            onArrange?()
        }
    }

    var placement: SoloPlacement = .underKeys {
        didSet {
            guard placement != oldValue else { return }
            release(held)
            onArrange?()
        }
    }

    /// Whether the strip is where the chord colors would be.
    var takesColorsPlace: Bool { isOn && placement == .colors }

    /// Where the strip is by the chord keys, while it is on and there.
    var placementByKeys: SoloPlacement? { isOn && placement != .colors ? placement : nil }

    /// Called when the strip is switched on or off, or moved: the screen is
    /// laid out anew.
    @ObservationIgnored var onArrange: (() -> Void)?

    /// The strip's height under the chord keys, as a share of the screen's:
    /// what the keys give up. The handle between them changes it.
    private(set) var share: CGFloat = 0.22
    static let shareRange: ClosedRange<CGFloat> = 0.12...0.36

    func resize(to share: CGFloat) {
        self.share = share.clamped(to: Self.shareRange)
    }

    /// The cells that are down, oldest first; the last is the one that sounds.
    private(set) var held: [Int] = []

    @ObservationIgnored weak var host: (any SoloHost)?

    private let sink: (any ChordEventSink)?
    private let logger: (any Logger)?

    /// `sink` sounds the strip's notes, one at a time; a sink that is a
    /// `SoundControl` is given each note's sound. Without one the strip is silent.
    init(sink: (any ChordEventSink)? = nil, logger: (any Logger)? = nil) {
        self.sink = sink
        self.logger = logger
    }

    // MARK: – Notes

    /// The notes of the strip's first `count` cells, low to high. Fewer
    /// where MIDI's range ends first.
    func notes(_ count: Int) -> [SoloNote] {
        guard let chord = host?.soloChord else { return [] }
        let tonic = chord.key.root.rawValue + (chord.octave + 1) * 12
        return soloNotes(key: chord.key, spec: chord.spec, from: tonic, count: count)
    }

    // MARK: – Cells

    func press(cell: Int) {
        held.append(cell)
        sound(cell)
    }

    /// Cells lifted together. They leave as one step, so the note is handed
    /// back only to a cell that is still down afterwards.
    func release(_ cells: [Int]) {
        guard let active = held.last else { return }
        for cell in cells {
            if let index = held.lastIndex(of: cell) { held.remove(at: index) }
        }
        guard held.last != active else { return }
        if let resumed = held.last {
            sound(resumed)
        } else {
            sink?.stopChord()
        }
    }

    /// One cell change: `old` went up and `new` came down (either may be
    /// nil). The new cell is pressed before the old one is released, so a
    /// finger sliding along the strip plays a run with no gaps in it.
    func movePointer(from old: Int?, to new: Int?) {
        guard old != new else { return }
        if let new { press(cell: new) }
        if let old { release([old]) }
    }

    /// Sounds the note of `cell` in place of the one sounding. A cell past
    /// the end of MIDI's range has no note and ends it.
    private func sound(_ cell: Int) {
        guard let host, let note = notes(cell + 1).dropFirst(cell).first else {
            sink?.stopChord()
            return
        }
        (sink as? any SoundControl)?.startNotes(in: host.soloSound)
        sink?.playChord(ChordEvent(voicing: Voicing(notes: [note.note]), articulation: .block,
                                   context: host.soloChord))
        logger?.log(.solo_note_played(note: note.note))
    }
}
