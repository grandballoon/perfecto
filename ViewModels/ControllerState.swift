import Foundation
import Observation

/// A MIDI controller as the app hears it: what each of its controls is
/// doing, drawn on its face (`ControllerView`), and what each sends.
///
/// `MidiInput` hears every MIDI source there is and hands this what they
/// send. A message is read against the controls' bindings, each the
/// factory's (`ControllerControl.address`) unless one has been learned:
/// while learning, a control chosen takes the next message heard as its
/// own, and the learned bindings are saved. A note no control has is one
/// of the keys, which work out their octave shift from it
/// (`ControllerKeys`).
///
/// It plays nothing yet: it is what the controller is doing, for what is
/// to be played from it.
@Observable
@MainActor
final class ControllerState {

    let layout: ControllerLayout

    /// The MIDI sources there are, by name. The app's own are not among
    /// them.
    private(set) var sources: [String] = []

    /// How far each control is moved or pressed, from 0 at rest to 1 (the
    /// pitch wheel from -1 to 1). A control that has sent nothing has none.
    private(set) var values: [ControllerControl.ID: Double] = [:]

    /// The notes held on the keys, each with its velocity.
    private(set) var heldNotes: [Int: Int] = [:]

    /// Which key each note is.
    private(set) var keys: ControllerKeys

    /// Whether a control chosen learns what it sends (`choose`).
    var isLearning = false {
        didSet { if !isLearning { learning = nil } }
    }

    /// The control the next message heard is bound to.
    private(set) var learning: ControllerControl.ID?

    /// The last message heard, and what it was read as.
    private(set) var heard: Heard?

    struct Heard: Equatable {
        let message: MidiMessage
        let target: Target
    }

    enum Target: Equatable {
        case control(ControllerControl.ID)
        /// The key, from 0 at the lowest.
        case key(Int)
        /// Nothing on the controller sends it.
        case none
    }

    /// The bindings learned, over the factory's: nil is a control that has
    /// given its message up to another.
    private var learned: [ControllerControl.ID: MidiAddress?] {
        didSet { save() }
    }

    private let defaults: UserDefaults?
    private let logger: (any Logger)?

    /// `defaults` is where the learned bindings are saved; with none they
    /// are not.
    init(layout: ControllerLayout = .alesisV61, defaults: UserDefaults? = .standard,
         logger: (any Logger)? = nil) {
        self.layout = layout
        self.defaults = defaults
        self.logger = logger
        keys = ControllerKeys(layout.keyboard)
        learned = defaults?.data(forKey: Self.savedKey(layout))
            .flatMap { try? JSONDecoder().decode([ControllerControl.ID: MidiAddress?].self, from: $0) }
            ?? [:]
    }

    // MARK: – The device

    /// The source that is the controller the layout is of, if one is
    /// connected. Whatever any source sends is drawn on it all the same.
    var device: String? {
        sources.first(where: layout.recognizes)
    }

    /// The sources there are now are `names`. One that has gone may have
    /// left its keys held, so they are let go.
    func connected(to names: [String]) {
        guard names != sources else { return }
        if !Set(sources).isSubset(of: names) { releaseNotes() }
        sources = names
        logger?.log(.midi_input_connected(sources: names))
    }

    /// CoreMIDI would not open the way in, with `status`.
    func inputFailed(status: Int32) {
        logger?.log(.midi_input_failed(status: status))
    }

    // MARK: – Hearing

    func hear(_ message: MidiMessage) {
        if let id = learning, let address = MidiAddress(learning: message) {
            bind(id, to: address)
        }
        if let control = layout.controls.first(where: { address(of: $0.id)?.matches(message) == true }) {
            values[control.id] = Self.reading(of: message)
            heard = Heard(message: message, target: .control(control.id))
            return
        }
        switch message {
        case let .noteOn(_, note, velocity):
            heldNotes[note] = velocity
            heard = Heard(message: message, target: .key(keys.key(of: note)))
        case let .noteOff(_, note):
            heldNotes[note] = nil
            heard = Heard(message: message, target: keys.key(at: note).map(Target.key) ?? .none)
        default:
            heard = Heard(message: message, target: .none)
        }
    }

    /// How far `message` moves the control it is from, 0 to 1: a pitch
    /// bend from -1 to 1, and a program, which has no value, all the way.
    private static func reading(of message: MidiMessage) -> Double {
        switch message {
        case let .noteOn(_, _, velocity):         return Double(velocity) / 127
        case .noteOff:                            return 0
        case let .polyPressure(_, _, pressure):   return Double(pressure) / 127
        case let .controlChange(_, _, value):     return Double(value) / 127
        case .programChange:                      return 1
        case let .channelPressure(_, pressure):   return Double(pressure) / 127
        case let .pitchBend(_, value):            return max(-1, Double(value) / 8191)
        }
    }

    /// The velocity `key` is held at, from 0 at the lowest key as the keys
    /// are shifted now; nil while it is up.
    func velocity(ofKey key: Int) -> Int? {
        heldNotes.first { keys.key(at: $0.key) == key }?.value
    }

    private func releaseNotes() {
        heldNotes = [:]
        for control in layout.controls where address(of: control.id)?.kind == .note {
            values[control.id] = nil
        }
    }

    // MARK: – Learning

    /// What `id` is heard by: the binding learned for it, or the factory's.
    func address(of id: ControllerControl.ID) -> MidiAddress? {
        if let learned = learned[id] { return learned }
        return layout.control(id)?.address
    }

    /// Whether `id` sends something other than it did from the factory.
    func hasLearned(_ id: ControllerControl.ID) -> Bool {
        learned[id] != nil
    }

    var hasLearnedAny: Bool { !learned.isEmpty }

    /// While learning, `id` is the control the next message heard is bound
    /// to, or, chosen again, no longer. A control that sends nothing has
    /// nothing to learn.
    func choose(_ id: ControllerControl.ID) {
        guard isLearning, layout.control(id)?.isLearnable == true else { return }
        learning = learning == id ? nil : id
    }

    /// Every control sends what it did from the factory.
    func forgetLearned() {
        learned = [:]
        logger?.log(.controller_learned_forgotten(layout: layout.id))
    }

    /// `id` is heard by `address` from now on, and any other control that
    /// was heard by it is not: a message is one control's.
    private func bind(_ id: ControllerControl.ID, to address: MidiAddress) {
        learning = nil
        for control in layout.controls where control.id != id {
            if let other = self.address(of: control.id), other.overlaps(address) {
                learned[control.id] = .some(nil)
                values[control.id] = nil
            }
        }
        if layout.control(id)?.address == address {
            learned.removeValue(forKey: id)
        } else {
            learned[id] = .some(address)
        }
        values[id] = nil
        logger?.log(.controller_control_learned(control: id, address: address.label))
    }

    // MARK: – Saving

    private static func savedKey(_ layout: ControllerLayout) -> String {
        "controllerBindings.\(layout.id)"
    }

    private func save() {
        guard let defaults, let data = try? JSONEncoder().encode(learned) else { return }
        defaults.set(data, forKey: Self.savedKey(layout))
    }
}

extension MidiAddress {
    /// Whether a message could be heard by both this address and `other`.
    func overlaps(_ other: MidiAddress) -> Bool {
        kind == other.kind && number == other.number
            && (channel == nil || other.channel == nil || channel == other.channel)
    }
}
