import Foundation
import Observation

/// What a MIDI controller played as an Orchid plays through.
@MainActor
protocol OrchidHost: AnyObject {
    /// `key` struck in `octave`, which its chord's root is in.
    func press(_ key: ChordKey, inOctave octave: Int?)
    func release(_ key: ChordKey, inOctave octave: Int?)
    /// The chord buttons held build `build`; nil: they build nothing, and
    /// the chords are colored as the screen colors them.
    func chordButtonsMoved(to build: ChordBuild?)
    var key: Key { get set }
    var inversion: Inversion { get set }
    /// The arpeggio's control holds `arpeggio` on; nil: it holds none.
    func holdArpeggio(_ arpeggio: HeldArpeggio?)
    /// The Orchid is played only at the desk.
    var isAtDesk: Bool { get }
}

/// A MIDI controller played as Telepathic Instruments' Orchid is, without
/// its sounds: each of its keys is a chord's root, in the octave the key
/// is in, and buttons beside them choose its type and extensions
/// (`OrchidMap` says which). So the keyboard's width is the octave, as the
/// voicing dial is the inversion, and neither is chosen on the screen.
///
/// - A type button held (Dim, Min, Maj, Sus) builds the chord on that
///   triad, on whatever root; of several held, the last pressed. The
///   extension buttons (6, m7, M7, 9) add their notes to it, as many as are
///   held (`ChordBuild`).
/// - In key mode a root with no type button held plays its chord as the
///   key has it (`ChordKey.root`, borrowed for a note outside the key), and
///   the extensions add to that. Out of key mode it plays the root alone.
/// - The key button switches key mode, and held, the next root struck is
///   the key: minor while the Min button is held, major otherwise.
/// - The key change button, which the Orchid has not, does the same
///   without being held: pressed, the next root struck is the key, and
///   pressed again before one is, none is.
/// - Any knob or wheel can be given the voicing or the arpeggio
///   (`OrchidPart`, `give(_:to:)`), and a control plays one part.
/// - The voicing dial rolls the chords through their inversions, one note
///   at a time, and reaches the chord being held at once.
/// - The arpeggio, which the Orchid has not: its control turned up from
///   its middle plays the chord's notes from the lowest to the highest,
///   down from it from the highest to the lowest, and the further from the
///   middle the faster, through the arpeggiator's cycles.
/// - The velocity, which the Orchid does not play: while it plays the
///   arpeggio (`velocityPlaysArpeggio`), every chord is arpeggiated in the
///   order its key was struck with, soft going up and hard coming down
///   (`pattern(struckAt:)`), so the order is chosen as the key is struck
///   and kept while it is held. The arpeggio's control, if it is pushed,
///   still says how fast, and the arpeggiator's cycle does otherwise.
///
/// It is one more finger, as the computer keyboard is: a root presses and
/// releases through the host's own calls, so the modes, the loops and the
/// effects know nothing of it, and the buttons are a color surface of
/// their own, so a button held also builds the chords the screen plays.
///
/// `ControllerState` hears the controller and tells this what each control
/// and note does.
@Observable
@MainActor
final class OrchidState {

    let map: OrchidMap

    /// Whether a root with no type button held plays its chord in the key
    /// (on) or the root alone (off). It is on to start with, so a key alone
    /// plays a chord, and is remembered.
    private(set) var isKeyMode: Bool {
        didSet {
            guard isKeyMode != oldValue else { return }
            defaults?.set(isKeyMode, forKey: Self.keyModeKey)
            logger?.log(.orchid_key_mode_switched(isOn: isKeyMode))
        }
    }

    /// The knob or wheel each part is played by; a part that is not here
    /// has none. Each is the map's to start with, and remembered.
    private(set) var controls: [OrchidPart: TurnedControl] = [:]

    /// Whether every chord is arpeggiated, in the order the velocity its
    /// key was struck with plays (`pattern(struckAt:)`). It is off to start
    /// with, and is remembered.
    private(set) var velocityPlaysArpeggio: Bool {
        didSet {
            guard velocityPlaysArpeggio != oldValue else { return }
            defaults?.set(velocityPlaysArpeggio, forKey: Self.velocityArpeggioKey)
            logger?.log(.orchid_velocity_arpeggio_switched(isOn: velocityPlaysArpeggio))
        }
    }

    /// The velocity from which a key is struck hard, and its chord's
    /// arpeggio comes down rather than goes up: the middle of MIDI's
    /// velocities.
    static let hardVelocity = 64

    /// The arpeggio held on now, by its control or the velocity; nil while
    /// neither holds one.
    private(set) var heldArpeggio: HeldArpeggio?

    /// The arpeggio its control holds on; nil while it is at its middle.
    private var pushedArpeggio: HeldArpeggio?

    /// How far either way of its middle the arpeggio's control plays
    /// nothing, as a share of its travel, so a wheel at rest that reads a
    /// little off its middle, or a knob left near it, plays no arpeggio.
    static let arpeggioRest = 0.1

