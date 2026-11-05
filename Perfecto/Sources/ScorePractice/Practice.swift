import Foundation

/// What a learner has made of a score: runs, each a stretch of it to
/// watch on its own.
///
/// Runs are independent views of the one score. Each is of one hand or
/// of both together (`Hands`), begins and ends on any step of them, and
/// may overlap any other run, lie inside it or repeat part of it: adding,
/// naming or deleting one leaves every other as it was.
///
/// Every change is a function from one practice to the next, so the
/// screen keeps one value, saves it as it is, and undoes a change by
/// going back to the value before it (`History`). A practice saved when a
/// hand's runs were cut from its whole part, as a tree, is read as the
/// runs of that tree, each its own; one saved when pieces had recordings
/// is read the same, what was kept of the recording passed over.
struct Practice: Equatable, Sendable {
    /// In the order they were added.
    private(set) var runs: [PracticeRun] = []
    private var nextID = 1

    init() {}

    func run(_ id: RunID) -> PracticeRun? {
        runs.first { $0.id == id }
    }

    /// The runs of `hands`, in the order they are in the score.
    func runs(of hands: Hands, in score: Score) -> [PracticeRun] {
        runs.filter { $0.passage.hands == hands }
            .sorted { $0.passage.order(in: score) < $1.passage.order(in: score) }
    }

    /// A run of `passage` added, and its id; a passage that is a run
    /// already is not added again, and its run's id is given.
    func adding(_ passage: Passage, name: String? = nil) -> (Practice, RunID) {
        if let same = runs.first(where: { $0.passage == passage }) { return (self, same.id) }
        var next = self
        let id = RunID(rawValue: nextID)
        next.nextID += 1
        next.runs.append(PracticeRun(id: id, passage: passage, name: Self.trimmed(name)))
        return (next, id)
    }

    /// The run with `id` taken away; nothing else changes.
    func removing(_ id: RunID) -> Practice {
        var next = self
        next.runs.removeAll { $0.id == id }
        return next
    }

    /// The run with `id` made to watch `passage` in place of its own; its
    /// id and name stay, and nothing else changes.
    func replacing(_ id: RunID, with passage: Passage) -> Practice {
        var next = self
        guard let i = runs.firstIndex(where: { $0.id == id }) else { return self }
        next.runs[i] = PracticeRun(id: id, passage: passage, name: runs[i].name)
        return next
    }

    /// The run with `id` given the name `name`, trimmed; a name of
    /// nothing but spaces takes its name away.
    func naming(_ id: RunID, _ name: String) -> Practice {
        var next = self
        guard let i = runs.firstIndex(where: { $0.id == id }) else { return self }
        next.runs[i].name = Self.trimmed(name)
        return next
    }

    private static func trimmed(_ name: String?) -> String? {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    /// For each span, in order, the lane it is drawn in when spans that
    /// overlap are drawn apart: the lowest lane none of the spans before it
    /// in that lane overlaps. Spans that only touch share a lane.
    static func lanes(of spans: [ClosedRange<Double>]) -> [Int] {
        var ends: [Double] = []
        var lanes = Array(repeating: 0, count: spans.count)
        for i in spans.indices.sorted(by: { spans[$0].lowerBound < spans[$1].lowerBound }) {
            let span = spans[i]
            if let lane = ends.firstIndex(where: { $0 <= span.lowerBound + Playback.touching }) {
                lanes[i] = lane
                ends[lane] = span.upperBound
            } else {
                lanes[i] = ends.count
                ends.append(span.upperBound)
            }
        }
        return lanes
    }
}

/// A stretch of the score to watch: the steps of `hands` from `first` to
/// `last`, both included.
struct Passage: Hashable, Codable, Sendable {
    let hands: Hands
    let first: Int
    let last: Int

    /// From step `a` to step `b` of `hands`, in whichever order they come.
    init(_ hands: Hands, from a: Int, to b: Int) {
        self.hands = hands
        first = max(0, min(a, b))
        last = max(0, max(a, b))
    }

    /// The whole part of `hands`; nil if they have no notes.
    static func whole(_ hands: Hands, in score: Score) -> Passage? {
        let count = score.steps(hands).count
        return count > 0 ? Passage(hands, from: 0, to: count - 1) : nil
    }

    var steps: ClosedRange<Int> { first...last }

    /// A new run's passage with the playhead standing at `time`: the one
    /// step of `hands` struck then, or the last struck by then, to be taken
    /// further a note at a time. Nil if the hands have no notes.
    static func step(_ hands: Hands, at time: Double, in score: Score) -> Passage? {
        guard !score.steps(hands).isEmpty else { return nil }
        let at = score.step(hands, at: time)
        return Passage(hands, from: at, to: at)
    }

    /// The same number of steps, moved so it begins with the step struck
    /// at `time` (the last one struck by then), and kept within the part.
    func moved(toStartAt time: Double, in score: Score) -> Passage {
        let count = score.steps(hands).count
        let length = last - first
        let start = min(score.step(hands, at: time), max(0, count - 1 - length))
        return Passage(hands, from: start, to: start + length)
    }

    /// One more step before its first, if the part has one.
    func extendingStart() -> Passage {
        Passage(hands, from: max(0, first - 1), to: last)
    }

    /// One more step after its last, if the part has one.
    func extendingEnd(in score: Score) -> Passage {
        Passage(hands, from: first, to: min(last + 1, score.steps(hands).count - 1))
    }

    /// One step fewer at its start; never fewer than one.
    func shrinkingStart() -> Passage {
        Passage(hands, from: min(first + 1, last), to: last)
    }

