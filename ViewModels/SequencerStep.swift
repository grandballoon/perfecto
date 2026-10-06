/// One step of a layer as the step editor sees and edits it: the chord on
/// it, how much of the step it sounds for, or a rest.
///
/// A layer holds notes of any length; this is the view of it one step at a
/// time. A step a long note runs through reads as that chord, tied (its
/// gate full), and writing a tied step beside the same chord makes one long
/// note of the two, so tying steps and holding a chord are the same thing.
struct SequencerStep: Codable, Equatable {
    var degree: Degree = .I
    var color: ChordColor = .base
    var gate: Double = TimelineNote.enteredGate     // fraction of step to hold chord (0...1)
    var isRest: Bool = false

    /// The chord this step plays.
    var spec: ChordSpec { ChordSpec(degree: degree, color: color) }

    func label(in key: Key) -> String { isRest ? "—" : degreeNumeral(key: key, degree: degree) }

    /// Gates this close to 100% tie: the chord rings into the next step
    /// instead of being released, the clearly-audible top of the gate range.
    static let tieThreshold = 0.98
    var isTied: Bool { gate >= Self.tieThreshold }
}

extension Layer {

    /// A layer with `steps` on its first steps, as if each were entered in turn.
    init(steps: [SequencerStep]) {
        self.init()
        for (index, step) in steps.enumerated() { setStep(index, to: step) }
    }

    /// Step `index` as the step editor sees it.
    func step(_ index: Int) -> SequencerStep {
        let ticks = TimelineTime.ticks(ofStep: index)
        // The note that starts in the step, or else one running through it.
        guard let note = notes.first(where: { ticks.contains($0.start) })
                      ?? notes.first(where: { $0.start < ticks.lowerBound && $0.end > ticks.lowerBound }) else {
            return SequencerStep(isRest: true)
        }
        let sounding = min(note.end, ticks.upperBound) - max(note.start, ticks.lowerBound)
        return SequencerStep(degree: note.chord.degree, color: note.chord.color,
                             gate: Double(sounding) / Double(ticks.count))
    }

    /// Makes step `index` what `step` says, leaving every other step as it was.
    mutating func setStep(_ index: Int, to step: SequencerStep) {
        let ticks = TimelineTime.ticks(ofStep: index)
        // What the step's note was played with is kept under a new chord.
        let before = notes.first { $0.start < ticks.upperBound && $0.end > ticks.lowerBound }
        // Cut a long note free at both of the step's lines, so only this
        // step changes.
        split(steps: [index, index + 1])
        clear(ticks)
        guard !step.isRest else { return }

        let length = step.isTied ? ticks.count : max(1, Int((step.gate * Double(ticks.count)).rounded()))
        var note = TimelineNote(start: ticks.lowerBound, length: length, chord: step.spec)
        if let before {
            note.playing = before.playing
            note.pitch = before.pitch
        }
        insert(note)

        // A tie into the same chord is one held note.
        if let previous = notes.firstIndex(where: { $0.end == ticks.lowerBound }), notes[previous].ties(into: note) {
            notes[previous].length += note.length
            notes.removeAll { $0.start == ticks.lowerBound }
            note = notes[previous]
        }
        if note.end == ticks.upperBound,
           let next = notes.first(where: { $0.start == ticks.upperBound }), note.ties(into: next),
           let held = notes.firstIndex(where: { $0.start == note.start }) {
            notes[held].length += next.length
            notes.removeAll { $0.start == ticks.upperBound }
        }
    }
}

private extension TimelineNote {
    /// Whether this note, ending where `next` starts, is the same chord
    /// played the same way: held on, not struck again.
    func ties(into next: TimelineNote) -> Bool {
        chord == next.chord && pitch == next.pitch && playing == next.playing
    }
}
