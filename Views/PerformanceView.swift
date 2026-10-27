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
        .closingLoopBar()
        .showingHotkeyTips()
        .showingFieldPad()
        .background(KeyboardInput(keyboard: state.keyboard))
        .environment(sidePanel)
    }

    private var screen: some View {
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
    }

    // MARK: – Portrait layout

    private func portraitLayout(geo: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            // The OLED shares the top row with the menu button, inset past
            // it and top-aligned with it.
            displayAndSound
                .padding(.leading, 66)
                .padding(.trailing, 24)
                .padding(.top, 12)

            functionButtons()
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

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

    // MARK: – Landscape layout

    @ViewBuilder
    private func landscapeLayout(geo: GeometryProxy) -> some View {
        if state.chordGridLayout.arrangement(isLandscape: true) == .circle {
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
    /// display, the sound, the loops, and the key and the voicing are
    /// over the chord keys, which have the trailing half.
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
                LoopBar()
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

    /// The screen's buttons: MIDI, at the trailing end of its row, until it
    /// has a place of its own.
    private func functionButtons() -> some View {
        @Bindable var state = state
        return HStack(spacing: 10) {
            Spacer(minLength: 0)
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

