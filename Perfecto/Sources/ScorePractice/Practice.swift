import Foundation

/// What a learner has made of a score: each hand diced into runs.
///
/// A run is a stretch of one hand's steps (`Run`). Each hand's part is one
/// run, its root, and dicing a run cuts it into runs of its own, which can
/// be cut again when the fingering is still too much to follow: a tree, in
/// which a run's runs always cover it end to end.
///
/// Every change is a function from one practice to the next, so the
/// screen keeps one value, saves it as it is, and undoes nothing by hand.
/// A practice saved when pieces had recordings is read the same, what was
/// kept of the recording passed over.
struct Practice: Equatable, Codable, Sendable {
    /// Each hand's whole part; nil for a hand with no notes.
    private(set) var right: Run?
    private(set) var left: Run?
    private var nextID = 1

    init(score: Score) {
        right = makeRoot(score.steps(.right).count)
        left = makeRoot(score.steps(.left).count)
    }

    private mutating func makeRoot(_ steps: Int) -> Run? {
        guard steps > 0 else { return nil }
        return Run(id: Run.take(&nextID), first: 0, last: steps - 1)
    }

    func root(_ hand: Hand) -> Run? {
        hand == .right ? right : left
    }

    /// The run with `id`, and the hand whose it is.
    func find(_ id: RunID) -> (run: Run, hand: Hand)? {
        for hand in Hand.allCases {
            if let run = root(hand)?.find(id) { return (run, hand) }
        }
        return nil
    }

    /// The runs from the hand's root down to the run with `id`, both
    /// included; empty if there is none.
    func path(to id: RunID) -> [Run] {
        for hand in Hand.allCases {
            if let path = root(hand)?.path(to: id) { return path }
        }
        return []
    }

    // MARK: – Dicing

    /// The run with `id` cut before step `step`, into runs of its own: if
    /// it has none yet, into two; if it has, the one of them that holds
    /// the step is cut in two. A cut where there is one already, or at the
    /// run's own start, changes nothing.
    func cutting(_ id: RunID, before step: Int) -> Practice {
        var next = self
        var ids = nextID
        next.update(id) { run in
            guard step > run.first, step <= run.last else { return }
            if run.children.isEmpty {
                run.children = [Run(id: Run.take(&ids), first: run.first, last: step - 1),
                                Run(id: Run.take(&ids), first: step, last: run.last)]
            } else if let i = run.children.firstIndex(where: { $0.first < step && step <= $0.last }) {
                let (low, high) = run.children[i].split(before: step, ids: &ids)
                run.children.replaceSubrange(i...i, with: [low, high])
            }
        }
        next.nextID = ids
        return next
    }

    /// The cut before step `step` among the runs of the run with `id`
    /// taken away: the two runs it divided are one, which keeps the runs
    /// either had. A run left with one run of its own has none.
    func joining(_ id: RunID, before step: Int) -> Practice {
        var next = self
        next.update(id) { run in
            guard let i = run.children.firstIndex(where: { $0.first == step }), i > 0 else { return }
            let low = run.children[i - 1], high = run.children[i]
            let inner = (low.children.isEmpty && high.children.isEmpty)
                ? [] : low.pieces + high.pieces
            run.children.replaceSubrange((i - 1)...i, with: [
                Run(id: low.id, first: low.first, last: high.last, children: inner, name: low.name ?? high.name),
            ])
            run.normalize()
        }
        return next
    }

    /// The run with `id` given the name `name`, trimmed; a name of
    /// nothing but spaces takes its name away.
    func naming(_ id: RunID, _ name: String) -> Practice {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var next = self
        next.update(id) { $0.name = trimmed.isEmpty ? nil : trimmed }
        return next
    }

    /// Every run of `hand`, the root first and each run before its own
    /// runs, with how deep it is (the root 0): the outline of all the runs.
    func outline(_ hand: Hand) -> [(run: Run, depth: Int)] {
        guard let root = root(hand) else { return [] }
        func walk(_ run: Run, _ depth: Int) -> [(run: Run, depth: Int)] {
            [(run, depth)] + run.children.flatMap { walk($0, depth + 1) }
        }
        return walk(root, 0)
    }

    /// Where the run with `id` is cut into its runs: the step each of its
    /// runs after the first begins with.
    func cuts(of id: RunID) -> [Int] {
        find(id)?.run.children.dropFirst().map(\.first) ?? []
    }

    private mutating func update(_ id: RunID, _ change: (inout Run) -> Void) {
        for hand in Hand.allCases {
            guard var root = root(hand), root.find(id) != nil else { continue }
            root.update(id, change)
            if hand == .right { right = root } else { left = root }
            return
        }
    }

    // MARK: – Time

    /// Where the run with `id` is played: from its first step to the end
    /// of its last, in score seconds.
    func span(of id: RunID, in score: Score) -> ClosedRange<Double>? {
        guard let found = find(id) else { return nil }
        let (run, hand) = (found.run, found.hand)
        let start = score.boundary(hand, run.first)
        let end = score.boundary(hand, run.last + 1)
        return start...max(start, end)
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

/// A stretch of one hand's steps, `first` to `last` of them, and the runs
/// it is cut into, which cover it end to end in order (none, or two or
/// more).
struct Run: Equatable, Codable, Sendable, Identifiable {
    let id: RunID
    let first: Int
    let last: Int
    fileprivate(set) var children: [Run] = []
    /// What the learner calls it ("the leap", "bars 5–8"); nil for none,
    /// when it goes by its place. Cutting a run leaves its name on the
    /// first part, and joining two keeps the first's, or the second's.
    fileprivate(set) var name: String?

    var steps: ClosedRange<Int> { first...last }
    var isLeaf: Bool { children.isEmpty }

    /// The next id from a counter of them.
    fileprivate static func take(_ ids: inout Int) -> RunID {
        defer { ids += 1 }
        return RunID(rawValue: ids)
    }

    /// Its runs, or itself if it has none.
    fileprivate var pieces: [Run] { children.isEmpty ? [self] : children }

    func find(_ id: RunID) -> Run? {
        path(to: id)?.last
    }

    func path(to id: RunID) -> [Run]? {
        if self.id == id { return [self] }
        for child in children {
            if let path = child.path(to: id) { return [self] + path }
        }
        return nil
    }

    /// The run of this one's that holds step `step`, at every depth, from
    /// this run down.
    func path(holding step: Int) -> [Run] {
        guard steps.contains(step) else { return [] }
        return [self] + (children.first { $0.steps.contains(step) }?.path(holding: step) ?? [])
    }

    fileprivate mutating func update(_ id: RunID, _ change: (inout Run) -> Void) {
        if self.id == id { change(&self); return }
        for i in children.indices where children[i].find(id) != nil {
            children[i].update(id, change)
        }
    }

    /// Two runs, before `step` and from it, with this run's runs shared
    /// out between them and a run of its that holds the step split too.
    /// The low one keeps this run's id.
    fileprivate func split(before step: Int, ids: inout Int) -> (Run, Run) {
        var low = Run(id: id, first: first, last: step - 1, name: name)
        var high = Run(id: Run.take(&ids), first: step, last: last)
        for child in children {
            if child.last < step {
                low.children.append(child)
            } else if child.first >= step {
                high.children.append(child)
            } else {
                let (l, h) = child.split(before: step, ids: &ids)
                low.children.append(l)
                high.children.append(h)
            }
        }
        low.normalize()
        high.normalize()
        return (low, high)
    }

    /// A run with one run of its own is that run: it takes its runs.
    fileprivate mutating func normalize() {
        if children.count == 1 { children = children[0].children }
    }
}
