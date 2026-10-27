/// A loop being recorded from the keys: the chords played, each with the
/// moment it started and ended on the clock, in beats. Closing the take
/// turns them into notes for a timeline.
///
/// What is recorded is what was asked for (the chord, before the
/// arpeggiator), with everything it was played with as the note's own
/// settings, so the loop keeps its key, octave, sound and effects.
struct LoopTake {

    private struct Played {
        var start: Double
        var end: Double?
        var event: ChordEvent
        var pitch: NotePitch
        var playing: NotePlaying
        var changes: [(beats: Double, effects: NoteEffects)] = []
    }

    /// The clock's position when the take began.
    let start: Double
    private var chords: [Played] = []

    init(start: Double) {
        self.start = start
    }

    var isEmpty: Bool { chords.isEmpty }

    /// A chord started at `beats`. It replaces the one before, which ends there.
    mutating func chordStarted(_ event: ChordEvent, pitch: NotePitch, playing: NotePlaying, at beats: Double) {
        chordEnded(at: beats)
        chords.append(Played(start: beats, event: event, pitch: pitch, playing: playing))
    }

    /// The sounding chord ended at `beats`. Does nothing if none is sounding.
    mutating func chordEnded(at beats: Double) {
        guard let last = chords.indices.last, chords[last].end == nil else { return }
        chords[last].end = beats
    }

    /// The effects became `effects` at `beats`, while a chord was held: one
    /// point of a slide. Ignored when no chord is sounding, or nothing changed.
    mutating func effectsChanged(to effects: NoteEffects, at beats: Double) {
        guard let last = chords.indices.last, chords[last].end == nil else { return }
        let latest = chords[last].changes.last?.effects ?? chords[last].playing.effects
        guard effects != latest else { return }
        chords[last].changes.append((beats, effects))
    }

    /// The take's notes, closed at `end`, with `ticksPerBeat` ticks to each
    /// beat that was played. Times are ticks from the start of the take. A
    /// chord still held at the close ends there.
    func notes(closedAt end: Double, ticksPerBeat: Double) -> [TimelineNote] {
        func ticks(_ beats: Double) -> Int {
            Int(((beats - start) * ticksPerBeat).rounded())
        }
        return chords.compactMap { chord in
            let from = ticks(chord.start)
            let to = ticks(min(chord.end ?? end, end))
            guard to > from else { return nil }
            return TimelineNote(
                start: from,
                length: to - from,
                chord: chord.event.context.spec,
                pitch: chord.pitch,
                articulation: chord.event.articulation,
                playing: chord.playing,
                changes: chord.changes.compactMap { change in
                    let offset = ticks(change.beats) - from
                    return offset < to - from ? SoundChange(offset: max(offset, 0), effects: change.effects) : nil
                })
        }
    }
}

extension Timeline {

    /// The timeline with a take of `bars` bars layered on it: `lines`, each
    /// a line of notes timed from the start of the take, which began
    /// `offset` ticks into the timeline. Each line that played becomes a
    /// layer. A take on an empty timeline makes it `bars` long. Otherwise
    /// the timeline and the take are each repeated to the least length that
    /// is a whole number of both, so every layer comes round in time with
    /// the rest: a loop of one bar over one of four plays four times.
    func layering(_ lines: [[TimelineNote]], bars: Int, from offset: Int) -> Timeline {
        var layered = isEmpty ? Timeline(signature: signature, barCount: bars) : self
        layered.repeatNotes(toBars: Self.leastCommonMultiple(layered.barCount, bars))
        let period = bars * signature.ticksPerBar
        let start = isEmpty ? 0 : offset
        let laid = lines.map { layered.laidRound($0, every: period, from: start) }
        layered.add(layers: laid.filter { !$0.isEmpty })
        return layered
    }

    /// Makes the timeline `bars` long, a whole number of times its length,
    /// with every layer playing what it had again each time round.
    mutating func repeatNotes(toBars bars: Int) {
        guard bars > barCount, bars.isMultiple(of: barCount) else { return }
        let period = length
        let times = bars / barCount
        barCount = bars
        for index in layers.indices {
            let notes = layers[index].notes
            layers[index].notes = (0..<times).flatMap { round in
                notes.map { note in
                    var copy = note
                    copy.start += round * period
                    return copy
                }
            }
        }
    }

    /// `notes`, a take `period` ticks long begun `offset` ticks into the
    /// timeline, played again every `period` ticks all the way round it, as
    /// one line in order. `period` divides the timeline's length.
    func laidRound(_ notes: [TimelineNote], every period: Int, from offset: Int) -> [TimelineNote] {
        let repeated = (0..<length / period).flatMap { round in
            notes.map { note in
                var copy = note
                copy.start += round * period
                return copy
            }
        }
        // One time round the whole timeline from the offset: what passes the
        // end comes round to the start, where nothing else is.
        return folded(repeated, from: offset).flatMap { $0 }.sorted { $0.start < $1.start }
    }

    /// Adds a layer for each of `lines`. The first of them take the places
    /// of layers that are still empty.
    mutating func add(layers lines: [[TimelineNote]]) {
        for notes in lines {
            if let empty = layers.firstIndex(where: \.notes.isEmpty) {
                layers[empty].notes = notes
            } else {
                layers.append(Layer(notes: notes))
            }
        }
    }

    private static func leastCommonMultiple(_ a: Int, _ b: Int) -> Int {
        func greatestCommonDivisor(_ a: Int, _ b: Int) -> Int { b == 0 ? a : greatestCommonDivisor(b, a % b) }
        return a / greatestCommonDivisor(a, b) * b
    }

    /// `notes`, timed from `offset` ticks into the timeline, wrapped onto its
    /// length: one array for each time round, in order. A note that runs
    /// over the end carries on from the start of the next time round.
    func folded(_ notes: [TimelineNote], from offset: Int) -> [[TimelineNote]] {
        var rounds: [[TimelineNote]] = []
        for note in notes {
            var piece = note
            piece.start += offset
            while piece.length > 0 {
                let round = piece.start / length
                let start = piece.start % length
                let fits = min(piece.length, length - start)
                var placed = piece
                placed.start = start
                placed.length = fits
                placed.changes = piece.changes.filter { $0.offset < fits }
                while rounds.count <= round { rounds.append([]) }
                rounds[round].append(placed)

                piece.start += fits
                piece.length -= fits
                piece.changes = piece.changes.compactMap {
                    $0.offset >= fits ? SoundChange(offset: $0.offset - fits, effects: $0.effects) : nil
                }
            }
        }
        return rounds.filter { !$0.isEmpty }
    }
}
