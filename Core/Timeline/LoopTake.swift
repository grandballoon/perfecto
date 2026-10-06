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

    /// The bars and tempo a first loop is taken to be. A loop played with
    /// no metronome lasted `beats` beats at `bpm`; it is read as the whole
    /// number of bars that puts the tempo nearest `bpm`, and the tempo is
    /// what makes it exactly that many. If that tempo is outside `tempos`,
    /// the bar count gives until it is not.
    static func fit(loopOf beats: Double, at bpm: Double, signature: TimeSignature,
                    tempos: ClosedRange<Double> = MusicalTime.tempoRange) -> (bars: Int, bpm: Double) {
        let bar = signature.quarterBeatsPerBar
        var bars = max(1, Int((beats / bar).rounded()))
        func tempo(_ bars: Int) -> Double { bpm * Double(bars) * bar / beats }
        while tempo(bars) > tempos.upperBound, bars > 1 { bars -= 1 }
        while tempo(bars) < tempos.lowerBound { bars += 1 }
        return (bars, tempo(bars).clamped(to: tempos))
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
