import SwiftUI

@main
struct PerfectoApp: App {
    @State private var state: PerformanceState = {
        let logger    = FileLogger()
        let output    = AudioOutput(logger: logger)
        let midi      = MidiSink(logger: logger)
        let announcer = MidiAnnouncerSink(logger: logger)
        let clock     = MasterClock()
        // The keys' notes and each layer's go through players of their
        // own, so each has its own sound, on the same audio and MIDI. The
        // layers' are sounded a moment after the clock's time, which is
        // what keeps them exactly in time; the keys sound at once, and so
        // do the solo strip, the Tonnetz, each pad and the chord–scale
        // tree, lines of their own over them; the Dissonance Lab is one
        // too, on the kernel alone. The pads' sequence is the
        // clock's, like a layer. Each is also shown on the piano, as a
        // source of its own.
        let piano = PianoState(logger: logger)
        let keys = NotePlayer([output.sink, midi, piano.line(.keys)], clock: clock)
        let state = PerformanceState(
            sink:    keys,
            chordListener: announcer,
            layerSink: {
                NotePlayer([output.sink, midi, piano.line(.layers)], clock: clock,
                           lead: NotePlayer.sequencedLead)
            },
            layerLead: NotePlayer.sequencedLead,
            soloSink: NotePlayer([output.sink, midi, piano.line(.solo)], clock: clock),
            tonnetzSink: NotePlayer([output.sink, midi, piano.line(.tonnetz)], clock: clock),
            tonnetzNoteSink: NotePlayer([output.sink, midi, piano.line(.tonnetz)], clock: clock),
            padSink: { NotePlayer([output.sink, midi, piano.line(.pads)], clock: clock) },
            padSequenceSink: NotePlayer([output.sink, midi, piano.line(.pads)], clock: clock,
                                        lead: NotePlayer.sequencedLead),
            padDefaults: .standard,
            // The bars' notes slide, which the MIDI the app sends has no
            // way to say, so they are heard and not sent.
            trautoniumSink: { NotePlayer([output.sink, piano.line(.trautonium)], clock: clock) },
            treeSink: NotePlayer([output.sink, midi, piano.line(.tree)], clock: clock),
            // The lab sets each note's partials, which only the kernel can,
            // and tunes anywhere, which MIDI cannot: it is heard, not sent.
            labSynth: DissonanceSynth(sink: output.sink, display: [piano.line(.lab)], clock: clock),
            piano: piano,
            liveSound: keys,
            output:  output,
            micGate: MicrophonePermissionGate(logger: logger),
            effectsListener: midi,
            tempoListener: output.sink,
            clock:   clock,
            logger:  logger
        )
        MidiNetwork.enableSession(logger: logger)
        // v0.1.0 plays its colors from the compass; Setup still has the others.
        state.colorSurface = .compass
        return state
    }()

    @State private var gamepadInput = GamepadInput()
    @State private var midiInput = MidiInput()

    var body: some Scene {
        WindowGroup {
            PerformanceView()
                .environment(state)
                .environment(state.sequencerState)
                .background(WindowSize())
                .onAppear {
                    MidiSink.logTopology()
                    gamepadInput.play(state.gamepad)
                    midiInput.play(state.controller)
                }
        }
    }
}

/// A Mac's window: it opens with room for the desk's layout (`DeskLayout`),
/// can be made as large as the screen or full screen, and no smaller than a
/// phone's screen, which is the least the layouts are drawn for. A phone's
/// own window is never resized.
///
/// SwiftUI's `defaultSize` is not used: on Mac Catalyst it pins the window's
/// largest size to the size it opens at, so the window could not be made
/// larger or full screen.
private struct WindowSize: UIViewRepresentable {
    private static let minimum = CGSize(width: 390, height: 700)
    private static let opening = CGSize(width: 1500, height: 950)
    /// Marks a window's session once it has been given its opening size, so
    /// a window the system restores keeps the size it was left at.
    private static let sizedKey = "perfecto.windowSized"

    func makeUIView(context: Context) -> UIView { SceneView() }
    func updateUIView(_ view: UIView, context: Context) {}

    private final class SceneView: UIView {
        #if targetEnvironment(macCatalyst)
        override func didMoveToWindow() {
            super.didMoveToWindow()
            window?.windowScene?.sizeRestrictions?.minimumSize = WindowSize.minimum
        }

        /// Gives a new window its opening size, once the window has a size
        /// of its own to measure the Mac's scale by.
        override func layoutSubviews() {
            super.layoutSubviews()
            guard let window, let scene = window.windowScene,
                  scene.session.userInfo?[WindowSize.sizedKey] == nil else { return }
            // The system's frame is in the Mac's points, which the app's are
            // scaled to; both take in the title bar.
            let system = scene.effectiveGeometry.systemFrame
            guard system.width > 0, window.bounds.width > 0 else { return }
            scene.session.userInfo = (scene.session.userInfo ?? [:])
                .merging([WindowSize.sizedKey: true]) { $1 }
            let scale = system.width / window.bounds.width
            let size = CGSize(width: WindowSize.opening.width * scale,
                              height: WindowSize.opening.height * scale)
            scene.requestGeometryUpdate(.Mac(systemFrame: CGRect(origin: system.origin,
                                                                 size: size)))
        }
        #endif
    }
}
