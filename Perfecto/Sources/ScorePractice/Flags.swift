import Foundation

/// The flags a learner has put on a score: moments marked as they listen
/// or step through it, each with a note of what is there, if they wrote
/// one ("the leap", "left hand crosses over").
///
/// A flag is a moment of the score, in its seconds, so it means the same
/// in every view: it is put on in one (`ScoreFlag.hands`, which says so)
/// and is seen in all of them. In a view a flag marks one step, the step
/// of those hands struck at its moment or the last struck by then
/// (`step(_:in:)`), by the rule a new run begins on; that is the step it is
/// "at" while the playhead stands there (`at(_:_:in:)`), and the step a
/// run begins or ends on when its edge is on the flag (`edges(of:in:)`).
///
/// Every change is a function from one value to the next, so flags are
/// kept, saved and undone with the runs (`Practice.flags`).
struct ScoreFlags: Equatable, Sendable {
    /// In order of their moments, then of when they were put on.
    private(set) var all: [ScoreFlag] = []
    private var nextID = 1

    init() {}

    func flag(_ id: FlagID) -> ScoreFlag? {
        all.first { $0.id == id }
    }

    /// A flag put on at `time`, put on in the view of `hands`, with `note`
    /// (trimmed; nothing but spaces is no note), and its id. A flag of the
    /// same hands at the same moment is that flag, given back as it is.
    func adding(at time: Double, _ hands: Hands, note: String? = nil) -> (ScoreFlags, FlagID) {
        let time = max(0, time)
        if let same = all.first(where: { $0.hands == hands && abs($0.time - time) < Score.sameTime }) {
            return (self, same.id)
        }
        var next = self
        let id = FlagID(rawValue: nextID)
        next.nextID += 1
        next.all.append(ScoreFlag(id: id, time: time, hands: hands, note: Self.trimmed(note)))
        next.all.sort { ($0.time, $0.id.rawValue) < ($1.time, $1.id.rawValue) }
        return (next, id)
    }

    /// The flag with `id` given the note `note`, trimmed; nothing but
    /// spaces takes its note away.
    func noting(_ id: FlagID, _ note: String) -> ScoreFlags {
        guard let i = all.firstIndex(where: { $0.id == id }) else { return self }
        var next = self
        next.all[i].note = Self.trimmed(note)
        return next
    }

    /// The flag with `id` taken away; nothing else changes.
    func removing(_ id: FlagID) -> ScoreFlags {
        var next = self
        next.all.removeAll { $0.id == id }
        return next
    }

    /// The step of `hands` a flag marks: the one struck at its moment, or
    /// the last struck by then. Nil if the hands have no notes.
    static func step(_ flag: ScoreFlag, _ hands: Hands, in score: Score) -> Int? {
        score.steps(hands).isEmpty ? nil : score.step(hands, at: flag.time)
    }

    /// The flags at the step of `hands` where the playhead stands at `time`:
    /// those that mark that same step.
    func at(_ time: Double, _ hands: Hands, in score: Score) -> [ScoreFlag] {
        guard !score.steps(hands).isEmpty else { return [] }
        let here = score.step(hands, at: time)
        return all.filter { Self.step($0, hands, in: score) == here }
    }

    /// The flags a passage begins on, those marking its first step, and
    /// ends on, those marking its last, in its own hands.
    func edges(of passage: Passage, in score: Score) -> RunEdgeFlags {
        let steps = all.map { ($0, Self.step($0, passage.hands, in: score)) }
        return RunEdgeFlags(start: steps.filter { $0.1 == passage.first }.map(\.0),
                            end: steps.filter { $0.1 == passage.last }.map(\.0))
    }

    private static func trimmed(_ note: String?) -> String? {
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// A moment of the score marked by the learner, and what they noted of it.
struct ScoreFlag: Equatable, Codable, Sendable, Identifiable {
    let id: FlagID
    /// In score seconds from the start of the piece.
    let time: Double
    /// The view it was put on in; it is seen in every view.
    let hands: Hands
    /// What the learner noted of the moment; nil for none.
    fileprivate(set) var note: String?
}

struct FlagID: Hashable, Codable, Sendable {
    let rawValue: Int

    init(rawValue: Int) { self.rawValue = rawValue }
    init(from decoder: Decoder) throws { rawValue = try decoder.singleValueContainer().decode(Int.self) }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// The flags a run's edges are on: those marking its first step, and its
/// last. A run of one step has the same flags at both.
struct RunEdgeFlags: Equatable, Sendable {
    let start: [ScoreFlag]
    let end: [ScoreFlag]

    var isEmpty: Bool { start.isEmpty && end.isEmpty }
}

extension ScoreFlags: Codable {
    private enum Key: String, CodingKey { case all, nextID }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        all = try c.decodeIfPresent([ScoreFlag].self, forKey: .all) ?? []
        all.sort { ($0.time, $0.id.rawValue) < ($1.time, $1.id.rawValue) }
        let highest = all.map(\.id.rawValue).max() ?? 0
        nextID = max(try c.decodeIfPresent(Int.self, forKey: .nextID) ?? 1, highest + 1)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        try c.encode(all, forKey: .all)
        try c.encode(nextID, forKey: .nextID)
    }
}

// MARK: – Stepping

extension Score {
    /// The step of `hands` after the moment `time`: the first struck later
    /// than it. Nil past the last.
    func step(_ hands: Hands, after time: Double) -> Int? {
        steps(hands).firstIndex { $0.onset > time + Self.sameTime }
    }

    /// The step of `hands` before the moment `time`: the last struck
    /// earlier than it. Nil at or before the first.
    func step(_ hands: Hands, before time: Double) -> Int? {
        steps(hands).lastIndex { $0.onset < time - Self.sameTime }
    }
}

extension Step {
    /// What is heard of the step when it is stepped to: each of its notes
    /// struck at once and held for as long as the score holds it.
    var sounded: [PassNote] {
        notes.map { PassNote(pitch: $0.pitch, start: 0, end: $0.duration) }
    }
}
