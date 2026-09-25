import SwiftUI

/// The chord grid, shared by Play mode (`ColorSurfaceView`) and the Sequencer
/// step editor, as `ChordColorBar` is for the joystick.
///
/// Columns stack thirds higher from left to right (triad → 13th); rows are
/// modes from brightest at the top to darkest, centred on `degree`'s own
/// mode, which is shaded. Each cell shows the chord it plays on `degree`.
/// Callers decide what "selected" means and what a change does; the only
/// state kept here is the cell under the finger, so `onChange` fires once per
/// cell crossed (same contract as `ChordColorBar`).
struct ChordGridPad: View {

    let key: Key
    /// The degree the labels and rows are drawn for.
    let degree: Degree
    /// The highlighted cell.
    let selected: GridPosition?
    /// Called as the drag crosses into a new cell.
    let onChange: (GridPosition) -> Void
    /// Called when the drag ends. Play mode lifts back to the triad; the
    /// sequencer keeps the chosen cell, so it passes `nil`.
    var onEnd: (() -> Void)? = nil

    @State private var lastPosition: GridPosition? = nil
    private let haptic = UIImpactFeedbackGenerator(style: .rigid)

    private let heights = StackHeight.allCases
    private let lineWidth: CGFloat = 1

    var body: some View {
        let rows = ChordGrid.rows(key: key, degree: degree)
        let own = ChordGrid.ownMode(key: key, degree: degree)
        GeometryReader { geo in
            VStack(spacing: lineWidth) {
                ForEach(rows.indices, id: \.self) { row in
                    HStack(spacing: lineWidth) {
                        ForEach(heights, id: \.self) { height in
                            cell(mode: rows[row], height: height,
                                 isOwn: rows[row] == own,
                                 active: selected == GridPosition(height: height, row: row))
                        }
                    }
                }
            }
            .background(Color(white: 0.2))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        let position = position(at: value.location, in: geo.size, rowCount: rows.count)
                        guard position != lastPosition else { return }
                        lastPosition = position
                        haptic.impactOccurred()
                        onChange(position)
                    }
                    .onEnded { _ in
                        lastPosition = nil
                        onEnd?()
                    }
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(white: 0.25), lineWidth: 1))
    }

    private func cell(mode: HeptatonicMode, height: StackHeight, isOwn: Bool, active: Bool) -> some View {
        ZStack {
            active ? Color.orange.opacity(0.85) : Color(white: isOwn ? 0.15 : 0.08)
            VStack(spacing: 0) {
                Text(tertianChordName(mode, height: height))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(active ? .black.opacity(0.8) : Color(white: isOwn ? 0.75 : 0.5))
                // The triad column names the row's mode.
                if height == .triad {
                    Text(mode.displayName)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(active ? .black.opacity(0.6) : Color(white: 0.4))
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(.horizontal, 3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func position(at point: CGPoint, in size: CGSize, rowCount: Int) -> GridPosition {
        let column = Int(point.x / size.width * CGFloat(heights.count))
        let row = Int(point.y / size.height * CGFloat(rowCount))
        return GridPosition(height: heights[max(0, min(heights.count - 1, column))],
                            row: max(0, min(rowCount - 1, row)))
    }
}
