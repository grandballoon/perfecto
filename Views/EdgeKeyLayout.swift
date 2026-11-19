import CoreGraphics

/// Where the edge layout puts the seven chord keys, and the space they leave
/// in the middle for a surface that colors the chord (`CenterSurface`).
///
/// The keys are two columns at the sides of the area. The root's column has
/// I to IV from the bottom up, so the root is in a bottom corner, and the
/// other has V to vii° from the top down: the degrees go round from the
/// root, clockwise for the right hand. For the left hand everything is
/// mirrored, so the root is in the other bottom corner. Each column's keys
/// share its height, so the column of three has taller keys than the
/// column of four.
///
/// It is a value worked out from the area's size alone, so the keys
/// (`ChordKeysView`) and the middle (`PerformanceView`) are laid out by the
/// same frames.
struct EdgeKeyLayout: Equatable {
    /// Each degree's key.
    var keys: [Degree: CGRect]
    /// What is left between the columns.
    var center: CGRect

    /// The root's column, from the bottom up.
    static let rootColumn: [Degree] = [.I, .ii, .iii, .IV]
    /// The other column, from the top down.
    static let otherColumn: [Degree] = [.V, .vi, .viiDim]
    /// A column's width as a share of the area's, within `columnWidths`.
    static let columnShare: CGFloat = 0.15
    static let columnWidths: ClosedRange<CGFloat> = 88...150
    /// The space between two keys of a column.
    static let keyGap: CGFloat = 10
    /// The space between a column and the middle.
    static let centerGap: CGFloat = 12

    init(size: CGSize, handedness: Handedness) {
        let width = max(size.width, 0), height = max(size.height, 0)
        // Never so wide that the middle is narrower than a column.
        let column = min((width * Self.columnShare).clamped(to: Self.columnWidths), width / 3)
        let rootX = handedness == .right ? 0 : width - column
        let otherX = handedness == .right ? width - column : 0

        func keyHeight(_ count: Int) -> CGFloat {
            max((height - Self.keyGap * CGFloat(count - 1)) / CGFloat(count), 0)
        }
        var keys: [Degree: CGRect] = [:]
        let rootHeight = keyHeight(Self.rootColumn.count)
        for (place, degree) in Self.rootColumn.enumerated() {
            let y = height - CGFloat(place + 1) * rootHeight - CGFloat(place) * Self.keyGap
            keys[degree] = CGRect(x: rootX, y: y, width: column, height: rootHeight)
        }
        let otherHeight = keyHeight(Self.otherColumn.count)
        for (place, degree) in Self.otherColumn.enumerated() {
            let y = CGFloat(place) * (otherHeight + Self.keyGap)
            keys[degree] = CGRect(x: otherX, y: y, width: column, height: otherHeight)
        }
        self.keys = keys
        let side = column + Self.centerGap
        center = CGRect(x: side, y: 0, width: max(width - 2 * side, 0), height: height)
    }
}
