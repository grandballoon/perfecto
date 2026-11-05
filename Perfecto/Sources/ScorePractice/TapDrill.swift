/// Practising a run by touch: the learner taps its steps on the keys, one
/// after another, and every tap is told right or wrong.
///
/// It is the steps of what is watched, in the order of the score, and how
/// far the learner has got: the step to tap now, and which of its notes
/// have been tapped. A step of several notes (a chord, or both hands
/// together) is done when each of its notes has been tapped, in any order,
/// together or one by one. A wrong note is told and changes nothing else,
/// so the learner tries again from where they are. The last note of the
/// last step finishes a pass, and the next tap begins another from the
/// first step.
///
/// Whether the next notes are shown is the screen's choice, not the
/// drill's (`lights(showingNext:)`), so it can be switched at any moment
/// without losing the place.
struct TapDrill: Equatable, Sendable {
    /// What is tapped, in order.
    let steps: [TapStep]
    /// The step being tapped.
    private(set) var index = 0
    /// The notes of that step tapped so far.
    private(set) var tapped: Set<Int> = []
    /// The wrong taps in the pass so far.
    private(set) var mistakes = 0
    /// How many passes have been finished.
    private(set) var passes = 0

    init(steps: [TapStep]) {
        self.steps = steps
    }

    /// The steps of `passages` in the order of the score, each once: runs
    /// that overlap or touch are tapped straight through, as they play.
    init(_ passages: [Passage], in score: Score) {
        var seen: [StepKey: TapStep] = [:]
        for passage in passages {
            for step in passage.steps(in: score) {
                let key = StepKey(hands: passage.hands, onset: step.onset)
                seen[key] = TapStep(onset: step.onset, notes: step.notes)
            }
        }
        let order = Hands.allCases
        self.init(steps: seen.sorted {
            ($0.key.onset, order.firstIndex(of: $0.key.hands) ?? 0)
                < ($1.key.onset, order.firstIndex(of: $1.key.hands) ?? 0)
        }.map { $0.value })
    }

    var isEmpty: Bool { steps.isEmpty }

    /// The step to tap now; nil if there are none.
    var current: TapStep? {
        steps.indices.contains(index) ? steps[index] : nil
    }

    /// The notes of the step to tap now that have not been tapped yet.
    var remaining: [Int] {
        current?.pitches.filter { !tapped.contains($0) } ?? []
    }

    /// `pitch` tapped: the drill as it is after, and what the tap was.
    ///
    /// A note of the step not yet tapped is right, and the last of them
    /// moves on to the next step, or after the last step finishes the
    /// pass. A note of the step tapped again is right and changes nothing.
    /// Any other note is wrong.
    func tapping(_ pitch: Int) -> (TapDrill, TapOutcome) {
        guard let step = current else { return (self, .wrong) }
        var next = self
        guard step.pitches.contains(pitch) else {
            next.mistakes += 1
            return (next, .wrong)
        }
        next.tapped.insert(pitch)
        guard next.tapped.count == Set(step.pitches).count else { return (next, .right) }
        next.tapped = []
        guard index + 1 < steps.count else {
            next.index = 0
            next.passes += 1
            next.mistakes = 0
            return (next, .passed(mistakes: mistakes))
        }
        next.index += 1
        return (next, .stepDone)
    }

    /// Begun again from the first step, with no mistakes; the passes
    /// finished are kept.
    func restarted() -> TapDrill {
        var next = TapDrill(steps: steps)
        next.passes = passes
        return next
    }

    /// Taken to the step struck at `time` (the last one struck by then,
    /// or the first), its notes all still to tap: the playhead moved while
    /// tapping. The mistakes and passes are kept.
    func moved(to time: Double) -> TapDrill {
        var next = self
        next.index = steps.lastIndex { $0.onset <= time + Score.sameTime } ?? 0
        next.tapped = []
        return next
    }

    /// The keys lit while tapping: the notes of this step already tapped,
    /// in their hands' colors, and with `showingNext`, the notes still to
    /// tap, marked as a hand's next keys are.
    func lights(showingNext: Bool) -> [Int: [KeyLight]] {
        guard let step = current else { return [:] }
        var lights: [Int: [KeyLight]] = [:]
        for note in step.notes {
            if tapped.contains(note.pitch) {
                // Long enough ago that it does not flash as a struck key.
                lights[note.pitch, default: []].append(KeyLight(hand: note.hand, kind: .sounding(since: 1)))
            } else if showingNext {
                lights[note.pitch, default: []].append(KeyLight(hand: note.hand, kind: .next))
            }
        }
        return lights
    }

    private struct StepKey: Hashable {
        let hands: Hands
        let onset: Double
    }
}

/// One step to tap: the notes struck together there, of the hands of its
/// run.
struct TapStep: Equatable, Sendable {
    /// In score seconds.
    let onset: Double
    let notes: [ScoreNote]

    /// Its notes' pitches, each once, from the lowest.
    var pitches: [Int] {
        Array(Set(notes.map(\.pitch))).sorted()
    }
}

/// What a tap was.
enum TapOutcome: Equatable, Sendable {
    /// A note of the step, with more of it still to tap.
    case right
    /// The last note of the step: on to the next.
    case stepDone
    /// The last note of the last step: the pass is finished, with
    /// `mistakes` wrong taps in it, and the next tap begins another.
    case passed(mistakes: Int)
    /// Not a note of the step.
    case wrong

    var isRight: Bool { self != .wrong }
}

/// A note's name as a pianist reads it: "C4" is middle C, "F♯3" the F
/// sharp below it.
func pitchName(_ pitch: Int) -> String {
    let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
    let octave = pitch >= 0 ? pitch / 12 - 1 : (pitch - 11) / 12 - 1
    return names[((pitch % 12) + 12) % 12] + String(octave)
}
