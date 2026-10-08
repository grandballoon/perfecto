/// An effect's settings that a finger on a chord key can play. Each names
/// one played control: the one set value a finger's place on the key stands
/// in for.
///
/// The slide is how far up its chord key a finger is, from 0 at the bottom
/// to 1 at the top. While the effect is on and follows it, the slide plays
/// the control. A key zone (`KeyZoneSettings`) holds the control at one
/// place on the slide instead, and switches the effect on to do it. Either
/// way, lifting the key returns to the set values. The effect slider
/// (`EffectsState.slider`) plays the same control from a surface of its own.
protocol SlidePlayed {
    /// Which effect these are the settings of.
    static var kind: EffectKind { get }
    var isOn: Bool { get set }
    /// Whether the slide plays this effect.
    var followsSlide: Bool { get }
    /// These settings with the played control at `slide` (0...1).
    func playing(_ slide: Float) -> Self
    /// Where the played control is, as a place on the slide (0...1): a
    /// slide to there would play these settings as they are.
    var place: Float { get }
}

extension SlidePlayed {
    /// Whether a slide would change how this effect sounds.
    var isPlayed: Bool { isOn && followsSlide }

    /// The settings as they sound with a finger at `slide`; nil is no key held.
    func played(by slide: Float?) -> Self {
        guard isPlayed, let slide else { return self }
        return playing(slide)
    }

    /// The settings as they sound from a key zone: switched on, the played
    /// control held at `value` (a place on the slide).
    func held(at value: Float) -> Self {
        var held = playing(value)
        held.isOn = true
        return held
    }
}
