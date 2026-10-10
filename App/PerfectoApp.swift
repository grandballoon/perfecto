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
        // do the solo strip and the Tonnetz, lines of their own over them.
        // Each is also shown on the piano, as a source of its own.
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
            piano: piano,
            liveSound: keys,
            output:  output,
            micGate: MicrophonePermissionGate(logger: logger),
            effectsListener: midi,
            clock:   clock,
            logger:  logger
        )
        MidiNetwork.enableSession(logger: logger)
        return state
    }()

    var body: some Scene {
        WindowGroup {
            PerformanceView()
                .environment(state)
                .environment(state.sequencerState)
                .background(WindowMinimum())
                .onAppear { MidiSink.logTopology() }
        }
        // On the Mac: room for the desk's layout (`DeskLayout`).
        .defaultSize(width: 1500, height: 950)
    }
}

/// Keeps a Mac's window from being made smaller than a phone's screen,
/// which is the least the layouts are drawn for. A phone's own window is
/// never resized.
private struct WindowMinimum: UIViewRepresentable {
    private static let size = CGSize(width: 390, height: 700)

    func makeUIView(context: Context) -> UIView { SceneView() }
    func updateUIView(_ view: UIView, context: Context) {}

    private final class SceneView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard ProcessInfo.processInfo.isMacCatalystApp else { return }
            window?.windowScene?.sizeRestrictions?.minimumSize = WindowMinimum.size
        }
    }
}
