import SwiftUI

/// The color table: chord qualities in rows that never change, whatever
/// chord is held, so a quality is always found in the same place. A row is
/// a family (triads; sixths and adds; sevenths; ninths, altered and 11ths),
/// commonest first. A quality is played on whatever chord is held, in key
/// or not: maj7 on V is G maj7.
///
/// The last column has the table's controls: the plain chord at the top,
/// and the pin at the bottom.
enum ColorTable {
    /// The qualities, row by row, each as its tones above the root.
    static let rows: [[ChordTones]] = [triads, sixthsAndAdds, sevenths, ninths].map { $0.map { ChordTones($0) } }
    private static let triads: [[Int]] = [[0, 4, 7], [0, 3, 7], [0, 2, 7], [0, 5, 7], [0, 3, 6], [0, 4, 8], [0, 7]]
    private static let sixthsAndAdds: [[Int]] = [[0, 4, 7, 9], [0, 3, 7, 9], [0, 2, 4, 7], [0, 2, 3, 7],
                                                 [0, 2, 4, 7, 9], [0, 2, 3, 7, 9]]
    private static let sevenths: [[Int]] = [[0, 4, 7, 11], [0, 4, 7, 10], [0, 3, 7, 10], [0, 3, 6, 10],
                                            [0, 3, 6, 9], [0, 3, 7, 11], [0, 5, 7, 10]]
    private static let ninths: [[Int]] = [[0, 2, 4, 7, 11], [0, 2, 4, 7, 10], [0, 2, 3, 7, 10], [0, 1, 4, 7, 10],
                                          [0, 3, 4, 7, 10], [0, 4, 5, 7], [0, 3, 5, 7]]

    /// The columns: as many as the longest row, and the controls'.
    static let columns = rows.map { $0.count }.max()! + 1
    /// The gap between neighbouring cells.
    static let spacing: CGFloat = 4

    /// What a finger can be on.
    enum Target: Hashable {
        case quality(ChordTones)
        /// The plain chord: whatever the table was playing or keeping is let go.
        case plain
    }

    /// Where the controls are: the plain chord, and the pin.
    static let plainCell = (column: columns - 1, row: 0)
    static let pinCell = (column: columns - 1, row: rows.count - 1)

    /// The frame of the cell at `column` and `row` in a table of `size`.
    static func frame(column: Int, row: Int, in size: CGSize) -> CGRect {
        let (n, m) = (CGFloat(columns), CGFloat(rows.count))
        let width = (size.width - spacing * (n - 1)) / n
        let height = (size.height - spacing * (m - 1)) / m
        return CGRect(x: CGFloat(column) * (width + spacing), y: CGFloat(row) * (height + spacing),
                      width: width, height: height)
    }

    /// The column and row of `target`.
    static func cell(of target: Target) -> (column: Int, row: Int)? {
        switch target {
        case .plain: return plainCell
        case .quality(let tones):
            for (row, qualities) in rows.enumerated() {
                if let column = qualities.firstIndex(of: tones) { return (column, row) }
            }
            return nil
        }
    }

    /// What is under `point` in a table of `size`: nil in a gap, an empty
    /// cell, the pin or outside it, so a finger sliding across one stays on
    /// what it was on.
    static func target(at point: CGPoint, in size: CGSize) -> Target? {
        let targets = [Target.plain] + rows.joined().map { .quality($0) }
        return targets.first { target in
            guard let cell = cell(of: target) else { return false }
            return frame(column: cell.column, row: cell.row, in: size).contains(point)
        }
    }

    /// Whether every tone of `quality` on `degree` is in `key`.
    static func isInKey(_ quality: ChordTones, key: Key, degree: Degree) -> Bool {
        let root = key.scale.offset(of: degree)
        return quality.pitchClasses.allSatisfy { key.scale.intervals.contains((root + $0) % 12) }
    }
}

