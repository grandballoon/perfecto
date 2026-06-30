import SwiftUI
import UIKit

private enum InputViewMode: CaseIterable {
    case joystick, ring, bar
    var label: String {
        switch self {
        case .joystick: return "PAD"
        case .ring:     return "RING"
        case .bar:      return "BAR"
        }
    }
    var next: InputViewMode {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

struct PerformanceView: View {
    @Environment(PerformanceState.self) private var state

    @State private var showKeySheet      = false
    @State private var showSoundSheet    = false
    @State private var showModeSheet     = false
    @State private var showSettingsSheet = false
    @State private var inputViewMode: InputViewMode = .joystick

    private let topRow:    [(Degree, String, Color)] = [
        (.I,   "I",    .orange),
        (.ii,  "ii",   .blue),
        (.iii, "iii",  .indigo),
        (.IV,  "IV",   .orange),
    ]
    private let bottomRow: [(Degree, String, Color)] = [
        (.V,      "V",    .orange),
        (.vi,     "vi",   .blue),
        (.viiDim, "vii°", .purple),
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
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(.leading, 16)
                    .padding(.bottom, 20)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .sheet(isPresented: $showKeySheet)      { KeySheet().environment(state) }
        .sheet(isPresented: $showSoundSheet)    { SoundSheet().environment(state) }
        .sheet(isPresented: $showModeSheet)     { ModeSheet().environment(state) }
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
            HStack(alignment: .top, spacing: 0) {
                statusColumn(label: "KEY",
                             value: "\(state.key.root.name) \(state.key.scale.displayName)")
                Spacer()
                statusColumn(label: "SOUND", value: state.synthPreset.name)
                Spacer()
                statusColumn(label: "MODE",  value: state.mode.name)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            oledDisplay
                .padding(.horizontal, 24)
                .padding(.top, 16)

            let isFullScreenMode = state.mode.name == "Sequencer"
                                || state.mode.name == "Looper"
            if !isFullScreenMode { Spacer() }

            functionButtons
                .padding(.horizontal, 20)
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
                chordGrid
                    .padding(.horizontal, 20)

                Spacer()

                // Bottom input strip
                switch inputViewMode {
                case .bar:
                    HStack(spacing: 8) {
                        ChordBarView(axis: .horizontal)
                            .environment(state)
                            .frame(height: 88)
                        modeToggle
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                case .joystick:
                    HStack(alignment: .center, spacing: 0) {
                        JoystickView()
                            .padding(.leading, 28)
                        Spacer()
                        modeToggle
                            .padding(.trailing, 20)
                    }
                    .padding(.bottom, 40)
                case .ring:
                    HStack(alignment: .center, spacing: 0) {
                        RingView()
                            .environment(state)
                            .padding(.leading, 28)
                        Spacer()
                        modeToggle
                            .padding(.trailing, 20)
                    }
                    .padding(.bottom, 40)
                }
            }
        }
    }

    // MARK: – Landscape layout

    private func landscapeLayout(geo: GeometryProxy) -> some View {
        HStack(spacing: 0) {
                let panelW = geo.size.width / 2
                let panelH = geo.size.height
                let circleRadius = min(panelW * 0.40, panelH * 0.35)

                // Left panel: input control
                let isFullScreenMode = state.mode.name == "Sequencer" || state.mode.name == "Looper"
                VStack(spacing: 8) {
                    if isFullScreenMode {
                        modeToggle
                    } else {
                        HStack(alignment: .top, spacing: 8) {
                            loopControlColumn
                            Spacer()
                            modeToggle
                        }
                        .padding(.horizontal, 16)

                        switch inputViewMode {
                        case .bar:
                            ChordBarView(axis: .vertical)
                                .environment(state)
                                .frame(maxWidth: panelW * 0.55, maxHeight: .infinity)
                        case .joystick:
                            Spacer()
                            JoystickView(outerRadius: circleRadius)
                            Spacer()
                        case .ring:
                            Spacer()
                            RingView(outerRadius: circleRadius)
                                .environment(state)
                            Spacer()
                        }
                    }
                }
                .padding(.vertical, 16)
                .frame(width: panelW, height: panelH)

                // Right panel: OLED + chord grid + function buttons
                VStack(spacing: 0) {
                    if state.mode.name == "Sequencer" {
                        SequencerView()
                            .environment(state.sequencerState)
                    } else if state.mode.name == "Looper" {
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
                        if state.horizontalLandscapeChords {
                            ChordRowView()
                                .environment(state)
                                .frame(maxHeight: .infinity)
                                .padding(.vertical, 8)
                        } else {
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

    // MARK: – Shared subviews

    private var modeToggle: some View {
        Button { inputViewMode = inputViewMode.next } label: {
            Text(inputViewMode.label)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(white: 0.7))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(white: 0.13))
                        .overlay(RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(white: 0.28), lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
    }

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
            functionButton(label: "KEY")   { showKeySheet   = true }
            functionButton(label: "SOUND") { showSoundSheet = true }
            functionButton(label: "MODE")  { showModeSheet  = true }
            toggleButton(label: "MIDI", isOn: $state.isExternalSynth)
        }
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

