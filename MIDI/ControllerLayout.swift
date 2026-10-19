import CoreGraphics

/// The face of a MIDI controller: where each of its controls is, what kind
/// it is and the messages it sends from the factory, so that what it sends
/// can be drawn on it.
///
/// MIDI says nothing of what a device looks like. CoreMIDI gives a device's
/// name and its ports, and a controller of MIDI 1.0 (as nearly all are)
/// has no way to say what controls it has, so a layout is written for each
/// device and recognized by its name. Whatever the controls are set to
/// send is learned by hearing them (`ControllerState.learn`).
///
/// Everything is measured on the device's panel, in its own units (the
/// V61's are centimetres), so a layout reads against the real thing.
struct ControllerLayout: Sendable {
    /// What the controller's learned bindings are saved under.
    let id: String
    let name: String
    /// The panel's width and height.
    let size: CGSize
    /// Where the maker's name is written.
    let nameplate: CGRect
    let keyboard: ControllerKeyboard
    let controls: [ControllerControl]
    /// The names written on the panel beside groups of controls.
    let captions: [ControllerCaption]
    /// Whether a device CoreMIDI names `name` is this one.
    let recognizes: @Sendable (_ name: String) -> Bool

    func control(_ id: ControllerControl.ID) -> ControllerControl? {
        controls.first { $0.id == id }
    }
}

/// The keys of a controller: `count` keys from `lowestNote` with no octave
/// shift, along `frame`.
struct ControllerKeyboard: Equatable, Sendable {
    let lowestNote: Int
    let count: Int
    let frame: CGRect

    var notes: ClosedRange<Int> { lowestNote...(lowestNote + count - 1) }
}

/// One control of a controller other than its keys.
struct ControllerControl: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case pad, knob, button, pitchWheel, modWheel, pedal
        /// The octave buttons send nothing: the shift they make is read
        /// from the notes the keys send (`ControllerKeys`).
        case octaveDown, octaveUp
    }

    let id: String
    /// "Pad 1": what the control is called.
    let name: String
    /// "1": what is written on it, if anything.
    let mark: String
    let kind: Kind
    let frame: CGRect
    /// What it sends from the factory; nil for a control that sends nothing.
    let address: MidiAddress?

    /// Whether a control of this kind can be told what it sends.
    var isLearnable: Bool { address != nil }
}

struct ControllerCaption: Hashable, Sendable {
    let text: String
    let frame: CGRect
}
