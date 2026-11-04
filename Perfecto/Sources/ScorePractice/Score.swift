/// A score as the practice screen reads it: the notes a piano plays, each
/// in the hand that plays it, in seconds as written (its tempo already
/// resolved), and nothing else of the notation.
///
/// A hand's notes are read as steps: the notes struck together, one step
/// after another (`steps(_:)`). A step is what lights at once on the
/// piano and what a run is counted in, so a chord is one step and a held
/// note under moving ones is in the step it was struck in.
struct Score: Equatable, Sendable {
    let title: String
    /// In order of onset, then pitch.
    let notes: [ScoreNote]
    /// The barlines as fence posts, in seconds: the first opens the first
    /// bar and the last closes the piece. Never empty.
    let barlines: [Double]

    private let parts: [Hand: [Step]]

    /// Two onsets this close are one: seconds are sums of written lengths.
    static let sameTime = 1e-6

    init(title: String, notes: [ScoreNote], barlines: [Double] = []) {
        self.title = title
        self.notes = notes.sorted { ($0.onset, $0.pitch) < ($1.onset, $1.pitch) }
        let end = self.notes.map(\.end).max() ?? 0
        self.barlines = barlines.isEmpty ? [0, end] : barlines
        var parts: [Hand: [Step]] = [:]
        for hand in Hand.allCases {
            parts[hand] = Self.steps(of: self.notes.filter { $0.hand == hand })
        }
        self.parts = parts
    }

    /// `hand`'s notes, struck together or one after another.
    func steps(_ hand: Hand) -> [Step] {
        parts[hand] ?? []
    }

    /// Where boundary `index` of `hand`'s steps is, in score seconds: the
    /// onset of step `index`, or for the boundary after the last step,
    /// where its last note ends.
    func boundary(_ hand: Hand, _ index: Int) -> Double {
        let steps = steps(hand)
        if index < steps.count { return steps[max(index, 0)].onset }
        return steps.last.map { $0.notes.map(\.end).max() ?? $0.onset } ?? 0
    }

    private static func steps(of notes: [ScoreNote]) -> [Step] {
        var steps: [Step] = []
        for note in notes {
            if let last = steps.last, note.onset - last.onset < sameTime {
                steps[steps.count - 1] = Step(onset: last.onset, notes: last.notes + [note])
            } else {
                steps.append(Step(onset: note.onset, notes: [note]))
            }
        }
        return steps
    }
}

/// Which hand plays a note: the upper staff's notes are the right hand's.
enum Hand: String, CaseIterable, Codable, Sendable {
    case right
    case left
}

struct ScoreNote: Equatable, Sendable {
    /// A MIDI note: 60 is middle C.
    let pitch: Int
    /// In score seconds from the start of the piece.
    let onset: Double
    let duration: Double
    let hand: Hand

    var end: Double { onset + duration }
}

/// The notes of one hand that are struck together.
struct Step: Equatable, Sendable {
    let onset: Double
    /// In order of pitch.
    let notes: [ScoreNote]
}
