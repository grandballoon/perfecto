import SwiftUI

struct SequencerView: View {
    @Environment(PerformanceState.self)  private var perfState
    @Environment(SequencerState.self)   private var seqState

    var body: some View {
        VStack(spacing: 12) {
            transportBar
            stepGrid
            stepEditor
        }
        .padding(.horizontal, 16)
    }

    // MARK: – Transport

    private var transportBar: some View {
        HStack(spacing: 16) {
            Button {
                if seqState.isPlaying {
                    seqState.isPlaying = false
                    seqState.currentStep = -1
                    perfState.endChord()
                } else {
                    seqState.currentStep = -1
                    seqState.isPlaying = true
                }
            } label: {
                Label(seqState.isPlaying ? "Stop" : "Play",
                      systemImage: seqState.isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(seqState.isPlaying ? Color.red : Color.green)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.12)))
            }
            .buttonStyle(.plain)

            Button {
                seqState.isPlaying = false
                seqState.currentStep = -1
                perfState.endChord()
                seqState.steps = Array(repeating: SequencerStep(), count: 16)
                seqState.save()
            } label: {
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

    // MARK: – 4×4 Grid

    private var stepGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(0..<16, id: \.self) { idx in
                stepCell(idx)
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

    private var stepEditor: some View {
        let idx  = seqState.selectedStep
        let step = seqState.steps[idx]

        return VStack(alignment: .leading, spacing: 10) {
            Text("STEP \(idx + 1)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(white: 0.4))
                .kerning(2)

            // Degree picker
            let degrees: [(Degree, String)] = [
                (.I, "I"), (.ii, "ii"), (.iii, "iii"), (.IV, "IV"),
                (.V, "V"), (.vi, "vi"), (.viiDim, "vii°")
            ]
            HStack(spacing: 5) {
                ForEach(degrees, id: \.0) { degree, label in
                    Button {
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

            // Direction picker (3×3 joystick grid) + Rest toggle
            HStack(alignment: .top, spacing: 12) {
                directionPicker(idx: idx, step: step)

                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: Binding(
                        get: { seqState.steps[idx].isRest },
                        set: { seqState.steps[idx].isRest = $0; seqState.save() }
                    )) {
                        Text("Rest")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Color(white: 0.7))
                    }
                    .toggleStyle(SwitchToggleStyle(tint: .orange))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Gate \(Int(seqState.steps[idx].gate * 100))%")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Color(white: 0.4))
                        Slider(value: Binding(
                            get: { seqState.steps[idx].gate },
                            set: { seqState.steps[idx].gate = $0; seqState.save() }
                        ), in: 0.1...1.0)
                        .tint(.orange)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.07)))
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
