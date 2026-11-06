import Foundation

/// What a learner has made of a score: runs, each a stretch of it to
/// watch on its own.
///
/// Runs are independent views of the one score. Each is of one hand or
/// of both together (`Hands`), begins and ends on any step of them, and
/// may overlap any other run, lie inside it or repeat part of it: adding,
/// naming or deleting one leaves every other as it was.
///
/// A run can also be made within another, as its sub-run (`parent`): a
/// part of it to watch on its own, which leaves the run itself whole and
/// watched as it was. A sub-run is always within its parent's steps: it
/// moves with its parent, the parent cannot give up the steps it has
/// (`RunDraft`), and it goes when its parent does. Sub-runs can have
/// their own.
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
        runs.filter { $0.passage.hands == hands }.sorted { Self.isBefore($0, $1, in: score) }
    }

    /// The sub-runs of the run with `id`, the runs made within it, in the
    /// order they are in the score; not theirs.
    func subRuns(of id: RunID, in score: Score) -> [PracticeRun] {
        runs.filter { $0.parent == id }.sorted { Self.isBefore($0, $1, in: score) }
    }

    /// The runs of `hands` as they are nested: each run of the score, in
    /// the order of the score, followed by its sub-runs, each followed by
    /// its own, and how deep each is (0 for a run of the score).
    func outline(of hands: Hands, in score: Score) -> [OutlinedRun] {
        func under(_ parent: RunID?, depth: Int) -> [OutlinedRun] {
            runs.filter { $0.parent == parent && $0.passage.hands == hands }
                .sorted { Self.isBefore($0, $1, in: score) }
                .flatMap { [OutlinedRun(run: $0, depth: depth)] + under($0.id, depth: depth + 1) }
        }
        return under(nil, depth: 0)
    }

    private static func isBefore(_ a: PracticeRun, _ b: PracticeRun, in score: Score) -> Bool {
        a.passage.order(in: score) < b.passage.order(in: score)
    }

    /// A run of `passage` added, and its id. Under `parent` it is a sub-run
    /// of that run, kept within its steps (of its hands). A passage that is
    /// a run already beside it is not added again, and that run's id is
    /// given; so is the parent's, for a sub-run of the whole parent.
    func adding(_ passage: Passage, under parent: RunID? = nil, name: String? = nil) -> (Practice, RunID) {
        let parentRun = parent.flatMap(run)
        let passage = parentRun.map { passage.fitted(into: $0.passage) } ?? passage
        if let parentRun, passage == parentRun.passage { return (self, parentRun.id) }
        if let same = runs.first(where: { $0.passage == passage && $0.parent == parentRun?.id }) {
            return (self, same.id)
        }
        var next = self
        let id = RunID(rawValue: nextID)
        next.nextID += 1
        next.runs.append(PracticeRun(id: id, passage: passage, name: Self.trimmed(name), parent: parentRun?.id))
        return (next, id)
    }

    /// The run with `id` taken away, and its sub-runs with it, which were
    /// within it; nothing else changes.
    func removing(_ id: RunID) -> Practice {
        var next = self
        let gone = descendants(of: id).union([id])
        next.runs.removeAll { gone.contains($0.id) }
        return next
    }

    /// The runs made within the run with `id`, and within them, all the
    /// way down.
    func descendants(of id: RunID) -> Set<RunID> {
        runs.filter { $0.parent == id }.reduce(into: Set()) { all, child in
            all.insert(child.id)
            all.formUnion(descendants(of: child.id))
        }
    }

    /// The run with `id` made to watch `passage` in place of its own, kept
    /// within its parent if it has one; its id and name stay. Its sub-runs
    /// are moved `steps` along with it (a run dragged along the score takes
    /// them with it) and kept within it; nothing else changes.
    func replacing(_ id: RunID, with passage: Passage, movedBy steps: Int = 0) -> Practice {
        guard let i = runs.firstIndex(where: { $0.id == id }) else { return self }
        var next = self
        let old = runs[i]
        let fitted = old.parent.flatMap(run).map { passage.fitted(into: $0.passage) } ?? passage
        next.runs[i] = PracticeRun(id: id, passage: fitted, name: old.name, parent: old.parent)
        next.refitSubRuns(of: id, movedBy: steps)
        return next
    }

    /// The sub-runs of `id`, and theirs, moved `steps` and kept within
    /// their parents.
    private mutating func refitSubRuns(of id: RunID, movedBy steps: Int) {
        guard let parent = run(id) else { return }
        for i in runs.indices where runs[i].parent == id {
            let child = runs[i]
            let moved = Passage(child.passage.hands, from: child.passage.first + steps, to: child.passage.last + steps)
            runs[i] = PracticeRun(id: child.id, passage: moved.fitted(into: parent.passage),
                                  name: child.name, parent: id)
            refitSubRuns(of: child.id, movedBy: steps)
        }
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

    /// The same steps, each kept within `other`'s, and of its hands.
    func fitted(into other: Passage) -> Passage {
        Passage(other.hands, from: other.steps.nearest(first), to: other.steps.nearest(last))
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

extension ClosedRange<Int> {
    /// The step of these nearest `step`: itself if it is one of them.
    func nearest(_ step: Int) -> Int {
        Swift.min(Swift.max(step, lowerBound), upperBound)
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
    /// The run this is a sub-run of, made within it: its steps are within
    /// that run's, of the same hands. Nil for a run of the score.
    let parent: RunID?

    init(id: RunID, passage: Passage, name: String? = nil, parent: RunID? = nil) {
        self.id = id
        self.passage = passage
        self.name = name
        self.parent = parent
    }
}

/// A run in the outline of the runs, and how deep it is nested: 0 for a
/// run of the score, 1 for a sub-run of one, and so on.
struct OutlinedRun: Equatable, Sendable, Identifiable {
    let run: PracticeRun
    let depth: Int

    var id: RunID { run.id }
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
        // A sub-run comes after the run it was made within; one that does
        // not, or whose parent is gone, is a run of the score.
        for i in runs.indices {
            if let parent = runs[i].parent, !runs[..<i].contains(where: { $0.id == parent }) {
                runs[i] = PracticeRun(id: runs[i].id, passage: runs[i].passage, name: runs[i].name)
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
