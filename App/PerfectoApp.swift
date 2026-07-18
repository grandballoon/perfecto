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
            sink:    CompositeSink([audio, midi, announcer]),
            engine:  audio,
            logger:  logger,
            micGate: micGate
        )
        // The announcer needs the semantic selection at send time, but the
        // state is constructed with the sink — so the provider is bound after.
        // Inversion and voice leading mirror makeVoicing's current fixed values.
        announcer.contextProvider = { [weak state] in
            guard let state, let degree = state.activeDegree else { return nil }
            return MidiAnnouncerSink.Context(
                key: state.key,
                degree: degree,
                joystickMode: state.joystickMode,
                joystickDirection: state.joystickDirection,
                inversion: .root,
                octave: state.octave,
                voiceLeading: false
            )
        }
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
