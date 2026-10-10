import Foundation

/// Music that repeats, as notes in layers: a sequence entered by hand and a
/// loop recorded from playing are both this. It is plain data. The edits are
/// in `TimelineEdits`, and `compile` turns a layer into what is played.
struct Timeline: Equatable, Codable, Sendable {
    var signature = TimeSignature.common
    /// The timeline's length in bars, at least 1. Every layer shares it.
    var barCount = 1
    var layers: [Layer] = [Layer()]
    /// The stretch of time that repeats, in ticks; nil repeats all of it.
    var loop: Range<Int>?

    /// The most layers a timeline is given: what can be told apart by ear
    /// and reached from the loop bar.
    static let maxLayers = 6

    /// The timeline's length in ticks.
    var length: Int { barCount * signature.ticksPerBar }

    var stepCount: Int { barCount * signature.stepsPerBar }

    /// The ticks playback runs through before starting again.
    var playedRange: Range<Int> {
        guard let loop else { return 0..<length }
        let clamped = loop.clamped(to: 0..<length)
        return clamped.isEmpty ? 0..<length : clamped
    }

    /// Whether no layer has a note.
    var isEmpty: Bool { layers.allSatisfy(\.notes.isEmpty) }

    /// Whether the stretch that repeats has no note starting in it.
    var playsNothing: Bool {
        let range = playedRange
        return layers.allSatisfy { layer in !layer.notes.contains { range.contains($0.start) } }
    }

    func layer(_ id: Layer.ID) -> Layer? {
        layers.first { $0.id == id }
    }
}

/// One line of chords on a timeline: one chord at a time, as one hand plays
/// them. Its notes are in order and never overlap; the edits keep them so.
struct Layer: Equatable, Identifiable, Codable, Sendable {
    let id: UUID
    var notes: [TimelineNote]
    var isMuted = false
    var volume: Float = 1

    init(id: UUID = UUID(), notes: [TimelineNote] = []) {
        self.id = id
        self.notes = notes
    }
}

/// One chord (or one note of it) at a place in time, and how it is played.
struct TimelineNote: Equatable, Codable, Sendable {
    /// Ticks from the start of the timeline.
    var start: Int
    /// Ticks it sounds for, at least 1.
    var length: Int
    var chord: ChordSpec
    var pitch = NotePitch.chord
    var articulation = Articulation.block
    var playing = NotePlaying()
    /// A slide played while the note was held, in order of time.
    var changes: [SoundChange] = []

    /// The share of its step a newly entered note sounds for, leaving a gap
    /// before the next so repeated chords are heard as separate strikes.
    static let enteredGate = 0.75

    var end: Int { start + length }

    /// Whether the note starts and ends on step lines.
    var isOnGrid: Bool { TimelineTime.isOnGrid(start) && TimelineTime.isOnGrid(end) }

    /// The step the note belongs to: the one whose line its start is
    /// nearest. It is drawn from there and edited through it.
    var step: Int { TimelineTime.step(nearest: start) }

    /// The steps the note is drawn across: from its own to the step line
    /// nearest its end, and at least the one.
    var steps: Range<Int> { step ..< max(step + 1, TimelineTime.step(nearest: end)) }

    /// The steps it is held across, counting a part of one as one: a chord
    /// entered on a step is 1 however crisp, and two tied steps are 2.
    var heldSteps: Int {
        max(1, Int((Double(length) / Double(TimelineTime.ticksPerStep)).rounded(.up)))
    }

    /// How much of the last of those steps it sounds for, above 0 and up to 1.
    var gate: Double {
        Double(length - (heldSteps - 1) * TimelineTime.ticksPerStep) / Double(TimelineTime.ticksPerStep)
    }
}

/// What of its chord a note sounds.
enum NotePitch: Equatable, Codable, Sendable {
    /// Every note of the chord.
    case chord
    /// The scale degree alone, as Lead mode plays it.
    case lead
    /// These MIDI notes, whatever the chord, key and octave: what was
    /// played from the net of notes, where no chord says them (the Tonnetz).
    case notes([Int])
}

/// The settings a note is played with. Each is either the note's own or,
/// when nil, whatever is chosen now: a note entered in the sequencer follows
/// the live key and sound, and a note recorded from playing keeps the ones
/// it was played with.
struct NotePlaying: Equatable, Codable, Sendable {
    var key: Key?
    var octave: Int?
    var preset: SynthPreset?
    var effects: NoteEffects?

    /// Whether anything is the note's own.
    var hasOwn: Bool { key != nil || octave != nil || preset != nil || effects != nil }
}

/// Every effect's settings, as one note is played with them.
struct NoteEffects: Equatable, Codable, Sendable {
    var arpeggiator = ArpeggiatorSettings()
    var filter = FilterSettings()
    var chorus = ChorusSettings()
    var reverb = ReverbSettings()
    var vocoder = VocoderSettings()
}

extension NoteEffects {
    /// A timeline saved before there was a vocoder has none.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        arpeggiator = try container.decode(ArpeggiatorSettings.self, forKey: .arpeggiator)
        filter = try container.decode(FilterSettings.self, forKey: .filter)
        chorus = try container.decode(ChorusSettings.self, forKey: .chorus)
        reverb = try container.decode(ReverbSettings.self, forKey: .reverb)
        vocoder = try container.decodeIfPresent(VocoderSettings.self, forKey: .vocoder) ?? VocoderSettings()
    }
}

/// The effects as they became at a moment inside a held note: one point of
/// a slide.
struct SoundChange: Equatable, Codable, Sendable {
    /// Ticks after the note's start.
    var offset: Int
    var effects: NoteEffects
}
