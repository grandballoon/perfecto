/// Time on a timeline is whole ticks from its start. A note may start on any
/// tick and last any number, so something played loosely is kept exactly as
/// it was played; steps are how time is drawn and edited, not how it is stored.
enum TimelineTime {
    /// Ticks in a quarter note: divisible by the sixteenths of the grid and
    /// by triplets, and the resolution the MIDI export writes.
    static let ticksPerBeat = 480
    /// Ticks in a step of the grid, a sixteenth note.
    static let ticksPerStep = ticksPerBeat / MusicalTime.stepsPerBeat

    /// The step `tick` falls in.
    static func step(at tick: Int) -> Int {
        Int((Double(tick) / Double(ticksPerStep)).rounded(.down))
    }

    /// The step line nearest `tick`, as a tick.
    static func nearestStepLine(to tick: Int) -> Int {
        Int((Double(tick) / Double(ticksPerStep)).rounded()) * ticksPerStep
    }

    /// The ticks step `step` covers.
    static func ticks(ofStep step: Int) -> Range<Int> {
        step * ticksPerStep ..< (step + 1) * ticksPerStep
    }

    /// Whether `tick` is on a step line.
    static func isOnGrid(_ tick: Int) -> Bool {
        tick.isMultiple(of: ticksPerStep)
    }
}

/// How a bar is counted: `beats` notes of one `unit` each.
struct TimeSignature: Hashable, Codable, Sendable {

    /// The note a signature counts in.
    enum Unit: Int, CaseIterable, Codable, Sendable {
        case quarter = 4
        case eighth = 8
    }

    var beats: Int
    var unit: Unit

    static let common = TimeSignature(beats: 4, unit: .quarter)

    /// The signatures the sequencer offers.
    static let offered: [TimeSignature] = [
        TimeSignature(beats: 2, unit: .quarter),
        TimeSignature(beats: 3, unit: .quarter),
        .common,
        TimeSignature(beats: 5, unit: .quarter),
        TimeSignature(beats: 5, unit: .eighth),
        TimeSignature(beats: 6, unit: .eighth),
        TimeSignature(beats: 7, unit: .eighth),
        TimeSignature(beats: 9, unit: .eighth),
        TimeSignature(beats: 12, unit: .eighth),
    ]

    /// As written on a score: "6/8".
    var label: String { "\(beats)/\(unit.rawValue)" }

    var ticksPerBar: Int {
        beats * TimelineTime.ticksPerBeat * Unit.quarter.rawValue / unit.rawValue
    }

    var stepsPerBar: Int { ticksPerBar / TimelineTime.ticksPerStep }

    /// The bar's length in quarter-note beats, the clock's unit.
    var quarterBeatsPerBar: Double { Double(ticksPerBar) / Double(TimelineTime.ticksPerBeat) }

    /// Steps in a row of the grid, so each row is one felt beat: a quarter
    /// note, or a dotted quarter where eighths go in threes (6/8, 9/8, 12/8).
    /// The other signatures in eighths get rows of a quarter with a short
    /// last row.
    var stepsPerRow: Int {
        unit == .eighth && beats.isMultiple(of: 3) ? 6 : 4
    }
}
