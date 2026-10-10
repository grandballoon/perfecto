import CoreGraphics

/// Where the net's notes and triangles are, for a net drawn in `size` with
/// the triangle `center` in the middle and every side `edge` long. The one
/// place that says so: both Tonnetz views draw from it and read their
/// touches against it, so the two cannot disagree.
///
/// Fifths run to the right, and major thirds up and to the right, so minor
/// thirds run down and to the right: a triangle that points up is a major
/// triad and one that points down a minor one.
struct TonnetzNet: Equatable {
    let size: CGSize
    let center: TonnetzCell
    let edge: CGFloat

    /// How far apart the rows of notes are.
    var rowHeight: CGFloat { edge * CGFloat(3).squareRoot() / 2 }

    /// The net that shows `cell` and the three triangles it can be flipped
    /// into, as large as `size` has room for whichever way `cell` points.
    static func around(_ cell: TonnetzCell, in size: CGSize) -> TonnetzNet {
        // The four make one triangle with sides twice as long. Its middle
        // is `cell`'s, a third of the way down it or up it.
        let widest = size.width / 2
        let tallest = size.height * 0.75 / CGFloat(3).squareRoot()
        return TonnetzNet(size: size, center: cell, edge: max(0, min(widest, tallest)) * roomForNotes)
    }

    /// The share of the room the triangles take, the rest being left for
    /// the notes drawn on their outer corners.
    private static let roomForNotes: CGFloat = 0.84

    // MARK: – Places

    func place(of point: TonnetzPoint) -> CGPoint {
        let offset = offset(of: point)
        return CGPoint(x: origin.x + offset.x, y: origin.y + offset.y)
    }

    /// The corners of `cell`: its root, third and fifth.
    func corners(of cell: TonnetzCell) -> [CGPoint] {
        cell.points.map(place(of:))
    }

    /// The middle of `cell`, where its name is drawn.
    func middle(of cell: TonnetzCell) -> CGPoint {
        let offset = middleOffset(of: cell)
        return CGPoint(x: origin.x + offset.x, y: origin.y + offset.y)
    }

    /// The rectangle around `cell`.
    func frame(of cell: TonnetzCell) -> CGRect {
        let corners = corners(of: cell)
        let xs = corners.map(\.x), ys = corners.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }

    /// The triangle `point` is in. The net has no end, so every point is in one.
    func cell(at point: CGPoint) -> TonnetzCell {
        guard edge > 0 else { return center }
        let thirds = (origin.y - point.y) / rowHeight
        let fifths = (point.x - origin.x) / edge - thirds / 2
        let corner = TonnetzPoint(fifths: Int(fifths.rounded(.down)), thirds: Int(thirds.rounded(.down)))
        // Of the two triangles at a corner, the one that points up is the
        // half nearer the corner.
        let along = fifths - fifths.rounded(.down) + thirds - thirds.rounded(.down)
        return TonnetzCell(corner: corner, pointsUp: along < 1)
    }

    /// What a pointer at `point` is on: a note, inside its disc
    /// (`noteDiameter` across), and the triangle around it otherwise.
    func target(at point: CGPoint, noteDiameter: CGFloat) -> TonnetzTarget {
        let cell = cell(at: point)
        // The note nearest a point is a corner of the triangle it is in.
        let onNote = cell.points.first { corner in
            let place = place(of: corner)
            return hypot(place.x - point.x, place.y - point.y) <= noteDiameter / 2
        }
        return onNote.map { .note($0.pitchClass) } ?? .cell(cell)
    }

    // MARK: – What is in view

    /// Every triangle any part of which is within `size`, and a few just
    /// outside it.
    var cells: [TonnetzCell] {
        guard edge > 0, size.width > 0, size.height > 0 else { return [] }
        let origin = origin
        let lowest = Int(((origin.y - size.height) / rowHeight).rounded(.down))
        let highest = Int((origin.y / rowHeight).rounded(.down))
        return (lowest...highest).flatMap { thirds -> [TonnetzCell] in
            // The row's triangles lean right as they rise, so its first is
            // found from its upper edge and its last from its lower.
            let first = Int((-origin.x / edge - CGFloat(thirds + 1) / 2).rounded(.down))
            let last = Int(((size.width - origin.x) / edge - CGFloat(thirds) / 2).rounded(.down))
            return (first...last).flatMap { fifths in
                [true, false].map {
                    TonnetzCell(corner: TonnetzPoint(fifths: fifths, thirds: thirds), pointsUp: $0)
                }
            }
        }
    }

    /// Every note that is a corner of a triangle in view.
    var points: [TonnetzPoint] {
        Array(Set(cells.flatMap(\.points)))
    }

    // MARK: – Private

    /// A note's place measured from the origin's.
    private func offset(of point: TonnetzPoint) -> CGPoint {
        CGPoint(x: (CGFloat(point.fifths) + CGFloat(point.thirds) / 2) * edge,
                y: -CGFloat(point.thirds) * rowHeight)
    }

    private func middleOffset(of cell: TonnetzCell) -> CGPoint {
        let offsets = cell.points.map(offset(of:))
        return CGPoint(x: offsets.map(\.x).reduce(0, +) / 3, y: offsets.map(\.y).reduce(0, +) / 3)
    }

    /// Where the note at the net's origin is drawn, which puts `center`'s
    /// middle in the middle of `size`.
    private var origin: CGPoint {
        let middle = middleOffset(of: center)
        return CGPoint(x: size.width / 2 - middle.x, y: size.height / 2 - middle.y)
    }
}
