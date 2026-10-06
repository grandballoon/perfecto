/// The chorus's controls, as plain data: `EffectsChain` realizes them.
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
}

/// The reverb's controls, as plain data: `EffectsChain` realizes them.
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
}

/// The filter's controls, as plain data: `BrightnessFilter` realizes them.
/// Unlike the chorus and reverb it shapes the sound before it is recorded,
/// so a loop holds the brightness it was played with.
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
}

/// The sound effects' settings together: what the player hears now, and
/// what a loop keeps from the moment it is closed.
struct SoundEffects: Equatable, Sendable {
    var chorus = ChorusSettings()
    var reverb = ReverbSettings()
}

/// Something that follows the sound effects as they are played: each call
/// carries an effect as it sounds now, the slide and the key zones already
/// applied.
/// `AudioSink` makes the sound; `MidiSink` sends the amounts on as controllers.
@MainActor
protocol EffectsControl: AnyObject {
    func setFilter(_ played: FilterSettings)
    func setChorus(_ played: ChorusSettings)
    func setReverb(_ played: ReverbSettings)
}

/// What the effects controls need from the audio layer. `AudioSink` is the
/// real one; tests substitute their own.
@MainActor
protocol AudioEffects: EffectsControl {
    /// The chorus and reverb as set, whatever is being played: what a loop
    /// keeps when it is closed.
    func setLoopEffects(_ effects: SoundEffects)
}
