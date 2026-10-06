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
    /// Step entry: while on, a chord chosen on the ring goes on the selected
    /// step and the selection moves to the next, so a progression is entered
    /// by choosing its chords in order.
    @State private var isEnteringSteps = false

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
            layerTabs
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
                layerTabs
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

    /// Shares what the timeline plays (in the current key, octave, sound
    /// and tempo): as sound, a `.wav` file of every layer as it is heard, or
    /// as notes, a `.mid` file. Disabled when every played step is a rest —
    /// there would be nothing in the file.
    private var exportButton: some View {
        let isEmpty = seqState.timeline.playsNothing
        return Menu {
            ShareLink(item: perfState.timelineAudioExport,
                      preview: SharePreview("Perfecto audio", image: Image(systemName: "waveform"))) {
                Label("Audio (WAV)", systemImage: "waveform")
            }
            ShareLink(item: perfState.sequencerMidiExport,
                      preview: SharePreview("Perfecto MIDI pattern", image: Image(systemName: "pianokeys"))) {
                Label("MIDI", systemImage: "pianokeys")
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isEmpty ? Color(white: 0.3) : Color(white: 0.6))
                .frame(width: 34, height: 29)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.12)))
        }
        .buttonStyle(.plain)
        .disabled(isEmpty)
        .accessibilityLabel("Export audio or MIDI")
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
            barsMenu

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

    /// The time signature, and the changes to how the notes are counted
    /// into bars: the same notes read as twice or half as many (with the
    /// tempo changed to match, so they sound as they did), and the empty
    /// bars at the end dropped.
    private var barsMenu: some View {
        Menu {
            Picker("Time signature", selection: Binding(
                get: { seqState.timeline.signature },
                set: { seqState.setSignature($0) }
            )) {
                ForEach(TimeSignature.offered, id: \.self) { Text($0.label).tag($0) }
            }
            Divider()
            Button("Double the bars") { scaleBars(by: 2) }
                .disabled(!canScaleBars(by: 2))
            Button("Halve the bars") { scaleBars(by: 0.5) }
                .disabled(!canScaleBars(by: 0.5))
            Button("Trim empty bars") { seqState.trimEmptyBars() }
                .disabled(!seqState.canTrimBars)
        } label: {
            Text(seqState.timeline.signature.label)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(white: 0.6))
                .padding(.horizontal, 8)
                .frame(height: 29)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.13)))
        }
        .accessibilityLabel("Time signature and bars")
    }

    /// Whether the notes can be read as `factor` times as many bars at
    /// `factor` times the tempo.
    private func canScaleBars(by factor: Double) -> Bool {
        MusicalTime.tempoRange.contains(perfState.bpm * factor) && (factor > 1 || seqState.canHalveBars)
    }

    private func scaleBars(by factor: Double) {
        guard canScaleBars(by: factor) else { return }
        if factor > 1 { seqState.doubleBars() } else { seqState.halveBars() }
        perfState.setBPM(perfState.bpm * factor)
    }

    // MARK: – Layers

    /// One tab per layer, and a plus. The layer chosen is the one the grid
    /// shows and the editor changes; the others play on. The menu at the end
    /// acts on the layer chosen.
    private var layerTabs: some View {
        HStack(spacing: 8) {
            fieldLabel("LAYER")
            ForEach(Array(seqState.layers.enumerated()), id: \.element.id) { index, layer in
                layerTab(index, layer)
            }
            barCountButton("plus", label: "Add layer") { seqState.addLayer() }
                .disabled(!seqState.canAddLayer)
                .opacity(seqState.canAddLayer ? 1 : 0.4)
            Spacer(minLength: 0)
            layerMenu
        }
    }

    private func layerTab(_ index: Int, _ layer: Layer) -> some View {
        let on = seqState.layerID == layer.id
        return Button { seqState.showLayer(layer.id) } label: {
            Text("\(index + 1)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .strikethrough(layer.isMuted)
                .foregroundStyle(on ? .black : Color(white: layer.isMuted ? 0.35 : 0.6))
                .frame(minWidth: 26)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 6)
                    .fill(on ? Color.orange : Color(white: 0.13)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Layer \(index + 1)" + (layer.isMuted ? ", muted" : ""))
    }

    private var layerMenu: some View {
        let layer = seqState.layers.first { $0.id == seqState.layerID }
        let isMuted = layer?.isMuted ?? false
        return Menu {
            Button(isMuted ? "Unmute" : "Mute") { seqState.setLayer(seqState.layerID, muted: !isMuted) }
            Button("Duplicate") { seqState.duplicateLayer() }
                .disabled(!seqState.canAddLayer)
            Button("Delete", role: .destructive) { seqState.removeLayer(seqState.layerID) }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(white: 0.6))
                .frame(width: 30, height: 29)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.13)))
        }
        .accessibilityLabel("Layer actions")
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
        let primary = seqState.primaryNote
        // The grid needs a row per mode, so it is taller than the strip.
        let surfaceHeight: CGFloat = perfState.colorSurface == .grid
            ? (boxed ? 168 : ColorSurfaceView.portraitHeight(.grid))
            : colorBarHeight

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                restButton
                gateControl(primary)
                undoButton
            }
            noteControls

            // Chord-degree (scale-number) ring — the same circular layout as the
            // Play-mode chord ring, filling the free space above the coloration
            // bar. It sets the degree of the selected notes, and puts a chord on
            // a selected step that has none; nothing is highlighted on a rest.
            DegreeRingView(
                key: primary?.playing.key ?? perfState.key,
                selected: primary?.chord.degree,
                onChange: { degree in
                    guard !seqState.selectedSteps.isEmpty else { return }
                    // One undo snapshot per drag: take it on the first change,
                    // clear the flag when the gesture ends.
                    if !stepDegreeEditActive {
                        seqState.snapshot()
                        stepDegreeEditActive = true
                    }
                    // As on the keys, a coloration held while the degree is
                    // chosen is the chord's.
                    seqState.editSelectedChords {
                        ChordSpec(degree: degree, color: heldColor(for: degree) ?? $0.color)
                    }
                },
                onEnd: {
                    if stepDegreeEditActive, isEnteringSteps { seqState.advanceSelection() }
                    stepDegreeEditActive = false
                }
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
                    stepColorGrid(degree: primary?.chord.degree ?? .I)
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

    /// The coloration a finger is holding on the color surface now, if one is.
    private func heldColor(for degree: Degree) -> ChordColor? {
        if stepColorTransient != .center { return .joystick(perfState.joystickMode, stepColorTransient) }
        return stepGridTransient.map { ChordGrid.color(at: $0, key: perfState.key, degree: degree) }
    }

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
                // Use the mode the labels were drawn from, so playback and
                // the note's coloration tag match what the bar showed.
                seqState.editSelectedChords {
                    ChordSpec(degree: $0.degree, color: .joystick(perfState.joystickMode, direction))
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
                seqState.editSelectedChords {
                    ChordSpec(degree: $0.degree,
                              color: ChordGrid.color(at: position, key: key, degree: $0.degree))
                }
            },
            onEnd: {
                stepGridTransient = nil
                stepColorEditActive = false
            }
        )
    }

    // MARK: – Rest / length (apply to every selected note)

    private var hasSelectedNotes: Bool { !seqState.selectedNotes.isEmpty }

    /// Makes the selected steps rests.
    private var restButton: some View {
        editButton("REST", enabled: hasSelectedNotes) { seqState.restSelected() }
    }

    /// How much of its last step the note sounds for. The steps it is held
    /// across are changed by the buttons under it.
    private func gateControl(_ primary: TimelineNote?) -> some View {
        let gate = primary?.gate ?? TimelineNote.enteredGate
        return VStack(alignment: .leading, spacing: 2) {
            Text(lengthLabel(primary))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color(white: 0.4))
            HStack(spacing: 6) {
                Slider(value: Binding(
                    get: { gate },
                    set: { seqState.setGateOfSelected($0) }
                ), in: 0.1...1.0, onEditingChanged: { editing in
                    if editing { seqState.snapshot() }
                })
                .tint(.orange)
                barCountButton("minus", label: "A step shorter") { seqState.lengthenSelected(bySteps: -1) }
                barCountButton("plus", label: "A step longer") { seqState.lengthenSelected(bySteps: 1) }
            }
        }
        .frame(maxWidth: .infinity)
        .disabled(!hasSelectedNotes)
        .opacity(hasSelectedNotes ? 1 : 0.5)
    }

    /// The length read-out names the audible behavior: crisp at the bottom
    /// of the slider, running into the next chord at the very top.
    private func lengthLabel(_ note: TimelineNote?) -> String {
        guard let note else { return "Length" }
        let steps = Double(note.length) / Double(TimelineTime.ticksPerStep)
        let length = "Length \(steps.formatted(.number.precision(.fractionLength(0...2))))"
        if note.gate >= 1 { return length + " · held" }
        if note.gate <= 0.30 { return length + " · staccato" }
        return length
    }

    /// The edits that change how notes sit on the steps (one held note from
    /// the selected steps, a note for each of them, onto the grid's lines),
    /// what the selected notes keep of their own, and step entry.
    private var noteControls: some View {
        HStack(spacing: 8) {
            editButton("JOIN", enabled: seqState.canJoin) { seqState.joinSelected() }
            editButton("SPLIT", enabled: seqState.canSplit) { seqState.splitSelected() }
            editButton("SNAP", enabled: seqState.canSnap) { seqState.snapSelected() }
            Spacer(minLength: 0)
            ownSettingsMenu
            stepEntryToggle
        }
    }

    /// A note follows the key, octave, sound and effects chosen now unless
    /// it has its own. Keeping one sets it to what is chosen now, so a
    /// note's key is changed by choosing the key and keeping it; following
    /// gives it up again.
    private var ownSettingsMenu: some View {
        let playing = seqState.primaryNote?.playing
        let (liveKey, liveOctave) = (perfState.key, perfState.octave)
        let (livePreset, liveEffects) = (perfState.synthPreset, perfState.effects.asSet)
        let hasOwn = playing?.hasOwn ?? false
        return Menu {
            Section(playing?.key.map { "Key: its own, \(keyName($0))" } ?? "Key: follows the key chosen") {
                Button("Keep \(keyName(liveKey))") { seqState.editSelectedPlaying { $0.key = liveKey } }
                Button("Follow the key chosen") { seqState.editSelectedPlaying { $0.key = nil } }
                    .disabled(playing?.key == nil)
            }
            Section(playing?.octave.map { "Octave: its own, \($0)" } ?? "Octave: follows the octave chosen") {
                Button("Keep octave \(liveOctave)") { seqState.editSelectedPlaying { $0.octave = liveOctave } }
                Button("Follow the octave chosen") { seqState.editSelectedPlaying { $0.octave = nil } }
                    .disabled(playing?.octave == nil)
            }
            Section(playing?.preset.map { "Sound: its own, \($0.name)" } ?? "Sound: follows the sound chosen") {
                Button("Keep \(livePreset.name)") { seqState.editSelectedPlaying { $0.preset = livePreset } }
                Button("Follow the sound chosen") { seqState.editSelectedPlaying { $0.preset = nil } }
                    .disabled(playing?.preset == nil)
            }
            Section(playing?.effects == nil ? "Effects: follow the effects set" : "Effects: its own") {
                Button("Keep the effects as set now") { seqState.editSelectedPlaying { $0.effects = liveEffects } }
                Button("Follow the effects set") { seqState.editSelectedPlaying { $0.effects = nil } }
                    .disabled(playing?.effects == nil)
            }
        } label: {
            Text("◆ OWN")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(!hasSelectedNotes ? Color(white: 0.3)
                                 : hasOwn ? Color.orange : Color(white: 0.7))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color(white: 0.12)))
        }
        .disabled(!hasSelectedNotes)
        .accessibilityLabel("The note's own key, octave, sound and effects")
    }

    private func keyName(_ key: Key) -> String {
        "\(key.root.name) \(key.scale.displayName)"
    }

    private var stepEntryToggle: some View {
        Button { isEnteringSteps.toggle() } label: {
            Label("ENTRY", systemImage: "arrow.right.to.line")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(isEnteringSteps ? Color.black : Color(white: 0.7))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 7)
                    .fill(isEnteringSteps ? Color.orange : Color(white: 0.12)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Step entry")
        .accessibilityAddTraits(isEnteringSteps ? .isSelected : [])
    }

    private func editButton(_ label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(enabled ? Color(white: 0.7) : Color(white: 0.3))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color(white: 0.12)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
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
