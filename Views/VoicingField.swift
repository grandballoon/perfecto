import SwiftUI

/// A finger's travel from where it came down on a voicing field, read as a
/// voicing: along is the inversion, a step to the right rolling the chord
/// up and to the left down, and across is the octave, up being higher
/// (`PadSwipe`, over `VoicingSpan`).
typealias VoicingSwipe = PadSwipe<VoicingSpan>

extension PadSwipe where Map == VoicingSpan {
    var voicing: KeyVoicing { value }
}

/// The octave and the inversion as one setting: a pad field (`PadField`)
/// that shows both. While a finger is on it, every voicing there is is laid
/// out around it (`VoicingPad`), at the place the voicing has now, and the
/// finger moves that place: along the span through the inversions and
/// across it through the octaves.
///
/// `set` is called with each voicing the finger reaches, and `onEnd` when
/// the finger has gone, however it went.
struct VoicingField: View {
    let name: String
    let voicing: KeyVoicing
    var onEnd: () -> Void = {}
    let set: (KeyVoicing) -> Void

    var body: some View {
        PadField<VoicingSpan, VoicingPad>(name: name, value: voicing,
                                          text: "\(voicing.octave) · \(voicing.inversion.label)",
                                          onEnd: onEnd, pad: { VoicingPad(voicing: $0) }, set: set)
            .accessibilityLabel("Octave and inversion")
            .accessibilityValue("Octave \(voicing.octave), inversion \(voicing.inversion.label)")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: step(inversion: 1)
                case .decrement: step(inversion: -1)
                @unknown default: break
                }
            }
            .accessibilityAction(named: "Octave up") { step(octave: 1) }
            .accessibilityAction(named: "Octave down") { step(octave: -1) }
    }

    /// A change made in one step, with no finger on the field.
    private func step(octave: Int = 0, inversion: Int = 0) {
        let new = KeyVoicing(
            octave: (voicing.octave + octave).clamped(to: VoicingSpan.octaves),
            inversion: Inversion(steps: (voicing.inversion.steps + inversion).clamped(to: VoicingSpan.inversions)))
        if new != voicing { set(new) }
        onEnd()
    }
}

/// The keys' voicing on the key strip: the octave their chords are built
/// in and how far they are rolled (`VoicingField`), with the switch that
/// says whether the field keeps what it is set to
/// (`PerformanceState.keepsVoicing`). While it does, the field sets the Key
/// page's octave and the inversion. While it does not, the field is played
/// like a whammy bar: the chords are voiced where the finger is, and go
/// back to the voicing as set when it lifts. Either way a chord being held
/// follows the finger.
struct KeyVoicingField: View {
    @Environment(PerformanceState.self) private var state

    private static let width: CGFloat = 78

    var body: some View {
        HStack(spacing: 4) {
            VoicingField(name: "OCT · INV", voicing: state.heldVoicing, onEnd: state.releaseVoicing) {
                state.holdVoicing(at: $0)
            }
            .frame(width: Self.width)
            @Bindable var state = state
            KeepSwitch(label: "Keep the voicing", keeps: $state.keepsVoicing)
        }
    }
}

/// The switch beside a pad field on the key strip that says whether the
/// field keeps what it is set to, or is played and lets go of it.
struct KeepSwitch: View {
    let label: String
    @Binding var keeps: Bool

    var body: some View {
        Button { keeps.toggle() } label: {
            Image(systemName: keeps ? "pin.fill" : "pin.slash")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(keeps ? Color.orange : Color(white: 0.5))
                .frame(maxHeight: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(white: 0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(keeps ? Color.orange : Color(white: 0.25), lineWidth: 1)
                        )
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(keeps ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }
}

extension Inversion {
    /// The inversion as its steps from root position: "0", "+2", "−1".
    var label: String {
        steps > 0 ? "+\(steps)" : steps < 0 ? "−\(-steps)" : "0"
    }
}
