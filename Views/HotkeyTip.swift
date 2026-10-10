import SwiftUI

/// The key that taps a button, shown in a small chit by the button while a
/// pointer is over it. It is drawn by the screen, over everything, so no
/// neighbour or clipped edge hides it; a finger never hovers, so a phone
/// never shows one.
struct HotkeyTip {
    /// The key's name, as the keyboard's map has it.
    let key: String
    /// Where the button is.
    let bounds: Anchor<CGRect>
}

private struct HotkeyTipKey: PreferenceKey {
    static let defaultValue: HotkeyTip? = nil

    static func reduce(value: inout HotkeyTip?, nextValue: () -> HotkeyTip?) {
        value = value ?? nextValue()
    }
}

extension View {
    /// Shows the key that taps `button` while a pointer is over this view.
    /// Nothing is shown for no button, or for one with no key.
    func hotkeyTip(_ button: KeyboardButton?) -> some View {
        modifier(HotkeyTipSource(button: button))
    }

    /// Draws the tip of whichever view inside this one is hovered over
    /// (`hotkeyTip`). It goes on the screen as a whole.
    func showingHotkeyTips() -> some View {
        overlayPreferenceValue(HotkeyTipKey.self) { tip in
            GeometryReader { geo in
                if let tip {
                    let button = geo[tip.bounds]
                    // Under the button, or over it at the foot of the screen.
                    let below = button.maxY + HotkeyTipChit.reach
                    let fits = below + HotkeyTipChit.reach <= geo.size.height
                    HotkeyTipChit(key: tip.key)
                        .position(x: button.midX, y: fits ? below : button.minY - HotkeyTipChit.reach)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.12), value: tip?.key)
            .allowsHitTesting(false)
        }
    }
}

private struct HotkeyTipSource: ViewModifier {
    let button: KeyboardButton?
    @Environment(PerformanceState.self) private var state
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .onHover { isHovered = $0 }
            .anchorPreference(key: HotkeyTipKey.self, value: .bounds) { bounds in
                guard isHovered, let button, let key = state.keyboard.keyName(for: button) else { return nil }
                return HotkeyTip(key: key, bounds: bounds)
            }
    }
}

private struct HotkeyTipChit: View {
    let key: String

    /// How far from a button's edge the middle of its tip is.
    static let reach: CGFloat = 16

    var body: some View {
        Text(key)
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color(red: 1, green: 0.65, blue: 0))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(white: 0.16))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(white: 0.4), lineWidth: 1))
            )
            .shadow(color: .black.opacity(0.6), radius: 4, y: 1)
    }
}
