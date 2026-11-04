/// The recording matched to the score by ear: an anchor at every moment
/// a note of the score is struck, so the runs line up with no help, and
/// the stretches where the match is doubtful, to be looked at.
///
/// It is audio-to-score alignment, done in two passes:
///
/// 1. The recording's pitch classes (`RecordingFeatures`) and the score's
///    (`ScoreChroma`), and the classes struck in each, are compared a few
///    dozen times a second (the strikes are what tell one bar of a repeated
///    chord from the next), and dynamic
///    time warping finds the path through the two that agrees best, end to
///    end. It follows rubato, pauses and changes of tempo, because the
///    whole piece is matched at once. The score is first stretched to the
///    length the recording sounds for, so the path runs near the diagonal,
///    and its pace is kept between half and twice that, and every path
///    weighs the same, so no tempo is favoured. It begins where the
///    recording first sounds and ends where it last does, so silence
///    either side of the playing is passed over.
/// 2. Each moment of the score the path gives a time is then moved to
///    where its own notes' pitch classes rise most nearby, a hundredth of
///    a second at a time, which is where they are struck.
///
/// The learner's pins (`Practice.anchors`) are held to: the path is found
/// stretch by stretch between them, so it passes through each, and a
/// nudge rematches only the music either side of it.
enum AutoMatch {

    struct Result: Equatable, Sendable {
        /// Score seconds to recording seconds, at each moment a note is
        /// struck, in order.
        let anchors: [AlignmentAnchor]
        /// Where the match is doubtful, in recording seconds: the start of
        /// each stretch whose sound agrees poorly with the score's.
        let unsure: [Double]
    }

    /// The most cells of the path's grid, which bounds its memory (a byte
    /// a cell) and its time.
    static let maxCells = 16_000_000
    /// How often the score and the recording are compared, at most.
    static let maxRate = 20.0
    /// How long the recording may ring on after the score's last note, in
    /// seconds.
    static let ringOn = 4.0
    /// How much the strikes count against the classes in comparing a
    /// moment of the score with one of the recording.
    static let strikeWeight: Float = 0.65

