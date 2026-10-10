import SwiftUI
import UIKit

/// The desk's arrangement: a window with room for it shows the keys and the
/// sequencer side by side, and the menu as a column beside them. The
/// Tonnetz takes the sequencer's place when it is chosen (`DeskPane`).
///
/// It is the phone's own screens put next to one another, chosen by one
/// threshold, and nothing else is built on it: the layout as a whole is to
/// be thought through again.
enum DeskLayout {
    /// The smallest window that is laid out this way. A phone on its side
    /// is narrower.
    static let minimumSize = CGSize(width: 1100, height: 640)
    /// The width of the keys' column: about a phone's, upright.
    static let playWidth: CGFloat = 420

    static func fits(_ size: CGSize) -> Bool {
        size.width >= minimumSize.width && size.height >= minimumSize.height
    }
}

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
    /// The screen's toggle where it shares a row with a screen's controls.
    private static let landscapeToggleWidth: CGFloat = 210
    /// The solo strip's width where it stands upright beside the chord keys.
    private static let soloRibbonWidth: CGFloat = 64

    var body: some View {
        // The piano, while it is shown, is the bottom of the window from
        // edge to edge, and the screen is laid out in what is left above it.
        GeometryReader { window in
            VStack(spacing: 0) {
                screen
                if state.piano.isOn {
                    PianoView()
                        .frame(height: PianoKeys.height(forWidth: window.size.width))
                        .padding(.bottom, window.safeAreaInsets.bottom)
                        .background(Color.black)
                }
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .showingHotkeyTips()
        .background(KeyboardInput(keyboard: state.keyboard))
        .environment(sidePanel)
    }

    private var screen: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height
            let isDesk = DeskLayout.fits(geo.size)
            ZStack {
                Color.black.ignoresSafeArea()
                if isDesk {
                    deskLayout(geo: geo)
                } else if isLandscape {
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
            // With the sequencer always in view the keys are always played,
            // so there is no sequencer mode to be in.
            .onChange(of: isDesk, initial: true) {
                state.isAtDesk = isDesk
                if isDesk { state.selectMode(.play) }
            }
        }
    }

    // MARK: – Desk layout

    /// The keys' column as a phone held upright shows it, and the sequencer
    /// or the Tonnetz in the rest of the window. The menu, while it is open,
    /// lies over a column of its own, so it covers nothing.
    private func deskLayout(geo: GeometryProxy) -> some View {
        let menuWidth = sidePanel.isOpen ? SidePanelLayout.width(in: geo.size.width) : 0
        let paneWidth = geo.size.width - menuWidth - DeskLayout.playWidth - 1
        return HStack(spacing: 0) {
            Color.clear
                .frame(width: menuWidth)
            portraitLayout(geo: geo, besideSequencer: true)
                .frame(width: DeskLayout.playWidth)
            Rectangle()
                .fill(Color(white: 0.18))
                .frame(width: 1)
            Group {
                switch state.deskPane {
                case .sequencer:
                    SequencerView(besidePlay: true)
                        .environment(state.sequencerState)
                case .tonnetz:
                    TonnetzView()
                        .padding(16)
                }
            }
            .frame(width: paneWidth)
        }
        .animation(.easeOut(duration: 0.22), value: sidePanel.isOpen)
    }

    // MARK: – Portrait layout

    /// `besideSequencer`: the sequencer has a place of its own on screen, so
    /// this column is the keys' whatever the mode, and its toggle chooses
    /// what is beside it instead.
    private func portraitLayout(geo: GeometryProxy, besideSequencer: Bool = false) -> some View {
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
            functionButtons(besideSequencer: besideSequencer)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

            if !besideSequencer, state.deskPane == .tonnetz {
                // The Tonnetz has the screen, whatever the mode under it.
                TonnetzView()
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 20)
            } else if !besideSequencer, state.mode.kind.surface == .sequencer {
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
        if state.deskPane == .tonnetz {
            // The Tonnetz has the whole screen, as the sequencer does, and
            // its controls share the one row with the screen's own, inset
            // past the menu button and level with it.
            @Bindable var state = state
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    PhoneScreenToggle()
                        .frame(width: Self.landscapeToggleWidth)
                    TonnetzControls()
                    toggleButton(label: "MIDI", isOn: $state.isExternalSynth)
                        .frame(width: Self.midiChitWidth)
                        .hotkeyTip(.midi)
                }
                .padding(.leading, SidePanelLayout.buttonLeading + SidePanelLayout.buttonSize + 12
                         - Self.edgeMargin)
                TonnetzBoard()
            }
            .padding(Self.edgeMargin)
            .frame(width: geo.size.width, height: geo.size.height)
        } else if state.mode.kind.surface == .sequencer {
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
                    functionButtons()
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

    /// A toggle takes the row; SOLO and MIDI keep to a narrow fixed width.
    /// The toggle is the mode's, or beside the sequencer's own place the
    /// one that chooses what is shown there.
    private func functionButtons(besideSequencer: Bool = false) -> some View {
        @Bindable var state = state
        @Bindable var solo = state.solo
        return HStack(spacing: 10) {
            if besideSequencer {
                SegmentedToggle(choices: DeskPane.allCases, label: \.displayName,
                                hotkey: { $0 == .sequencer ? .sequencer : .tonnetz },
                                selection: $state.deskPane)
            } else {
                PhoneScreenToggle()
            }
            toggleButton(label: "SOLO", isOn: $solo.isOn)
                .frame(width: Self.midiChitWidth)
                .hotkeyTip(.solo)
            toggleButton(label: "MIDI", isOn: $state.isExternalSynth)
                .frame(width: Self.midiChitWidth)
                .hotkeyTip(.midi)
        }
    }

    /// The chord keys, played: pressed as the fingers on them are, and
    /// named in the key being played (a key zone can have its own).
    private func chordKeys(_ arrangement: ChordKeyArrangement) -> some View {
        ChordKeySurface {
            ChordKeysView(arrangement: arrangement, key: state.playedKey, lit: state.heldDegrees)
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

/// The toggle that chooses what a phone's screen shows: the keys, the
/// sequencer or the Tonnetz. None is on under a mode that is none of them.
struct PhoneScreenToggle: View {
    @Environment(PerformanceState.self) private var state

    var body: some View {
        SegmentedToggle(choices: PhoneScreen.allCases.map(Optional.some),
                        label: { $0?.displayName ?? "" },
                        hotkey: {
                            switch $0 {
                            case .sequencer: return .sequencer
                            case .tonnetz:   return .tonnetz
                            case .play, nil: return nil
                            }
                        },
                        selection: Binding(get: { state.phoneScreen },
                                           set: { if let screen = $0 { state.show(screen) } }))
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

