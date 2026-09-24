import SwiftUI
import UIKit

struct PerformanceView: View {
    @Environment(PerformanceState.self) private var state

    @State private var showKeySheet      = false
    @State private var showSettingsSheet = false

    @State private var keyQuick = KeyQuickController()
    @State private var keyButtonCenter: CGPoint = .zero

    private let topRow:    [(Degree, String, Color)] = [
        (.I,   "I",    .orange),
        (.ii,  "ii",   .orange),
        (.iii, "iii",  .orange),
        (.IV,  "IV",   .orange),
    ]
    private let bottomRow: [(Degree, String, Color)] = [
        (.V,      "V",    .orange),
        (.vi,     "vi",   .orange),
        (.viiDim, "vii°", .orange),
    ]

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height
            ZStack {
                Color.black.ignoresSafeArea()
                if isLandscape {
                    landscapeLayout(geo: geo)
                } else {
                    portraitLayout
                }

                settingsButton
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.leading, 16)
                    .padding(.top, 12)

                if keyQuick.isActive {
                    KeyQuickSelectOverlay(controller: keyQuick)
                        .allowsHitTesting(false)
                }
            }
            .coordinateSpace(.named("perf"))
        }
        .ignoresSafeArea(edges: .bottom)
        .sheet(isPresented: $showKeySheet)      { KeySheet().environment(state) }
        .sheet(isPresented: $showSettingsSheet) { SettingsSheet().environment(state) }
    }

    private var settingsButton: some View {
        Button { showSettingsSheet = true } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color(white: 0.6))
                .frame(width: 38, height: 38)
                .background(
                    Circle()
                        .fill(Color(white: 0.13))
                        .overlay(Circle().stroke(Color(white: 0.25), lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: – Portrait layout

    private var portraitLayout: some View {
        VStack(spacing: 0) {
            statusColumn(label: "KEY",
                         value: "\(state.key.root.name) \(state.key.scale.displayName)")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 66)
                .padding(.trailing, 24)
                .padding(.top, 16)

            oledDisplay
                .padding(.horizontal, 24)
                .padding(.top, 16)

            // The chits sit a uniform distance below the note display in every
            // mode: play/lead/etc. anchor them here (a single Spacer below pushes
            // the input strip to the bottom), and the full-screen modes get the
            // same gap instead of butting straight against the OLED.
            functionButtons
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

            if state.mode.name == "Sequencer" {
                SequencerView()
                    .environment(state.sequencerState)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
            } else if state.mode.name == "Looper" {
                LooperView()
                    .environment(state.looperState)
                    .padding(.top, 8)
            } else {
                if state.mode.name == "Mic Sample" {
                    MicSampleView()
                        .environment(state)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                }
                // Push the chord ring toward the bottom so it falls under the
                // thumb when the phone is held normally, rather than sitting
                // high under the function buttons.
                Spacer()

                if state.chordGridLayout == .circle {
                    CircleChordGridView()
                        .environment(state)
                        .padding(.horizontal, 20)
                } else {
                    chordGrid
                        .padding(.horizontal, 20)
                }

                // Bottom input strip
                ChordBarView(axis: .horizontal)
                    .environment(state)
                    .frame(height: 88)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 40)
            }
        }
    }

    // MARK: – Landscape layout

    @ViewBuilder
    private func landscapeLayout(geo: GeometryProxy) -> some View {
        if state.mode.name == "Sequencer" {
            // Sequencer owns the whole screen in landscape and lays out its own
            // two-column editor/grid. No split panel.
            SequencerView()
                .environment(state.sequencerState)
                .frame(width: geo.size.width, height: geo.size.height)
        } else {
        HStack(spacing: 0) {
                let panelW = geo.size.width / 2
                let panelH = geo.size.height

                // Left panel: input control. The coloration bar stays
                // horizontal here (as in portrait) and keeps the same 88pt
                // height. It sits at the bottom so its lower margin lines up
                // with the function buttons in the right panel.
                let isFullScreenMode = state.mode.name == "Looper"
                VStack(spacing: 8) {
                    Spacer(minLength: 0)
                    if !isFullScreenMode {
                        ChordBarView(axis: .horizontal)
                            .environment(state)
                            .frame(maxWidth: .infinity)
                            .frame(height: 88)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .frame(width: panelW, height: panelH)

                // Right panel: OLED + chord grid + function buttons
                VStack(spacing: 0) {
                    if state.mode.name == "Looper" {
                        LooperView()
                            .environment(state.looperState)
                    } else {
                        oledDisplay
                            .padding(.bottom, 8)
                        if state.mode.name == "Mic Sample" {
                            MicSampleView()
                                .environment(state)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 8)
                        }
                        switch state.chordGridLayout {
                        case .horizontalBar:
                            ChordRowView()
                                .environment(state)
                                .frame(maxHeight: .infinity)
                                .padding(.vertical, 8)
                        case .circle:
                            CircleChordGridView()
                                .environment(state)
                                .padding(.vertical, 8)
                        case .grid:
                            Spacer()
                            chordGrid
                            Spacer()
                        }
                        functionButtons
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .frame(width: panelW, height: panelH)
        }
        }
    }

    // MARK: – Shared subviews

    private var oledDisplay: some View {
        Text(state.activeVoicingText)
            .font(.system(size: 14, weight: .medium, design: .monospaced))
            .foregroundStyle(Color(red: 1, green: 0.65, blue: 0))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(white: 0.05))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(white: 0.15), lineWidth: 1))
            )
            .onLongPressGesture(minimumDuration: 3) { shareLogs() }
    }

    private var functionButtons: some View {
        @Bindable var state = state
        return HStack(spacing: 10) {
            keyQuickButton
            modeSegToggle
            toggleButton(label: "MIDI", isOn: $state.isExternalSynth)
        }
    }

    // MARK: – Mode: inline Play / Sequencer toggle (replaces the Mode sheet)

    private var modeSegToggle: some View {
        HStack(spacing: 3) {
            modeSegButton(label: "PLAY", active: state.mode.name == "Play") {
                if state.mode.name != "Play" { state.setMode(PlayMode()) }
            }
            modeSegButton(label: "SEQ", active: state.mode.name == "Sequencer") {
                if state.mode.name != "Sequencer" { state.setMode(SequencerMode(state.sequencerState)) }
            }
        }
        .padding(3)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(white: 0.09))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(white: 0.25), lineWidth: 1))
        )
    }

    private func modeSegButton(label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(active ? Color.black : Color(white: 0.7))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 6).fill(active ? Color.orange : Color.clear))
        }
        .buttonStyle(.plain)
    }

    // MARK: – KEY button: tap opens the sheet, press-and-hold quick-selects

    private var keyQuickButton: some View {
        functionButton(label: "KEY") { showKeySheet = true }
            .background(
                GeometryReader { g in
                    Color.clear
                        .onAppear { updateKeyCenter(g) }
                        .onChange(of: g.frame(in: .named("perf"))) { updateKeyCenter(g) }
                }
            )
            .highPriorityGesture(keyQuickGesture)
    }

    private var keyQuickGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.22)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("perf")))
            .onChanged { value in
                if case .second(true, let drag) = value {
                    if !keyQuick.isActive {
                        keyQuick.begin(at: keyButtonCenter,
                                       key: state.key,
                                       style: state.keyQuickStyle)
                    }
                    if let drag { keyQuick.update(location: drag.location) }
                }
            }
            .onEnded { _ in
                if keyQuick.isActive, let newKey = keyQuick.end() {
                    state.key = newKey
                }
            }
    }

    private func updateKeyCenter(_ g: GeometryProxy) {
        let f = g.frame(in: .named("perf"))
        keyButtonCenter = CGPoint(x: f.midX, y: f.midY)
    }

    private var chordGrid: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                ForEach(topRow, id: \.0) { degree, label, color in
                    ChordButton(degree: degree, label: label, color: color)
                }
            }
            HStack(spacing: 10) {
                ForEach(bottomRow, id: \.0) { degree, label, color in
                    ChordButton(degree: degree, label: label, color: color)
                }
                Spacer()
            }
        }
    }

    // MARK: – Quick loop panel (landscape only)

    private var loopControlColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            loopTriggerButton
            loopDots
        }
    }

    private var loopTriggerButton: some View {
        Button { state.quickLoopState.triggerTapped() } label: {
            loopTriggerLabel
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(white: 0.13))
                        .overlay(RoundedRectangle(cornerRadius: 6)
                            .stroke(loopTriggerStroke, lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
        .disabled(state.quickLoopState.phase == .idle && !state.quickLoopState.canStartNew)
    }

    @ViewBuilder
    private var loopTriggerLabel: some View {
        switch state.quickLoopState.phase {
        case .idle:
            Text("● LOOP")
                .foregroundStyle(
                    state.quickLoopState.canStartNew ? Color(white: 0.7) : Color(white: 0.3)
                )
        case .recording:
            Text("■ STOP")
                .foregroundStyle(Color.red)
        }
    }

    private var loopTriggerStroke: Color {
        switch state.quickLoopState.phase {
        case .idle:      return state.quickLoopState.canStartNew ? Color(white: 0.28) : Color(white: 0.15)
        case .recording: return Color.red.opacity(0.5)
        }
    }

    private var loopDots: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(state.quickLoopState.loops) { loop in
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 10, height: 10)
                    Button {
                        state.quickLoopState.removeLoop(id: loop.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(Color(white: 0.5))
                            .frame(width: 20, height: 20)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color(white: 0.12))
                            )
                    }
                    .buttonStyle(.plain)
                    Button {
                        state.quickLoopState.togglePlayback(id: loop.id)
                    } label: {
                        Image(systemName: loop.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(loop.isPlaying ? Color.green : Color(white: 0.45))
                            .frame(width: 50, height: 20)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color(white: 0.12))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: – Helpers

    private func statusColumn(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(white: 0.32))
                .kerning(1.5)
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(white: 0.6))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func toggleButton(label: String, isOn: Binding<Bool>) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            Text(label)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(isOn.wrappedValue ? Color.black : Color(white: 0.85))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isOn.wrappedValue ? Color.orange : Color(white: 0.13))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isOn.wrappedValue ? Color.orange : Color(white: 0.25),
                                        lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private func functionButton(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(white: 0.85))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(white: 0.13))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(white: 0.25), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
    }
}

extension Degree: Identifiable {
    public var id: Int { rawValue }
}

// MARK: – Send Logs

extension PerformanceView {
    private func shareLogs() {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("perfecto.log")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let ac = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.rootViewController?
            .present(ac, animated: true)
    }
}