    static func match(_ score: Score, _ recording: RecordingFeatures,
                      pins: [AlignmentAnchor] = []) -> Result {
        let notes = score.notes.sorted { $0.onset < $1.onset }
        guard let first = notes.first, recording.frames > 1 else { return Result(anchors: [], unsure: []) }
        let scoreStart = first.onset
        let scoreEnd = notes.map(\.end).max() ?? first.end
        let sounding = soundingRange(recording)
        let recordingLength = recording.duration

        // The score stretched to the length the recording sounds for.
        let stretch = max(scoreEnd - scoreStart, 0.1) / max(sounding.upperBound - sounding.lowerBound, 0.1)
        let rate = min(maxRate, (Double(maxCells) / max(recordingLength * recordingLength, 1)).squareRoot())
        let scoreStep = stretch / rate                 // score seconds a frame
        let n = max(2, Int((scoreEnd / scoreStep).rounded(.up)) + 1)
        let m = max(2, Int(recordingLength * rate))

        let scoreFrames = (0..<n).map { i in
            let t = Double(i) * scoreStep
            return unit(ScoreChroma.at(t, notes)) + unit(ScoreChroma.struck(t - scoreStep / 2, t + scoreStep / 2, notes))
        }
        let audioFrames = coarse(recording, rate: rate, frames: m)

        // The path, stretch by stretch between the pins.
        let held = pins.filter { pin in
            (0...scoreEnd).contains(pin.score) && (0...recordingLength).contains(pin.recording)
        }.sorted { $0.score < $1.score }
        // The playing begins where the recording first sounds and ends where
        // it last does, unless pins say otherwise.
        let iFirst = min(n - 1, Int(scoreStart / scoreStep))
        let jFirst = min(m - 1, Int(sounding.lowerBound * rate))
        let jLast = min(m - 1, max(jFirst + 1, Int(sounding.upperBound * rate)))
        var ends: [(i: Int, j: Int)] = []
        for pin in held {
            let i = min(n - 1, Int((pin.score / scoreStep).rounded()))
            let j = min(m - 1, Int((pin.recording * rate).rounded()))
            if let last = ends.last, i <= last.i || j <= last.j { continue }
            ends.append((i, j))
        }
        if ends.first.map({ $0.i > iFirst && $0.j > jFirst }) ?? true { ends.insert((iFirst, jFirst), at: 0) }
        if ends.last!.i < n - 1 && ends.last!.j < jLast { ends.append((n - 1, jLast)) }
        var entry = [Int](repeating: 0, count: n)       // the first audio frame each score frame meets
        // How well the path agrees with the recording at each audio frame
        // it crosses; nil off the path.
        var along = [Float?](repeating: nil, count: m)
        // Before the first end, and after the last, the score keeps the pace
        // it was stretched to.
        for i in 0..<ends[0].i { entry[i] = max(0, ends[0].j - (ends[0].i - i)) }
        for k in 0..<(ends.count - 1) {
            let from = ends[k], to = ends[k + 1]
            // The last stretch, unless pinned, may end before the sound
            // does: a pedal or a hall rings on after the last note.
            let openEnd = k == ends.count - 2 && !held.contains { abs($0.score - scoreEnd) < Score.sameTime }
                && to.i == n - 1
            let ringing = openEnd ? min(to.j - from.j - 1, Int(ringOn * rate)) : 0
            if !warp(scoreFrames, audioFrames, i: from.i...to.i, j: from.j...to.j, endsWithin: ringing,
                     entry: &entry, along: &along) {
                // No path at a pace that fits: evenly between the two.
                for r in from.i...to.i {
                    entry[r] = from.j + (to.j - from.j) * (r - from.i) / max(1, to.i - from.i)
                }
            }
        }
        if let last = ends.last, last.i < n - 1 {
            for i in (last.i + 1)..<n { entry[i] = min(m - 1, last.j + (i - last.i)) }
        }

        // Each moment a note is struck, by the path, then by its own notes.
        var onsets: [(t: Double, classes: Set<Int>)] = []
        for note in notes {
            if let last = onsets.last, note.onset - last.t < Score.sameTime {
                onsets[onsets.count - 1].classes.insert(note.pitch % 12)
            } else {
                onsets.append((note.onset, [note.pitch % 12]))
            }
        }
        let estimates = onsets.map { onset -> Double in
            let at = onset.t / scoreStep
            let i = min(n - 2, max(0, Int(at)))
            let f = at - Double(i)
            // A frame's moment is its middle.
            return ((Double(entry[i]) * (1 - f) + Double(entry[i + 1]) * f) + 0.5) / rate
        }
        // How far from the path a strike is looked for: the long window
        // hears a note a little before it is struck.
        let reach = max(0.2, 4 / rate)
        var anchors: [AlignmentAnchor] = []
        for (k, onset) in onsets.enumerated() {
            let low = max(estimates[k] - reach, (anchors.last?.recording ?? -1) + 0.03, 0)
            let high = min(estimates[k] + reach, k + 1 < estimates.count ? estimates[k + 1] - 0.03 : recordingLength)
            var at = estimates[k]
            if high > low, let struck = strike(onset.classes, in: recording, between: low...high) {
                at = struck
            } else {
                // Not near the path: further, but never past the notes either side.
                let wideLow = max(estimates[k] - 2.5 * reach, (anchors.last?.recording ?? -1) + 0.03, 0)
                let wideHigh = min(estimates[k] + 2.5 * reach,
                                   k + 1 < estimates.count ? estimates[k + 1] + reach - 0.03 : recordingLength)
                if wideHigh > wideLow,
                   let struck = strike(onset.classes, in: recording, between: wideLow...wideHigh) { at = struck }
            }
            if let last = anchors.last, at <= last.recording { at = last.recording + 0.005 }
            anchors.append(AlignmentAnchor(score: onset.t, recording: at))
        }
        anchors = steadied(anchors, onsets.map(\.classes), in: recording, pins: held)
        let pinned = Alignment.merged(pins: held, matched: anchors)
        return Result(anchors: pinned.filter { a in !held.contains { abs($0.score - a.score) < Score.sameTime } },
                      unsure: doubtful(along, rate: rate))
    }

    // MARK: – Steadying