    /// One step fewer at its end; never fewer than one.
    func shrinkingEnd() -> Passage {
        Passage(hands, from: first, to: max(last - 1, first))
    }

    /// Its steps that the score has.
    func steps(in score: Score) -> [Step] {
        let steps = score.steps(hands)
        return steps.indices.contains(first) ? Array(steps[first...min(last, steps.count - 1)]) : []
    }

    /// Where it is played: from its first step to where the step after its
    /// last begins, or the last's notes end, in score seconds.
    func span(in score: Score) -> ClosedRange<Double> {
        let start = score.boundary(hands, first)
        return start...max(start, score.boundary(hands, last + 1))
    }

    /// What passages are put in order by: where they begin, the longer
    /// first, then the right hand's before the left's before both.
    fileprivate func order(in score: Score) -> Order {
        let span = span(in: score)
        return Order(start: span.lowerBound, end: span.upperBound,
                     hands: Hands.allCases.firstIndex(of: hands) ?? 0)
    }

    fileprivate struct Order: Comparable {
        let start: Double
        let end: Double
        let hands: Int

        static func < (a: Order, b: Order) -> Bool {
            (a.start, b.end, a.hands) < (b.start, a.end, b.hands)
        }
    }
}

struct RunID: Hashable, Codable, Sendable, Comparable {
    let rawValue: Int

    static func < (a: RunID, b: RunID) -> Bool { a.rawValue < b.rawValue }

    init(rawValue: Int) { self.rawValue = rawValue }
    init(from decoder: Decoder) throws { rawValue = try decoder.singleValueContainer().decode(Int.self) }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// A passage the learner keeps to watch, and what they call it.
struct PracticeRun: Equatable, Codable, Sendable, Identifiable {
    let id: RunID
    let passage: Passage
    /// What the learner calls it ("the leap", "bars 5–8"); nil for none,
    /// when it goes by its bars.
    fileprivate(set) var name: String?
}

/// Where a run is in the score as its bars say: "Bar 5", "Bars 5–8".
extension Score {
    func bars(of span: ClosedRange<Double>) -> String {
        let first = bar(at: span.lowerBound)
        // The last bar is the one the span ends in, not one it ends at.
        let opened = barlines.dropLast().lastIndex { $0 < span.upperBound - Self.sameTime } ?? 0
        let last = max(first, opened + 1)
        return first == last ? "Bar \(first)" : "Bars \(first)–\(last)"
    }

    /// The step of `hands` struck at `time`, or the last one struck by
    /// then; the first before any.
    func step(_ hands: Hands, at time: Double) -> Int {
        steps(hands).lastIndex { $0.onset <= time + Self.sameTime } ?? 0
    }

    /// The bar a moment is in, counted from 1.
    func bar(at time: Double) -> Int {
        (barlines.dropLast().lastIndex { $0 <= time + Self.sameTime } ?? 0) + 1
    }
}

// MARK: – Kept

extension Practice: Codable {
    private enum Key: String, CodingKey {
        case runs, nextID
        // A tree of runs cut from each hand's whole part, as practice was
        // once kept.
        case right, left
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        if let runs = try c.decodeIfPresent([PracticeRun].self, forKey: .runs) {
            self.runs = runs
        } else {
            for (hand, key) in [(Hands.right, Key.right), (.left, .left)] {
                guard let root = try c.decodeIfPresent(CutRun.self, forKey: key) else { continue }
                runs += root.children.flatMap { $0.flattened(hand) }
            }
        }
        let highest = runs.map(\.id.rawValue).max() ?? 0
        nextID = max(try c.decodeIfPresent(Int.self, forKey: .nextID) ?? 1, highest + 1)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        try c.encode(runs, forKey: .runs)
        try c.encode(nextID, forKey: .nextID)
    }
}

/// A run as it was kept in a tree: a stretch of one hand's steps and the
/// runs it was cut into.
private struct CutRun: Decodable {
    let id: RunID
    let first: Int
    let last: Int
    var children: [CutRun] = []
    var name: String?

    private enum Key: String, CodingKey { case id, first, last, children, name }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        id = try c.decode(RunID.self, forKey: .id)
        first = try c.decode(Int.self, forKey: .first)
        last = try c.decode(Int.self, forKey: .last)
        children = try c.decodeIfPresent([CutRun].self, forKey: .children) ?? []
        name = try c.decodeIfPresent(String.self, forKey: .name)
    }

    /// This run and every run under it, each a run of its own.
    func flattened(_ hands: Hands) -> [PracticeRun] {
        [PracticeRun(id: id, passage: Passage(hands, from: first, to: last), name: name)]
            + children.flatMap { $0.flattened(hands) }
    }
}

// MARK: – Undo

/// A value as it has been changed: the values before the present one, to
/// undo to, and the values undone, to redo. A change made after an undo
/// leaves nothing to redo.
struct History<Value: Equatable & Sendable>: Equatable, Sendable {
    private(set) var present: Value
    private var past: [Value] = []
    private var future: [Value] = []

    init(_ value: Value) {
        present = value
    }

    var canUndo: Bool { !past.isEmpty }
    var canRedo: Bool { !future.isEmpty }

    /// `next` the present value; the same value again is no change.
    func doing(_ next: Value) -> History {
        guard next != present else { return self }
        var history = self
        history.past.append(present)
        history.present = next
        history.future = []
        return history
    }

    func undoing() -> History {
        guard let last = past.last else { return self }
        var history = self
        history.past.removeLast()
        history.future.append(present)
        history.present = last
        return history
    }

    func redoing() -> History {
        guard let next = future.last else { return self }
        var history = self
        history.future.removeLast()
        history.past.append(present)
        history.present = next
        return history
    }
}
