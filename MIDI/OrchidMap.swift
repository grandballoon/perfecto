/// What a controller's controls play as an Orchid's would (`OrchidState`):
/// which are its chord buttons and its key button, and which of its knobs
/// and wheels can be given the voicing or the arpeggio. Every one of its
/// keys is a root.
///
/// A control is named by its id on the controller's layout, so it plays
/// its part whatever it has been taught to send.
struct OrchidMap: Sendable {
    /// The top row of the Orchid's buttons: the chord's triad.
    let types: [ControllerControl.ID: ChordType]
    /// The bottom row: what is added to the triad.
    let extensions: [ControllerControl.ID: ChordExtension]
    /// The key button: a press switches key mode, and held, the next key
    /// struck is the key.
    let key: ControllerControl.ID
    /// The key change button, which the Orchid has not: pressed, the next
    /// key struck is the key, with the button let go.
    let keyChange: ControllerControl.ID
    /// The knobs and wheels that can be given a part that is turned
    /// (`OrchidPart`), in the order the pane offers them.
    let turned: [TurnedControl]
    /// The control each part has to start with; a part with none has no
    /// control until it is given one.
    let standard: [OrchidPart: ControllerControl.ID]

    func turned(_ id: ControllerControl.ID?) -> TurnedControl? {
        turned.first { $0.id == id }
    }

    /// What `id` is marked with here, if it is a button with a part.
    func mark(of id: ControllerControl.ID) -> String? {
        if let type = types[id] { return type.mark.uppercased() }
        if let chordExtension = extensions[id] { return chordExtension.mark }
        if id == key { return "KEY" }
        return id == keyChange ? "SET KEY" : nil
    }
}

/// A part of the Orchid played by turning a knob or pushing a wheel.
enum OrchidPart: String, CaseIterable, Sendable {
    /// The voicing dial: from one end of its control to the other it rolls
    /// the chords through every inversion the keys can be set to.
    case voicing
    /// The arpeggio, which the Orchid has not: up from the control's middle
    /// it goes from the lowest note up, down from it from the highest down,
    /// and the further from the middle the faster.
    case arpeggio

    /// What the pane calls it.
    var name: String {
        switch self {
        case .voicing:  return "VOICE"
        case .arpeggio: return "ARP"
        }
    }
}

/// A knob or a wheel, which can be given a part that is turned.
struct TurnedControl: Hashable, Sendable {
    let id: ControllerControl.ID
    /// "KNOB 1", "PITCH": what the pane calls it.
    let name: String
    /// What it reads from one end to the other: the pitch wheel's are -1 to
    /// 1, a knob's and the mod wheel's 0 to 1.
    let values: ClosedRange<Double>

    /// How far along it `value` is: from 0 at its lowest to 1 at its highest.
    func position(at value: Double) -> Double {
        ((value - values.lowerBound) / (values.upperBound - values.lowerBound)).clamped(to: 0...1)
    }

    /// How far `value` is from its middle: from -1 all the way down to 1
    /// all the way up.
    func push(at value: Double) -> Double {
        position(at: value) * 2 - 1
    }
}

extension OrchidMap {
    /// The V61's pads are two rows of four, as the Orchid's buttons are,
    /// and in the same place, under the left hand: the top row is the
    /// types, the bottom the extensions. Its first button is the key
    /// button and its second the key change button. Any of its four knobs or either wheel can
    /// be given the voicing or the arpeggio: the voicing is on its first
    /// knob to start with, as the Orchid's dial is beside its buttons, and
    /// the arpeggio on none. The pitch wheel springs back to its middle;
    /// the knobs and the mod wheel stay where they are left.
    static let alesisV61 = OrchidMap(
        types: ["pad5": .diminished, "pad6": .minor, "pad7": .major, "pad8": .suspended],
        extensions: ["pad1": .sixth, "pad2": .minorSeventh, "pad3": .majorSeventh, "pad4": .ninth],
        key: "button1",
        keyChange: "button2",
        turned: (1...4).map { TurnedControl(id: "knob\($0)", name: "KNOB \($0)", values: 0...1) }
            + [TurnedControl(id: "pitch", name: "PITCH", values: -1...1),
               TurnedControl(id: "mod", name: "MOD", values: 0...1)],
        standard: [.voicing: "knob1"])
}
