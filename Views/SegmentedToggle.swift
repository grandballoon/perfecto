import SwiftUI

/// A row of choices, one of which is on: the chit the screens switch
/// between two or three things with. `hotkey` is the button a choice is to
/// the computer keyboard, whose key a pointer over it is shown.
struct SegmentedToggle<Choice: Hashable>: View {
    let choices: [Choice]
    let label: (Choice) -> String
    let hotkey: (Choice) -> KeyboardButton?
    @Binding var selection: Choice

    var body: some View {
        HStack(spacing: 3) {
            ForEach(choices, id: \.self) { choice in
                let active = choice == selection
                Button { selection = choice } label: {
                    Text(label(choice))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(active ? Color.black : Color(white: 0.7))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(active ? Color.orange : Color.clear))
                        // A choice that is off is drawn clear, and what is
                        // clear takes no press: the whole of it is the button.
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hotkeyTip(hotkey(choice))
            }
        }
        .padding(3)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(white: 0.09))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(white: 0.25), lineWidth: 1))
        )
    }
}
