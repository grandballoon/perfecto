import SwiftUI

/// The edit offered by the sequencer's selection, in a small chit beside it:
/// Join where the selected steps could be one held note, Split where they
/// are one already. It is the step editor's Join and Split button, put where
/// the selection is; `SequencerStepGrid` says which it is
/// (`SequencerState.joinEdit`) and places the tip
/// (`StepGridGeometry.frame(ofTip:by:)`).
///
/// Its size is fixed, so it can be placed, and its touches kept from the
/// steps under it, before it is drawn.
struct StepSelectionTip: View {
    let edit: JoinEdit
    let onTap: () -> Void

    static let size = CGSize(width: 58, height: 32)
    private static let corner: CGFloat = 7

    var body: some View {
        Button(action: onTap) {
            Text(edit.label)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(red: 1, green: 0.65, blue: 0))
                .lineLimit(1)
                .frame(width: Self.size.width, height: Self.size.height)
                .background(
                    RoundedRectangle(cornerRadius: Self.corner)
                        .fill(Color(white: 0.16))
                        .overlay(RoundedRectangle(cornerRadius: Self.corner).stroke(Color(white: 0.4), lineWidth: 1))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(edit.accessibilityLabel)
        .shadow(color: .black.opacity(0.6), radius: 4, y: 1)
    }
}
