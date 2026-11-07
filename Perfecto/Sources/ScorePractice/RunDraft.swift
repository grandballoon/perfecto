/// A run as it is being made or edited: moved along the score and taken
/// further or shorter a note at a time, and kept only when it is saved
/// (`Practice.keeping`), so a run is never changed by a touch meant for
/// something else.
///
/// It stays within its room: the steps of its parent, for a sub-run, or
/// else the whole part of its hands. A run with sub-runs keeps their
/// steps: it can be moved, which takes them with it, but not shortened
/// past them.
struct RunDraft: Equatable, Sendable {
    private(set) var passage: Passage
    /// The run being edited; nil while a new one is made.
    let run: RunID?
    /// The run it is a sub-run of; nil for a run of the score.
    let parent: RunID?
    /// The steps it may take.
    let room: ClosedRange<Int>
    /// The steps it must keep, its sub-runs'; nil with none.
    private(set) var keeps: ClosedRange<Int>?
    /// How many steps it has been moved along, which its sub-runs are moved
    /// with it when it is kept.
    private(set) var moved = 0

    init(_ passage: Passage, run: RunID? = nil, parent: RunID? = nil,
         room: ClosedRange<Int>, keeps: ClosedRange<Int>? = nil) {
        self.passage = passage
        self.run = run
        self.parent = parent
        self.room = room
        self.keeps = keeps
    }

    var canExtendStart: Bool { passage.first > room.lowerBound }
    var canExtendEnd: Bool { passage.last < room.upperBound }
    var canShrinkStart: Bool { passage.first < min(passage.last, keeps?.lowerBound ?? .max) }
    var canShrinkEnd: Bool { passage.last > max(passage.first, keeps?.upperBound ?? .min) }

    /// The same number of steps, moved so it begins with the step struck at
    /// `time` (the last one struck by then), and kept within its room.
    func moved(toStartAt time: Double, in score: Score) -> RunDraft {
        let length = passage.last - passage.first
        let start = max(room.lowerBound, min(score.step(passage.hands, at: time), room.upperBound - length))
        return shifted(by: start - passage.first)
    }

    /// One more step before its first, if its room has one.
    func extendingStart() -> RunDraft {
        canExtendStart ? with(first: passage.first - 1) : self
    }

    /// One more step after its last, if its room has one.
    func extendingEnd() -> RunDraft {
        canExtendEnd ? with(last: passage.last + 1) : self
    }

    /// One step fewer at its start; never fewer than one, nor fewer than
    /// its sub-runs have.
    func shrinkingStart() -> RunDraft {
        canShrinkStart ? with(first: passage.first + 1) : self
    }

    /// One step fewer at its end; never fewer than one, nor fewer than its
    /// sub-runs have.
    func shrinkingEnd() -> RunDraft {
        canShrinkEnd ? with(last: passage.last - 1) : self
    }

    private func shifted(by steps: Int) -> RunDraft {
        var next = self
        next.passage = Passage(passage.hands, from: passage.first + steps, to: passage.last + steps)
        next.keeps = keeps.map { ($0.lowerBound + steps)...($0.upperBound + steps) }
        next.moved += steps
        return next
    }

    private func with(first: Int? = nil, last: Int? = nil) -> RunDraft {
        var next = self
        next.passage = Passage(passage.hands, from: first ?? passage.first, to: last ?? passage.last)
        return next
    }
}

extension Practice {
    /// A new run of `hands` begun with the playhead at `time`: the one step
    /// struck then, or the last struck by then. Under `parent` it is a
    /// sub-run of that run, of its hands, begun on the step of it nearest
    /// the playhead. Nil if there are no steps to begin on.
    func newRun(_ hands: Hands, at time: Double, in score: Score, under parent: RunID? = nil) -> RunDraft? {
        if let parent {
            guard let parentRun = run(parent) else { return nil }
            let room = parentRun.passage.steps
            let step = room.nearest(score.step(parentRun.passage.hands, at: time))
            return RunDraft(Passage(parentRun.passage.hands, from: step, to: step), parent: parent, room: room)
        }
        guard let whole = Passage.whole(hands, in: score), let step = Passage.step(hands, at: time, in: score)
        else { return nil }
        return RunDraft(step, room: whole.steps)
    }

    /// The run with `id` put into editing: within its parent, and keeping
    /// its sub-runs' steps.
    func editing(_ id: RunID, in score: Score) -> RunDraft? {
        guard let edited = run(id) else { return nil }
        let parent = edited.parent.flatMap(run)
        guard let room = parent?.passage.steps ?? Passage.whole(edited.passage.hands, in: score)?.steps
        else { return nil }
        let children = runs.filter { $0.parent == id }.map(\.passage)
        let keeps = children.map(\.first).min().flatMap { first in children.map(\.last).max().map { first...$0 } }
        return RunDraft(edited.passage, run: id, parent: edited.parent, room: room, keeps: keeps)
    }

    /// `draft` kept: the run edited changed, its sub-runs moved with it, or
    /// a new run added; and its id.
    func keeping(_ draft: RunDraft) -> (Practice, RunID) {
        if let id = draft.run {
            return (replacing(id, with: draft.passage, movedBy: draft.moved), id)
        }
        return adding(draft.passage, under: draft.parent)
    }
}
