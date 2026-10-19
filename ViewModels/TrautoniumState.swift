import Observation

/// One of the Trautonium's two bars, each a voice of its own.
enum TrautoniumBar: Int, CaseIterable, Sendable {
    /// The bar nearer the player, which starts in the octave the chords
    /// are built in.
    case low
    /// The bar beyond it, an octave higher.
    case high
}

/// Where a finger is on a bar: how far along it, from its low end (0) to
/// its high end (1), and how far across it, from its quiet edge (0) to its
/// loud one (1).
struct BarPlace: Equatable, Sendable {
    var along: Double
    var across: Double
}

/// The pitches along a bar: `semitones` of them up from `lowest`, a MIDI
/// note, each with as much of the bar's length as the next, so the lowest
/// and the highest have room on both sides as the others do. The one place
/// that says where a pitch is on a bar: the bar is drawn and played by it.
struct BarRange: Equatable, Sendable {
    /// Two octaves.
    static let semitones = 24

    let lowest: Int

    var highest: Int { lowest + Self.semitones }

    /// The pitch `along` the bar, as a MIDI note and any part of a
    /// semitone past it.
    func pitch(at along: Double) -> Double {
        let pitch: Double = Double(lowest) - 0.5 + along * Double(Self.semitones + 1)
        return pitch.clamped(to: Double(lowest)...Double(highest))
    }

    /// How far along the bar `pitch` is.
    func place(of pitch: Double) -> Double {
        (pitch - Double(lowest) + 0.5) / Double(Self.semitones + 1)
    }
}

/// What the Trautonium needs from whatever plays the chords.
@MainActor
protocol TrautoniumHost: AnyObject {
    /// The key and the octave the bars are in, as the tonic's own chord.
    var trautoniumContext: ChordContext { get }
    /// The sound a bar's note is played with.
    var trautoniumSound: NoteSound { get }
}

/// The Trautonium: two bars, each one voice, played by where a finger is on
/// them. Along a bar is pitch, which is anywhere and not only on the notes;
/// across it is how loud, in place of the pressure a real one is played by.
///
/// A finger that comes down sounds the note of the key nearest it, exactly,
/// so a bar is in tune however roughly it is struck. From there the pitch
/// follows the finger as far as it moves, so a slide is a slide and a
/// finger that rocks is a vibrato around the note. A finger that comes to
/// rest is brought to the note of the key nearest it again (`rest`).
///
/// Each bar is a line of its own, like the solo strip: a sink beside the
/// keys' chord, in the keys' preset with the effects as set, and no mode
/// knows of it. A bar's note is started once and then bent and made louder
/// or softer where it sounds (`NoteSound.bend`, `level`), which a sink with
/// a sound of its own glides to. A second finger on a bar takes the note to
/// where it is without striking it again.
@Observable
@MainActor
final class TrautoniumState {

    /// What a bar is sounding.
    struct Playing: Equatable {
        /// The note the bar started, which its pitch is bent from.
        let note: Int
        /// Where the finger is.
        var place: BarPlace
        /// How far the pitch sounded is from the pitch under the finger:
        /// what brought the finger's place onto a note of the key.
        var offset: Double
        /// The pitch sounded, as a MIDI note and any part of a semitone.
        var pitch: Double
        /// How loud, from 0 to 1.
        var level: Float
    }

    /// Whether the bars are on screen. Off it, nothing of theirs sounds.
    var isShown = false {
        didSet { if !isShown { TrautoniumBar.allCases.forEach(release) } }
    }

    private(set) var playing: [TrautoniumBar: Playing] = [:]

    @ObservationIgnored weak var host: (any TrautoniumHost)?

    /// How long a finger is still, in seconds, before it is at rest and its
    /// pitch is brought onto a note of the key: longer than the turn of a
    /// vibrato, short enough that a slide ends in tune as it is heard to end.
    static let rest = 0.15
    /// The quietest a bar sounds, at its quiet edge.
    static let quietest: Float = 0.06

    private let sinks: [TrautoniumBar: any ChordEventSink]
    private let clock: any ClockTickable
    private let logger: (any Logger)?
    /// Each bar's call for when its finger has come to rest.
    @ObservationIgnored private var resting: [TrautoniumBar: ClockCall] = [:]

    /// `makeSink` makes the sink a bar sounds through, one for each; a sink
    /// that is a `SoundControl` is given the bar's sound, and so its slides.
    /// Without one the bars are silent.
    init(makeSink: (() -> any ChordEventSink)? = nil, clock: any ClockTickable,
         logger: (any Logger)? = nil) {
        var sinks: [TrautoniumBar: any ChordEventSink] = [:]
        if let makeSink {
            for bar in TrautoniumBar.allCases { sinks[bar] = makeSink() }
        }
        self.sinks = sinks
        self.clock = clock
        self.logger = logger
    }

