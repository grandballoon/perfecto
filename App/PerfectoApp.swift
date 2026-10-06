import SwiftUI

@main
struct PerfectoApp: App {
    @State private var state: PerformanceState = {
        let logger    = FileLogger()
        let audio     = AudioSink(logger: logger)
        let midi      = MidiSink(logger: logger)
        let announcer = MidiAnnouncerSink(logger: logger)
        let micGate   = MicrophonePermissionGate(logger: logger)
        let clock     = MasterClock()
        let state = PerformanceState(
            sink:    NotePlayer([audio, midi], clock: clock),
            chordListener: announcer,
            layerSink: { NotePlayer([audio, midi], clock: clock) },
            engine:  audio,
            effectsListener: midi,
            clock:   clock,
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
                .environment(state.micSampleState)
                .onAppear { MidiSink.logTopology() }
        }
    }
}
