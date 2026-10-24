import SwiftUI

/// The Setup page's section for a set of keys that play by a map (the
/// computer keyboard's, or a game controller's buttons): what each key
/// plays, changed a key at a time.
struct KeyboardMapEditor: View {
    let title: String
    let keyboard: KeyboardState
    let detail: String
    let resetLabel: String

    /// The compass's places, each kind's first choice beside its second.
    private static let places: [(CompassPlace, String)] = [
        (.init(.add, 1), "↑ Add"), (.init(.add, 2), "↑↑ Add"),
        (.init(.raise, 1), "→ Raise"), (.init(.raise, 2), "→→ Raise"),
        (.init(.lower, 1), "← Lower"), (.init(.lower, 2), "←← Lower"),
        (.init(.takeAway, 1), "↓ Take"), (.init(.takeAway, 2), "↓↓ Take"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SidePanelSectionLabel(title)
            group("Chords", Degree.allCases.map { (.chord($0), String($0.rawValue)) })
            group("Compass", Self.places.map { (.compass($0.0), $0.1) }, columns: 2)
            group("Tonnetz", TonnetzMove.allCases.map { (.tonnetz($0), $0.displayName) }, columns: 2)
            group("Buttons", KeyboardButton.allCases.map { (.button($0), $0.displayName) }, columns: 2)
            Text(detail)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color(white: 0.3))
                .fixedSize(horizontal: false, vertical: true)
            SidePanelChip(label: resetLabel, selected: false) { keyboard.reset() }
        }
    }

    private func group(_ title: String, _ actions: [(KeyboardAction, String)], columns: Int = 3) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color(white: 0.45))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 8) {
                ForEach(actions, id: \.0) { action, label in
                    key(action, label: label)
                }
            }
        }
    }

    private func key(_ action: KeyboardAction, label: String) -> some View {
        let choosing = keyboard.choosing == action
        return Button {
            keyboard.choosing = choosing ? nil : action
        } label: {
            HStack(spacing: 4) {
                Text(label)
                    .foregroundStyle(choosing ? Color.black.opacity(0.65) : Color(white: 0.45))
                Spacer(minLength: 0)
                Text(choosing ? "…" : keyboard.map.key(for: action)?.name ?? "—")
                    .fontWeight(.semibold)
                    .foregroundStyle(choosing ? .black : .white)
            }
            .font(.system(size: 14, design: .monospaced))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(choosing ? Color.orange : Color(white: 0.15))
            )
        }
        .buttonStyle(.plain)
    }
}

extension KeyboardMapEditor {
    /// The computer keyboard's keys.
    init(keyboard: KeyboardState) {
        self.init(title: "KEYBOARD", keyboard: keyboard,
                  detail: "What each key of the computer keyboard plays or taps. Choose one and press the key for it: Delete leaves it with no key, and Escape leaves it as it was. A compass key plays its place while it is held, as a finger on it does. The Tonnetz's moves are made, and its Net, Triad and Hold buttons tapped, while it is on screen.",
                  resetLabel: "Reset keys")
    }

    /// A game controller's buttons.
    init(gamepad: GamepadState, named name: String) {
        self.init(title: "CONTROLLER", keyboard: gamepad.buttons,
                  detail: "What each button of \(name) plays or taps. Choose one and press the button for it, or choose it again to leave it as it was. A button given to something else leaves what it had. The left stick plays the compass's first choices, whatever the buttons are.",
                  resetLabel: "Reset buttons")
    }
}
