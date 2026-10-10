import CoreGraphics
import Observation

/// The two ways the Tonnetz is shown.
enum TonnetzViewKind: CaseIterable {
    /// The net from above: every triad a triangle, played by pressing it.
    case net
    /// One triad at a time, and the three it can be flipped into.
    case triad

    var displayName: String {
        switch self {
        case .net:   return "NET"
        case .triad: return "TRIAD"
        }
    }
}

/// What of the net a pointer is on: a triangle, or one of its notes. A note
/// is at many places on the net and is the same note at each.
enum TonnetzTarget: Hashable {
    case cell(TonnetzCell)
    case note(PitchClass)
}

/// The Tonnetz's two lines: each sounds by itself, and is a layer of its
/// own in a loop.
enum TonnetzLine {
    /// The triad of the triangle it is at.
    case triads
    /// The notes played by themselves.
    case notes
}

/// What the Tonnetz needs from whatever plays the chords.
@MainActor
protocol TonnetzHost: AnyObject {
    /// The octave the triads and the notes are built in.
    var octave: Int { get }
    /// The sound the Tonnetz is played with.
    var tonnetzSound: NoteSound { get }
    /// `line` started `event`, or fell silent (nil): what a loop being
    /// recorded keeps.
    func tonnetz(_ line: TonnetzLine, played event: ChordEvent?)
}

/// The Tonnetz: triads played from the net of notes (`TonnetzCell`), in no
/// key, and the notes of the net played by themselves.
///
/// It is at one triangle of the net at a time, the triad last played. Both
/// views play it the same way: a triangle pressed is where it is next and
/// sounds for as long as it is held, and a move (P, L, R) is a press of the
/// triangle across one side. It is one line of chords, sounded through a
/// sink of its own beside the keys', and each triad is voiced as near the
/// last as it can be, so a move is heard as the one note that changes.
///
/// A note pressed sounds by itself, whatever triangle the Tonnetz is at:
/// a note of the triad taken apart from it, or one outside it. The notes
/// are a second line through a sink of their own, so they are heard over
/// the triad and neither ends the other.
///
/// While it holds (`holds`), what is pressed stays on when the pointer
/// lifts and is pressed again to end it, so one pointer can leave a triad
/// sounding and add notes to it, or set several notes sounding that make
/// no triangle.
@Observable
@MainActor
final class TonnetzState {

    var view: TonnetzViewKind = .net {
        didSet {
            guard view != oldValue else { return }
            letGo()
            // The net is shown again around wherever the moves have led.
            netCenter = cell
        }
    }

    /// Whether the Tonnetz is on screen (`PerformanceState.deskPane`). Off screen it
    /// is silent, and the computer keyboard's moves are not made.
    var isShown = false {
        didSet {
            if !isShown { silence() }
        }
    }

    /// Whether what is pressed stays on once the pointer lifts. Switching
    /// it off ends everything that was left on.
    var holds = false {
        didSet {
            guard holds != oldValue else { return }
            logger?.log(.tonnetz_hold_switched(isOn: holds))
            if !holds { silence() }
        }
    }

    /// The triangle the Tonnetz is at.
    private(set) var cell = TonnetzCell.home
    /// Whether its triad is sounding.
    private(set) var isSounding = false

    /// The notes sounding by themselves, as MIDI notes in the order they
    /// were pressed.
    private(set) var notes: [Int] = []

    /// Whether `note` is sounding by itself.
    func sounds(_ note: PitchClass) -> Bool {
        notes.contains { $0 % 12 == note.rawValue }
    }

    /// The notes sounding by themselves, in the order they were pressed.
    var soundingNotes: [PitchClass] {
        notes.compactMap { PitchClass(rawValue: $0 % 12) }
    }

    /// What the pointer that is down is playing.
    private var pointer: TonnetzTarget?

    /// The triangle in the middle of the net as it is drawn.
    private(set) var netCenter = TonnetzCell.home

    /// How long a side of a triangle is drawn on the net, in points: how
    /// far in the net is zoomed.
    private(set) var netEdge: CGFloat = 104
    static let netEdgeRange: ClosedRange<CGFloat> = 56...168
    static let netEdgeStep: CGFloat = 16

    /// Draws the net around the triangle the Tonnetz is at: moves have led
    /// it out of what the net shows.
    func centerNet() {
        netCenter = cell
    }

    func zoomNet(to edge: CGFloat) {
        netEdge = edge.clamped(to: Self.netEdgeRange)
    }

    @ObservationIgnored weak var host: (any TonnetzHost)?

    /// The notes last sounded, which the next triad is voiced near.
    private var lastVoicing: Voicing?

    private let sink: (any ChordEventSink)?
    private let noteSink: (any ChordEventSink)?
    private let logger: (any Logger)?

    /// `sink` sounds the triads and `noteSink` the notes played by
    /// themselves; a sink that is a `SoundControl` is given the sound of
    /// what it starts. Without one that line is silent.
    init(sink: (any ChordEventSink)? = nil, noteSink: (any ChordEventSink)? = nil,
         logger: (any Logger)? = nil) {
        self.sink = sink
        self.noteSink = noteSink
        self.logger = logger
    }