    /// The type buttons held, oldest first: the last is the chord's type.
    private(set) var heldTypes: [ChordType] = []
    private(set) var heldExtensions: Set<ChordExtension> = []

    /// The keys held, oldest first: the last is the chord sounding.
    private var heldNotes: [HeldNote] = []

    private struct HeldNote {
        let note: Int
        let root: PitchClass
        let velocity: Int
    }

    /// The controls held down, so a control is pressed once however often
    /// it says so.
    private var heldControls: Set<ControllerControl.ID> = []

    /// While the key button is held: whether a key has been chosen with it,
    /// which leaves key mode on as it lifts.
    private var keyButton: KeyButton?

    private struct KeyButton {
        var choseKey = false
    }

    /// Whether the key change button has been pressed and no key struck
    /// since, so the next root struck is the key.
    private(set) var isWaitingForKey = false {
        didSet {
            guard isWaitingForKey != oldValue else { return }
            logger?.log(.orchid_key_change_switched(isWaiting: isWaitingForKey))
        }
    }

    /// Whether a root struck now chooses the key: the key button is held,
    /// or the key change button is waiting for one.
    var isChoosingKey: Bool { keyButton != nil || isWaitingForKey }

    @ObservationIgnored weak var host: (any OrchidHost)?

    private let defaults: UserDefaults?
    private let logger: (any Logger)?

    private static let keyModeKey = "orchidKeyMode"
    private static let velocityArpeggioKey = "orchidVelocityArpeggio"

    private static func controlKey(_ part: OrchidPart) -> String { "orchidControl.\(part.rawValue)" }

    /// `defaults` is where key mode and the parts' controls are remembered;
    /// with none they are not.
    init(map: OrchidMap = .alesisV61, defaults: UserDefaults? = .standard,
         logger: (any Logger)? = nil) {
        self.map = map
        self.defaults = defaults
        self.logger = logger
        isKeyMode = defaults?.object(forKey: Self.keyModeKey) as? Bool ?? true
        velocityPlaysArpeggio = defaults?.bool(forKey: Self.velocityArpeggioKey) ?? false
        for part in OrchidPart.allCases {
            // A part saved with no control is saved as none.
            let id = defaults?.string(forKey: Self.controlKey(part)) ?? map.standard[part]
            controls[part] = map.turned(id)
        }
    }

    /// What the buttons held build. nil while they build nothing, so the
    /// screen's color is the chord's: no button held, in key mode or with
    /// no root held.
    var build: ChordBuild? {
        let type = heldTypes.last ?? (isKeyMode || heldNotes.isEmpty ? nil : .note)
        guard type != nil || !heldExtensions.isEmpty else { return nil }
        return ChordBuild(type: type, extensions: heldExtensions)
    }

    // MARK: – What the controller does

    /// The control `id` is moved to `value` (0 at rest to 1).
    func control(_ id: ControllerControl.ID, movedTo value: Double) {
        if let part = part(of: id), let turned = controls[part] {
            switch part {
            case .voicing:  turnVoicing(to: turned.position(at: value))
            case .arpeggio: pushArpeggio(turned.push(at: value))
            }
            return
        }
        guard map.types[id] != nil || map.extensions[id] != nil || id == map.key || id == map.keyChange
        else { return }
        // A pad is struck as hard or as soft as it is: any touch presses it.
        let isDown = value > 0
        guard isDown != heldControls.contains(id) else { return }
        if isDown {
            guard host?.isAtDesk == true else { return }
            heldControls.insert(id)
        } else {
            heldControls.remove(id)
        }

        if let type = map.types[id] {
            heldTypes.removeAll { $0 == type }
            if isDown { heldTypes.append(type) }
        } else if let chordExtension = map.extensions[id] {
            if isDown { heldExtensions.insert(chordExtension) } else { heldExtensions.remove(chordExtension) }
        } else if id == map.keyChange {
            if isDown { isWaitingForKey.toggle() }
            return
        } else {
            isDown ? pressKeyButton() : liftKeyButton()
            return
        }
        followButtons()
    }

    /// `note` went down on the controller's keys. The Orchid plays every
    /// chord as hard as the keys do, whatever the velocity, which plays
    /// only the arpeggio's order, and only while it is switched to.
    func keyDown(_ note: Int, velocity: Int) {
        guard !heldNotes.contains(where: { $0.note == note }), host?.isAtDesk == true,
              let root = PitchClass(rawValue: note % 12) else { return }
        if isChoosingKey {
            choose(Key(root: root, scale: heldTypes.contains(.minor) ? .naturalMinor : .major))
            return
        }
        heldNotes.append(HeldNote(note: note, root: root, velocity: velocity))
        // The chord is built and its arpeggio chosen before it is struck,
        // so it starts as it is.
        followButtons()
        followArpeggio()
        host?.press(.root(root), inOctave: Self.octave(of: note))
    }

    /// The octave `note` is in, as the keys' octaves are counted: middle C
    /// (60) is in octave 4.
    static func octave(of note: Int) -> Int { note / 12 - 1 }

