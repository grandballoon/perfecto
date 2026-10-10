import SwiftUI

/// Play mode's loop controls, in one row.
///
/// LOOP starts a take and, tapped again, closes it into a loop; each further
/// take is layered onto the first loop's length. The layers are the
/// timeline's, so a sequence made in the sequencer is among them. The
/// play/stop chit stops them all, and starts them again from the top. Every
/// layer gets a numbered chit: tap it to silence or bring back that layer.
/// The trash chit switches the layer chits to deleting: while it is on,
/// tapping a layer removes it.
struct LoopBar: View {
    @Environment(PerformanceState.self) private var state

    /// While on, tapping a layer chit deletes that layer.
    @State private var isDeleting = false

    private static let chitHeight: CGFloat = 34
    private static let loopWidth:  CGFloat = 76
    private static let layerWidth: CGFloat = 26

    var body: some View {
        HStack(spacing: 10) {
            loopButton
            if !loops.loops.isEmpty {
                runButton
                layerChits
            }
            Spacer(minLength: 0)
        }
        .onChange(of: loops.loops.isEmpty) { _, isEmpty in
            if isEmpty { isDeleting = false }
        }
    }

    private var loops: QuickLoopState { state.quickLoopState }

    // MARK: – Loop

    private var isRecording: Bool { loops.phase == .recording }
    private var canRecord: Bool { isRecording || loops.canStartNew }

    private var loopButton: some View {
        Button { loops.triggerTapped() } label: {
            Text(isRecording ? "■ STOP" : "● LOOP")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(loopLabelColor)
                .frame(width: Self.loopWidth, height: Self.chitHeight)
                .background(chit(stroke: isRecording ? Color.red : Color(white: 0.25)))
        }
        .buttonStyle(.plain)
        .disabled(!canRecord)
        .hotkeyTip(.loop)
    }

    private var loopLabelColor: Color {
        if isRecording { return .red }
        return canRecord ? Color(white: 0.85) : Color(white: 0.3)
    }

    /// Stops every layer, or starts them again from the top.
    private var runButton: some View {
        Button { loops.toggleRunning() } label: {
            Image(systemName: loops.isRunning ? "stop.fill" : "play.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(loops.isRunning ? Color.orange : Color(white: 0.85))
                .frame(width: Self.layerWidth, height: Self.chitHeight)
                .background(chit(stroke: loops.isRunning ? Color.orange : Color(white: 0.25)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(loops.isRunning ? "Stop loops" : "Play loops")
        .hotkeyTip(.playStop)
    }

    private var layerChits: some View {
        HStack(spacing: 4) {
            ForEach(Array(loops.loops.enumerated()), id: \.element.id) { index, loop in
                Button {
                    if isDeleting {
                        loops.removeLoop(id: loop.id)
                    } else {
                        loops.togglePlayback(id: loop.id)
                    }
                } label: {
                    layerLabel(number: index + 1, isPlaying: loop.isPlaying)
                }
                .buttonStyle(.plain)
            }
            deleteToggle
        }
    }

    @ViewBuilder
    private func layerLabel(number: Int, isPlaying: Bool) -> some View {
        let fill: Color = isDeleting ? Color(white: 0.13) : (isPlaying ? .orange : Color(white: 0.13))
        let stroke: Color = isDeleting ? .red : (isPlaying ? .orange : Color(white: 0.25))
        let text: Color = isDeleting ? .red : (isPlaying ? .black : Color(white: 0.5))
        Text("\(number)")
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
            .foregroundStyle(text)
            .frame(width: Self.layerWidth, height: Self.chitHeight)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(fill)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(stroke, lineWidth: 1))
            )
    }

    /// Tap to switch deleting on and off; hold to clear every loop at once.
    private var deleteToggle: some View {
        Button { isDeleting.toggle() } label: {
            Image(systemName: isDeleting ? "trash.fill" : "trash")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isDeleting ? Color.red : Color(white: 0.6))
                .frame(width: Self.layerWidth, height: Self.chitHeight)
                .background(chit(stroke: isDeleting ? Color.red : Color(white: 0.25)))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) { loops.clearAll() } label: {
                Label("Clear All Loops", systemImage: "xmark.circle")
            }
        }
    }

    private func chit(stroke: Color) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color(white: 0.13))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(stroke, lineWidth: 1))
    }
}
