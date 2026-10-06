import Foundation

// The edits a timeline can have. Each is a plain change to a value, so it
// can be tested with no screen and undone by keeping the value from before.
//
// Places are steps of the grid (sixteenths, counted from the start of the
// timeline), since that is what a finger selects. A note belongs to the step
// whose line its start is nearest (`TimelineNote.step`) and is on every step
// it is drawn across (`TimelineNote.steps`), so what an edit changes is what
// the grid shows selected.

extension Layer {

    // MARK: – Reading

    /// The notes on any of `steps`.
    func indicesOfNotes(on steps: Set<Int>) -> [Int] {
        notes.indices.filter { notes[$0].steps.contains(where: steps.contains) }
    }

    /// The note on `step`, if there is one. Of two (both played loosely,
    /// nearest the same line) it is the later.
    func note(on step: Int) -> TimelineNote? {
        notes.last { $0.steps.contains(step) }
    }

    /// How long the note at `index` may be: up to the next note's start, or
    /// to `limit`, the end of the timeline.
    private func room(for index: Int, limit: Int) -> Int {
        max((index + 1 < notes.count ? notes[index + 1].start : limit) - notes[index].start, 1)
    }

    // MARK: – Notes

    /// Puts `note` in, making room for it: whatever started inside its time
    /// goes, and a note still sounding when it starts is cut short there.
    mutating func insert(_ note: TimelineNote) {
        clear(note.start..<note.end)
        let index = notes.firstIndex { $0.start > note.start } ?? notes.count
        notes.insert(note, at: index)
    }

    /// Empties `range`: a note that starts inside it goes, and a note
    /// still sounding when it begins ends there.
    mutating func clear(_ range: Range<Int>) {
        notes.removeAll { range.contains($0.start) }
        for index in notes.indices where notes[index].start < range.lowerBound && notes[index].end > range.lowerBound {
            notes[index].length = range.lowerBound - notes[index].start
        }
    }

    /// Puts `chord` on each of `steps`, one note to a step, replacing the
    /// note that was its. New notes take `playing` and sound for `gate` of
    /// the step, or until the next note if that is sooner.
    mutating func place(_ chord: ChordSpec, onSteps steps: Set<Int>,
                        playing: NotePlaying = NotePlaying(),
                        gate: Double = TimelineNote.enteredGate) {
        let length = min(max(1, Int((gate * Double(TimelineTime.ticksPerStep)).rounded())), TimelineTime.ticksPerStep)
        for step in steps.sorted() {
            let line = TimelineTime.line(ofStep: step)
            notes.removeAll { $0.step == step }
            let room = (notes.first { $0.start > line }?.start ?? .max) - line
            insert(TimelineNote(start: line, length: min(length, room), chord: chord, playing: playing))
        }
    }

    /// Empties `steps`: a note drawn across more steps than these is cut at
    /// their edges, and keeps what is outside them.
    mutating func rest(onSteps steps: Set<Int>) {
        split(steps: steps)
        notes.removeAll { steps.contains($0.step) }
    }

    /// Makes each run of neighbouring steps in `steps` one long note: the
    /// first note on the run, held to the run's end (or to the next note, if
    /// one starts a little before that). The run's other notes go. A run
    /// with no note on it is left empty.
    mutating func join(steps: Set<Int>) {
        for run in Self.runs(of: steps) {
            guard let first = notes.firstIndex(where: { $0.steps.overlaps(run) }) else { continue }
            let start = notes[first].start
            notes.removeAll { run.contains($0.step) && $0.start != start }
            let held = max(TimelineTime.line(ofStep: run.upperBound) - start, notes[first].length)
            notes[first].length = min(held, room(for: first, limit: .max))
        }
    }

    /// Cuts every note on `steps` at the edges of each of them it is drawn
    /// across, so each selected step it covered has a note of its own.
    mutating func split(steps: Set<Int>) {
        for step in Set(steps.flatMap { [$0, $0 + 1] }).sorted() {
            guard let index = notes.firstIndex(where: { $0.steps.contains(step - 1) && $0.steps.contains(step) })
            else { continue }
            cut(index, at: TimelineTime.line(ofStep: step))
        }
    }