    // MARK: – The bars

    /// The pitches along `bar`: two octaves from the key's tonic, the low
    /// bar's in the octave the chords are built in. An octave lower where
    /// MIDI's range would end first.
    func range(of bar: TrautoniumBar) -> BarRange {
        guard let context = host?.trautoniumContext else { return BarRange(lowest: 60) }
        var lowest = context.key.root.rawValue + (context.octave + 1 + bar.rawValue) * 12
        while lowest + BarRange.semitones > Voicing.midiRange.upperBound { lowest -= 12 }
        return BarRange(lowest: max(lowest, Voicing.midiRange.lowerBound))
    }

    /// The notes of the key along `bar`, low to high: where it is in tune.
    func notes(of bar: TrautoniumBar) -> [Int] {
        guard let key = host?.trautoniumContext.key else { return [] }
        let range = range(of: bar)
        return (range.lowest...range.highest).filter(key.has)
    }

    /// How loud a bar is with a finger `across` it: little at the quiet
    /// edge, and more for each step the nearer the loud one, as pressing
    /// harder is.
    static func level(across: Double) -> Float {
        let share = Float(across.clamped(to: 0...1))
        return quietest + (1 - quietest) * share * share
    }

    // MARK: – Playing

    /// A finger comes down on `bar` at `place`: the note of the key nearest
    /// it sounds. On a bar that is sounding, its note goes there and is not
    /// struck again.
    func press(_ bar: TrautoniumBar, at place: BarPlace) {
        guard let host else { return }
        let key = host.trautoniumContext.key
        let under = range(of: bar).pitch(at: place.along)
        let landed = key.note(nearest: under)
        let level = Self.level(across: place.across)
        if let held = playing[bar] {
            playing[bar] = Playing(note: held.note, place: place, offset: Double(landed) - under,
                                   pitch: Double(landed), level: level)
            sound(bar)
        } else {
            playing[bar] = Playing(note: landed, place: place, offset: Double(landed) - under,
                                   pitch: Double(landed), level: level)
            (sinks[bar] as? any SoundControl)?.startNotes(in: sound(of: bar))
            sinks[bar]?.playChord(ChordEvent(voicing: Voicing(notes: [landed]), articulation: .block,
                                             context: host.trautoniumContext))
        }
        logger?.log(.trautonium_note_played(bar: bar.rawValue, note: landed))
        awaitRest(of: bar)
    }

    /// The finger on `bar` moves to `place`: the pitch goes as far as the
    /// finger did, and the level to where it is.
    func move(_ bar: TrautoniumBar, to place: BarPlace) {
        guard var held = playing[bar], place != held.place else { return }
        let range = range(of: bar)
        held.place = place
        held.pitch = (range.pitch(at: place.along) + held.offset)
            .clamped(to: Double(range.lowest)...Double(range.highest))
        held.level = Self.level(across: place.across)
        playing[bar] = held
        sound(bar)
        awaitRest(of: bar)
    }

    /// The finger on `bar` lifts, and its note ends.
    func release(_ bar: TrautoniumBar) {
        resting.removeValue(forKey: bar)?.cancel()
        guard playing.removeValue(forKey: bar) != nil else { return }
        sinks[bar]?.stopChord()
    }

    /// The finger on `bar` has moved, so it is not at rest until it has
    /// been still for `rest` from now.
    private func awaitRest(of bar: TrautoniumBar) {
        resting[bar]?.cancel()
        resting[bar] = clock.after(seconds: Self.rest) { [weak self] in self?.settle(bar) }
    }

    /// Brings `bar`'s pitch onto the note of the key nearest its finger,
    /// which has come to rest.
    private func settle(_ bar: TrautoniumBar) {
        resting[bar] = nil
        guard var held = playing[bar], let key = host?.trautoniumContext.key else { return }
        let under = range(of: bar).pitch(at: held.place.along)
        let landed = Double(key.note(nearest: under))
        guard landed != held.pitch else { return }
        held.offset = landed - under
        held.pitch = landed
        playing[bar] = held
        sound(bar)
    }

    // MARK: – Sound

    /// The host's sound, bent and as loud as `bar` is played.
    private func sound(of bar: TrautoniumBar) -> NoteSound {
        var sound = host?.trautoniumSound ?? NoteSound()
        if let held = playing[bar] {
            sound.bend = Float(held.pitch - Double(held.note))
            sound.level = held.level
        }
        return sound
    }

    /// Takes the note `bar` is holding to where it is played now.
    private func sound(_ bar: TrautoniumBar) {
        (sinks[bar] as? any SoundControl)?.sound = sound(of: bar)
    }
}
