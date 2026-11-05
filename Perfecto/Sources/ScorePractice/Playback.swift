/// What is played of the score, and what lights on the piano as it
/// plays: both worked out from the runs being watched, as values, so the
/// player and the piano only carry them out.
enum Playback {

    /// The stretches of the score that play `runs`: each run's span,
    /// in order, joined where two overlap or touch, so runs one after
    /// another play straight through and a run inside another is not
    /// played twice.
    static func segments(_ runs: [RunID], _ practice: Practice, _ score: Score) -> [Segment] {
        let spans = runs.compactMap { practice.span(of: $0, in: score) }
            .filter { $0.upperBound > $0.lowerBound }
            .sorted { $0.lowerBound < $1.lowerBound }
        var segments: [Segment] = []
        for span in spans {
            if let last = segments.last, span.lowerBound <= last.end + touching {
                segments[segments.count - 1] = Segment(start: last.start, end: max(last.end, span.upperBound))
            } else {
                segments.append(Segment(start: span.lowerBound, end: span.upperBound))
            }
        }
        return segments
    }

    /// Two stretches this close are one: no gap anyone would hear.
    static let touching = 0.001

    /// Where playing `segments` begins with the playhead standing at
    /// `time`: at `time` itself if it is inside one, so play goes on from
    /// where it was left or moved to; otherwise at the start of
    /// the next one after it, or of the first when none is after it. A
    /// playhead standing at a segment's very end (`nearEnd`), as one that
    /// has just played through it does, begins at the next. Nil for none.
    static func start(at time: Double, in segments: [Segment]) -> PlayStart? {
        guard let first = segments.first else { return nil }
        if let inside = segments.firstIndex(where: { time >= $0.start && time < $0.end - nearEnd }) {
            return PlayStart(segment: inside, time: time)
        }
        if let next = segments.firstIndex(where: { $0.start > time }) {
            return PlayStart(segment: next, time: segments[next].start)
        }
        return PlayStart(segment: 0, time: first.start)
    }

    /// How near a segment's end the playhead is taken to have played it.
    static let nearEnd = 0.05

    /// One pass through `segments` from `start`, sounding `notes`: the
    /// stretches of the score one after another, and each note struck in
    /// them, cut off where its stretch ends. A pass that begins inside a
    /// stretch also sounds the notes held over that moment, from the start.
    /// A repeat is the pass from the first segment's start.
    static func pass(_ notes: [ScoreNote], _ segments: [Segment], from start: PlayStart) -> PlayPass {
        guard segments.indices.contains(start.segment) else { return PlayPass(stretches: [], notes: []) }
        var stretches: [PlayPass.Stretch] = []
        var at = 0.0
        for (i, segment) in segments.enumerated() where i >= start.segment {
            let from = i == start.segment ? max(start.time, segment.start) : segment.start
            guard segment.end > from else { continue }
            stretches.append(PlayPass.Stretch(from: from, to: segment.end, at: at))
            at += segment.end - from
        }
        var sounded: [PassNote] = []
        for (i, stretch) in stretches.enumerated() {
            for note in notes {
                let struck = note.onset >= stretch.from - Score.sameTime && note.onset < stretch.to - Score.sameTime
                let held = i == 0 && note.onset < stretch.from && note.end > stretch.from + Score.sameTime
                guard struck || held else { continue }
                let begin = stretch.at + max(0, note.onset - stretch.from)
                let end = stretch.at + min(note.end, stretch.to) - stretch.from
                if end > begin { sounded.append(PassNote(pitch: note.pitch, start: begin, end: end)) }
            }
        }
        return PlayPass(stretches: stretches,
                        notes: sounded.sorted { ($0.start, $0.pitch) < ($1.start, $1.pitch) })
    }

    /// Every note of `runs`, each once, at its moments in the score, in
    /// order. A note is lit until it ends or its run does, so a run
    /// repeated does not leave its last notes lit into its start.
    static func notes(of runs: [RunID], _ practice: Practice, _ score: Score) -> [TimedNote] {
        var byNote: [NoteKey: TimedNote] = [:]
        for id in runs {
            guard let found = practice.find(id) else { continue }
            let (run, hand) = (found.run, found.hand)
            let steps = score.steps(hand)
            let runEnd = score.boundary(hand, run.last + 1)
            for index in run.steps where index < steps.count {
                for note in steps[index].notes {
                    let timed = TimedNote(
                        pitch: note.pitch, hand: hand, step: index,
                        on: note.onset, off: min(note.end, runEnd))
                    let key = NoteKey(hand: hand, step: index, pitch: note.pitch)
                    if let held = byNote[key], held.off >= timed.off { continue }
                    byNote[key] = timed
                }
            }
        }
        return byNote.values.sorted { ($0.on, $0.pitch) < ($1.on, $1.pitch) }
    }

