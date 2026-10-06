import SwiftUI

/// The sequencer's steps, the notes of the layer on screen drawn across them,
/// and the gestures that select steps, in whichever `SequencerLayout` is chosen:
///
///  • paged — the focused bar alone. Tap toggles a step; dragging sweeps.
///  • scroll — every bar in one scrolling column, ending in an "add bar" row.
///    One finger selects exactly as in the paged layout; two fingers scroll.
///
/// Both lay their cells out by `StepGridGeometry` and read touches back
/// through it, in global step indices, so a sweep can cross bars.
///
/// A bar is drawn in three layers: the step cells, then each note as a chit
/// as wide as the steps it is held across (in pieces where it runs past a
/// row's end), then what is said of each step: its number, the chord that
/// starts on it, and whether it is selected, playing or in the loop.
struct SequencerStepGrid: View {
    @Environment(PerformanceState.self) private var perfState
    @Environment(SequencerState.self)   private var seqState

    /// Scroll layout only: take all the height offered, instead of one bar
    /// plus a peek at the next.
    var fillsHeight = false

    /// True once a drag has left its starting cell; from then on the
    /// gesture is a selection sweep rather than a candidate tap.
    @State private var isSweeping = false
    /// Steps inside the sweep rectangle right now, highlighted but not yet
    /// committed. Recomputed from the anchor each frame, so backtracking
    /// shrinks it; it merges into the real selection only on finger lift.
    @State private var sweepPreview: Set<Int> = []
    private static let cellHeight: CGFloat = 45
    private static let headerHeight: CGFloat = 26
    private static let barGap: CGFloat = 10
    /// The space the paged layout's touches are read in: its origin is the
    /// top-left of the bar on screen.
    private static let columnSpace = "sequencerStepColumn"

    var body: some View {
        switch seqState.layout {
        case .paged:  pagedGrid
        case .scroll: scrollGrid
        }
    }

    // MARK: – Layouts

    private var isScroll: Bool { seqState.layout == .scroll }

    /// The bars laid out in the column, top to bottom.
    private var column: Range<Int> {
        isScroll ? 0..<seqState.barCount : seqState.focusedBar..<seqState.focusedBar + 1
    }

    private func geometry(width: CGFloat) -> StepGridGeometry {
        StepGridGeometry(shape: seqState.shape,
                         width: width,
                         cellHeight: Self.cellHeight,
                         headerHeight: isScroll ? Self.headerHeight : 0,
                         barGap: isScroll ? Self.barGap : 0)
    }

    /// A bar as it is drawn: its number, its steps and the notes on them,
    /// read from the layer while the grid's own body runs.
    ///
    /// The bar's views are handed what they draw rather than looking it up,
    /// because SwiftUI can redraw a bar once more after it has left the
    /// pattern (the column re-runs its bars before it drops one), and a view
    /// should draw what it was given, not look it up then.
    private struct Bar: Identifiable {
        /// The bar's number, counted from 0.
        var id: Int
        var steps: Range<Int>
        /// The pieces of notes drawn in this bar.
        var chits: [NoteChit]

        /// The note that starts on `step`, if one does.
        func head(on step: Int) -> NoteChit? {
            chits.first { $0.isHead && $0.steps.lowerBound == step }
        }

        func hasNote(on step: Int) -> Bool {
            chits.contains { $0.steps.contains(step) }
        }
    }

    private func bars(_ indices: Range<Int>) -> [Bar] {
        let (shape, chits) = (seqState.shape, seqState.chits)
        return indices.map { index in
            let steps = shape.steps(ofBar: index)
            return Bar(id: index, steps: steps, chits: chits.filter { steps.contains($0.steps.lowerBound) })
        }
    }

    private var pagedGrid: some View {
        ForEach(bars(column)) { barCells($0) }
            .coordinateSpace(.named(Self.columnSpace))
    }

