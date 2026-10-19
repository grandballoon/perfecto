import SwiftUI
import UIKit

/// A finger's travel from where it came down on a voicing field, read as a
/// voicing: along is the inversion, a step to the right rolling the chord
/// up and to the left down, and across is the octave, up being higher. A
/// step is a cell of the span the field shows meanwhile (`VoicingSpan`), so
/// the place lit there moves as the finger does, and each way is read as
/// any swipe is (`SwipeSteps`): a finger that only goes up or down changes
/// only the octave.
struct VoicingSwipe: Equatable {
    private var along: SwipeSteps
    private var across: SwipeSteps

    init(from voicing: KeyVoicing) {
        along = SwipeSteps(from: voicing.inversion.steps, in: VoicingSpan.inversions,
                           step: VoicingSpan.cell.width)
        across = SwipeSteps(from: voicing.octave, in: VoicingSpan.octaves, step: VoicingSpan.cell.height)
    }

    var voicing: KeyVoicing {
        KeyVoicing(octave: across.value, inversion: Inversion(steps: along.value))
    }

    /// The finger is `translation` from where it came down.
    mutating func moved(to translation: CGSize) {
        along.moved(to: translation.width)
        across.moved(to: -translation.height)
    }
}

/// The octave and the inversion as one setting: a chit that shows both and
/// is changed by pressing it. While a finger is on it, every voicing there
/// is is laid out around it (`VoicingPad`, drawn by the screen), at the
/// place the voicing has now, and the finger moves that place: along the
/// span through the inversions and across it through the octaves
/// (`VoicingSwipe`).
///
/// `set` is called with each voicing the finger reaches, and `onEnd` when
/// the finger has gone, however it went.
struct VoicingField: View {
    let name: String
    let voicing: KeyVoicing
    var onEnd: () -> Void = {}
    let set: (KeyVoicing) -> Void

    @State private var swipe: VoicingSwipe?
    /// The voicing when the finger came down, which the span is laid out
    /// around for as long as the finger is on it.
    @State private var pressed: KeyVoicing?
    /// False once the finger is gone, whether it lifted or was taken away.
    @GestureState private var isDown = false
    private let haptic = UIImpactFeedbackGenerator(style: .rigid)

    private var text: String { "\(voicing.octave) · \(voicing.inversion.label)" }

    var body: some View {
        VStack(spacing: 0) {
            Text(name)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(white: 0.5))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(text)
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundStyle(isActive ? Color.orange : Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(white: 0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isActive ? Color.orange : Color(white: 0.25), lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($isDown) { _, isDown, _ in isDown = true }
                .onChanged { drag in
                    if swipe == nil {
                        haptic.prepare()
                        pressed = voicing
                    }
                    var swipe = swipe ?? VoicingSwipe(from: voicing)
                    swipe.moved(to: drag.translation)
                    self.swipe = swipe
                    change(to: swipe.voicing)
                }
        )
        .onChange(of: isDown) {
            guard !isDown else { return }
            (swipe, pressed) = (nil, nil)
            onEnd()
        }
        .anchorPreference(key: VoicingPadKey.self, value: .bounds) { bounds in
            pressed.map { VoicingPadPlace(pressed: $0, voicing: voicing, field: bounds) }
        }
        .animation(.snappy(duration: 0.18), value: voicing)
        .accessibilityElement()
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

    /// A finger is on the field.
    private var isActive: Bool { pressed != nil }

    private func change(to new: KeyVoicing) {
        guard new != voicing else { return }
        set(new)
        haptic.impactOccurred()
    }

    /// A change made in one step, with no finger on the field.
    private func step(octave: Int = 0, inversion: Int = 0) {
        let new = KeyVoicing(
            octave: (voicing.octave + octave).clamped(to: VoicingSpan.octaves),
            inversion: Inversion(steps: (voicing.inversion.steps + inversion).clamped(to: VoicingSpan.inversions)))
        change(to: new)
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
            keepSwitch
        }
    }

    private var keepSwitch: some View {
        let keeps = state.keepsVoicing
        return Button { state.keepsVoicing.toggle() } label: {
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
        .accessibilityLabel("Keep the voicing")
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
