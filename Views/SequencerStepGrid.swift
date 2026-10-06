import SwiftUI

/// The sequencer's step cells and the gestures that select them, in whichever
/// `SequencerLayout` is chosen:
///
///  • paged — the focused bar alone. Tap toggles a step; dragging sweeps.
///  • scroll — every bar in one scrolling column, ending in an "add bar" row.
///    One finger selects exactly as in the paged layout; two fingers scroll.
///
/// Both lay their cells out by `StepGridGeometry` and read touches back
/// through it, in global step indices, so a sweep can cross bars.
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
        StepGridGeometry(width: width,
                         cellHeight: Self.cellHeight,
                         headerHeight: isScroll ? Self.headerHeight : 0,
                         barGap: isScroll ? Self.barGap : 0)
    }

    /// A bar as it is drawn: its number and its steps, read from the pattern
    /// while the grid's own body runs.
    ///
    /// The cells are handed their steps rather than looking them up, because
    /// SwiftUI can redraw a bar's cells once more after the bar has left the
    /// pattern (the lazy grid re-runs its cells before the column drops the
    /// bar), and a cell should draw what it was given, not look it up then.
    private struct Bar: Identifiable {
        /// The bar's number, counted from 0.
        var id: Int
        var cells: [Cell]
    }

    private struct Cell: Identifiable {
        /// The step's global index.
        var id: Int
        var step: SequencerStep
    }

    private func bar(_ index: Int) -> Bar {
        let base = index * SequencerState.stepsPerBar
        return Bar(id: index, cells: (base..<base + SequencerState.stepsPerBar).map {
            Cell(id: $0, step: seqState.step($0))
        })
    }

    private var pagedGrid: some View {
        barCells(bar(seqState.focusedBar))
            .coordinateSpace(.named(Self.columnSpace))
    }

    private var scrollGrid: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: Self.barGap) {
                    ForEach(column.map(bar)) { bar in
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
        let columns = Array(repeating: GridItem(.flexible(), spacing: StepGridGeometry.spacing),
                            count: StepGridGeometry.columns)
        return LazyVGrid(columns: columns, spacing: StepGridGeometry.spacing) {
            ForEach(bar.cells) { stepCell($0) }
        }
        // Paged: one surface over the bar handles its taps and sweeps, so
        // both share the cell-position math. The scroll layout's touches are
        // read behind the whole column instead.
        .overlay {
            if !isScroll {
                GeometryReader { geo in
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(dragSelection(geometry(width: geo.size.width)))
                }
            }
        }
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
        column.lowerBound * SequencerState.stepsPerBar
            + geometry.step(nearest: point, bars: column.count)
    }

    /// A drag that has left its starting cell is a sweep: preview the
    /// rectangle between that cell and the finger.
    private func sweepMoved(from anchor: Int, to current: Int) {
        // Still inside the start cell → still a candidate tap.
        guard isSweeping || current != anchor else { return }
        isSweeping = true
        sweepPreview = SequencerState.rectangle(from: anchor, to: current)
    }

    /// The finger lifted: a sweep merges into the selection, anything less
    /// was a tap on the start cell.
    private func sweepEnded(from anchor: Int, to current: Int) {
        if isSweeping {
            seqState.addToSelection(SequencerState.rectangle(from: anchor, to: current),
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

    @ViewBuilder
    private func stepCell(_ cell: Cell) -> some View {
        let idx       = cell.id
        let step      = cell.step
        let isPlaying = seqState.currentStep == idx
        let isSelected = seqState.selectedSteps.contains(idx) || sweepPreview.contains(idx)

        VStack(spacing: 2) {
            Text("\(idx + 1)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Color(white: 0.35))
            Text(step.label(in: perfState.key))
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(step.isRest ? Color(white: 0.3) : .white)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.cellHeight)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isPlaying  ? Color.orange.opacity(0.35) :
                      isSelected ? Color(white: 0.22) :
                                   Color(white: 0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isPlaying  ? Color.orange :
                                isSelected ? Color(white: 0.45) :
                                             Color(white: 0.18),
                                lineWidth: isPlaying ? 1.5 : 1)
                )
        )
        // Steps of the loop carry an orange bar along their top edge.
        .overlay(alignment: .top) {
            if seqState.loopSteps.contains(idx) {
                Capsule()
                    .fill(Color.orange.opacity(0.85))
                    .frame(height: 2)
                    .padding(.horizontal, 8)
                    .padding(.top, 3)
            }
        }
        // Coloration tag tucked into the lower-left corner, showing the
        // step's chord coloration (omitted for rests and uncolored steps).
        .overlay(alignment: .bottomLeading) { colorationTag(step) }
    }

    @ViewBuilder
    private func colorationTag(_ step: SequencerStep) -> some View {
        if !step.isRest, !step.color.isBase {
            Text(colorActionLabel(step.color))
                .font(.system(size: 8.75, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.orange.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.leading, 4)
                .padding(.bottom, 3)
        }
    }
}