    private var scrollGrid: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: Self.barGap) {
                    ForEach(bars(column)) { bar in
                        VStack(spacing: 0) {
                            barHeader(bar.id)
                            barCells(bar)
                        }
                        .id(bar.id)
                    }
                    addBarRow
                }
                .scrollTargetLayout()
                // One finger selects, two scroll (see `ScrollSelectionTouches`).
                .background {
                    GeometryReader { geo in
                        scrollSelection(geometry(width: geo.size.width))
                    }
                }
            }
            .scrollTargetBehavior(.viewAligned)
            .onAppear { proxy.scrollTo(seqState.focusedBar, anchor: .top) }
            .onChange(of: seqState.focusedBar) { _, bar in
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(bar, anchor: .top)
                }
            }
        }
        // One bar, the gap below it and the next bar's header: enough to show
        // there is more to scroll to.
        .frame(height: fillsHeight ? nil
                                   : geometry(width: 0).barHeight + Self.barGap + Self.headerHeight)
        .frame(maxHeight: fillsHeight ? .infinity : nil)
    }

    // MARK: – Bars

    private func barCells(_ bar: Bar) -> some View {
        GeometryReader { geo in
            let geometry = geometry(width: geo.size.width)
            ZStack(alignment: .topLeading) {
                ForEach(bar.steps, id: \.self) { step in
                    stepCell.placed(geometry.frame(of: step..<step + 1))
                }
                ForEach(bar.chits) { chit in
                    noteChit(chit).placed(geometry.frame(of: chit.steps))
                }
                ForEach(bar.steps, id: \.self) { step in
                    stepMarks(step, in: bar).placed(geometry.frame(of: step..<step + 1))
                }
                // Paged: one surface over the bar handles its taps and sweeps,
                // so both share the cell-position math. The scroll layout's
                // touches are read behind the whole column instead.
                if !isScroll {
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(dragSelection(geometry))
                }
            }
        }
        .frame(height: geometry(width: 0).cellsHeight)
    }

    private func barHeader(_ bar: Int) -> some View {
        HStack(spacing: 0) {
            Text("BAR \(bar + 1)")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(white: 0.35))
                .kerning(1)
            Spacer(minLength: 0)
            if seqState.canRemoveBar {
                Button { seqState.removeBar(bar) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color(white: 0.45))
                        .frame(width: 44, height: Self.headerHeight, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove bar \(bar + 1)")
            }
        }
        .frame(height: Self.headerHeight)
    }

    /// The end of the scroll: the pattern grows by a bar from here.
    private var addBarRow: some View {
        Button { seqState.addBar() } label: {
            Label("BAR", systemImage: "plus")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(white: 0.5))
                .frame(maxWidth: .infinity)
                .frame(height: Self.cellHeight)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color(white: 0.2),
                                      style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add bar")
    }

    // MARK: – Selection gestures

    /// The global step nearest a point in the column.
    private func step(nearest point: CGPoint, in geometry: StepGridGeometry) -> Int {
        column.lowerBound * seqState.stepsPerBar
            + geometry.step(nearest: point, bars: column.count)
    }

    /// A drag that has left its starting cell is a sweep: preview the
    /// rectangle between that cell and the finger.
    private func sweepMoved(from anchor: Int, to current: Int) {
        // Still inside the start cell → still a candidate tap.
        guard isSweeping || current != anchor else { return }
        isSweeping = true
        sweepPreview = seqState.shape.rectangle(from: anchor, to: current)
    }

    /// The finger lifted: a sweep merges into the selection, anything less
    /// was a tap on the start cell.
    private func sweepEnded(from anchor: Int, to current: Int) {
        if isSweeping {
            seqState.addToSelection(seqState.shape.rectangle(from: anchor, to: current),
                                    primary: current)
        } else {
            seqState.toggleStepSelection(anchor)
        }
        sweepCancelled()
    }

    private func sweepCancelled() {
        isSweeping = false
        sweepPreview = []
    }

    /// Paged layout. Tap toggles one step; dragging previews the rectangle
    /// between the drag's start cell and the finger. Nothing is committed
    /// until the finger lifts — like a chess piece, the sweep can be taken
    /// back by moving out of an accidentally entered row or column — and only
    /// then does the final rectangle merge into the selection (adding, never
    /// removing).
    private func dragSelection(_ geometry: StepGridGeometry) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.columnSpace))
            .onChanged { value in
                sweepMoved(from: step(nearest: value.startLocation, in: geometry),
                           to: step(nearest: value.location, in: geometry))
            }
            .onEnded { value in
                sweepEnded(from: step(nearest: value.startLocation, in: geometry),
                           to: step(nearest: value.location, in: geometry))
            }
    }

    /// Scroll layout: the same tap and sweep, on one finger, leaving two
    /// fingers to scroll.
    private func scrollSelection(_ geometry: StepGridGeometry) -> some View {
        ScrollSelectionTouches(
            canTap: { geometry.step(at: $0, bars: column.count) != nil },
            onTap: { seqState.toggleStepSelection(step(nearest: $0, in: geometry)) },
            onSweepChanged: { start, current in
                sweepMoved(from: step(nearest: start, in: geometry),
                           to: step(nearest: current, in: geometry))
            },
            onSweepEnded: { start, current in
                sweepEnded(from: step(nearest: start, in: geometry),
                           to: step(nearest: current, in: geometry))
            },
            onSweepCancelled: sweepCancelled
        )
    }

    // MARK: – Cells

    private static let corner: CGFloat = 6

    /// A step with nothing said of it yet: the bottom layer.
    private var stepCell: some View {
        RoundedRectangle(cornerRadius: Self.corner)
            .fill(Color(white: 0.10))
            .overlay(RoundedRectangle(cornerRadius: Self.corner).stroke(Color(white: 0.18), lineWidth: 1))
    }

    /// One piece of a note: a chit across the steps of a row it is held
    /// for. An end where the note runs on into another row is left square.
    private func noteChit(_ chit: NoteChit) -> some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: chit.isHead ? Self.corner : 0,
            bottomLeadingRadius: chit.isHead ? Self.corner : 0,
            bottomTrailingRadius: chit.isTail ? Self.corner : 0,
            topTrailingRadius: chit.isTail ? Self.corner : 0)
        return shape
            .fill(Color(white: 0.19))
            .overlay(shape.stroke(Color(white: 0.30), lineWidth: 1))
            // Coloration tag tucked into the lower-left corner, showing the
            // note's chord coloration (omitted for uncolored chords).
            .overlay(alignment: .bottomLeading) {
                if chit.isHead, !chit.note.chord.color.isBase {
                    chitTag(colorActionLabel(chit.note.chord.color), color: Color.orange.opacity(0.85))
                        .padding(.leading, 4)
                }
            }
            // Top right: played off the grid's lines (Snap moves it onto them).
            .overlay(alignment: .topTrailing) {
                if chit.isTail, chit.isOffGrid {
                    chitTag("≈", color: Color(white: 0.6)).padding(.trailing, 4)
                }
            }
            // Bottom right: it has a key, octave, sound or effects of its
            // own, and does not follow the ones chosen now.
            .overlay(alignment: .bottomTrailing) {
                if chit.isTail, chit.note.playing.hasOwn {
                    chitTag("◆", color: Color(white: 0.6)).padding(.trailing, 4)
                }
            }
    }

    private func chitTag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 8.75, weight: .medium, design: .monospaced))
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.vertical, 3)
    }

    /// What is said of one step, over the cells and chits: its number, the
    /// chord that starts on it (a dash where nothing sounds), and whether it
    /// is selected, playing or in the loop.
    private func stepMarks(_ step: Int, in bar: Bar) -> some View {
        let isPlaying = seqState.currentStep == step
        let isSelected = seqState.selectedSteps.contains(step) || sweepPreview.contains(step)
        let head = bar.head(on: step)

        return VStack(spacing: 2) {
            Text("\(step + 1)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Color(white: 0.35))
            Text(label(head, hasNote: bar.hasNote(on: step)))
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(head == nil ? Color(white: 0.3) : .white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if isPlaying || isSelected {
                RoundedRectangle(cornerRadius: Self.corner)
                    .fill(isPlaying ? Color.orange.opacity(0.35) : Color.white.opacity(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: Self.corner)
                            .stroke(isPlaying ? Color.orange : Color(white: 0.55),
                                    lineWidth: isPlaying ? 1.5 : 1)
                    )
            }
        }
        // Steps of the loop carry an orange bar along their top edge.
        .overlay(alignment: .top) {
            if seqState.loopSteps.contains(step) {
                Capsule()
                    .fill(Color.orange.opacity(0.85))
                    .frame(height: 2)
                    .padding(.horizontal, 8)
                    .padding(.top, 3)
            }
        }
    }

    /// The chord a note starts with, in its own key if it has one; nothing
    /// on the steps it is held across, and a dash on a rest.
    private func label(_ head: NoteChit?, hasNote: Bool) -> String {
        guard let head else { return hasNote ? "" : "—" }
        return degreeNumeral(key: head.note.playing.key ?? perfState.key, degree: head.note.chord.degree)
    }
}

private extension View {
    /// Puts the view at `frame` in a top-leading `ZStack`.
    func placed(_ frame: CGRect) -> some View {
        self.frame(width: max(frame.width, 0), height: frame.height)
            .offset(x: frame.minX, y: frame.minY)
    }
}
