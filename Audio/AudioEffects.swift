/// The chorus: one sound, on or off. The kernel realizes it.
struct ChorusSettings: Equatable, Codable, Sendable, EffectSettings {
    static var kind: EffectKind { .chorus }

    /// How much chorus is mixed into a note that has it: 0 is none, 1 is
    /// the full effect.
    static let amount: Float = 0.6
    /// How fast the pitch wavers, from slow (0) to fast (1).
    static let rate: Float = 0.35

    var isOn = false
}

/// The reverb: one room, on or off. The kernel realizes it.
struct ReverbSettings: Equatable, Codable, Sendable, EffectSettings {
    static var kind: EffectKind { .reverb }

    /// How much of a note that has it goes into the reverb rather than
    /// straight out: 0 is dry, 1 is reverb alone.
    static let mix: Float = 0.3
    /// The size of the room, from a short tail (0) to a long one (1).
    static let size: Float = 0.4

    var isOn = false
}

/// The delay: echoes in time with the tempo, on or off. The kernel
/// realizes it.
struct DelaySettings: Equatable, Codable, Sendable, EffectSettings {
    static var kind: EffectKind { .delay }

    /// How loud the first echo of a note that has it is beside the note:
    /// 0 is none, 1 is as loud.
    static let amount: Float = 0.35
    /// The beats between one echo and the next: a dotted eighth note, which
    /// falls between the beats and the half-beats.
    static let beats = 0.75
    /// How loud each echo is beside the one before it.
    static let feedback: Float = 0.4

    /// The seconds between echoes at `bpm`.
    static func seconds(atBPM bpm: Double) -> Double { beats * 60 / bpm }

    var isOn = false
}

/// The vocoder's controls, as plain data. While it is on, the mic is open:
/// the notes sent to it are heard as the voice there shapes them.
struct VocoderSettings: Equatable, Codable, Sendable, SlidePlayed {
    static var kind: EffectKind { .vocoder }

    var isOn = false
    /// How much of each note goes to the vocoder and is not heard itself:
    /// 0 is none, 1 is all of it, so the notes are silent until the voice
    /// speaks.
    var amount: Float = 1
    /// The slide plays the amount.
    var followsSlide = false

    func playing(_ slide: Float) -> VocoderSettings {
        var played = self
        played.amount = slide
        return played
    }
}

/// Something that keeps time with the tempo: the delay, whose echoes are
/// a length of the beat apart.
@MainActor
protocol TempoControl: AnyObject {
    func setTempo(_ bpm: Double)
}

/// Something that follows the sound effects as they are played: each call
/// carries an effect as it sounds now, the slide and the key zones already
/// applied.
/// The keys' `NotePlayer` makes them its notes' sound; `MidiSink` sends the
/// chorus and the reverb on as controllers.
@MainActor
protocol EffectsControl: AnyObject {
    func setChorus(_ played: ChorusSettings)
    func setReverb(_ played: ReverbSettings)
    func setDelay(_ played: DelaySettings)
    func setVocoder(_ played: VocoderSettings)
    /// How bright the notes are, from 0 (dark) to 1 (all of their sound).
    func setBrightness(_ played: Float)
}
