import SwiftUI

/// Play mode's loop controls, in one row.
///
/// LOOP offers the lengths a loop can be, each with the seconds it lasts at
/// the tempo set. Choosing one counts in for three seconds on the button,
/// which pulses and taps the hand at each, and then records: the button
/// turns red and drains as the take runs out, and the take plays the moment
/// it ends. LOOP calls off a take counting in or recording. The layers are
/// the timeline's, so a sequence made in the sequencer is among them. The
/// play/stop chit stops them all, and starts them again from the top. Every
/// layer gets a numbered chit: tap it to pause or resume that layer. The
/// trash chit switches the layer chits to deleting: they turn red with an
/// X, and tapping one removes its layer. A tap anywhere else on the screen
/// puts the lengths away and stops deleting (`closingLoopBar`).
struct LoopBar: View {
    @Environment(PerformanceState.self) private var state

    private static let chitHeight:   CGFloat = 34
    private static let loopWidth:    CGFloat = 76
    private static let layerWidth:   CGFloat = 26
    private static let lengthWidth:  CGFloat = 52

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                loopButton
                if loops.phase == .choosing {
                    lengthChits
                } else if !loops.loops.isEmpty {
                    runButton
                    layerChits
                }
            }
            .loopBarBounds(isOpen: loops.isDeleting || loops.phase == .choosing)
            Spacer(minLength: 0)
        }
        .animation(.easeOut(duration: 0.15), value: loops.phase == .choosing)
        .animation(.easeOut(duration: 0.15), value: loops.isDeleting)
        .sensoryFeedback(trigger: loops.cue) { _, cue in cue.map(Self.feedback) }
    }

    private var loops: QuickLoopState { state.quickLoopState }

    /// What each moment of a take feels like.
    private static func feedback(_ cue: LoopCue) -> SensoryFeedback {
        switch cue {
        case .count:   .impact(weight: .medium, intensity: 0.8)
        case .go:      .impact(weight: .heavy, intensity: 1)
        case .done:    .success
        case .dropped: .warning
        }
    }

    // MARK: – Loop

    private var canRecord: Bool { loops.phase != .idle || loops.canStartNew }

    private var loopButton: some View {
        let glow = pulseColor
        return Button { loops.triggerTapped() } label: {
            loopLabel
                .frame(width: Self.loopWidth, height: Self.chitHeight)
                .keyframeAnimator(initialValue: Pulse(), trigger: loops.cue) { label, pulse in
                    label
                        .scaleEffect(pulse.scale)
                        .shadow(color: glow.opacity(pulse.glow), radius: 10)
                } keyframes: { _ in
                    KeyframeTrack(\.scale) {
                        CubicKeyframe(1.12, duration: 0.07)
                        SpringKeyframe(1, duration: 0.45, spring: .bouncy)
                    }
                    KeyframeTrack(\.glow) {
                        LinearKeyframe(1, duration: 0.05)
                        CubicKeyframe(0, duration: 0.7)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(!canRecord)
        .hotkeyTip(.loop)
        .accessibilityLabel(loopAccessibilityLabel)
    }

    @ViewBuilder
    private var loopLabel: some View {
        switch loops.phase {
        case .idle:
            Text("● LOOP")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(loops.canStartNew ? Color(white: 0.85) : Color(white: 0.3))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(chit(stroke: Color(white: 0.25)))
        case .choosing:
            Text("✕ LOOP")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(white: 0.85))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(chit(stroke: .orange))
        case let .countingIn(remaining):
            Text("\(remaining)")
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.orange)
                .contentTransition(.numericText(countsDown: true))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.orange.opacity(0.15))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.orange, lineWidth: 2))
                )
        case .recording:
            TimelineView(.animation) { _ in
                recordingLabel(loops.recordingProgress ?? (0, 0))
            }
        }
    }

    /// Red, and draining from the right as the take runs out, with the
    /// seconds left in it.
    private func recordingLabel(_ progress: (share: Double, secondsLeft: Double)) -> some View {
        Text(String(format: "● %.1f", progress.secondsLeft))
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(white: 0.13))
                    .overlay(alignment: .leading) {
                        GeometryReader { geo in
                            Rectangle()
                                .fill(Color.red)
                                .frame(width: geo.size.width * (1 - progress.share))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.red, lineWidth: 2))
            )
    }

    private var pulseColor: Color {
        if case .recording = loops.phase { return .red }
        return .orange
    }

    private var loopAccessibilityLabel: String {
        switch loops.phase {
        case .idle:                     "Loop"
        case .choosing:                 "Close loop lengths"
        case let .countingIn(remaining): "Counting in, \(remaining). Tap to cancel"
        case .recording:                "Recording loop. Tap to cancel"
        }
    }

    // MARK: – Lengths

    private var lengthChits: some View {
        HStack(spacing: 4) {
            ForEach(QuickLoopState.lengths, id: \.self) { bars in
                Button { loops.choose(bars: bars) } label: {
                    VStack(spacing: 1) {
                        Text(bars == 1 ? "1 BAR" : "\(bars) BARS")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color(white: 0.85))
                        Text(Self.secondsLabel(loops.seconds(ofBars: bars)))
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color(white: 0.5))
                    }
                    .frame(width: Self.lengthWidth, height: Self.chitHeight)
                    .background(chit(stroke: bars == loops.bars ? .orange : Color(white: 0.25)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Record \(bars == 1 ? "1 bar" : "\(bars) bars")")
            }
        }
        .transition(.opacity.combined(with: .move(edge: .leading)))
    }

    /// Seconds to a tenth under ten, and whole above.
    private static func secondsLabel(_ seconds: Double) -> String {
        seconds < 10 ? String(format: "%.1fs", seconds) : String(format: "%.0fs", seconds)
    }

    // MARK: – Layers

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
                Button { loops.loopTapped(id: loop.id) } label: {
                    layerLabel(number: index + 1, isPlaying: loop.isPlaying)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(layerAccessibilityLabel(number: index + 1, isPlaying: loop.isPlaying))
            }
            deleteToggle
        }
    }

    @ViewBuilder
    private func layerLabel(number: Int, isPlaying: Bool) -> some View {
        let fill: Color = loops.isDeleting ? .red : (isPlaying ? .orange : Color(white: 0.13))
        let stroke: Color = loops.isDeleting ? .red : (isPlaying ? .orange : Color(white: 0.25))
        let text: Color = loops.isDeleting ? .white : (isPlaying ? .black : Color(white: 0.5))
        Text("\(number)")
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
            .foregroundStyle(text)
            .frame(width: Self.layerWidth, height: Self.chitHeight)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(fill)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(stroke, lineWidth: 1))
            )
            .overlay(alignment: .topTrailing) {
                if loops.isDeleting {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white, Color(red: 0.55, green: 0, blue: 0))
                        .offset(x: 5, y: -5)
                        .transition(.scale.combined(with: .opacity))
                }
            }
    }

    private func layerAccessibilityLabel(number: Int, isPlaying: Bool) -> String {
        if loops.isDeleting { return "Delete loop \(number)" }
        return isPlaying ? "Pause loop \(number)" : "Resume loop \(number)"
    }

    /// Tap to switch deleting on and off; hold to clear every loop at once.
    private var deleteToggle: some View {
        Button { loops.toggleDeleting() } label: {
            Image(systemName: loops.isDeleting ? "trash.fill" : "trash")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(loops.isDeleting ? Color.red : Color(white: loops.isTaking ? 0.3 : 0.6))
                .frame(width: Self.layerWidth, height: Self.chitHeight)
                .background(chit(stroke: loops.isDeleting ? Color.red : Color(white: 0.25)))
        }
        .buttonStyle(.plain)
        .disabled(loops.isTaking)
        .accessibilityLabel(loops.isDeleting ? "Stop deleting loops" : "Delete loops")
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

/// The LOOP button's pulse: how much larger it is, and how bright its glow.
private struct Pulse {
    var scale: CGFloat = 1
    var glow: Double = 0
}

// MARK: – A tap elsewhere

/// Where the loop bar's controls are, while it is open: offering the
/// lengths, or deleting.
private struct LoopBarBoundsKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

extension View {
    fileprivate func loopBarBounds(isOpen: Bool) -> some View {
        anchorPreference(key: LoopBarBoundsKey.self, value: .bounds) { isOpen ? $0 : nil }
    }

    /// While the loop bar is open, a touch anywhere on the screen but its
    /// controls closes it (`QuickLoopState.dismiss`), and does nothing else:
    /// a chord key tapped then is not played. It goes on the screen as a
    /// whole.
    func closingLoopBar() -> some View {
        modifier(LoopBarClosing())
    }
}

private struct LoopBarClosing: ViewModifier {
    @Environment(PerformanceState.self) private var state

    func body(content: Content) -> some View {
        content.overlayPreferenceValue(LoopBarBoundsKey.self) { bounds in
            GeometryReader { geo in
                if let bounds {
                    Color.clear
                        .contentShape(Outside(hole: geo[bounds]), eoFill: true)
                        .gesture(DragGesture(minimumDistance: 0).onEnded { _ in
                            state.quickLoopState.dismiss()
                        })
                }
            }
            .ignoresSafeArea()
        }
    }

    /// Everything but `hole`.
    private struct Outside: Shape {
        let hole: CGRect

        func path(in rect: CGRect) -> Path {
            var path = Path(rect)
            path.addRect(hole)
            return path
        }
    }
}