    /// The keys lit at `time` seconds into the score, by `notes`: each
    /// note sounding then, and each hand's next step, which lights to say
    /// where the hand goes.
    static func lights(at time: Double, _ notes: [TimedNote]) -> [Int: [KeyLight]] {
        var lights: [Int: [KeyLight]] = [:]
        for note in notes where note.on <= time && time < note.off {
            lights[note.pitch, default: []].append(KeyLight(hand: note.hand, kind: .sounding(since: time - note.on)))
        }
        for hand in Hand.allCases {
            let ahead = notes.filter { $0.hand == hand && $0.on > time }
            guard let step = ahead.first?.step else { continue }
            for note in ahead where note.step == step && !(lights[note.pitch]?.contains { $0.hand == hand } ?? false) {
                lights[note.pitch, default: []].append(KeyLight(hand: hand, kind: .next))
            }
        }
        return lights.mapValues { $0.sorted { $0.order < $1.order } }
    }

    /// The keys of one step, lit as if it were sounding: a step looked at
    /// while a run is being cut.
    static func lights(of step: Step, _ hand: Hand) -> [Int: [KeyLight]] {
        Dictionary(step.notes.map { ($0.pitch, [KeyLight(hand: hand, kind: .sounding(since: .infinity))]) },
                   uniquingKeysWith: { a, _ in a })
    }

    /// The lowest and highest notes of `runs`, to bring the piano to.
    static func pitches(of runs: [RunID], _ practice: Practice, _ score: Score) -> ClosedRange<Int>? {
        let pitches = runs.compactMap { practice.find($0) }.flatMap { found in
            let steps = score.steps(found.hand)
            return found.run.steps.filter { $0 < steps.count }.flatMap { steps[$0].notes.map(\.pitch) }
        }
        guard let low = pitches.min(), let high = pitches.max() else { return nil }
        return low...high
    }

    private struct NoteKey: Hashable {
        let hand: Hand
        let step: Int
        let pitch: Int
    }
}

/// Where playing a list of segments begins: in which of them, and at what
/// moment of the score; repeats go back to the first segment's start.
struct PlayStart: Equatable, Sendable {
    let segment: Int
    let time: Double
}

/// A stretch of the score, in its seconds.
struct Segment: Equatable, Sendable {
    let start: Double
    let end: Double

    var duration: Double { end - start }
}

/// A note of the score lit on the piano, from when it is struck to when it
/// or its run ends, in score seconds.
struct TimedNote: Equatable, Sendable {
    let pitch: Int
    let hand: Hand
    /// The step of its hand's it is struck in.
    let step: Int
    let on: Double
    let off: Double
}

/// A key lit for a hand: sounding, struck `since` seconds ago, or the
/// hand's next.
struct KeyLight: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case sounding(since: Double)
        case next
    }

    let hand: Hand
    let kind: Kind

    fileprivate var order: Int {
        (hand == .right ? 0 : 2) + (kind == .next ? 1 : 0)
    }
}

/// One pass of playing: the stretches of the score heard one after
/// another, each from `from` to `to` score seconds and begun `at` seconds
/// into the pass, and the notes struck in them.
struct PlayPass: Equatable, Sendable {
    struct Stretch: Equatable, Sendable {
        let from: Double
        let to: Double
        let at: Double
    }

    let stretches: [Stretch]
    /// In order of when they are struck.
    let notes: [PassNote]

    /// How long the pass plays, in seconds.
    var length: Double {
        stretches.last.map { $0.at + $0.to - $0.from } ?? 0
    }

    /// The moment of the score heard `elapsed` seconds into the pass: its
    /// first moment before it starts, and its last once it has ended.
    func scoreTime(at elapsed: Double) -> Double {
        guard let first = stretches.first, let last = stretches.last else { return 0 }
        if elapsed <= 0 { return first.from }
        guard let stretch = stretches.last(where: { $0.at <= elapsed }) else { return first.from }
        let t = stretch.from + (elapsed - stretch.at)
        return stretch == last ? min(t, last.to) : min(t, stretch.to)
    }
}

/// A note of the score sounded in a pass: struck `start` seconds into it,
/// let go at `end`.
struct PassNote: Equatable, Sendable {
    let pitch: Int
    let start: Double
    let end: Double
}
