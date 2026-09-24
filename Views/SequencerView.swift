import SwiftUI

struct SequencerView: View {
    @Environment(PerformanceState.self)  private var perfState
    @Environment(SequencerState.self)   private var seqState

    /// Guards the undo snapshot so one color-bar drag produces one undo step.
    @State private var stepColorEditActive = false
    /// Same guard for the degree-ring drag: one gesture → one undo step.
    @State private var stepDegreeEditActive = false
    /// Transient color-bar highlight — like Play mode, a section lights only
    /// while actively dragged and clears (`.center`) on release, so no button
    /// stays lit by default.
    @State private var stepColorTransient: JoystickDirection = .center
    /// Drives the KEY sheet for the landscape transport row, which owns the
    /// whole screen and so needs its own copy of the KEY control.
    @State private var showKeySheet = false
    /// Step index where the active grid drag began — the fixed corner of the
    /// selection sweep's rectangle.
    @State private var dragAnchor: Int?
    /// True once the active drag has left its starting cell; from then on the
    /// gesture is a selection sweep rather than a candidate tap.
    @State private var dragSelecting = false
    /// Chits inside the sweep rectangle right now, highlighted but not yet
    /// committed. Recomputed from the anchor each frame, so backtracking
    /// shrinks it; it merges into the real selection only on finger lift.
    @State private var sweepPreview: Set<Int> = []

    var body: some View {
        GeometryReader { geo in
            if geo.size.width > geo.size.height {
                landscapeBody(width: geo.size.width)
            } else {
                portraitBody
            }
        }
        .sheet(isPresented: $showKeySheet) { KeySheet().environment(perfState) }
    }

    // MARK: – Portrait (stacked)

    private var portraitBody: some View {
        VStack(spacing: 12) {
            transportBar
            stepGrid
            pageBar
            // Portrait: no surrounding box, and the coloration bar matches
            // play mode's height rather than being scaled down.
            stepEditorPanel(boxed: false, colorBarHeight: 88)
        }
        // Match the play-mode chit row above (horizontal 20) so the transport
        // bar's Play / BPM / Clear buttons line up with the chits. No bottom
        // padding here: the shared 40pt bottom padding on SequencerView (see
        // PerformanceView) is the sole bottom gap, so the coloration bar lands
        // at the same height as Play mode's bar.
        .padding(.horizontal, 20)
    }

    // MARK: – Landscape (editor left, grid + corner transport right)

    private func landscapeBody(width: CGFloat) -> some View {
        HStack(spacing: 12) {
            // Left: roomy step editor filling the freed half.
            VStack(spacing: 10) {
                pageBar
                stepEditorPanel(boxed: true, colorBarHeight: 72)
            }
            .frame(width: width * 0.40, alignment: .top)

            // Right: BPM + clear along the top, centered grid,
            // Play anchored bottom-right.
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 14) {
                    HStack(spacing: 12) {
                        Spacer(minLength: 0)
                        bpmControl
                        exportButton
                        clearButton
                        deselectButton
                    }
                    Spacer(minLength: 0)
                    stepGrid
                    Spacer(minLength: 0)
                }
                HStack(spacing: 10) {
                    playSeqToggle
                    keyButton
                    midiButton
                    playCornerButton
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(16)
    }

    // MARK: – Transport (portrait)

    // Play now lives in the lower-right, above the coloration bar (see the
    // overlay in `stepEditorPanel`), so the top row carries only BPM and Clear.
    private var transportBar: some View {
        HStack(spacing: 12) {
            bpmControl
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                exportButton
                clearButton
                deselectButton
            }
        }
    }

    private var bpmControl: some View {
        HStack(spacing: 0) {
            Button { perfState.setBPM(max(20, perfState.bpm - 5)) } label: {
                Image(systemName: "minus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(perfState.bpm > 20 ? Color(white: 0.7) : Color(white: 0.3))
                    .frame(width: 35, height: 43)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Text("\(Int(perfState.bpm))")
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(minWidth: 55)
            Button { perfState.setBPM(min(300, perfState.bpm + 5)) } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(perfState.bpm < 300 ? Color(white: 0.7) : Color(white: 0.3))
                    .frame(width: 35, height: 43)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.12)))
    }

    // MARK: – Transport pieces (landscape)

