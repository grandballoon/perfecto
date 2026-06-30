import Observation

enum TrackPhase: Equatable {
    case empty
    case recording
    case playing
    case stopped
}

struct LoopTrack {
    var phase: TrackPhase = .empty
    var isMuted: Bool = false
    var volume: Float = 1.0

    var hasContent: Bool { phase != .empty }
}

@Observable
@MainActor
final class LooperState {
    var tracks: [LoopTrack] = [LoopTrack(), LoopTrack()]
    var loopLengthTicks: Int = 0   // set by track 0; track 1 quantizes to multiples of this

    // UI → LooperMode: each flag is consumed once inside onClockTick
    var pendingRecord: Int? = nil
    var pendingStop:   Int? = nil
    var pendingClear:  Int? = nil
}
