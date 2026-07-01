import SwiftUI

struct SequencerView: View {
    @Environment(PerformanceState.self)  private var perfState
    @Environment(SequencerState.self)   private var seqState

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
            HStack(spacing: 12) {
                transportBar
                tempoControl
            }
            stepGrid
            pageBar
            stepEditorPanel
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    // MARK: – Landscape (editor left, grid + corner transport right)

    private func landscapeBody(width: CGFloat) -> some View {
        HStack(spacing: 12) {
            // Left: roomy step editor filling the freed half.
            stepEditorPanel
                .frame(width: width * 0.40, alignment: .top)

            // Right: clear control, centered grid, Play anchored bottom-right.
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 14) {
                    HStack(spacing: 10) { Spacer(); tempoControl; clearButton }
                    Spacer(minLength: 0)
                    stepGrid
                    Spacer(minLength: 0)
                    pageBar
                        .padding(.trailing, 72)   // clear the Play corner button
                }
                playCornerButton
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(16)
    }

    // MARK: – Transport (portrait)

    private var transportBar: some View {
        HStack(spacing: 16) {
            Button { togglePlay() } label: {
                Label(seqState.isPlaying ? "Stop" : "Play",
                      systemImage: seqState.isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(seqState.isPlaying ? Color.red : Color.green)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.12)))
            }
            .buttonStyle(.plain)

            Button { clearGrid() } label: {
                Label("Clear", systemImage: "arrow.counterclockwise")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(white: 0.6))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.12)))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: – Tempo (moved here from the old Mode sheet — BPM only matters in the Sequencer)

    private var tempoControl: some View {
        HStack(spacing: 8) {
            tempoStep(system: "minus", enabled: perfState.bpm > 20) {
                perfState.setBPM(perfState.bpm - 5)
            }
            VStack(spacing: 0) {
                Text("\(Int(perfState.bpm))")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                Text("BPM")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(white: 0.4))
                    .kerning(1)
            }
            .frame(minWidth: 40)
            tempoStep(system: "plus", enabled: perfState.bpm < 300) {
                perfState.setBPM(perfState.bpm + 5)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.12)))
    }

    private func tempoStep(system: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(enabled ? Color.orange : Color(white: 0.25))
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color(white: 0.16)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
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

    private var clearButton: some View {
        Button { clearGrid() } label: {
            Label("Clear", systemImage: "arrow.counterclockwise")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(white: 0.6))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.12)))
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
        seqState.snapshot()
        seqState.steps = Array(repeating: SequencerStep(), count: 16)
        seqState.save()
    }

    // MARK: – 4×4 Grid

    private var stepGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(0..<16, id: \.self) { col in
                stepCell(seqState.currentPage * 16 + col)
            }
        }
    }

    @ViewBuilder
    private func stepCell(_ idx: Int) -> some View {
        let step      = seqState.steps[idx]
        let isPlaying = seqState.currentStep == idx
        let isSelected = seqState.selectedStep == idx

        Button {
            seqState.selectedStep = idx
        } label: {
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
        }
        .buttonStyle(.plain)
    }

    // MARK: – Step Editor

    private var stepEditorPanel: some View {
        let idx  = seqState.selectedStep
        let step = seqState.steps[idx]

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("STEP \(idx + 1)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(white: 0.4))
                    .kerning(2)
                Spacer()
                undoButton
            }

            // Degree picker
            let degrees: [(Degree, String)] = [
                (.I, "I"), (.ii, "ii"), (.iii, "iii"), (.IV, "IV"),
                (.V, "V"), (.vi, "vi"), (.viiDim, "vii°")
            ]
            HStack(spacing: 5) {
                ForEach(degrees, id: \.0) { degree, label in
                    Button {
                        seqState.snapshot()
                        seqState.steps[idx].degree = degree
                        seqState.steps[idx].isRest = false
                        seqState.save()
                    } label: {
                        Text(label)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(step.degree == degree && !step.isRest ? .black : .white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(step.degree == degree && !step.isRest
                                          ? Color.orange : Color(white: 0.15))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            // Direction picker (3×3 joystick grid) + Rest toggle + Gate
            HStack(alignment: .top, spacing: 12) {
                directionPicker(idx: idx, step: step)

                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: Binding(
                        get: { seqState.steps[idx].isRest },
                        set: { seqState.snapshot(); seqState.steps[idx].isRest = $0; seqState.save() }
                    )) {
                        Text("Rest")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Color(white: 0.7))
                    }
                    .toggleStyle(SwitchToggleStyle(tint: .orange))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(gateLabel(step.gate))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Color(white: 0.4))
                        Slider(value: Binding(
                            get: { seqState.steps[idx].gate },
                            set: { seqState.steps[idx].gate = $0; seqState.save() }
                        ), in: 0.1...1.0, onEditingChanged: { editing in
                            if editing { seqState.snapshot() }
                        })
                        .tint(.orange)
                    }
                }
                .frame(maxWidth: .infinity)
            }

            Text("Edit while it loops — changes apply on the next pass.  ↶ Undo to revert.")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color(white: 0.3))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.07)))
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

    /// Gate read-out names the audible behavior, matching the prototype:
    /// crisp at the bottom, tied/legato at the very top.
    private func gateLabel(_ gate: Double) -> String {
        let pct = Int(gate * 100)
        if gate >= 0.98 { return "Gate \(pct)% · tie" }
        if gate <= 0.30 { return "Gate \(pct)% · staccato" }
        return "Gate \(pct)%"
    }

    @ViewBuilder
    private func directionPicker(idx: Int, step: SequencerStep) -> some View {
        let grid: [[JoystickDirection?]] = [
            [.upLeft,   .up,    .upRight],
            [.left,     .center, .right],
            [.downLeft, .down,  .downRight],
        ]
        let symbols: [JoystickDirection: String] = [
            .upLeft: "↖", .up: "↑", .upRight: "↗",
            .left: "←",   .center: "·", .right: "→",
            .downLeft: "↙", .down: "↓", .downRight: "↘",
        ]
        VStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { col in
                        if let dir = grid[row][col] {
                            Button {
                                seqState.snapshot()
                                seqState.steps[idx].joystickDirection = dir
                                seqState.save()
                            } label: {
                                Text(symbols[dir] ?? "·")
                                    .font(.system(size: 14))
                                    .frame(width: 30, height: 30)
                                    .foregroundStyle(step.joystickDirection == dir ? .black : .white)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(step.joystickDirection == dir
                                                  ? Color.orange : Color(white: 0.18))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}