    /// `anchors` with any that break the pace of those around them found
    /// again. Repeated chords all sound alike, so the path can put a run
    /// of them a chord early or late; but a player's pace changes smoothly
    /// over a few seconds. Each anchor is set against the line most of the
    /// anchors within `steadyReach` of it lie on, and one far off it is
    /// looked for again where the line puts it, unless it lies on the line
    /// of those before it or of those after it alone: that is where the
    /// pace changes, a pause or a hurry, and is left.
    private static func steadied(_ anchors: [AlignmentAnchor], _ classes: [Set<Int>],
                                 in recording: RecordingFeatures, pins: [AlignmentAnchor]) -> [AlignmentAnchor] {
        guard anchors.count > 4 else { return anchors }
        var result = anchors
        for _ in 0..<2 {
            let fixed = result
            for k in fixed.indices {
                let t = fixed[k].score
                if pins.contains(where: { abs($0.score - t) < Score.sameTime }) { continue }
                // The line of the anchors around it, and of those before it
                // and those after it on their own.
                let before = fixed.indices.filter { $0 < k && t - fixed[$0].score <= steadyReach }
                let after = fixed.indices.filter { $0 > k && fixed[$0].score - t <= steadyReach }
                guard before.count + after.count >= 4, let line = fit((before + after).map { fixed[$0] }) else { continue }
                // Near the ends of the piece there is one side only, and that
                // side alone could be a run that is out.
                let sides = before.count >= 3 && after.count >= 3
                    ? [before, after].compactMap { side in fit(side.map { fixed[$0] }) } : []
                // Half the way to the anchors either side, at the line's pace.
                let gapBefore = k > 0 ? (t - fixed[k - 1].score) * line.pace : 1
                let gapAfter = k + 1 < fixed.count ? (fixed[k + 1].score - t) * line.pace : 1
                let room = 0.45 * min(gapBefore, gapAfter)
                // On the line of either side alone, it is where the music
                // turns: a pause, or a hurry, is heard on one side only.
                guard ([line] + sides).allSatisfy({ abs(fixed[k].recording - $0.at(t)) > room }) else { continue }
                let expected = line.at(t)
                let low = max(expected - room, k > 0 ? result[k - 1].recording + 0.03 : 0)
                let high = min(expected + room, k + 1 < fixed.count ? fixed[k + 1].recording - 0.03 : .infinity)
                guard high > low else { continue }
                result[k] = AlignmentAnchor(score: t, recording: strike(classes[k], in: recording, between: low...high)
                                            ?? expected.clamped(low...high))
            }
        }
        return result
    }

    /// How far either side of an anchor, in score seconds, its pace is
    /// judged over.
    static let steadyReach = 4.0

    private struct Line {
        let start: Double
        let pace: Double
        func at(_ t: Double) -> Double { start + pace * t }
    }

    /// The straight line through `anchors` that most of them lie on: its
    /// pace the middle one of the paces between every two of them, and its
    /// place the middle one that pace gives (Theil and Sen's line), so a
    /// few anchors a chord out cannot pull it toward them.
    private static func fit(_ anchors: [AlignmentAnchor]) -> Line? {
        var paces: [Double] = []
        for a in anchors.indices {
            for b in anchors.indices where b > a {
                let ds = anchors[b].score - anchors[a].score
                if ds > Score.sameTime { paces.append((anchors[b].recording - anchors[a].recording) / ds) }
            }
        }
        guard !paces.isEmpty else { return nil }
        let pace = paces.sorted()[paces.count / 2]
        guard pace > 0 else { return nil }
        let starts = anchors.map { $0.recording - pace * $0.score }.sorted()
        return Line(start: starts[starts.count / 2], pace: pace)
    }

    // MARK: – The path

