import SwiftUI
import UIKit

/// The desk's arrangement: a window with room for it shows the keys and the
/// sequencer side by side, and the menu as a column beside them. The
/// Tonnetz, the pads, the Trautonium's bars, the chord–scale tree, the
/// Dissonance Lab or the MIDI controller take the sequencer's place when
/// chosen (`DeskPane`).
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

    var body: some View {
        // The piano, while it is shown, is the bottom of the window from
        // edge to edge, under a phone's notch too, and the screen is laid
        // out in what is left above it. Expanded, it lies over the whole
        // window, and the screen stays laid out as it was under it, so
        // nothing there changes or stops.
        GeometryReader { window in
            let insets = window.safeAreaInsets
            ZStack {
                VStack(spacing: 0) {
                    screen
                    if state.piano.isOn {
                        Group {
                            if state.piano.isExpanded { Color.black } else { PianoView() }
                        }
                        .frame(height: PianoKeys.height(
                            forWidth: window.size.width + insets.leading + insets.trailing))
                        .ignoresSafeArea(edges: .horizontal)
                        .padding(.bottom, insets.bottom)
                        .background(Color.black)
                    }
                }
                .ignoresSafeArea(edges: .bottom)
                if state.piano.isOn && state.piano.isExpanded {
                    PianoView(isExpanded: true)
                        .ignoresSafeArea()
                        .transition(.move(edge: .bottom))
                }
            }
        }
        .showingHotkeyTips()
        .showingFieldPad()
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
                case .pads:
                    PadsView()
                        .padding(16)
                case .trautonium:
                    TrautoniumView()
                        .padding(16)
                case .tree:
                    ChordScaleTreeView()
                        .padding(16)
                case .lab:
                    DissonanceLabView()
                        .padding(16)
                case .controller:
                    ControllerView()
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
            displayAndSound
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
                // The Tonnetz has the screen, whatever the mode under it,
                // under the effects it is played with.
                EffectStrip()
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                TonnetzView()
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 20)
            } else if !besideSequencer, state.deskPane == .pads {
                // So have the pads.
                PadsView()
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 40)
            } else if !besideSequencer, state.deskPane == .trautonium {
                // And the Trautonium's bars, under the key they are in and
                // the effects they are played with.
                if state.showsKeyStrip {
                    KeyStrip()
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                }
                EffectStrip()
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                TrautoniumView()
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 40)
            } else if !besideSequencer, state.deskPane == .tree {
                // And the chord–scale tree, under its own controls.
                ChordScaleTreeView()
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 20)
            } else if !besideSequencer, state.deskPane == .lab {
                // And the Dissonance Lab.
                DissonanceLabView()
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
            } else if !besideSequencer, state.mode.kind.surface == .sequencer {
                SequencerView()
                    .environment(state.sequencerState)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
            } else {
                LoopBar()
                    .padding(.horizontal, 20)
                if state.showsKeyStrip {
                    KeyStrip()
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                }
                EffectStrip()
                    .padding(.horizontal, 20)
                    .padding(.top, 10)

                // Push the chord ring toward the bottom so it falls under the
                // thumb when the phone is held normally, rather than sitting
                // high under the function buttons.
                Spacer()

                chordKeys(state.chordGridLayout.arrangement(isLandscape: false))
                    .padding(.horizontal, 20)

                // Bottom input: the chord colors
                StepCompassSurface()
                    .environment(state)
                    .frame(height: StepCompassSurface.portraitHeight)
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
            // past the menu button and level with it. The effects it is
            // played with are a row under them.
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
                EffectStrip()
                TonnetzBoard()
            }
            .padding(Self.edgeMargin)
            .frame(width: geo.size.width, height: geo.size.height)
        } else if state.deskPane == .pads {
            // So have the pads, with their editor beside the grid.
            @Bindable var state = state
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    PhoneScreenToggle()
                        .frame(width: Self.landscapeToggleWidth)
                    PadsControls()
                    toggleButton(label: "MIDI", isOn: $state.isExternalSynth)
                        .frame(width: Self.midiChitWidth)
                        .hotkeyTip(.midi)
                }
                .padding(.leading, SidePanelLayout.buttonLeading + SidePanelLayout.buttonSize + 12
                         - Self.edgeMargin)
                HStack(spacing: 12) {
                    PadsBoard()
                    if state.pads.isEditing {
                        PadEditor()
                            .frame(width: geo.size.width * 0.42)
                    }
                }
            }
            .padding(Self.edgeMargin)
            .frame(width: geo.size.width, height: geo.size.height)
        } else if state.deskPane == .trautonium {
            // And the Trautonium's bars, which lie along the screen. The key
            // they are in shares the one row with the screen's own, and
            // the effects they are played with are a row under it.
            @Bindable var state = state
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    PhoneScreenToggle()
                        .frame(width: Self.landscapeToggleWidth)
                    if state.showsKeyStrip { KeyStrip() } else { Spacer(minLength: 0) }
                    toggleButton(label: "MIDI", isOn: $state.isExternalSynth)
                        .frame(width: Self.midiChitWidth)
                        .hotkeyTip(.midi)
                }
                .padding(.leading, SidePanelLayout.buttonLeading + SidePanelLayout.buttonSize + 12
                         - Self.edgeMargin)
                EffectStrip()
                TrautoniumView()
            }
            .padding(Self.edgeMargin)
            .frame(width: geo.size.width, height: geo.size.height)
        } else if state.deskPane == .tree {
            // And the chord–scale tree, whose controls share the one row
            // with the screen's own.
            @Bindable var state = state
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    PhoneScreenToggle()
                        .frame(width: Self.landscapeToggleWidth)
                    TreeControls()
                    toggleButton(label: "MIDI", isOn: $state.isExternalSynth)
                        .frame(width: Self.midiChitWidth)
                        .hotkeyTip(.midi)
                }
                .padding(.leading, SidePanelLayout.buttonLeading + SidePanelLayout.buttonSize + 12
                         - Self.edgeMargin)
                ChordScaleTreeView(showsControls: false)
            }
            .padding(Self.edgeMargin)
            .frame(width: geo.size.width, height: geo.size.height)
        } else if state.deskPane == .lab {
            // And the Dissonance Lab, its pictures beside its controls.
            @Bindable var state = state
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    PhoneScreenToggle()
                        .frame(width: Self.landscapeToggleWidth)
                    Spacer(minLength: 0)
                    toggleButton(label: "MIDI", isOn: $state.isExternalSynth)
                        .frame(width: Self.midiChitWidth)
                        .hotkeyTip(.midi)
                }
                .padding(.leading, SidePanelLayout.buttonLeading + SidePanelLayout.buttonSize + 12
                         - Self.edgeMargin)
                DissonanceLabView()
            }
            .padding(Self.edgeMargin)
            .frame(width: geo.size.width, height: geo.size.height)
        } else if state.mode.kind.surface == .sequencer {
            // Sequencer owns the whole screen in landscape and lays out its own
            // two-column editor/grid. No split panel.
            SequencerView()
                .environment(state.sequencerState)
                .frame(width: geo.size.width, height: geo.size.height)
        } else if state.chordGridLayout.arrangement(isLandscape: true) == .circle {
            ringLandscapeLayout(geo: geo)
        } else {
        HStack(spacing: 0) {
                let leftW = geo.size.width / 2
                let panelH = geo.size.height

                // Left panel: the compass, at the bottom so its lower
                // margin lines up with the function buttons in the right
                // panel.
                StepCompassSurface()
                    .environment(state)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(Self.edgeMargin)
                    .frame(width: leftW, height: panelH)

                // Right panel: OLED + chord grid + function buttons
                VStack(spacing: 0) {
                    displayAndSound
                        .padding(.bottom, 8)
                    LoopBar()
                        .padding(.bottom, 8)
                    if state.showsKeyStrip {
                        KeyStrip()
                            .padding(.bottom, 8)
                    }
                    EffectStrip()
                        .padding(.bottom, 8)
                    let arrangement = state.chordGridLayout.arrangement(isLandscape: true)
                    switch arrangement {
                    case .row, .circle, .octave:
                        chordKeys(arrangement)
                            .padding(.vertical, 8)
                    case .grid:
                        Spacer()
                        chordKeys(arrangement)
                        Spacer()
                    }
                    functionButtons()
                }
                .padding(Self.edgeMargin)
                .frame(width: geo.size.width - leftW, height: panelH)
        }
        }
    }

    /// The circle's own arrangement on a phone on its side. The compass
    /// has the leading half to itself, as large as it can be; the note
    /// display, the sound, the key and the voicing are over the chord
    /// keys, which have the trailing half.
    private func ringLandscapeLayout(geo: GeometryProxy) -> some View {
        let half = geo.size.width / 2
        return HStack(spacing: 0) {
            StepCompassSurface()
                .environment(state)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(Self.edgeMargin)
                .frame(width: half, height: geo.size.height)
            VStack(spacing: 8) {
                displayAndSound
                if state.showsKeyStrip { KeyStrip() }
                chordKeys(.circle)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(Self.edgeMargin)
            .frame(width: geo.size.width - half, height: geo.size.height)
        }
    }

    // MARK: – Shared subviews

    /// The note display, and the sound field at its end, as tall as it is.
    private var displayAndSound: some View {
        HStack(spacing: 8) {
            oledDisplay
            SoundField()
        }
        .fixedSize(horizontal: false, vertical: true)
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

    /// A toggle takes the row; MIDI keeps to a narrow fixed width.
    /// The toggle is the mode's, or beside the sequencer's own place the
    /// one that chooses what is shown there.
    private func functionButtons(besideSequencer: Bool = false) -> some View {
        @Bindable var state = state
        return HStack(spacing: 10) {
            if besideSequencer {
                SegmentedToggle(choices: DeskPane.allCases, label: \.displayName,
                                hotkey: {
                                    switch $0 {
                                    case .sequencer: return .sequencer
                                    case .tonnetz:   return .tonnetz
                                    case .pads, .trautonium, .tree, .lab, .controller: return nil
                                    }
                                },
                                selection: $state.deskPane)
            } else {
                PhoneScreenToggle()
            }
            toggleButton(label: "MIDI", isOn: $state.isExternalSynth)
                .frame(width: Self.midiChitWidth)
                .hotkeyTip(.midi)
        }
    }

    /// The chord keys, played: pressed as the fingers on them are, and
    /// named in the key they are in (a key zone can have its own).
    private func chordKeys(_ arrangement: ChordKeyArrangement) -> some View {
        ChordKeySurface {
            ChordKeysView(arrangement: arrangement, key: state.homeKey, lit: state.heldKeys)
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
/// sequencer, the Tonnetz, the pads, the Trautonium's bars, the
/// chord–scale tree or the Dissonance Lab. None is on under a mode that is none of them.
struct PhoneScreenToggle: View {
    @Environment(PerformanceState.self) private var state

    var body: some View {
        SegmentedToggle(choices: PhoneScreen.allCases.map(Optional.some),
                        label: { $0?.displayName ?? "" },
                        hotkey: {
                            switch $0 {
                            case .sequencer: return .sequencer
                            case .tonnetz:   return .tonnetz
                            case .play, .pads, .trautonium, .tree, .lab, nil: return nil
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

