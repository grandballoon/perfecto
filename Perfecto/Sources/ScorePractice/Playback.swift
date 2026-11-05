/// What is played of the recording, and what lights on the piano as it
/// plays: both worked out from the runs being watched, as values, so the
/// player and the piano only carry them out.
enum Playback {

    /// The stretches of the recording that play `runs`: each run's span,
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

    /// Where playing `segments` begins with the recording standing at
    /// `time`: at `time` itself if it is inside one, so play goes on from
    /// where the recording was left or dragged to; otherwise at the start of
    /// the next one after it, or of the first when none is after it. A
    /// recording standing at a segment's very end (`nearEnd`), as one that
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

    /// How near a segment's end the recording is taken to have played it.
    static let nearEnd = 0.05

    /// Every note of `runs`, each once, at the moments the recording has
    /// it, in order. A note is lit until it ends or its run does, so a run
    /// repeated does not leave its last notes lit into its start.
    static func notes(of runs: [RunID], _ practice: Practice, _ score: Score) -> [TimedNote] {
        var byNote: [NoteKey: TimedNote] = [:]
        let alignment = practice.alignment
        for id in runs {
            guard let found = practice.find(id) else { continue }
            let (run, hand) = (found.run, found.hand)
            let steps = score.steps(hand)
            let runEnd = score.boundary(hand, run.last + 1)
            for index in run.steps where index < steps.count {
                for note in steps[index].notes {
                    let timed = TimedNote(
                        pitch: note.pitch, hand: hand, step: index,
                        on: Alignment.recordingTime(note.onset, alignment),
                        off: Alignment.recordingTime(min(note.end, runEnd), alignment))
                    let key = NoteKey(hand: hand, step: index, pitch: note.pitch)
                    if let held = byNote[key], held.off >= timed.off { continue }
                    byNote[key] = timed
                }
            }
        }
        return byNote.values.sorted { ($0.on, $0.pitch) < ($1.on, $1.pitch) }
    }

    /// The keys lit at `time` seconds into the recording, by `notes`: each
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
/// moment of the recording; repeats go back to the first segment's start.
struct PlayStart: Equatable, Sendable {
    let segment: Int
    let time: Double
}

/// A stretch of the recording, in its seconds.
struct Segment: Equatable, Sendable {
    let start: Double
    let end: Double

    var duration: Double { end - start }
}

/// A note of the score at the moments the recording has it.
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

/// A recording's loudness, drawn as its outline: the largest sample of
/// each stretch of `frames` frames.
enum Waveform {
    static func peaks(_ samples: [Float], frames: Int) -> [Float] {
        guard frames > 0 else { return [] }
        return stride(from: 0, to: samples.count, by: frames).map { start in
            samples[start..<min(start + frames, samples.count)].reduce(0) { max($0, abs($1)) }
        }
    }
}
