/// A pad's place on the grid: rows counted from the top, columns from the
/// leading edge.
struct PadPlace: Hashable, Codable, Sendable {
    var row: Int
    var column: Int
}

/// What a pad plays: a chord as the keys would play it, with everything it
/// is played with. All of it is the pad's own, so nothing chosen for the
/// keys afterwards reaches it.
struct PadSound: Equatable, Codable, Sendable {
    var chord: ChordSpec
    var key: Key
    var octave: Int
    var preset: SynthPreset
    var effects: NoteEffects
}

extension PadSound {
    /// The chord as the display names it: "D min7".
    var label: String { chordLabel(key: key, spec: chord) }

    /// The pad as a chord a voice plays (`TimelineVoice`), voiced as the
    /// keys voice it. It has no place in time: whoever plays it says when.
    var played: TimedChord {
        let context = performanceContext(key: key, octave: octave, spec: chord)
        return TimedChord(start: 0, end: 0,
                          event: ChordEvent(voicing: context.voicing(after: nil), articulation: .block,
                                            context: context),
                          preset: preset, effects: effects, changes: [])
    }
}

/// How long each pad's step is while the grid is played in sequence.
enum PadRate: String, CaseIterable, Codable, Sendable {
    case sixteenth, eighth, quarter, half, bar

    var beats: Double {
        switch self {
        case .sixteenth: return 0.25
        case .eighth:    return 0.5
        case .quarter:   return 1
        case .half:      return 2
        case .bar:       return Double(MusicalTime.beatsPerBar)
        }
    }

    /// The step as a note's length.
    var label: String {
        switch self {
        case .sixteenth: return "1/16"
        case .eighth:    return "1/8"
        case .quarter:   return "1/4"
        case .half:      return "1/2"
        case .bar:       return "Bar"
        }
    }
}

/// The pads: a grid of sounds, each played by itself or all of them in
/// sequence. It is plain data; `PadsState` plays it.
///
/// The rows and the columns are set apart from one another. A pad keeps its
/// place when the grid changes size, and one left outside a smaller grid is
/// kept, so making the grid larger again brings it back.
struct PadGrid: Equatable, Codable, Sendable {
    /// The rows, and the columns, a grid can have.
    static let sizes = 4...8

    private(set) var rows = Self.sizes.lowerBound
    private(set) var columns = Self.sizes.lowerBound
    /// The step of the sequence.
    var rate = PadRate.quarter
    /// Every pad that has a sound, those outside the grid as it is now too.
    private var sounds: [PadPlace: PadSound] = [:]

    mutating func resize(rows: Int, columns: Int) {
        self.rows = rows.clamped(to: Self.sizes)
        self.columns = columns.clamped(to: Self.sizes)
    }

    func contains(_ place: PadPlace) -> Bool {
        (0..<rows).contains(place.row) && (0..<columns).contains(place.column)
    }

    /// The pads' places in the order the sequence plays them: along each
    /// row from the leading edge, the rows from the top.
    var places: [PadPlace] {
        (0..<rows).flatMap { row in (0..<columns).map { PadPlace(row: row, column: $0) } }
    }

    /// The sound of the pad at `place`; nil for a pad that has none, and
    /// for a place outside the grid.
    subscript(place: PadPlace) -> PadSound? {
        get { contains(place) ? sounds[place] : nil }
        set {
            guard contains(place) else { return }
            sounds[place] = newValue
        }
    }

    /// The place the sequence plays after `place`: the next along, and
    /// from the last the first again. From nowhere, or from a place the
    /// grid no longer has, it is the first.
    func place(after place: PadPlace?) -> PadPlace {
        let first = PadPlace(row: 0, column: 0)
        guard let place, contains(place) else { return first }
        if place.column + 1 < columns { return PadPlace(row: place.row, column: place.column + 1) }
        return place.row + 1 < rows ? PadPlace(row: place.row + 1, column: 0) : first
    }
}
