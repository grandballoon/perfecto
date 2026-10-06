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
        // what keeps them exactly in time; the keys sound at once.
        let keys = NotePlayer([output.sink, midi], clock: clock)
        let state = PerformanceState(
            sink:    keys,
            chordListener: announcer,
            layerSink: { NotePlayer([output.sink, midi], clock: clock, lead: NotePlayer.sequencedLead) },
            layerLead: NotePlayer.sequencedLead,
            liveSound: keys,
            output:  output,
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
                .onAppear { MidiSink.logTopology() }
        }
    }
}
