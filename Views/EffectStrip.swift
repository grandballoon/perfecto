import SwiftUI

/// The effect strip: the keys' effects in a row on the play screen, under
/// the key strip, and on the Tonnetz's, which is played with them. Each
/// field is one effect that is on (`EffectsState.slots`), changed by a swipe (`SwipeField`) through the effects no other field has,
/// from off: Arpeggio 1 and 2, the chorus, the reverb and the vocoder.
/// There is one field to start with, and the button at the end adds another,
/// so several effects can be on together; a field left off goes when the
/// finger lifts, but for the last.
///
/// An arpeggio's field has its cycle beside it (`ArpeggioCycleField`).
/// These are the Effects page's switches, within reach while playing, so
/// either follows the other.
struct EffectStrip: View {
    @Environment(PerformanceState.self) private var state

    private static let height: CGFloat = 34

    var body: some View {
        let effects = state.effects
        HStack(spacing: 8) {
            // A field is its place in the row, whatever effect it has, so
            // it stays under the finger that is changing it.
            ForEach(Array(effects.slotChoices.enumerated()), id: \.offset) { slot, choice in
                EffectField(slot: slot, choice: choice)
                if choice?.kind == .arpeggiator { ArpeggioCycleField() }
            }
            if effects.slots.canAdd { addButton }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Self.height)
        .animation(.snappy(duration: 0.18), value: effects.slots)
    }

    private var addButton: some View {
        Button { state.effects.addSlot() } label: {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.orange)
                .frame(width: Self.height)
                .frame(maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(white: 0.12))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(white: 0.25), lineWidth: 1))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add an effect")
    }
}

/// One field of the effect strip: the effect in `slot`, or off.
private struct EffectField: View {
    let slot: Int
    let choice: EffectChoice?

    @Environment(PerformanceState.self) private var state

    var body: some View {
        let effects = state.effects
        let choices = effects.slots.choices(for: slot)
        SwipeField(name: "EFFECT", value: choices.firstIndex(of: choice) ?? 0,
                   range: 0...(choices.count - 1), textSize: 12,
                   onEnd: { effects.settleSlots() },
                   label: { choices[$0]?.shortLabel ?? "OFF" }) {
            effects.setSlot(slot, to: choices[$0])
        }
        .frame(maxWidth: SoundField.width)
    }
}

/// The arpeggio's cycle beside its field on the effect strip: how long one
/// pass over a chord takes, in beats, changed by a swipe from the shortest
/// to the longest. It is the Effects page's cycle.
private struct ArpeggioCycleField: View {
    @Environment(PerformanceState.self) private var state

    private static let cycles = ArpeggioCycle.allCases
    private static let width: CGFloat = 54

    var body: some View {
        let effects = state.effects
        SwipeField(name: "CYCLE", value: Self.cycles.firstIndex(of: effects.arpeggiator.cycle) ?? 0,
                   range: 0...(Self.cycles.count - 1),
                   label: { Self.cycles[$0].label }) {
            effects.arpeggiator.cycle = Self.cycles[$0]
        }
        .frame(width: Self.width)
    }
}
