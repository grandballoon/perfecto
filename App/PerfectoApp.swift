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
        // what keeps them exactly in time; the keys sound at once. Each is
        // also shown on the piano, as a source of its own.
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
        return state
    }()

    @State private var gamepadInput = GamepadInput()

    var body: some Scene {
        WindowGroup {
            PerformanceView()
                .environment(state)
                .environment(state.sequencerState)
                .background(WindowSize())
                .onAppear {
                    MidiSink.logTopology()
                    gamepadInput.play(state.gamepad)
                }
        }
    }
}

/// A Mac's window: it opens large, laid out as a phone on its side is,
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