    private var playCornerButton: some View {
        Button { togglePlay() } label: {
            Image(systemName: seqState.isPlaying ? "stop.fill" : "play.fill")
                .font(.system(size: 22))
                .foregroundStyle(seqState.isPlaying ? Color.red : Color.green)
                .frame(width: 60, height: 60)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(white: 0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(seqState.isPlaying ? Color.red.opacity(0.6)
                                                           : Color.green.opacity(0.5),
                                        lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
    }

    /// Shares the pattern as it plays (current key, octave and tempo) as a
    /// `.mid` file. Disabled when every played step is a rest — there would be
    /// nothing in the file.
    private var exportButton: some View {
        let isEmpty = seqState.playedSteps.allSatisfy(\.isRest)
        return ShareLink(item: perfState.sequencerMidiExport,
                         preview: SharePreview("Perfecto MIDI pattern",
                                               image: Image(systemName: "pianokeys"))) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isEmpty ? Color(white: 0.3) : Color(white: 0.6))
                .frame(width: 34, height: 29)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.12)))
        }
        .buttonStyle(.plain)
        .disabled(isEmpty)
        .accessibilityLabel("Export MIDI")
    }

    private var clearButton: some View {
        Button { clearGrid() } label: {
            Label("Reset", systemImage: "arrow.counterclockwise")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(white: 0.6))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.12)))
        }
        .buttonStyle(.plain)
    }

    private var deselectButton: some View {
        Button { seqState.deselectAll() } label: {
            Text("Clear")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(seqState.selectedSteps.isEmpty ? Color(white: 0.3)
                                                                : Color(white: 0.6))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.12)))
        }
        .buttonStyle(.plain)
        .disabled(seqState.selectedSteps.isEmpty)
    }

    // MARK: – Mode / Key / MIDI (landscape bottom row)
    //
    // The landscape sequencer owns the whole screen, so it carries its own
    // compact copies of PerformanceView's PLAY/SEQ, KEY, and MIDI controls.
    // They keep the standard button height and just narrow horizontally.

    private var playSeqToggle: some View {
        HStack(spacing: 0) {
            modeSegButton("PLAY", active: perfState.mode.name == "Play") {
                perfState.setMode(PlayMode())
            }
            modeSegButton("SEQ", active: perfState.mode.name == "Sequencer") {
                perfState.setMode(SequencerMode(perfState.sequencerState))
            }
        }
        .padding(3)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color(white: 0.10))
                .overlay(RoundedRectangle(cornerRadius: 9)
                    .stroke(Color(white: 0.22), lineWidth: 1))
        )
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }

    private func modeSegButton(_ label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(active ? Color.black : Color(white: 0.85))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 6).fill(active ? Color.orange : Color.clear))
        }
        .buttonStyle(.plain)
    }

    private var keyButton: some View {
        Text("KEY")
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color(white: 0.85))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(white: 0.13))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(white: 0.25), lineWidth: 1))
            )
            .contentShape(Rectangle())
            .onTapGesture { showKeySheet = true }
    }

    private var midiButton: some View {
        Button { perfState.isExternalSynth.toggle() } label: {
            Text("MIDI")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(perfState.isExternalSynth ? Color.black : Color(white: 0.85))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(perfState.isExternalSynth ? Color.orange : Color(white: 0.13))
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .stroke(perfState.isExternalSynth ? Color.orange : Color(white: 0.25),
                                    lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: – Bars / pagination bar

    private var pageBar: some View {
        HStack(spacing: 8) {
            Text("BARS")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(white: 0.35))
                .kerning(1)
            ForEach(SequencerState.barOptions, id: \.self) { barsPill($0) }

            Rectangle().fill(Color(white: 0.2)).frame(width: 1, height: 18)

            ForEach(Array(0..<seqState.bars), id: \.self) { pageTab($0) }
            if seqState.canAddBar { addBarButton }

            Spacer(minLength: 0)
            chainToggle
        }
    }

    private func barsPill(_ b: Int) -> some View {
        let on = seqState.bars == b
        return Button { seqState.setBars(b) } label: {
            Text("\(b)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(on ? Color.orange : Color(white: 0.5))
                .frame(minWidth: 22)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(white: 0.10))
                        .overlay(RoundedRectangle(cornerRadius: 6)
                            .stroke(on ? Color.orange.opacity(0.7) : Color(white: 0.2), lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
    }

    private func pageTab(_ p: Int) -> some View {
        let on = seqState.currentPage == p
        return Button { seqState.currentPage = p } label: {
            Text("\(p + 1)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(on ? .black : Color(white: 0.6))
                .frame(minWidth: 22)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 6)
                    .fill(on ? Color.orange : Color(white: 0.13)))
        }
        .buttonStyle(.plain)
    }

    private var addBarButton: some View {
        Button { seqState.addBar() } label: {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(white: 0.6))
                .frame(width: 26, height: 29)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.13)))
        }
        .buttonStyle(.plain)
    }

    private var chainToggle: some View {
        Button { seqState.chain.toggle(); seqState.save() } label: {
            Text("⟳ chain")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(seqState.chain ? .black : Color(white: 0.6))
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 6)
                    .fill(seqState.chain ? Color.orange : Color(white: 0.13)))
        }
        .buttonStyle(.plain)
    }

    // MARK: – Transport actions

    private func togglePlay() {
        if seqState.isPlaying {
            seqState.isPlaying = false
            seqState.currentStep = -1
            perfState.endChord()
        } else {
            seqState.currentStep = -1
            seqState.isPlaying = true
        }
    }

    private func clearGrid() {
        seqState.isPlaying = false
        seqState.currentStep = -1
        perfState.endChord()
        seqState.clearPattern()
    }

    // MARK: – 4×4 Grid

    private static let gridColumns = 4
    private static let gridSpacing: CGFloat = 6

    /// Global index of the first step on the visible page. The grid and its
    /// gesture work in page-local indices (0 ..< 16) and add this offset.
    private var pageBase: Int { seqState.currentPage * SequencerState.stepsPerBar }

    private var stepGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: Self.gridSpacing),
                            count: Self.gridColumns)
        return LazyVGrid(columns: columns, spacing: Self.gridSpacing) {
            ForEach(0..<SequencerState.stepsPerBar, id: \.self) { col in
                stepCell(pageBase + col)
            }
        }
        // One gesture over the whole grid handles both tap-to-toggle and the
        // drag-to-sweep multi-selection, so both share the cell-position math.
        .overlay {
            GeometryReader { geo in
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(selectionGesture(gridSize: geo.size))
            }
        }
    }

    /// Maps a touch point to a page-local step index. Points in the gutters
    /// or slightly outside the grid clamp to the nearest cell so a sweep never
    /// drops out mid-drag.
    private func stepIndex(at point: CGPoint, in size: CGSize) -> Int {
        let n = CGFloat(Self.gridColumns)
        let cellW = (size.width  - (n - 1) * Self.gridSpacing) / n
        let cellH = (size.height - (n - 1) * Self.gridSpacing) / n
        let col = min(Self.gridColumns - 1, max(0, Int(point.x / (cellW + Self.gridSpacing))))
        let row = min(Self.gridColumns - 1, max(0, Int(point.y / (cellH + Self.gridSpacing))))
        return row * Self.gridColumns + col
    }

    /// Tap toggles one chit; dragging previews the rectangle between the
    /// drag's start cell and the finger. Nothing is committed until the finger
    /// lifts — like a chess piece, the sweep can be taken back by moving out
    /// of an accidentally entered row or column — and only then does the final
    /// rectangle merge into the selection (adding, never removing).
    private func selectionGesture(gridSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let anchor = dragAnchor ?? stepIndex(at: value.startLocation, in: gridSize)
                dragAnchor = anchor
                let current = stepIndex(at: value.location, in: gridSize)
                // Still inside the start cell → still a candidate tap.
                guard dragSelecting || current != anchor else { return }
                dragSelecting = true
                sweepPreview = globalIndices(SequencerState.rectangle(from: anchor, to: current))
            }
            .onEnded { value in
                if dragSelecting, let anchor = dragAnchor {
                    let current = stepIndex(at: value.location, in: gridSize)
                    seqState.addToSelection(globalIndices(SequencerState.rectangle(from: anchor, to: current)),
                                            primary: pageBase + current)
                } else {
                    seqState.toggleStepSelection(pageBase + stepIndex(at: value.startLocation, in: gridSize))
                }
                dragAnchor = nil
                dragSelecting = false
                sweepPreview = []
            }
    }

    private func globalIndices(_ local: Set<Int>) -> Set<Int> {
        Set(local.map { pageBase + $0 })
    }

    @ViewBuilder
    private func stepCell(_ idx: Int) -> some View {
        let step      = seqState.steps[idx]
        let isPlaying = seqState.currentStep == idx
        let isSelected = seqState.selectedSteps.contains(idx) || sweepPreview.contains(idx)

        VStack(spacing: 2) {
            Text("\(idx + 1)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Color(white: 0.35))
            Text(step.label)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(step.isRest ? Color(white: 0.3) : .white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
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
        // Coloration tag tucked into the lower-left corner, showing the
        // step's chord coloration (omitted for rests and uncolored steps).
        .overlay(alignment: .bottomLeading) { colorationTag(step) }
    }

    @ViewBuilder
    private func colorationTag(_ step: SequencerStep) -> some View {
        if !step.isRest, step.joystickDirection != .center {
            Text(joystickActionLabel(mode: step.joystickMode, direction: step.joystickDirection))
                .font(.system(size: 8.75, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.orange.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.leading, 4)
                .padding(.bottom, 3)
        }
    }

    // MARK: – Step Editor

    private func stepEditorPanel(boxed: Bool, colorBarHeight: CGFloat) -> some View {
        // The editor displays the most recently touched step and applies every
        // edit to all selected steps at once.
        let primary = seqState.primaryStep.map { seqState.steps[$0] }

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                restButton(primary)
                gateControl
                undoButton
            }

            // Chord-degree (scale-number) ring — the same circular layout as the
            // Play-mode chord ring, filling the free space above the coloration
            // bar. It edits the selected step's `degree`; nothing is highlighted
            // while the step is a rest.
            DegreeRingView(
                selected: (primary?.isRest ?? true) ? nil : primary?.degree,
                onChange: { degree in
                    guard !seqState.selectedSteps.isEmpty else { return }
                    // One undo snapshot per drag: take it on the first change,
                    // clear the flag when the gesture ends.
                    if !stepDegreeEditActive {
                        seqState.snapshot()
                        stepDegreeEditActive = true
                    }
                    seqState.editSelectedSteps {
                        $0.degree = degree
                        $0.isRest = false
                    }
                },
                onEnd: { stepDegreeEditActive = false }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scaleEffect(1.1)
            .padding(.vertical, 4)

            // Chord-coloration bar — the same strip used in Play mode. It edits
            // the selected step's `joystickDirection` instead of the live
            // performance direction. In portrait (no box) it bleeds past the
            // panel's 12pt inset on the sides and bottom so it spans the full
            // width and drops to the same 40pt-from-bottom position as Play
            // mode's bar, keeping the bar visually identical across modes.
            ChordColorBar(
                axis: .horizontal,
                mode: perfState.joystickMode,
                selected: stepColorTransient,
                onChange: { direction in
                    guard !seqState.selectedSteps.isEmpty else { return }
                    // One undo snapshot per drag: take it on the first change,
                    // clear the flag when the gesture ends.
                    if !stepColorEditActive {
                        seqState.snapshot()
                        stepColorEditActive = true
                    }
                    stepColorTransient = direction
                    seqState.editSelectedSteps {
                        $0.joystickDirection = direction
                        // Record the mode the labels were drawn from, so playback
                        // and the step's coloration indicator match what the bar
                        // showed.
                        $0.joystickMode = perfState.joystickMode
                        $0.isRest = false
                    }
                },
                onEnd: {
                    stepColorTransient = .center
                    stepColorEditActive = false
                }
            )
            .frame(height: colorBarHeight)
            .padding(.horizontal, boxed ? 0 : -12)
            .padding(.bottom, boxed ? 0 : -12)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            if boxed {
                RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.07))
            }
        }
        // Portrait: the Play button rides in the lower-right, floating just
        // above the coloration bar's top-right corner. The panel frame's
        // trailing edge is exactly where the full-bleed color bar ends, so a
        // bottom-trailing overlay keeps the button's right edge flush with the
        // bar's right edge; the bottom inset clears the bar's height plus a gap.
        .overlay(alignment: .bottomTrailing) {
            if !boxed {
                playCornerButton
                    .padding(.bottom, colorBarHeight + 12)
            }
        }
    }

    // MARK: – Rest / Gate (apply to every selected step)

    private func restButton(_ primary: SequencerStep?) -> some View {
        let on = primary?.isRest ?? false
        return Button {
            seqState.snapshot()
            seqState.editSelectedSteps { $0.isRest = !on }
        } label: {
            Text("REST")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(on ? Color.black : Color(white: 0.7))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 7)
                    .fill(on ? Color.orange : Color(white: 0.12)))
        }
        .buttonStyle(.plain)
        .disabled(seqState.selectedSteps.isEmpty)
    }

    /// Gate of the primary step, or the default when nothing is selected.
    private var primaryGate: Double {
        seqState.primaryStep.map { seqState.steps[$0].gate } ?? SequencerStep().gate
    }

    private var gateControl: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(gateLabel(primaryGate))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color(white: 0.4))
            Slider(value: Binding(
                get: { primaryGate },
                set: { gate in seqState.editSelectedSteps { $0.gate = gate } }
            ), in: 0.1...1.0, onEditingChanged: { editing in
                if editing { seqState.snapshot() }
            })
            .tint(.orange)
        }
        .frame(maxWidth: .infinity)
        .disabled(seqState.selectedSteps.isEmpty)
    }

    /// Gate read-out names the audible behavior, matching the prototype:
    /// crisp at the bottom, tied/legato at the very top.
    private func gateLabel(_ gate: Double) -> String {
        let pct = Int(gate * 100)
        if gate >= SequencerStep.tieThreshold { return "Gate \(pct)% · tie" }
        if gate <= 0.30 { return "Gate \(pct)% · staccato" }
        return "Gate \(pct)%"
    }

    private var undoButton: some View {
        Button { seqState.undo() } label: {
            Label("Undo", systemImage: "arrow.uturn.backward")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(seqState.canUndo ? Color(white: 0.6) : Color(white: 0.25))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color(white: 0.12))
                        .overlay(RoundedRectangle(cornerRadius: 7)
                            .stroke(Color(white: 0.2), lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
        .disabled(!seqState.canUndo)
    }
}
