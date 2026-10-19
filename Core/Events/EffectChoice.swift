/// An effect as it is offered where one is chosen (the play screen's effect
/// fields, a key zone): the two arpeggios are two choices of the one
/// arpeggiator, and the others are their effects.
enum EffectChoice: Hashable, CaseIterable, Sendable {
    case arpeggio(ArpeggioPattern)
    case chorus
    case reverb
    case delay
    case vocoder

    static let allCases: [EffectChoice] = ArpeggioPattern.allCases.map(arpeggio) + [.chorus, .reverb, .delay, .vocoder]

    /// The effect this is a choice of.
    var kind: EffectKind {
        switch self {
        case .arpeggio: return .arpeggiator
        case .chorus:   return .chorus
        case .reverb:   return .reverb
        case .delay:    return .delay
        case .vocoder:  return .vocoder
        }
    }

    /// The pattern an arpeggio plays; nil for the other effects.
    var pattern: ArpeggioPattern? {
        if case .arpeggio(let pattern) = self { pattern } else { nil }
    }

    var label: String {
        switch self {
        case .arpeggio(let pattern): return pattern.label
        case .chorus:                return "Chorus"
        case .reverb:                return "Reverb"
        case .delay:                 return "Delay"
        case .vocoder:               return "Vocoder"
        }
    }

    /// The label on a field of the play screen.
    var shortLabel: String {
        switch self {
        case .arpeggio(.up):   return "ARP 1"
        case .arpeggio(.down): return "ARP 2"
        case .chorus:          return "CHORUS"
        case .reverb:          return "REVERB"
        case .delay:           return "DELAY"
        case .vocoder:         return "VOCODER"
        }
    }

    /// The label where there is room for three letters.
    var abbreviation: String {
        switch self {
        case .arpeggio(.up):   return "AR1"
        case .arpeggio(.down): return "AR2"
        case .chorus:          return "CHO"
        case .reverb:          return "REV"
        case .delay:           return "DLY"
        case .vocoder:         return "VOC"
        }
    }
}

extension NoteEffects {
    /// The choice of `kind` that is on; nil while that effect is off.
    func choice(of kind: EffectKind) -> EffectChoice? {
        switch kind {
        case .arpeggiator: return arpeggiator.isOn ? .arpeggio(arpeggiator.pattern) : nil
        case .chorus:      return chorus.isOn ? .chorus : nil
        case .reverb:      return reverb.isOn ? .reverb : nil
        case .delay:       return delay.isOn ? .delay : nil
        case .vocoder:     return vocoder.isOn ? .vocoder : nil
        }
    }

    /// Switches `kind` off.
    mutating func switchOff(_ kind: EffectKind) {
        switch kind {
        case .arpeggiator: arpeggiator.isOn = false
        case .chorus:      chorus.isOn = false
        case .reverb:      reverb.isOn = false
        case .delay:       delay.isOn = false
        case .vocoder:     vocoder.isOn = false
        }
    }

    /// Switches `choice` on: its effect, and for an arpeggio its pattern.
    mutating func switchOn(_ choice: EffectChoice) {
        switch choice {
        case .arpeggio(let pattern):
            arpeggiator.isOn = true
            arpeggiator.pattern = pattern
        case .chorus:  chorus.isOn = true
        case .reverb:  reverb.isOn = true
        case .delay:   delay.isOn = true
        case .vocoder: vocoder.isOn = true
        }
    }
}

/// The play screen's effect fields, as places in a row: each holds one of
/// the effects that are on, or is empty. There is one to start with, and
/// more are added one at a time, so the row is as short as what is on.
///
/// A slot keeps its place while it is being changed, also while it is
/// empty, so the field a finger is swiping stays under it; `settle` closes
/// the row up once the finger has lifted.
struct EffectSlots: Equatable, Sendable {
    /// The effect in each slot, in the order the row shows them; nil is an
    /// empty slot. No effect is in two, and there is always a slot.
    private(set) var kinds: [EffectKind?] = [nil]

    /// Whether a slot can be added: every slot has an effect, and there is
    /// an effect left to choose.
    var canAdd: Bool { !kinds.contains(nil) && kinds.count < EffectKind.allCases.count }

    /// Adds an empty slot at the end of the row.
    mutating func add() {
        guard canAdd else { return }
        kinds.append(nil)
    }

    /// What `slot` can be changed to, in the order its field goes through
    /// them, from empty (nil): every choice of an effect that no other slot has.
    func choices(for slot: Int) -> [EffectChoice?] {
        let taken = Set(kinds.enumerated().compactMap { $0.offset == slot ? nil : $0.element })
        return [nil] + EffectChoice.allCases.filter { !taken.contains($0.kind) }
    }

    /// Puts `kind` in `slot` (nil empties it), unless another slot has it.
    mutating func put(_ kind: EffectKind?, in slot: Int) {
        guard kinds.indices.contains(slot) else { return }
        if let kind, let other = kinds.firstIndex(of: kind), other != slot { return }
        kinds[slot] = kind
    }

    /// `kind` was switched on or off by something other than its slot: on,
    /// it is given the first empty slot, or a new one; off, its slot goes.
    mutating func follow(_ kind: EffectKind, isOn: Bool) {
        let slot = kinds.firstIndex(of: kind)
        guard isOn != (slot != nil) else { return }
        if let slot {
            kinds[slot] = nil
            settle()
        } else if let empty = kinds.firstIndex(of: nil) {
            kinds[empty] = kind
        } else {
            kinds.append(kind)
        }
    }

    /// Closes the row up: the empty slots go, but for one where every slot
    /// is empty.
    mutating func settle() {
        kinds.removeAll { $0 == nil }
        if kinds.isEmpty { kinds = [nil] }
    }
}
