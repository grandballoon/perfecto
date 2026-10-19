/// One band of a chord key's height, and what a finger in it plays: an
/// effect, and the key, octave and inversion its chord is in.
struct KeyZone: Equatable, Sendable {
    /// The effect a finger here switches on; nil leaves every effect as set.
    var effect: EffectChoice?
    /// Where the effect's played control is held while a finger is here, as
    /// a place on the slide (0...1): the value a slide to that place would
    /// play. An effect with nothing to play (the chorus, the reverb) is
    /// only switched on.
    var value: Float = 0.5
    /// The key a chord played from here is in; nil is the key chosen.
    var key: Key?
    /// The octave a chord played from here is in; nil is the octave chosen.
    var octave: Int?
    /// How far a chord played from here is rolled from root position; nil
    /// is the inversion chosen.
    var inversion: Inversion?

    /// Whether a finger here plays nothing of the zone's own.
    var isPlain: Bool { effect == nil && key == nil && octave == nil && inversion == nil }
}

/// Key zones: a chord key divided into bands, each with an equal share
/// of the slide, so where on a key a finger is chooses what it plays. A
/// finger in a zone switches the zone's effect on, with its played control
/// (`SlidePlayed`), if it has one, held at the zone's value, whatever the
/// effect is set to;
/// out of the zone, or lifted, the effect is as set again. A zone can also
/// have a key, an octave and an inversion of its own, which a chord played
/// from it is in (`PerformanceState.playedKey`), so one key plays a chord
/// of each.
///
/// Zones are independent of one another: they can name different effects,
/// or the same effect at different values (an arpeggio at three speeds),
/// and keys far apart; a zone with none of them is plain.
///
/// Every key is divided the same way unless it has zones of its own
/// (`EffectsState.keyZones`). One zone is the whole key: what that key
/// plays wherever it is struck, and for every key, no division at all.
struct KeyZoneSettings: Equatable, Sendable {
    /// How many zones a key can have.
    static let counts = 1...4

    /// What a key's own zones start as: the whole key, plain.
    static let ofOneKey = KeyZoneSettings(zones: [KeyZone()])

    var isOn = false
    /// The zones, from the bottom of the key to the top.
    var zones = [KeyZone(), KeyZone(effect: .arpeggio(.up))]

    /// The number of zones. Adding zones adds plain ones at the top; taking
    /// zones away takes them from the top.
    var count: Int {
        get { zones.count }
        set {
            let count = newValue.clamped(to: Self.counts)
            zones = Array(zones.prefix(count))
            zones += Array(repeating: KeyZone(), count: count - zones.count)
        }
    }

    /// The places on the slide (0...1) where one zone gives way to the next,
    /// from the bottom; empty while off.
    var edges: [Float] {
        guard isOn else { return [] }
        return (1..<zones.count).map { Float($0) / Float(zones.count) }
    }

    /// The zone of a key held with no place on it (a key of the computer
    /// keyboard): the whole key, if that is its one zone.
    var whole: Int? { isOn && zones.count == 1 ? 0 : nil }

    /// The zone a finger at `slide` is in, counted from the bottom, given the
    /// zone it was in before (`current`), which holds on to a finger at its
    /// edge (`SlideBands`); nil while off or no key is held.
    func zone(at slide: Float?, from current: Int?) -> Int? {
        guard isOn, let slide else { return nil }
        return SlideBands.band(at: slide, of: zones.count, from: current)
    }
}
