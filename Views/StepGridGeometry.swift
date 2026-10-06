import CoreGraphics

/// Where the sequencer's step cells sit in a column of bars: one row per beat,
/// the bars stacked top to bottom, each under an optional header. The grid
/// draws from it and its gestures read touches back through it, so the two
/// cannot disagree.
struct StepGridGeometry: Equatable {
    static let columns = MusicalTime.stepsPerBeat
    static let rowsPerBar = MusicalTime.beatsPerBar
    /// Gutter between neighbouring cells, across and down.
    static let spacing: CGFloat = 6

    /// Width of the whole column.
    var width: CGFloat
    var cellHeight: CGFloat
    /// Height of the header above each bar's cells; 0 when bars have none.
    var headerHeight: CGFloat = 0
    /// Gap between one bar's last row and the next bar's header.
    var barGap: CGFloat = 0

    var cellWidth: CGFloat {
        (width - CGFloat(Self.columns - 1) * Self.spacing) / CGFloat(Self.columns)
    }

    /// Height of one bar: its header and its rows of cells.
    var barHeight: CGFloat {
        headerHeight + CGFloat(Self.rowsPerBar) * cellHeight
            + CGFloat(Self.rowsPerBar - 1) * Self.spacing
    }

    /// The step nearest `point`, as an index into `bars` bars counted from the
    /// top of the column. Points in a gutter, a header or outside the column
    /// resolve to the closest cell, so a sweep never drops out mid-drag.
    func step(nearest point: CGPoint, bars: Int) -> Int {
        let barPitch = barHeight + barGap
        let bar = Self.index(point.y, pitch: barPitch, count: bars)
        let yInBar = point.y - CGFloat(bar) * barPitch - headerHeight
        let row = Self.index(yInBar, pitch: cellHeight + Self.spacing, count: Self.rowsPerBar)
        let column = Self.index(point.x, pitch: cellWidth + Self.spacing, count: Self.columns)
        return (bar * Self.rowsPerBar + row) * Self.columns + column
    }

    /// The step whose row of cells holds `point`, or nil in a header, in the
    /// gap between bars or outside the bars. For taps, which must not act
    /// through the controls that sit there.
    func step(at point: CGPoint, bars: Int) -> Int? {
        let barPitch = barHeight + barGap
        guard (0...width).contains(point.x), point.y >= 0 else { return nil }
        let yInBar = point.y.truncatingRemainder(dividingBy: barPitch)
        guard point.y < CGFloat(bars) * barPitch,
              (headerHeight...barHeight).contains(yInBar) else { return nil }
        return step(nearest: point, bars: bars)
    }

    /// Which of `count` slots, `pitch` apart, holds `offset`; clamped to the
    /// first and last.
    private static func index(_ offset: CGFloat, pitch: CGFloat, count: Int) -> Int {
        guard pitch > 0, offset > 0 else { return 0 }
        return min(count - 1, Int(offset / pitch))
    }
}
