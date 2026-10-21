import Foundation

/// What one line of the Dissonance Lab sounds: a note in a sound made of
/// partials, at a pitch anywhere (a MIDI note and any part of a semitone),
/// with each of its partials set apart.
struct PartialNote: Equatable, Sendable {
    var sound: PartialSound
    /// The pitch as a MIDI note, with the part of a semitone past it.
    var pitch: Double
    var velocity: Float
    var pan: Float = 0
    /// The partials, the fundamental first; any it does not name are silent.
    var partials: [PartialSetting]
}

/// The lines the Dissonance Lab sounds at once.
enum LabLine: Hashable, Sendable {
    /// A note as it was keyed, by its MIDI note.
    case keyed(Int)
    /// A quiet sine at the root the notes imply.
    case root
    /// A quiet sine at the spotlighted pair's beat rate.
    case difference
}

/// The Dissonance Lab's synth: it is told what each line should sound now
/// (`sound`), and makes it so through a `PartialSink` with as little as it
/// can. A line that is new starts, one that is gone ends, and one that goes
/// on is changed where it differs, partial by partial, so a change of a
/// setting is glided to and never struck again: that is how equal
/// temperament is heard to settle into just intonation, beat by beat.
///
/// A line that moves more than a semitone, or to another sound, pan or
/// velocity, is struck again, since a glide that far is heard as a slide.
/// The keyed lines are shown on the piano too, at the nearest note.
@MainActor
final class DissonanceSynth {

    private struct Sounding {
        let id: NoteID
        /// The MIDI note the kernel was given; the pitch is bent from it.
        let base: Int
        var note: PartialNote
        /// The note the piano shows, for a keyed line.
        let shown: Int?
    }

    /// Farther than this, in semitones, a line is struck again.
    static let widestGlide = 1.0

    private let sink: (any PartialSink)?
    private let display: [any NoteSink]
    private let clock: any ClockTickable
    private var sounding: [LabLine: Sounding] = [:]

    /// `sink` sounds the notes; without one the lab is silent. `display`
    /// is shown the keyed lines (the piano's line).
    init(sink: (any PartialSink)?, display: [any NoteSink] = [], clock: any ClockTickable) {
        self.sink = sink
        self.display = display
        self.clock = clock
    }

    /// The most partials a line has.
    var partialCount: Int { sink?.partialCount ?? 16 }

    /// What is sounding now, by line.
    var lines: [LabLine: PartialNote] { sounding.mapValues(\.note) }

    /// Makes `lines` what is sounding.
    func sound(_ lines: [LabLine: PartialNote]) {
        let time = clock.time
        for line in sounding.keys where lines[line] == nil { end(line, at: time) }
        for (line, note) in lines {
            if let held = sounding[line], Self.canGlide(from: held.note, to: note) {
                change(line, to: note, at: time)
            } else {
                end(line, at: time)
                start(line, note, at: time)
            }
        }
    }

    /// Ends every line.
    func silence() { sound([:]) }

    private static func canGlide(from old: PartialNote, to new: PartialNote) -> Bool {
        old.sound == new.sound && old.pan == new.pan && old.velocity == new.velocity
            && abs(old.pitch - new.pitch) <= widestGlide
    }

    private func start(_ line: LabLine, _ note: PartialNote, at time: TimeInterval) {
        let id = NoteID.next()
        let base = Int(note.pitch.rounded()).clamped(to: Voicing.midiRange)
        sink?.partialNoteOn(id, note: base, bend: Float(note.pitch - Double(base)), sound: note.sound,
                            velocity: note.velocity, pan: note.pan, at: time)
        // Sent on the frame it starts, so it starts so.
        for (number, setting) in padded(note.partials).enumerated() {
            sink?.partialChange(id, partial: number, to: setting, at: time)
        }
        var shown: Int?
        if case .keyed = line {
            shown = base
            display.forEach { $0.noteOn(id, note: base, sound: NoteSound(), at: time) }
        }
        sounding[line] = Sounding(id: id, base: base, note: note, shown: shown)
    }

    private func change(_ line: LabLine, to note: PartialNote, at time: TimeInterval) {
        guard var held = sounding[line] else { return }
        if note.pitch != held.note.pitch {
            sink?.partialBend(held.id, to: Float(note.pitch - Double(held.base)), at: time)
        }
        let before = padded(held.note.partials)
        for (number, setting) in padded(note.partials).enumerated() where setting != before[number] {
            sink?.partialChange(held.id, partial: number, to: setting, at: time)
        }
        held.note = note
        sounding[line] = held
    }

    private func end(_ line: LabLine, at time: TimeInterval) {
        guard let held = sounding.removeValue(forKey: line) else { return }
        sink?.partialNoteOff(held.id, at: time)
        if held.shown != nil { display.forEach { $0.noteOff(held.id, at: time) } }
    }

    /// `partials` as many as a line has, the rest silent.
    private func padded(_ partials: [PartialSetting]) -> [PartialSetting] {
        let count = partialCount
        return Array(partials.prefix(count)) + Array(repeating: .silent, count: max(count - partials.count, 0))
    }
}
