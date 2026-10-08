import SwiftUI
import UIKit

struct PerformanceView: View {
    @Environment(PerformanceState.self) private var state

    /// The menu. Its panel lies over part of this screen, and whatever stays
    /// visible beside it stays playable.
    @State private var sidePanel: SidePanelState

    /// `sidePanel` is the menu as the screen first shows it: closed, unless
    /// a screen is wanted with it already open (the UI spec's drawings).
    init(sidePanel: SidePanelState = SidePanelState()) {
        _sidePanel = State(initialValue: sidePanel)
    }

    /// Landscape panels' inset from the screen edges and from each other.
    private static let edgeMargin: CGFloat = 16
    private static let midiChitWidth: CGFloat = 64
    /// The solo strip's width where it stands upright beside the chord keys.
    private static let soloRibbonWidth: CGFloat = 64

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height
            ZStack {
                Color.black.ignoresSafeArea()
                if isLandscape {
                    landscapeLayout(geo: geo)
                } else {
                    portraitLayout(geo: geo)
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

    private func portraitLayout(geo: GeometryProxy) -> some View {
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
            } else {
                LoopBar()
                    .padding(.horizontal, 20)

                // Push the chord ring toward the bottom so it falls under the
                // thumb when the phone is held normally, rather than sitting
                // high under the function buttons.
                Spacer()

                keysAndSolo(state.chordGridLayout.arrangement(isLandscape: false),
                            screenHeight: geo.size.height)
                    .padding(.horizontal, 20)

                // Bottom input: the chord colors or the effect slider
                PlaySurfaceView()
                    .environment(state)
                    .frame(height: state.surfaceShape.portraitHeight)
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
                // With the horizontal chord row, a bar stands upright along
                // the leading edge so the row can take the width a
                // half-screen bar would have used.
                let barIsVertical = state.chordGridLayout == .horizontalBar
                    && state.surfaceShape == .bar
                let leftW = barIsVertical
                    ? Self.edgeMargin + SurfaceShape.barThickness
                    : geo.size.width / 2
                let panelH = geo.size.height
                // A panel of its own for the play surface has room to
                // spare above it, which the solo strip takes before the
                // chord keys have to give anything up.
                let soloInPanel = !barIsVertical && state.solo.placementByKeys != nil

                if barIsVertical {
                    // Left panel: the upright bar, starting below the
                    // menu button. Its trailing gap is the right panel's
                    // own leading margin.
                    PlaySurfaceView(barAxis: .vertical)
                        .environment(state)
                        .padding(.leading, Self.edgeMargin)
                        .padding(.top, SidePanelLayout.buttonTop + SidePanelLayout.buttonSize + 8)
                        .padding(.bottom, Self.edgeMargin)
                        .frame(width: leftW, height: panelH)
                } else {
                    // Left panel: input control. A bar stays horizontal
                    // here (as in portrait) and keeps the same thickness;
                    // a grid fills the panel. Both sit at
                    // the bottom so their lower margin lines up with the
                    // function buttons in the right panel.
                    VStack(spacing: 8) {
                        if soloInPanel {
                            // Starting below the menu button.
                            SoloStripView(axis: .horizontal)
                                .padding(.top, SidePanelLayout.buttonTop + SidePanelLayout.buttonSize + 8
                                         - Self.edgeMargin)
                        } else {
                            Spacer(minLength: 0)
                        }
                        PlaySurfaceView()
                            .environment(state)
                            .frame(maxWidth: .infinity)
                            .frame(maxHeight: state.surfaceShape == .grid
                                   ? .infinity : SurfaceShape.barThickness)
                    }
                    .padding(Self.edgeMargin)
                    .frame(width: leftW, height: panelH)
                }

                // Right panel: OLED + chord grid + function buttons
                VStack(spacing: 0) {
                    oledDisplay
                        .padding(.bottom, 8)
                    LoopBar()
                        .padding(.bottom, 8)
                    let arrangement = state.chordGridLayout.arrangement(isLandscape: true)
                    switch arrangement {
                    case .row, .circle:
                        keysAndSolo(arrangement, screenHeight: panelH, soloIsElsewhere: soloInPanel)
                            .padding(.vertical, 8)
                    case .grid:
                        Spacer()
                        keysAndSolo(arrangement, screenHeight: panelH, soloIsElsewhere: soloInPanel)
                        Spacer()
                    }
                    functionButtons
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

    /// The mode toggle takes the row; SOLO and MIDI keep to a narrow fixed width.
    private var functionButtons: some View {
        @Bindable var state = state
        @Bindable var solo = state.solo
        return HStack(spacing: 10) {
            modeSegToggle
            toggleButton(label: "SOLO", isOn: $solo.isOn)
                .frame(width: Self.midiChitWidth)
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

    /// The chord keys, played: pressed as the fingers on them are.
    private func chordKeys(_ arrangement: ChordKeyArrangement) -> some View {
        ChordKeySurface {
            ChordKeysView(arrangement: arrangement, key: state.key, lit: state.heldDegrees)
        }
    }

    /// The chord keys, and the solo strip where it is by them: under them,
    /// across the handle that sets how much of their height it takes, or
    /// upright along their trailing edge. `soloIsElsewhere` says the screen
    /// has found the strip room of its own.
    @ViewBuilder
    private func keysAndSolo(_ arrangement: ChordKeyArrangement, screenHeight: CGFloat,
                             soloIsElsewhere: Bool = false) -> some View {
        switch soloIsElsewhere ? nil : state.solo.placementByKeys {
        case .underKeys?:
            VStack(spacing: 0) {
                chordKeys(arrangement)
                SoloStripHandle(screenHeight: screenHeight)
                SoloStripView(axis: .horizontal)
                    .frame(height: screenHeight * state.solo.share)
            }
        case .besideKeys?:
            HStack(spacing: 10) {
                chordKeys(arrangement)
                SoloStripView(axis: .vertical)
                    .frame(width: Self.soloRibbonWidth)
            }
        default:
            chordKeys(arrangement)
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

