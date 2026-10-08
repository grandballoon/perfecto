/// The chorus's controls, as plain data: the kernel realizes them.
/// Both amounts run 0...1.
struct ChorusSettings: Equatable, Codable, Sendable, SlidePlayed {
    static var kind: EffectKind { .chorus }

    var isOn = false
    /// How much chorus is mixed in: 0 is none, 1 is the full effect.
    var amount: Float = 0.6
    /// How fast the pitch wavers, from slow (0) to fast (1).
    var rate: Float = 0.35
    /// The slide plays the amount.
    var followsSlide = false

    func playing(_ slide: Float) -> ChorusSettings {
        var played = self
        played.amount = slide
        return played
    }

    var place: Float { amount }
}

/// The reverb's controls, as plain data: the kernel realizes them.
/// Both amounts run 0...1.
struct ReverbSettings: Equatable, Codable, Sendable, SlidePlayed {
    static var kind: EffectKind { .reverb }

    var isOn = false
    /// How much of the sound goes into the reverb rather than straight out:
    /// 0 is dry, 1 is reverb alone.
    var mix: Float = 0.3
    /// The size of the room, from a short tail (0) to a long one (1).
    var size: Float = 0.4
    /// The slide plays the mix.
    var followsSlide = false

    func playing(_ slide: Float) -> ReverbSettings {
        var played = self
        played.mix = slide
        return played
    }

    var place: Float { mix }
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

    var place: Float { amount }
}

/// The filter's controls, as plain data: the kernel realizes them.
struct FilterSettings: Equatable, Codable, Sendable, SlidePlayed {
    static var kind: EffectKind { .filter }

    var isOn = false
    /// How much of the sound's top end comes through: 0 is dark, 1 is all of it.
    var brightness: Float = 1
    /// The slide plays the brightness.
    var followsSlide = true

    func playing(_ slide: Float) -> FilterSettings {
        var played = self
        played.brightness = slide
        return played
    }

    var place: Float { brightness }
}

/// Something that follows the sound effects as they are played: each call
/// carries an effect as it sounds now, the slide and the key zones already
/// applied.
/// The keys' `NotePlayer` makes them its notes' sound; `MidiSink` sends the
/// amounts on as controllers.
@MainActor
protocol EffectsControl: AnyObject {
    func setFilter(_ played: FilterSettings)
    func setChorus(_ played: ChorusSettings)
    func setReverb(_ played: ReverbSettings)
    func setVocoder(_ played: VocoderSettings)
}