    /// Cuts the note at `index` in two at `tick`, which is inside it. A
    /// slide played across the cut carries on in the second note.
    private mutating func cut(_ index: Int, at tick: Int) {
        let offset = tick - notes[index].start
        var tail = notes[index]
        tail.start = tick
        tail.length = notes[index].end - tick
        if let before = tail.changes.last(where: { $0.offset < offset }) {
            tail.playing.effects = before.effects
        }
        tail.changes = tail.changes.filter { $0.offset >= offset }.map {
            SoundChange(offset: $0.offset - offset, effects: $0.effects)
        }
        notes[index].length = offset
        notes[index].changes.removeAll { $0.offset >= offset }
        notes.insert(tail, at: index + 1)
    }

    /// Changes the length of the notes on `steps` by `ticks` (shorter if
    /// negative). A note keeps at least one tick, and stops where the next
    /// note starts or at `limit`, the end of the timeline.
    mutating func lengthen(notesOn steps: Set<Int>, by ticks: Int, limit: Int) {
        for index in indicesOfNotes(on: steps) {
            notes[index].length = min(max(notes[index].length + ticks, 1), room(for: index, limit: limit))
        }
    }

    /// Sets how much of its last step each note on `steps` sounds for
    /// (`gate`, 0 to 1), keeping the steps it is held across: what makes a
    /// chord crisp or runs it into the next.
    mutating func hold(notesOn steps: Set<Int>, forGate gate: Double, limit: Int) {
        let step = TimelineTime.ticksPerStep
        for index in indicesOfNotes(on: steps) {
            let whole = notes[index].heldSteps - 1
            let length = whole * step + max(1, Int((gate * Double(step)).rounded()))
            notes[index].length = min(length, room(for: index, limit: limit))
        }
    }

    /// Moves the starts and ends of the notes on `steps` to the nearest
    /// step lines: what tidies a loosely played loop. A note keeps at least
    /// a step, and two notes that land on one step line keep the later one.
    mutating func snap(notesOn steps: Set<Int>, limit: Int) {
        let step = TimelineTime.ticksPerStep
        var snapped: [TimelineNote] = []
        for note in notes {
            guard note.steps.contains(where: steps.contains) else {
                snapped.append(note)
                continue
            }
            var moved = note
            moved.start = min(TimelineTime.nearestStepLine(to: note.start), max(limit - step, 0))
            moved.length = max(TimelineTime.nearestStepLine(to: note.end) - moved.start, step)
            snapped.append(moved)
        }
        notes = []
        for note in snapped.sorted(by: { $0.start < $1.start }) {
            var note = note
            note.length = min(note.length, max(limit - note.start, 1))
            insert(note)
        }
    }

    /// Changes the notes on `steps`.
    mutating func edit(notesOn steps: Set<Int>, _ change: (inout TimelineNote) -> Void) {
        for index in indicesOfNotes(on: steps) {
            let (start, length) = (notes[index].start, notes[index].length)
            change(&notes[index])
            // Where a note is and how long is for the edits above to say.
            notes[index].start = start
            notes[index].length = length
        }
    }

    /// The runs of neighbouring steps in `steps`, each as a range of steps.
    static func runs(of steps: Set<Int>) -> [Range<Int>] {
        var runs: [Range<Int>] = []
        for step in steps.sorted() {
            if let last = runs.last, last.upperBound == step {
                runs[runs.count - 1] = last.lowerBound ..< step + 1
            } else {
                runs.append(step ..< step + 1)
            }
        }
        return runs
    }
}

extension Timeline {

    // MARK: – Bars

    /// Adds an empty bar at the end.
    mutating func addBar() {
        barCount += 1
    }

    var canRemoveBar: Bool { barCount > 1 }

    /// Removes `bar` (counted from 0): its notes go, later notes move up,
    /// and a note sounding into it ends where it began. A loop that lay
    /// wholly inside the bar goes with it. The last bar stays.
    mutating func removeBar(_ bar: Int) {
        guard canRemoveBar, (0..<barCount).contains(bar) else { return }
        let removed = bar * signature.ticksPerBar ..< (bar + 1) * signature.ticksPerBar
        for index in layers.indices {
            layers[index].clear(removed)
            for note in layers[index].notes.indices where layers[index].notes[note].start >= removed.upperBound {
                layers[index].notes[note].start -= removed.count
            }
        }
        if let loop {
            /// Where a tick is after the removal; a tick inside the bar lands at its start.
            func moved(_ tick: Int) -> Int {
                tick >= removed.upperBound ? tick - removed.count : min(tick, removed.lowerBound)
            }
            let range = moved(loop.lowerBound) ..< moved(loop.upperBound)
            self.loop = range.isEmpty ? nil : range
        }
        barCount -= 1
    }