/// The color table, wired to the live performance: a quality played while
/// a finger is on it, or kept by the pin until another is chosen or the
/// plain chord. A finger slides from cell to cell as on the compass. With a
/// chord held (and the compass's names on) each cell is named by the chord
/// it plays, marked if it is out of key; otherwise by its quality.
struct ColorTableSurface: View {
    @Environment(PerformanceState.self) private var state

    /// What the finger on the table is on, while one is.
    @State private var touched: ColorTable.Target?
    /// False once the finger is gone, whether it lifted or was taken away.
    @GestureState private var isDown = false

    var body: some View {
        let degree = state.compassShowsChords ? state.activeDegree : nil
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    ForEach(Array(ColorTable.rows.enumerated()), id: \.offset) { row, qualities in
                        ForEach(Array(qualities.enumerated()), id: \.offset) { column, quality in
                            let frame = ColorTable.frame(column: column, row: row, in: geo.size)
                            qualityChip(quality, degree: degree)
                                .frame(width: frame.width, height: frame.height)
                                .offset(x: frame.minX, y: frame.minY)
                        }
                    }
                    let plain = ColorTable.frame(column: ColorTable.plainCell.column,
                                                 row: ColorTable.plainCell.row, in: geo.size)
                    plainChip(degree: degree)
                        .frame(width: plain.width, height: plain.height)
                        .offset(x: plain.minX, y: plain.minY)
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .updating($isDown) { _, isDown, _ in isDown = true }
                        .onChanged { drag in
                            guard let target = ColorTable.target(at: drag.location, in: geo.size),
                                  target != touched else { return }
                            touched = target
                            switch target {
                            case .quality(let quality): state.tablePressed(quality)
                            case .plain:                state.compassCleared()
                            }
                        }
                )
                .onChange(of: isDown) {
                    guard !isDown else { return }
                    if case .quality(let quality) = touched { state.tableLifted(quality) }
                    touched = nil
                }
                let pin = ColorTable.frame(column: ColorTable.pinCell.column,
                                           row: ColorTable.pinCell.row, in: geo.size)
                let keeps = state.keepsCompassColor
                CornerChip(text: keeps ? "kept" : "played", detail: "PIN", isOn: keeps, isEnabled: true) {
                    state.keepsCompassColor.toggle()
                }
                .accessibilityLabel("Keep the table's color")
                .accessibilityValue(keeps ? "On" : "Off")
                .frame(width: pin.width, height: pin.height)
                .offset(x: pin.minX, y: pin.minY)
            }
        }
    }

    private func qualityChip(_ quality: ChordTones, degree: Degree?) -> some View {
        let isOn = state.tableTones == quality
        let text: String, detail: String, isBorrowed: Bool
        if let degree {
            isBorrowed = !ColorTable.isInKey(quality, key: state.playedKey, degree: degree)
            text = chordLabel(key: state.playedKey, spec: ChordSpec(degree: degree, color: .tones(quality)))
                + (isBorrowed ? "*" : "")
            detail = isBorrowed ? "OUT OF KEY" : quality.name.uppercased()
        } else {
            isBorrowed = false
            text = quality.name
            detail = ""
        }
        return CompassChip(text: text, detail: detail, isOn: isOn, isEnabled: true, isBorrowed: isBorrowed,
                           onTap: { state.tablePressed(quality); state.tableLifted(quality) })
            .accessibilityLabel(quality.name)
            .accessibilityValue(degree == nil ? "" : text)
    }

    private func plainChip(degree: Degree?) -> some View {
        let plain = degree.map { chordLabel(key: state.playedKey, spec: ChordSpec(degree: $0, color: .base)) }
        let keeps = state.keepsCompassColor
        return CompassChip(text: keeps ? "clear" : plain ?? "plain", detail: keeps ? "BACK TO PLAIN" : "AS IT IS",
                           isOn: false, isEnabled: true, isBorrowed: false, isMiddle: true,
                           onTap: { state.compassCleared() })
            .accessibilityLabel(keeps ? "Back to the plain chord" : "The plain chord")
    }
}
