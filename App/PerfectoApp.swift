import SwiftUI

@main
struct PerfectoApp: App {
    @State private var state: PerformanceState = {
        let logger  = FileLogger()
        let audio   = AudioSink(logger: logger)
        let midi    = MidiSink(logger: logger)
        let micGate = MicrophonePermissionGate(logger: logger)
        return PerformanceState(
            sink:    CompositeSink([audio, midi]),
            engine:  audio,
            logger:  logger,
            micGate: micGate
        )
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