    /// Drops the empty bars at the end, keeping at least one: what cuts the
    /// silence off a loop that was closed late.
    mutating func trimEmptyBars() {
        let lastTick = layers.flatMap(\.notes).map(\.end).max() ?? 0
        let needed = Int((Double(lastTick) / Double(signature.ticksPerBar)).rounded(.up))
        barCount = min(barCount, max(needed, 1))
        if let loop { self.loop = loop.clamped(to: 0..<length).isEmpty ? nil : loop.clamped(to: 0..<length) }
    }

    /// Reads the same notes as twice as many bars: everything is twice as
    /// far along and twice as long. For a loop whose bar count was guessed
    /// too low; played at twice the tempo it sounds as it did.
    mutating func doubleBars() {
        barCount *= 2
        scale { $0 * 2 }
    }

    /// Whether the timeline can be read as half as many bars.
    var canHalveBars: Bool { barCount.isMultiple(of: 2) }

    /// Reads the same notes as half as many bars. Notes keep at least a tick.
    mutating func halveBars() {
        guard canHalveBars else { return }
        barCount /= 2
        scale { $0 / 2 }
    }

    private mutating func scale(_ scaled: (Int) -> Int) {
        for layer in layers.indices {
            for note in layers[layer].notes.indices {
                let end = scaled(layers[layer].notes[note].end)
                layers[layer].notes[note].start = scaled(layers[layer].notes[note].start)
                layers[layer].notes[note].length = max(end - layers[layer].notes[note].start, 1)
                for change in layers[layer].notes[note].changes.indices {
                    layers[layer].notes[note].changes[change].offset = scaled(layers[layer].notes[note].changes[change].offset)
                }
            }
        }
        if let loop { self.loop = scaled(loop.lowerBound) ..< scaled(loop.upperBound) }
    }

    /// Changes the time signature. Notes stay on their ticks, so nothing
    /// moves in time; there are as many bars of the new length as hold
    /// everything that was there.
    mutating func setSignature(_ new: TimeSignature) {
        let oldLength = length
        signature = new
        barCount = max(1, Int((Double(oldLength) / Double(new.ticksPerBar)).rounded(.up)))
    }

    // MARK: – Loop

    /// Makes playback repeat the stretch from the first of `steps` to the
    /// last. No steps repeats the whole timeline.
    mutating func setLoop(steps: Set<Int>) {
        guard let first = steps.min(), let last = steps.max() else {
            loop = nil
            return
        }
        loop = first * TimelineTime.ticksPerStep ..< (last + 1) * TimelineTime.ticksPerStep
    }

    // MARK: – Layers

    /// Adds an empty layer and returns its id.
    @discardableResult
    mutating func addLayer() -> Layer.ID {
        let layer = Layer()
        layers.append(layer)
        return layer.id
    }

    /// Adds a copy of `id` after it and returns the copy's id.
    @discardableResult
    mutating func duplicateLayer(_ id: Layer.ID) -> Layer.ID? {
        guard let index = layers.firstIndex(where: { $0.id == id }) else { return nil }
        var copy = Layer(notes: layers[index].notes)
        copy.isMuted = layers[index].isMuted
        copy.volume = layers[index].volume
        layers.insert(copy, at: index + 1)
        return copy.id
    }

    /// Removes `id`. A timeline always has a layer: removing the last one
    /// leaves an empty one in its place.
    mutating func removeLayer(_ id: Layer.ID) {
        layers.removeAll { $0.id == id }
        if layers.isEmpty { layers = [Layer()] }
    }

    /// Changes the layer `id`, if there is one.
    mutating func edit(layer id: Layer.ID, _ change: (inout Layer) -> Void) {
        guard let index = layers.firstIndex(where: { $0.id == id }) else { return }
        change(&layers[index])
    }
}
