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
    /// The chord grid's equivalent: a cell lights only while dragged.
    @State private var stepGridTransient: GridPosition? = nil

    var body: some View {
        GeometryReader { geo in
            if geo.size.width > geo.size.height {
                landscapeBody(width: geo.size.width)
            } else {
                portraitBody
            }
        }
    }

    // MARK: – Portrait (stacked)

    private var portraitBody: some View {
        VStack(spacing: 12) {
            transportBar
            SequencerStepGrid()
            barControls
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
                barControls
                stepEditorPanel(boxed: true, colorBarHeight: 72)
            }
            .frame(width: width * 0.40, alignment: .top)

            // Right: BPM + clear along the top, the grid in the middle
            // (centered when paged, filling the height when it scrolls), Play
            // anchored bottom-right.
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Spacer(minLength: 0)
                    bpmControl
                    exportButton
                    clearButton
                    deselectButton
                }
                .padding(.bottom, 14)
                switch seqState.layout {
                case .paged:
                    Spacer(minLength: 0)
                    SequencerStepGrid()
                    Spacer(minLength: 0)
                case .scroll:
                    SequencerStepGrid(fillsHeight: true)
                }
                HStack(spacing: 10) {
                    playSeqToggle
                    midiButton
                    playCornerButton
                }
                .padding(.top, 14)
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
            Button { perfState.setBPM(perfState.bpm - 5) } label: {
                Image(systemName: "minus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(perfState.bpm > MusicalTime.tempoRange.lowerBound ? Color(white: 0.7) : Color(white: 0.3))
                    .frame(width: 35, height: 43)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Text("\(Int(perfState.bpm))")
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(minWidth: 55)
            Button { perfState.setBPM(perfState.bpm + 5) } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(perfState.bpm < MusicalTime.tempoRange.upperBound ? Color(white: 0.7) : Color(white: 0.3))
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
        let isEmpty = seqState.timeline.playsNothing
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
    // compact copies of PerformanceView's PLAY/SEQ, KEY, FX, and MIDI controls.
    // They keep the standard button height and just narrow horizontally.

    private var playSeqToggle: some View {
        HStack(spacing: 0) {
            modeSegButton("PLAY", active: perfState.mode.kind == .play) {
                perfState.selectMode(.play)
            }
            modeSegButton("SEQ", active: perfState.mode.kind == .sequencer) {
                perfState.selectMode(.sequencer)
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

    // MARK: – Bars / loop bar

    /// The pattern's length and what repeats. The paged layout reaches its
    /// bars here, by numbered tab; the scroll layout shows every bar in the
    /// grid, so only the count is stated.
    private var barControls: some View {
        HStack(spacing: 8) {
            fieldLabel("BARS")
            switch seqState.layout {
            case .paged:
                pageTabs
                removeBarButton
            case .scroll:
                Text("\(seqState.barCount)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(white: 0.6))
                Spacer(minLength: 0)
            }
            addBarButton

            Rectangle().fill(Color(white: 0.2)).frame(width: 1, height: 18)

            fieldLabel("LOOP")
            loopToggle
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(Color(white: 0.35))
            .kerning(1)
    }

    /// One tab per bar. They scroll sideways once there are more than fit,
    /// keeping the focused bar's tab in view.
    private var pageTabs: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(0..<seqState.barCount, id: \.self) { pageTab($0).id($0) }
                }
            }
            .onAppear { proxy.scrollTo(seqState.focusedBar) }
            .onChange(of: seqState.focusedBar) { _, bar in
                withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(bar) }
            }
        }
    }

    private func pageTab(_ p: Int) -> some View {
        let on = seqState.focusedBar == p
        return Button { seqState.focusedBar = p } label: {
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
        barCountButton("plus", label: "Add bar") { seqState.addBar() }
    }

    /// Removes the bar on screen (paged layout).
    private var removeBarButton: some View {
        barCountButton("minus", label: "Remove bar \(seqState.focusedBar + 1)") {
            seqState.removeBar(seqState.focusedBar)
        }
        .disabled(!seqState.canRemoveBar)
        .opacity(seqState.canRemoveBar ? 1 : 0.4)
    }

    private func barCountButton(_ symbol: String, label: String,
                                action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(white: 0.6))
                .frame(width: 26, height: 29)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.13)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// ALL repeats the whole pattern; SEL captures the selected steps as the
    /// loop. Tapping SEL again with a different selection moves the loop there.
    private var loopToggle: some View {
        let looping = !seqState.loopSteps.isEmpty
        return HStack(spacing: 0) {
            loopSegButton("ALL", active: !looping) { seqState.loopAll() }
            loopSegButton("SEL", active: looping) { seqState.loopSelection() }
                .disabled(seqState.selectedSteps.isEmpty)
                .opacity(seqState.selectedSteps.isEmpty && !looping ? 0.4 : 1)
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color(white: 0.13)))
    }

    private func loopSegButton(_ label: String, active: Bool,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(active ? .black : Color(white: 0.6))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 5)
                    .fill(active ? Color.orange : Color.clear))
                .contentShape(Rectangle())
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

    // MARK: – Step Editor

    private func stepEditorPanel(boxed: Bool, colorBarHeight: CGFloat) -> some View {
        // The editor displays the most recently touched step and applies every
        // edit to all selected steps at once.
        let primary = seqState.primaryStep.map(seqState.step)
        // The grid needs a row per mode, so it is taller than the strip.
        let surfaceHeight: CGFloat = perfState.colorSurface == .grid
            ? (boxed ? 168 : ColorSurfaceView.portraitHeight(.grid))
            : colorBarHeight

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
                key: perfState.key,
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

            // Chord-coloration input — the same surface Play mode shows (the
            // joystick strip or the chord grid). It edits the selected steps'
            // color instead of the live one. In portrait (no box) it bleeds
            // past the panel's 12pt inset on the sides and bottom so it spans
            // the full width and drops to the same 40pt-from-bottom position
            // as Play mode's, keeping the surface visually identical across modes.
            Group {
                switch perfState.colorSurface {
                case .joystick:
                    stepColorBar
                case .grid:
                    stepColorGrid(degree: primary.flatMap { $0.isRest ? nil : $0.degree } ?? .I)
                }
            }
            .frame(height: surfaceHeight)
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
                    .padding(.bottom, surfaceHeight + 12)
            }
        }
    }

    // MARK: – Step color surfaces

    private var stepColorBar: some View {
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
                    // Use the mode the labels were drawn from, so playback
                    // and the step's coloration indicator match what the bar
                    // showed.
                    $0.color = .joystick(perfState.joystickMode, direction)
                    $0.isRest = false
                }
            },
            onEnd: {
                stepColorTransient = .center
                stepColorEditActive = false
            }
        )
    }

    /// Each selected step resolves the cell against its own degree, as live
    /// playback resolves it against the degree that plays.
    private func stepColorGrid(degree: Degree) -> some View {
        ChordGridPad(
            key: perfState.key,
            degree: degree,
            selected: stepGridTransient,
            onChange: { position in
                guard !seqState.selectedSteps.isEmpty else { return }
                if !stepColorEditActive {
                    seqState.snapshot()
                    stepColorEditActive = true
                }
                stepGridTransient = position
                let key = perfState.key
                seqState.editSelectedSteps {
                    $0.color = ChordGrid.color(at: position, key: key, degree: $0.degree)
                    $0.isRest = false
                }
            },
            onEnd: {
                stepGridTransient = nil
                stepColorEditActive = false
            }
        )
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
        seqState.primaryStep.map { seqState.step($0).gate } ?? SequencerStep().gate
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
