import SwiftUI

@main
struct PerfectoApp: App {
    @State private var state: PerformanceState = {
        let logger    = FileLogger()
        let audio     = AudioSink(logger: logger)
        let midi      = MidiSink(logger: logger)
        let announcer = MidiAnnouncerSink(logger: logger)
        let micGate   = MicrophonePermissionGate(logger: logger)
        let state = PerformanceState(
            sink:    CompositeSink([audio, midi]),
            chordListener: announcer,
            engine:  audio,
            effectsListener: midi,
            logger:  logger,
            micGate: micGate
        )
        MidiNetwork.enableSession(logger: logger)
        return state
    }()

    var body: some Scene {
        WindowGroup {
            PerformanceView()
                .environment(state)
                .environment(state.sequencerState)
                .environment(state.looperState)
                .environment(state.micSampleState)
                .onAppear { MidiSink.logTopology() }
        }
    }
}
