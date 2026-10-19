/// One effect's settings. Every effect has a switch; what else it has is
/// its own.
///
/// A key zone (`KeyZoneSettings`) switches an effect on while a finger is
/// in it, whatever the switch says, and lifting the key returns to the
/// settings as set.
protocol EffectSettings {
    /// Which effect these are the settings of.
    static var kind: EffectKind { get }
    var isOn: Bool { get set }
    /// Whether a slide would change how this effect sounds.
    var isPlayed: Bool { get }
    /// The settings as they sound with a finger at `slide`; nil is no key held.
    func played(by slide: Float?) -> Self
    /// The settings as they sound from a key zone: switched on, with
    /// whatever the effect has to play held at `value` (a place on the slide).
    func held(at value: Float) -> Self
}

extension EffectSettings {
    var isPlayed: Bool { false }

    func played(by slide: Float?) -> Self { self }

    func held(at value: Float) -> Self {
        var held = self
        held.isOn = true
        return held
    }
}

/// An effect's settings that a finger on a chord key can play. Each names
/// one played control: the one set value a finger's place on the key stands
/// in for. The chorus and the reverb have none: each is one sound, on or off.
///
/// The slide is how far up its chord key a finger is, from 0 at the bottom
/// to 1 at the top. While the effect is on and follows it, the slide plays
/// the control. A key zone holds the control at one place on the slide
/// instead, and switches the effect on to do it. Either way, lifting the
/// key returns to the set values.
protocol SlidePlayed: EffectSettings {
    /// Whether the slide plays this effect.
    var followsSlide: Bool { get }
    /// These settings with the played control at `slide` (0...1).
    func playing(_ slide: Float) -> Self
}

extension SlidePlayed {
    var isPlayed: Bool { isOn && followsSlide }

    func played(by slide: Float?) -> Self {
        guard isPlayed, let slide else { return self }
        return playing(slide)
    }

    func held(at value: Float) -> Self {
        var held = playing(value)
        held.isOn = true
        return held
    }
}