    /// `note` came up.
    /// A key held beneath it takes the chord back in the order it was
    /// struck with, as a key zone's effect is handed back, and the last key
    /// up ends its chord before its arpeggio, which switching off would
    /// sound the chord once more.
    func keyUp(_ note: Int) {
        guard let index = heldNotes.firstIndex(where: { $0.note == note }) else { return }
        let lifted = heldNotes.remove(at: index)
        if !heldNotes.isEmpty { followArpeggio() }
        host?.release(.root(lifted.root), inOctave: Self.octave(of: note))
        if heldNotes.isEmpty { followArpeggio() }
        followButtons()
    }

    /// Everything held is let go: the controller is gone, or the desk.
    func releaseAll() {
        for note in heldNotes.map(\.note).sorted() { keyUp(note) }
        heldTypes = []
        heldExtensions = []
        heldControls = []
        keyButton = nil
        isWaitingForKey = false
        followButtons()
        pushedArpeggio = nil
        followArpeggio()
    }

    /// The part `id` plays, if it has one.
    func part(of id: ControllerControl.ID) -> OrchidPart? {
        controls.first { $0.value.id == id }?.key
    }

    /// `part` is played by `control` from now on; nil: by none. A control
    /// plays one part, so a part it played has none now, and an arpeggio
    /// held on by a control that is no longer the arpeggio's stops.
    func give(_ part: OrchidPart, to control: TurnedControl?) {
        guard controls[part] != control else { return }
        if let control, let other = self.part(of: control.id) { set(other, to: nil) }
        set(part, to: control)
        if controls[.arpeggio] == nil || part == .arpeggio {
            pushedArpeggio = nil
            followArpeggio()
        }
    }

    private func set(_ part: OrchidPart, to control: TurnedControl?) {
        controls[part] = control
        defaults?.set(control?.id ?? "", forKey: Self.controlKey(part))
        logger?.log(.orchid_part_given(part: part.rawValue, control: control?.id))
    }

    /// Key mode switched from the screen, as the key button switches it.
    func switchKeyMode() {
        isKeyMode.toggle()
        followButtons()
    }

    /// The velocity switched to play the arpeggio's order, or not to. A
    /// chord being held is arpeggiated at once, in its key's order.
    func switchVelocityArpeggio() {
        velocityPlaysArpeggio.toggle()
        followArpeggio()
    }

    /// The order a chord is arpeggiated in when its key is struck at
    /// `velocity` (1 to 127): soft, from the lowest note up; hard, from the
    /// highest down.
    static func pattern(struckAt velocity: Int) -> ArpeggioPattern {
        velocity < hardVelocity ? .up : .down
    }

    // MARK: – The controls

    private func followButtons() {
        host?.chordButtonsMoved(to: build)
    }

    /// The dial's whole turn is every inversion the keys can be set to, so
    /// its middle is root position. `position` is how far along it is, 0
    /// to 1.
    private func turnVoicing(to position: Double) {
        guard let host, host.isAtDesk else { return }
        let range = PerformanceState.inversions
        let steps = range.lowerBound + Int((position * Double(range.count - 1)).rounded())
        host.inversion = Inversion(steps: steps)
    }

    /// The arpeggio's control is `push` from its middle (-1 all the way
    /// down to 1 all the way up). Past its rest, the rest of its travel is
    /// divided among the cycles, the slowest nearest the middle.
    private func pushArpeggio(_ push: Double) {
        let distance = abs(push)
        if distance > Self.arpeggioRest, host?.isAtDesk == true {
            let share = (distance - Self.arpeggioRest) / (1 - Self.arpeggioRest)
            pushedArpeggio = HeldArpeggio(pattern: push > 0 ? .up : .down, cycle: .played(by: Float(share)))
        } else {
            pushedArpeggio = nil
        }
        followArpeggio()
    }

    /// Holds on the arpeggio the control and the velocity play together:
    /// the order is the velocity's while it plays one and the chord
    /// sounding was struck by a key, and the speed is the control's while
    /// it is pushed.
    private func followArpeggio() {
        let struck = velocityPlaysArpeggio ? heldNotes.last.map { Self.pattern(struckAt: $0.velocity) } : nil
        if var pushed = pushedArpeggio {
            pushed.pattern = struck ?? pushed.pattern
            hold(pushed)
        } else {
            hold(struck.map { HeldArpeggio(pattern: $0) })
        }
    }

    private func hold(_ arpeggio: HeldArpeggio?) {
        guard arpeggio != heldArpeggio else { return }
        heldArpeggio = arpeggio
        host?.holdArpeggio(arpeggio)
    }

    private func pressKeyButton() {
        keyButton = KeyButton()
    }

    /// A press that chose no key switches key mode.
    private func liftKeyButton() {
        guard let keyButton else { return }
        self.keyButton = nil
        if !keyButton.choseKey { isKeyMode.toggle() }
        followButtons()
    }

    private func choose(_ key: Key) {
        keyButton?.choseKey = true
        isWaitingForKey = false
        isKeyMode = true
        host?.key = key
        logger?.log(.orchid_key_chosen(key: "\(key.root.name) \(key.scale.displayName)"))
    }
}
