/// What a learner has made of a score and its recording: each hand diced
/// into runs, and the recording matched to them.
///
/// A run is a stretch of one hand's steps (`Run`). Each hand's part is one
/// run, its root, and dicing a run cuts it into runs of its own, which can
/// be cut again when the fingering is still too much to follow: a tree, in
/// which a run's runs always cover it end to end.
///
/// A run's place in the recording is where its first step and the end of
/// its last are heard (`span`), by the alignment: the learner's pins
/// (`anchors`), and between them the recording matched by ear (`matched`,
/// from `AutoMatch`), which is worked out again around the pins whenever
/// they change. Matching a run by hand pins its ends.
///
/// Nudge points (`nudges`) are moments of the recording the learner tagged
/// while listening, to come back to, and `unsure` the moments the match
/// itself doubts.
///
/// Every change is a function from one practice to the next, so the
/// screen keeps one value, saves it as it is, and undoes nothing by hand.
struct Practice: Equatable, Codable, Sendable {
    /// Each hand's whole part; nil for a hand with no notes.
    private(set) var right: Run?
    private(set) var left: Run?
    /// The learner's pins: where the recording has a moment of the score,
    /// set by hand. They always win over the match.
    private(set) var anchors: [AlignmentAnchor] = []
    /// The recording matched to the score by ear, an anchor at each moment
    /// a note is struck; empty until it is matched.
    private(set) var matched: [AlignmentAnchor] = []
    /// Where the match doubts itself, in recording seconds.
    private(set) var unsure: [Double] = []
    /// The moments tagged while listening, in recording seconds, in order.
    private(set) var nudges: [Double] = []
    private var nextID = 1

    /// The score put to the recording: the pins, and the match between
    /// them.
    var alignment: [AlignmentAnchor] {
        Alignment.merged(pins: anchors, matched: matched)
    }

    /// The moments to look at again: those tagged, and those the match
    /// doubts, in order.
    var nudgePoints: [Double] {
        (nudges + unsure).sorted()
    }

    private enum CodingKeys: String, CodingKey {
        case right, left, anchors, matched, unsure, nudges, nextID
    }

    /// A practice saved before the match and the nudge points were kept
    /// is read with none.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        right = try c.decodeIfPresent(Run.self, forKey: .right)
        left = try c.decodeIfPresent(Run.self, forKey: .left)
        anchors = try c.decodeIfPresent([AlignmentAnchor].self, forKey: .anchors) ?? []
        matched = try c.decodeIfPresent([AlignmentAnchor].self, forKey: .matched) ?? []
        unsure = try c.decodeIfPresent([Double].self, forKey: .unsure) ?? []
        nudges = try c.decodeIfPresent([Double].self, forKey: .nudges) ?? []
        nextID = try c.decode(Int.self, forKey: .nextID)
    }

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
                Run(id: low.id, first: low.first, last: high.last, children: inner),
            ])
            run.normalize()
        }
        return next
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

    // MARK: – Matching the recording

    /// Where the run with `id` is heard: from its first step to the end
    /// of its last, in recording seconds.
    func span(of id: RunID, in score: Score) -> ClosedRange<Double>? {
        guard let found = find(id) else { return nil }
        let (run, hand) = (found.run, found.hand)
        let alignment = alignment
        let start = Alignment.recordingTime(score.boundary(hand, run.first), alignment)
        let end = Alignment.recordingTime(score.boundary(hand, run.last + 1), alignment)
        return start...max(start, end)
    }

    /// The run with `id` heard from `recording` seconds on: an anchor at
    /// its first step.
    func settingStart(of id: RunID, to recording: Double, in score: Score) -> Practice {
        guard let found = find(id) else { return self }
        let (run, hand) = (found.run, found.hand)
        return anchoring(score.boundary(hand, run.first), to: recording)
    }

    /// The run with `id` heard to `recording` seconds: an anchor at the end
    /// of its last step.
    func settingEnd(of id: RunID, to recording: Double, in score: Score) -> Practice {
        guard let found = find(id) else { return self }
        let (run, hand) = (found.run, found.hand)
        return anchoring(score.boundary(hand, run.last + 1), to: recording)
    }

    /// The run with `id` kept where it is heard now: its ends anchored
    /// there, if they are not already. Done before matching a run inside
    /// it, so the runs around it stay where they were. A recording matched
    /// by ear is anchored at every step already, so nothing is added.
    func keeping(_ id: RunID, in score: Score) -> Practice {
        guard matched.isEmpty, let found = find(id) else { return self }
        var next = self
        for boundary in [found.run.first, found.run.last + 1] {
            let t = score.boundary(found.hand, boundary)
            guard !anchors.contains(where: { abs($0.score - t) < Score.sameTime }) else { continue }
            next = next.anchoring(t, to: Alignment.recordingTime(t, next.anchors))
        }
        return next
    }

    /// The moment `score` of the score heard at `recording` seconds.
    func anchoring(_ score: Double, to recording: Double) -> Practice {
        var next = self
        next.anchors = Alignment.set(AlignmentAnchor(score: score, recording: max(0, recording)), in: anchors)
        return next
    }

    /// The pins cleared: the match alone, or with none, the score heard at
    /// its own tempo from the recording's start.
    func clearingAnchors() -> Practice {
        var next = self
        next.anchors = []
        return next
    }

    /// The recording matched by ear, as `AutoMatch` found it.
    func matching(_ result: AutoMatch.Result) -> Practice {
        var next = self
        next.matched = result.anchors
        next.unsure = result.unsure
        return next
    }

    /// The match forgotten, as for a new recording.
    func clearingMatch() -> Practice {
        var next = self
        next.matched = []
        next.unsure = []
        return next
    }

    /// Everything made of a recording forgotten, for a new one: the pins,
    /// the match and the nudge points.
    func clearingRecording() -> Practice {
        var next = clearingAnchors().clearingMatch()
        next.nudges = []
        return next
    }

    // MARK: – Nudge points

    /// Moments closer than this are one nudge point, in seconds.
    static let nudgeReach = 0.3

    /// A nudge point tagged at `recording` seconds, unless there is one
    /// there already.
    func tagging(_ recording: Double) -> Practice {
        guard nudge(near: recording) == nil else { return self }
        var next = self
        next.nudges = (nudges + [max(0, recording)]).sorted()
        return next
    }

    /// The nudge point tagged nearest `recording` seconds taken away, and
    /// a doubt the match had there too.
    func untagging(_ recording: Double) -> Practice {
        var next = self
        if let tagged = nudge(near: recording) { next.nudges.removeAll { $0 == tagged } }
        next.unsure.removeAll { abs($0 - recording) < Self.nudgeReach }
        return next
    }

    /// The nudge point tagged within reach of `recording` seconds, if any.
    func nudge(near recording: Double) -> Double? {
        nudges.filter { abs($0 - recording) < Self.nudgeReach }
            .min { abs($0 - recording) < abs($1 - recording) }
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
        var low = Run(id: id, first: first, last: step - 1)
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
