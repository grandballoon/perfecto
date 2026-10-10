import SwiftUI

/// The Setup page's section for the computer keyboard: what each key plays,
/// changed a key at a time.
struct KeyboardMapEditor: View {
    @Environment(PerformanceState.self) private var state

    private static let directions: [(JoystickDirection, String)] = [
        (.upLeft, "↖"), (.up, "↑"), (.upRight, "↗"), (.left, "←"),
        (.right, "→"), (.downLeft, "↙"), (.down, "↓"), (.downRight, "↘"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SidePanelSectionLabel("KEYBOARD")
            group("Chords", Degree.allCases.map { (.chord($0), String($0.rawValue)) })
            group("Chord color", Self.directions.map { (.color($0.0), $0.1) })
            group("Solo strip", (0..<KeyboardMap.soloCells).map { (.solo(cell: $0), String($0 + 1)) })
            group("Tonnetz", TonnetzMove.allCases.map { (.tonnetz($0), $0.displayName) }, columns: 2)
            group("Buttons", KeyboardButton.allCases.map { (.button($0), $0.displayName) }, columns: 2)
            Text("What each key of the computer keyboard plays or taps. Choose one and press the key for it: Delete leaves it with no key, and Escape leaves it as it was. Color keys held together add up, so two arrows make a diagonal. The Tonnetz's moves are made, and its Net, Triad and Hold buttons tapped, while it is on screen.")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color(white: 0.3))
                .fixedSize(horizontal: false, vertical: true)
            SidePanelChip(label: "Reset keys", selected: false) { state.keyboard.reset() }
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
        let keyboard = state.keyboard
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