    // MARK: – The pointer

    /// A pointer came down on `target`, which sounds. While the Tonnetz
    /// holds, a press of what is sounding ends it instead.
    func pointerDown(on target: TonnetzTarget) {
        pointer = target
        switch target {
        case .cell(let cell):
            if holds, isSounding, cell == self.cell { endTriad() } else { go(to: cell) }
        case .note(let note):
            if holds, sounds(note) { end(note) } else { start(note) }
        }
    }

    /// The pointer that is down moved onto `target`. It goes on playing
    /// what it came down on: one on a triangle slides from triad to triad
    /// and passes over the notes, and one on a note plays a run of notes
    /// (or adds each to those held) and passes over the triangles.
    func pointerMoved(to target: TonnetzTarget) {
        guard let pointer, target != pointer else { return }
        switch (pointer, target) {
        case (.cell, .cell(let cell)):
            go(to: cell)
        case (.note(let old), .note(let new)):
            // The new note starts before the old one ends: a run has no gaps.
            start(new)
            if !holds { end(old) }
        default:
            return
        }
        self.pointer = target
    }

    /// The pointer lifted: what it was playing ends, unless the Tonnetz holds.
    func pointerUp() {
        guard let pointer else { return }
        self.pointer = nil
        guard !holds else { return }
        switch pointer {
        case .cell:           endTriad()
        case .note(let note): end(note)
        }
    }

    /// Sounds the triad of `cell`. A triangle across a side of the one the
    /// Tonnetz is at is a move.
    private func go(to cell: TonnetzCell) {
        if let move = TonnetzMove.allCases.first(where: { self.cell.flipped($0) == cell }) {
            apply(move)
        } else {
            press(cell)
        }
    }

    // MARK: – Triads

    /// Goes to `cell` and sounds its triad, in place of the one sounding.
    func press(_ cell: TonnetzCell) {
        self.cell = cell
        isSounding = true
        guard let host else { return }
        let context = Self.chord(cell.triad, octave: host.octave)
        let voicing = context.voicing(after: lastVoicing)
        lastVoicing = voicing
        let event = ChordEvent(voicing: voicing, articulation: .block, context: context)
        (sink as? any SoundControl)?.startNotes(in: host.tonnetzSound)
        sink?.playChord(event)
        host.tonnetz(.triads, played: event)
        logger?.log(.tonnetz_triad_played(triad: cell.triad.name, notes: voicing.notes))
    }

    /// Flips the triangle over the side `move` keeps, and sounds the triad
    /// it lands on.
    func apply(_ move: TonnetzMove) {
        let next = cell.flipped(move)
        logger?.log(.tonnetz_moved(move: move.symbol, to: next.triad.name))
        press(next)
    }

    /// The press of a triangle ended: its triad ends, unless the Tonnetz
    /// holds. The Tonnetz stays where it is.
    func release() {
        if !holds { endTriad() }
    }

    private func endTriad() {
        guard isSounding else { return }
        isSounding = false
        sink?.stopChord()
        host?.tonnetz(.triads, played: nil)
    }

    // MARK: – Notes

    /// Sounds `note` by itself, in the octave set, beside the notes
    /// already sounding.
    private func start(_ note: PitchClass) {
        guard let host, !sounds(note) else { return }
        let pitch = note.rawValue + (host.octave + 1) * 12
        notes.append(pitch)
        soundNotes()
        logger?.log(.tonnetz_note_played(note: pitch))
    }

    private func end(_ note: PitchClass) {
        guard sounds(note) else { return }
        notes.removeAll { $0 % 12 == note.rawValue }
        soundNotes()
    }

    /// Makes the notes line sound `notes`. They are sent as one chord, tied
    /// to the last, so the notes that were sounding already are held over
    /// and only the one that came or went is heard to.
    private func soundNotes() {
        guard !notes.isEmpty, let host else {
            noteSink?.stopChord()
            host?.tonnetz(.notes, played: nil)
            return
        }
        let event = ChordEvent(voicing: Voicing(notes: notes), articulation: .tied,
                               context: Self.chord(cell.triad, octave: host.octave))
        (noteSink as? any SoundControl)?.startNotes(in: host.tonnetzSound)
        noteSink?.playChord(event)
        host.tonnetz(.notes, played: event)
    }

    // MARK: – Letting go

    /// Whatever is pressed is let go, as if the pointer had lifted: what
    /// the Tonnetz holds stays on.
    private func letGo() {
        pointer = nil
        guard !holds else { return }
        silence()
    }

    /// Ends everything that is sounding, held or not.
    private func silence() {
        pointer = nil
        endTriad()
        guard !notes.isEmpty else { return }
        notes = []
        soundNotes()
    }

    /// `triad` as a chord the sinks can read: the tonic of its own key,
    /// since it is in none of the performance's. It is voice-led, unlike the
    /// keys' chords.
    private static func chord(_ triad: Triad, octave: Int) -> ChordContext {
        let key = Key(root: triad.root, scale: triad.quality == .major ? .major : .naturalMinor)
        return ChordContext(key: key, spec: ChordSpec(degree: .I, color: .base),
                            octave: octave, inversion: .root, voiceLeading: true)
    }
}
