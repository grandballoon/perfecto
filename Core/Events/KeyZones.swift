/// One band of a chord key's height, and the effect a finger in it plays.
struct KeyZone: Equatable, Sendable {
    /// The effect a finger here switches on; nil leaves every effect as set.
    var effect: EffectKind?
    /// Where the effect's played control is held while a finger is here, as
    /// a place on the slide (0...1): the value a slide to that place would play.
    var value: Float = 0.5
}

/// Key zones: every chord key divided into bands, each with an equal share
/// of the slide, so where on a key a finger is chooses what it plays. A
/// finger in a zone switches the zone's effect on, with its played control
/// (`SlidePlayed`) held at the zone's value, whatever the effect is set to;
/// out of the zone, or lifted, the effect is as set again.
///
/// Zones are independent of one another: they can name different effects,
/// or the same effect at different values (an arpeggio at three speeds),
/// and a zone with no effect is plain.
struct KeyZoneSettings: Equatable, Sendable {
    /// How many zones a key can have.
    static let counts = 2...4

    /// How far past the edge of its zone a finger must go to leave it, as a
    /// share of the slide. A finger resting on an edge would otherwise switch
    /// the two zones' effects back and forth.
    static var hold: Float { 0.04 }

    var isOn = false
    /// The zones, from the bottom of the key to the top.
    var zones = [KeyZone(), KeyZone(effect: .arpeggiator)]

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

    /// The zone a finger at `slide` is in, counted from the bottom, given the
    /// zone it was in before (`current`); nil while off or no key is held.
    func zone(at slide: Float?, from current: Int?) -> Int? {
        guard isOn, let slide else { return nil }
        let place = slide.clamped(to: 0...1) * Float(zones.count)
        if let current, zones.indices.contains(current) {
            let reach = Self.hold * Float(zones.count)
            if place >= Float(current) - reach, place <= Float(current + 1) + reach { return current }
        }
        return min(Int(place), zones.count - 1)
    }
}

extension EffectKind {
    var label: String {
        switch self {
        case .arpeggiator: return "Arpeggiator"
        case .filter:      return "Filter"
        case .chorus:      return "Chorus"
        case .reverb:      return "Reverb"
        }
    }
}
