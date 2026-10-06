/// How the steps of a timeline are arranged in the sequencer's grid: rows of
/// one felt beat, bar after bar. A bar whose steps do not fill its rows has a
/// short last row (7/8 is rows of 4, 4, 4 and 2), so a step's row and column
/// are worked out here and nowhere else.
struct StepGridShape: Equatable {
    var stepsPerBar: Int
    /// Steps in a full row.
    var columns: Int

    init(_ signature: TimeSignature = .common) {
        stepsPerBar = signature.stepsPerBar
        columns = signature.stepsPerRow
    }

    var rowsPerBar: Int { (stepsPerBar + columns - 1) / columns }

    /// Steps in row `row` of a bar: `columns`, or fewer in a short last row.
    func columns(inRow row: Int) -> Int {
        min(columns, stepsPerBar - row * columns)
    }

    /// The row a step is in, counted through every bar, and its column.
    func cell(of step: Int) -> (row: Int, column: Int) {
        let inBar = step % stepsPerBar
        return (step / stepsPerBar * rowsPerBar + inBar / columns, inBar % columns)
    }

    /// The step at a row (counted through every bar) and column. A column
    /// past the end of a short row gives the row's last step.
    func step(row: Int, column: Int) -> Int {
        let (bar, rowInBar) = (row / rowsPerBar, row % rowsPerBar)
        return bar * stepsPerBar + rowInBar * columns + min(column, columns(inRow: rowInBar) - 1)
    }

    /// The steps of `bar`.
    func steps(ofBar bar: Int) -> Range<Int> {
        bar * stepsPerBar ..< (bar + 1) * stepsPerBar
    }

    /// The steps inside the rectangle spanned by two cells of the grid. A
    /// straight drag gives a run along a row or down a column; a diagonal
    /// one gives the block between its corners. Rows run on through the
    /// bars, so a sweep crosses bar lines.
    func rectangle(from a: Int, to b: Int) -> Set<Int> {
        let (first, second) = (cell(of: a), cell(of: b))
        var steps = Set<Int>()
        for row in min(first.row, second.row)...max(first.row, second.row) {
            for column in min(first.column, second.column)...max(first.column, second.column)
            where column < columns(inRow: row % rowsPerBar) {
                steps.insert(step(row: row, column: column))
            }
        }
        return steps
    }

    /// `steps` cut where rows end, each piece within one row.
    func rows(of steps: Range<Int>) -> [Range<Int>] {
        var pieces: [Range<Int>] = []
        var start = steps.lowerBound
        while start < steps.upperBound {
            let (row, column) = cell(of: start)
            let end = min(start + columns(inRow: row % rowsPerBar) - column, steps.upperBound)
            pieces.append(start..<end)
            start = end
        }
        return pieces
    }
}

/// One piece of a note as the grid draws it: the steps of one row it is on.
/// A note held across a row's end is several, the first its head.
struct NoteChit: Identifiable, Equatable {
    /// Its first step: no two pieces drawn share one.
    var id: Int { steps.lowerBound }
    var steps: Range<Int>
    var note: TimelineNote
    /// Whether the note starts in this piece, and whether it ends in it.
    var isHead: Bool
    var isTail: Bool

    /// Whether the note was played off the grid's lines, so that Snap would move it.
    var isOffGrid: Bool { !TimelineTime.isOnGrid(note.start) }
}

extension Layer {
    /// The layer as the grid draws it, over `stepCount` steps. A note
    /// played just before the end, nearest a line that is not there, is
    /// drawn on the last step; of two notes on one step the later is drawn.
    func chits(in shape: StepGridShape, stepCount: Int) -> [NoteChit] {
        var chits: [Int: NoteChit] = [:]
        for note in notes {
            let first = min(note.steps.lowerBound, stepCount - 1)
            let steps = first ..< min(max(note.steps.upperBound, first + 1), stepCount)
            let rows = shape.rows(of: steps)
            for (index, row) in rows.enumerated() {
                chits[row.lowerBound] = NoteChit(steps: row, note: note,
                                                 isHead: index == 0, isTail: index == rows.count - 1)
            }
        }
        return chits.values.sorted { $0.id < $1.id }
    }
}
