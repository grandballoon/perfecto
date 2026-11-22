import CoreGraphics

/// Where the circle layout puts its two halves on a phone on its side.
///
/// The compass is in the bottom leading corner, with the proportions it
/// would have filling its half but a third less area, so it is under the
/// hand that plays it and clear of the menu button. The trailing column has
/// the note display, the strips and the ring of chord keys, and the ring
/// sits in the column's bottom trailing corner.
///
/// It is a value worked out from the size alone.
struct RingLandscapeLayout: Equatable {
    /// The step compass.
    var compass: CGRect
    /// The display, the strips and the chord keys.
    var column: CGRect

    /// The space between the halves and along the top of the column.
    static let margin: CGFloat = 16
    /// The space between each half and the screen's edges it is against.
    static let edgeMargin: CGFloat = 8
    /// The compass's area, as a share of the area its half offers it.
    static let compassArea: CGFloat = 2.0 / 3.0

    init(size: CGSize) {
        let half = size.width / 2
        let scale = Self.compassArea.squareRoot()
        let width = max(half - 2 * Self.margin, 0) * scale
        let height = max(size.height - 2 * Self.margin, 0) * scale
        compass = CGRect(x: Self.edgeMargin, y: size.height - Self.edgeMargin - height,
                         width: width, height: height)
        column = CGRect(x: half + Self.margin, y: Self.margin,
                        width: max(half - Self.margin - Self.edgeMargin, 0),
                        height: max(size.height - Self.margin - Self.edgeMargin, 0))
    }
}
