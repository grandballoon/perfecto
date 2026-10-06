import SwiftUI
import UIKit

struct PerformanceView: View {
    @Environment(PerformanceState.self) private var state

    /// The menu. Its panel lies over part of this screen, and whatever stays
    /// visible beside it stays playable.
    @State private var sidePanel = SidePanelState()

    private let topRow:    [(Degree, Color)] = [
        (.I, .orange),
        (.ii, .orange),
        (.iii, .orange),
        (.IV, .orange),
    ]
    private let bottomRow: [(Degree, Color)] = [
        (.V, .orange),
        (.vi, .orange),
        (.viiDim, .orange),
    ]

    /// Landscape panels' inset from the screen edges and from each other.
    private static let edgeMargin: CGFloat = 16
    private static let midiChitWidth: CGFloat = 64

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

                SidePanel(containerWidth: geo.size.width)

                // On top of the panel, so the same spot opens and closes it.
                SidePanelButton()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.leading, SidePanelLayout.buttonLeading)
                    .padding(.top, SidePanelLayout.buttonTop)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .environment(sidePanel)
    }

    // MARK: – Portrait layout

    private var portraitLayout: some View {
        VStack(spacing: 0) {
            // The OLED shares the top row with the menu button, inset past
            // it and top-aligned with it.
            oledDisplay
                .padding(.leading, 66)
                .padding(.trailing, 24)
                .padding(.top, 12)

            // The chits sit a uniform distance below the note display in every
            // mode: play/lead/etc. anchor them here (a single Spacer below pushes
            // the input strip to the bottom), and the full-screen modes get the
            // same gap instead of butting straight against the OLED.
            functionButtons
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

            if state.mode.kind.surface == .sequencer {
                SequencerView()
                    .environment(state.sequencerState)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
            } else if state.mode.kind.surface == .looper {
                LooperView()
                    .environment(state.looperState)
                    .padding(.top, 8)
            } else {
                LoopBar()
                    .padding(.horizontal, 20)

                if state.mode.kind.surface == .micSample {
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

                // Bottom input: the joystick strip or the chord grid
                ColorSurfaceView()
                    .environment(state)
                    .frame(height: ColorSurfaceView.portraitHeight(state.colorSurface))
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 40)
            }
        }
    }

    // MARK: – Landscape layout

    @ViewBuilder
    private func landscapeLayout(geo: GeometryProxy) -> some View {
        if state.mode.kind.surface == .sequencer {
            // Sequencer owns the whole screen in landscape and lays out its own
            // two-column editor/grid. No split panel.
            SequencerView()
                .environment(state.sequencerState)
                .frame(width: geo.size.width, height: geo.size.height)
        } else {
        HStack(spacing: 0) {
                let isFullScreenMode = state.mode.kind.surface == .looper
                // With the horizontal chord row, the joystick bar stands
                // upright along the leading edge so the row can take the
                // width a half-screen bar would have used.
                let barIsVertical = state.chordGridLayout == .horizontalBar
                    && state.colorSurface == .joystick
                    && !isFullScreenMode
                let leftW = barIsVertical
                    ? Self.edgeMargin + ColorSurfaceView.barThickness
                    : geo.size.width / 2
                let panelH = geo.size.height

                if barIsVertical {
                    // Left panel: the upright bar, starting below the
                    // menu button. Its trailing gap is the right panel's
                    // own leading margin.
                    ColorSurfaceView(barAxis: .vertical)
                        .environment(state)
                        .padding(.leading, Self.edgeMargin)
                        .padding(.top, SidePanelLayout.buttonTop + SidePanelLayout.buttonSize + 8)
                        .padding(.bottom, Self.edgeMargin)
                        .frame(width: leftW, height: panelH)
                } else {
                    // Left panel: input control. The coloration bar stays
                    // horizontal here (as in portrait) and keeps the same
                    // thickness; the chord grid fills the panel. Both sit at
                    // the bottom so their lower margin lines up with the
                    // function buttons in the right panel.
                    VStack(spacing: 8) {
                        Spacer(minLength: 0)
                        if !isFullScreenMode {
                            ColorSurfaceView()
                                .environment(state)
                                .frame(maxWidth: .infinity)
                                .frame(maxHeight: state.colorSurface == .grid
                                       ? .infinity : ColorSurfaceView.barThickness)
                        }
                    }
                    .padding(Self.edgeMargin)
                    .frame(width: leftW, height: panelH)
                }

                // Right panel: OLED + chord grid + function buttons
                VStack(spacing: 0) {
                    if state.mode.kind.surface == .looper {
                        LooperView()
                            .environment(state.looperState)
                    } else {
                        oledDisplay
                            .padding(.bottom, 8)
                        LoopBar()
                            .padding(.bottom, 8)
                        if state.mode.kind.surface == .micSample {
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
                .padding(Self.edgeMargin)
                .frame(width: geo.size.width - leftW, height: panelH)
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

    /// The mode toggle takes the row; MIDI keeps to a narrow fixed width.
    private var functionButtons: some View {
        @Bindable var state = state
        return HStack(spacing: 10) {
            modeSegToggle
            toggleButton(label: "MIDI", isOn: $state.isExternalSynth)
                .frame(width: Self.midiChitWidth)
        }
    }

    // MARK: – Mode: inline Play / Sequencer toggle (replaces the Mode sheet)

    private var modeSegToggle: some View {
        HStack(spacing: 3) {
            modeSegButton(label: "PLAY", active: state.mode.kind == .play) {
                state.selectMode(.play)
            }
            modeSegButton(label: "SEQ", active: state.mode.kind == .sequencer) {
                state.selectMode(.sequencer)
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

    private var chordGrid: some View {
        ChordKeySurface {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    ForEach(topRow, id: \.0) { degree, color in
                        ChordButton(degree: degree, label: degreeNumeral(key: state.key, degree: degree), color: color)
                    }
                }
                HStack(spacing: 10) {
                    ForEach(bottomRow, id: \.0) { degree, color in
                        ChordButton(degree: degree, label: degreeNumeral(key: state.key, degree: degree), color: color)
                    }
                    Spacer()
                }
            }
        }
    }

    // MARK: – Helpers

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