    /// The cheapest path from the first corner of `i` × `j` to the last,
    /// by steps of one score frame and one audio frame, two and one, or one
    /// and two, so the music goes at no less than half the pace it was
    /// stretched to and no more than twice it, and never stands still in
    /// one while the other goes on. Its cells are weighed so that every
    /// path between the corners weighs the same (Sakoe and Chiba's
    /// symmetric steps), so no pace is favoured. With `ringing`, it may end
    /// that many audio frames before the last corner, wherever costs least
    /// for its length. False if no path fits, for two pins too close or too
    /// far apart for those paces.
    @discardableResult
    private static func warp(_ s: [[Float]], _ a: [[Float]], i: ClosedRange<Int>, j: ClosedRange<Int>,
                             endsWithin ringing: Int = 0, entry: inout [Int], along: inout [Float?]) -> Bool {
        let rows = i.count, cols = j.count
        // How each cell was reached: 0 by one and one, 1 by two score
        // frames and one audio frame, 2 by one and two.
        var step = [UInt8](repeating: 0, count: rows * cols)
        var twoBack = [Float](repeating: .infinity, count: cols)
        var oneBack = [Float](repeating: .infinity, count: cols)
        var current = [Float](repeating: .infinity, count: cols)
        func c(_ r: Int, _ q: Int) -> Float {
            let x = s[i.lowerBound + r], y = a[j.lowerBound + q]
            // How the classes agree, and how the strikes do.
            var classes: Float = 0, strikes: Float = 0
            for d in 0..<13 { classes += x[d] * y[d] }
            for d in 13..<26 { strikes += x[d] * y[d] }
            return 1 - (1 - strikeWeight) * classes - strikeWeight * strikes
        }
        // Row r's costs for the columns a path can reach it in.
        var previousCost = [Float](repeating: 0, count: cols)   // c(r - 1, q)
        var currentCost = [Float](repeating: 0, count: cols)
        for r in 0..<rows {
            for q in 0..<cols { currentCost[q] = c(r, q) }
            for q in 0..<cols {
                current[q] = .infinity
                if r == 0 {
                    if q == 0 { current[0] = currentCost[0] }
                    continue
                }
                guard q > 0 else { continue }
                var best = oneBack[q - 1] + 2 * currentCost[q]
                var how: UInt8 = 0
                if r > 1 {
                    let two = twoBack[q - 1] + 2 * previousCost[q] + currentCost[q]
                    if two < best { best = two; how = 1 }
                }
                if q > 1 {
                    let wide = oneBack[q - 2] + 2 * currentCost[q - 1] + currentCost[q]
                    if wide < best { best = wide; how = 2 }
                }
                current[q] = best
                step[r * cols + q] = how
            }
            swap(&twoBack, &oneBack)
            swap(&oneBack, &current)
            swap(&previousCost, &currentCost)
        }
        // The last corner, or with room to ring, the end among the last
        // columns that costs least for the length of its path.
        var end = cols - 1
        for k in max(0, cols - 1 - ringing)..<cols where oneBack[k].isFinite {
            if !oneBack[end].isFinite || oneBack[k] / Float(rows + k) < oneBack[end] / Float(rows + end) { end = k }
        }
        guard oneBack[end].isFinite else { return false }
        var r = rows - 1, q = end
        // Walked backwards, the last cell met on a row is its first.
        func visit(_ r: Int, _ q: Int) {
            entry[i.lowerBound + r] = j.lowerBound + q
            // Doubt is judged by the classes alone: strikes are sparse, and
            // a strike a frame off would count as music out of place.
            let x = s[i.lowerBound + r], y = a[j.lowerBound + q]
            var classes: Float = 0
            for d in 0..<13 { classes += x[d] * y[d] }
            along[j.lowerBound + q] = 1 - classes
        }
        visit(r, q)
        while r > 0 || q > 0 {
            switch step[r * cols + q] {
            case 0:
                r -= 1; q -= 1
            case 1:
                visit(r - 1, q)
                r -= 2; q -= 1
            default:
                visit(r, q - 1)
                r -= 1; q -= 2
            }
            visit(r, q)
        }
        return true
    }

    // MARK: – Features

    /// From the recording's first sound to its last, in seconds.
    static func soundingRange(_ recording: RecordingFeatures) -> ClosedRange<Double> {
        let levels = (0..<recording.frames).map { recording.frame($0).reduce(0, +) }
        let loud = levels.sorted()[Int(Double(levels.count - 1) * 0.95)]
        let floor = max(loud * silence, 1e-6)
        let first = levels.firstIndex { $0 > floor } ?? 0
        let last = levels.lastIndex { $0 > floor } ?? (recording.frames - 1)
        return (Double(first) / RecordingFeatures.rate)...(Double(max(first, last)) / RecordingFeatures.rate)
    }

