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
        SegmentRow(spacing: 3) {
            ForEach(choices, id: \.self) { choice in
                let active = choice == selection
                Button { selection = choice } label: {
                    Text(label(choice))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(active ? Color.black : Color(white: 0.7))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 2)
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

/// The choices side by side, filling the row: all as wide as one another
/// while each label has room in that, and otherwise each as wide as its
/// label wants, all made narrower alike, so a long label is not squeezed
/// more than a short one beside it.
private struct SegmentRow: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let widths = widths(in: proposal.width, of: subviews)
        let height = zip(subviews, widths)
            .map { $0.sizeThatFits(ProposedViewSize(width: $1, height: proposal.height)).height }
            .max() ?? 0
        return CGSize(width: widths.reduce(0, +) + gaps(subviews), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (subview, width) in zip(subviews, widths(in: bounds.width, of: subviews)) {
            subview.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading,
                          proposal: ProposedViewSize(width: width, height: bounds.height))
            x += width + spacing
        }
    }

    private func gaps(_ subviews: Subviews) -> CGFloat {
        spacing * CGFloat(max(subviews.count - 1, 0))
    }

    private func widths(in width: CGFloat?, of subviews: Subviews) -> [CGFloat] {
        let wanted = subviews.map { $0.sizeThatFits(.unspecified).width }
        let widest = wanted.max() ?? 0
        guard let width else { return wanted.map { _ in widest } }
        let room = max(width - gaps(subviews), 0)
        let total = wanted.reduce(0, +)
        if widest * CGFloat(wanted.count) <= room || total == 0 {
            return wanted.map { _ in room / CGFloat(wanted.count) }
        }
        return wanted.map { $0 * room / total }
    }
}