    /// Below this share of the recording's loud level, a frame is silence.
    private static let silence: Float = 0.1

    /// The recording at `rate` frames a second: its classes averaged over
    /// each frame and made unit length, with a thirteenth value that is the
    /// whole of a frame of silence; then how its classes rise over the
    /// frame, the same way, with a thirteenth that is the whole of a frame
    /// in which nothing is struck.
    private static func coarse(_ recording: RecordingFeatures, rate: Double, frames m: Int) -> [[Float]] {
        let levels = (0..<recording.frames).map { recording.frame($0).reduce(0, +) }
        let loud = levels.sorted()[Int(Double(levels.count - 1) * 0.95)]
        let floor = max(loud * silence, 1e-6)
        let per = RecordingFeatures.rate / rate
        return (0..<m).map { j in
            let low = Int(Double(j) * per), high = min(recording.frames, max(low + 1, Int(Double(j + 1) * per)))
            var v = [Float](repeating: 0, count: 12)
            var rises = [Float](repeating: 0, count: 12)
            var level: Float = 0
            for k in low..<high {
                for pc in 0..<12 {
                    v[pc] += recording.chroma[k * 12 + pc]
                    rises[pc] += recording.rise(k, pc)
                }
                level += levels[k]
            }
            let classes = level / Float(max(1, high - low)) > floor ? unit(v) : silent
            return classes + unit(rises.map { max(0, $0 - riseFloor) }, least: riseFloor)
        }
    }

    /// A rise this small in a frame is the sound wavering, not a strike.
    private static let riseFloor: Float = 0.1

    private static let silent: [Float] = Array(repeating: 0, count: 12) + [1]

    /// `v` made unit length, with its thirteenth value nought; silence if
    /// it is no longer than `least`.
    private static func unit(_ v: [Float], least: Float = 1e-6) -> [Float] {
        let length = v.reduce(0) { $0 + $1 * $1 }.squareRoot()
        guard length > least else { return silent }
        return v.map { $0 / length } + [0]
    }

    // MARK: – Striking and doubt

    /// Where in `range` (recording seconds) the pitch classes `classes`
    /// rise most together, if they rise enough to be a note struck.
    private static func strike(_ classes: Set<Int>, in recording: RecordingFeatures,
                               between range: ClosedRange<Double>) -> Double? {
        let low = max(1, Int((range.lowerBound * RecordingFeatures.rate).rounded(.up)))
        let high = min(recording.frames - 1, Int((range.upperBound * RecordingFeatures.rate).rounded(.down)))
        guard high >= low else { return nil }
        var best = low
        var bestRise: Float = 0
        for k in low...high {
            let rise = classes.reduce(Float(0)) { $0 + recording.rise(k, $1) }
            if rise > bestRise { bestRise = rise; best = k }
        }
        return bestRise >= struck * Float(classes.count).squareRoot() ? Double(best) / RecordingFeatures.rate : nil
    }

    /// How much a note's classes must rise to count as struck.
    private static let struck: Float = 0.15

    /// The moments where the sound agrees poorly with the score: the path's
    /// cost over each two seconds of the recording it crosses, against the
    /// piece's own usual cost. One mark to a stretch, where it begins, and
    /// two seconds apart at least.
    private static func doubtful(_ along: [Float?], rate: Double) -> [Double] {
        let crossed = along.compactMap { $0 }
        guard !crossed.isEmpty else { return [] }
        let usual = crossed.sorted()[crossed.count / 2]
        let limit = max(0.45, usual * 1.8)
        let width = max(1, Int(2 * rate))
        var marks: [Double] = []
        var inside = false
        for j in along.indices {
            let window = along[j..<min(along.count, j + width)].compactMap { $0 }
            guard window.count * 2 >= width else { inside = false; continue }
            let mean = window.reduce(0, +) / Float(window.count)
            let at = Double(j) / rate
            if mean > limit {
                if !inside, at - (marks.last ?? -.infinity) >= 2 { marks.append(at) }
                inside = true
            } else {
                inside = false
            }
        }
        return marks
    }
}

private extension Double {
    func clamped(_ range: ClosedRange<Double>) -> Double { Swift.min(Swift.max(self, range.lowerBound), range.upperBound) }
}
