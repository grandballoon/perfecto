/// Clock-driven state machine for the 2-track looper.
///
/// All timing (recording elapsed ticks, quantized stop) is driven by
/// onClockTick so loop boundaries always land on a 1/16th-note grid.
///
/// Chord buttons remain active — the player can perform over the loop.
@MainActor
final class LooperMode: PerformanceMode {
    var name: String { "Looper" }
    var requiresClock: Bool { true }

    private let looperState: LooperState
    private enum ClockPhase {
        case idle
        case recording(track: Int, elapsed: Int, stopAt: Int?)
    }
    private var clockPhase: ClockPhase = .idle

    init(_ looperState: LooperState) {
        self.looperState = looperState
    }

    // MARK: – PerformanceMode

    func onButtonDown(degree: Degree, state: PerformanceState) {
        state.startChord(degree: degree)
    }

    func onButtonUp(degree: Degree, state: PerformanceState) {
        state.endChord()
    }

    func onJoystickChange(direction: JoystickDirection, state: PerformanceState) {}

    func onClockTick(state: PerformanceState) {
        consumePendingActions(state: state)
        advanceClockPhase(state: state)
    }

    func deactivate(state: PerformanceState) {
        if let looper = state.looper {
            looper.stopRecording(0); looper.stopRecording(1)
            looper.stopPlayback(0);  looper.stopPlayback(1)
        }
        looperState.tracks[0].phase = .empty
        looperState.tracks[1].phase = .empty
        looperState.loopLengthTicks = 0
        clockPhase = .idle
        state.endChord()
    }

    // MARK: – Private: pending action dispatch

    private func consumePendingActions(state: PerformanceState) {
        if let track = looperState.pendingClear {
            looperState.pendingClear = nil
            state.looper?.clearTrack(track)
            looperState.tracks[track].phase = .empty
            if track == 0 { looperState.loopLengthTicks = 0 }
            switch clockPhase {
            case .recording(let t, _, _) where t == track: clockPhase = .idle
            default: break
            }
        }

        if let track = looperState.pendingRecord {
            looperState.pendingRecord = nil
            beginRecording(track: track, state: state)
        }

        if let track = looperState.pendingStop {
            looperState.pendingStop = nil
            switch clockPhase {
            case .recording(let t, let elapsed, _) where t == track:
                let barLen = looperState.loopLengthTicks > 0 ? looperState.loopLengthTicks : 16
                let rem    = elapsed % barLen
                let stopAt = rem == 0 ? elapsed : elapsed + (barLen - rem)
                clockPhase = .recording(track: t, elapsed: elapsed, stopAt: stopAt)

            default:
                // Stop playback immediately
                state.looper?.stopPlayback(track)
                looperState.tracks[track].phase = .stopped
            }
        }
    }

    // MARK: – Private: clock phase advancement

    private func beginRecording(track: Int, state: PerformanceState) {
        // Reject if already recording
        if case .recording = clockPhase { return }
        // Track 1 requires track 0 to have already set a loop length
        guard track == 0 || looperState.loopLengthTicks > 0 else { return }

        do {
            try state.looper?.startRecording(track)
            clockPhase = .recording(track: track, elapsed: 0, stopAt: nil)
            looperState.tracks[track].phase = .recording
        } catch {
            print("[LooperMode] startRecording error: \(error)")
            looperState.tracks[track].phase = .empty
        }
    }

    private func advanceClockPhase(state: PerformanceState) {
        switch clockPhase {
        case .idle:
            break

        case .recording(let track, let elapsed, let stopAt):
            let newElapsed = elapsed + 1

            if let target = stopAt, newElapsed >= target {
                state.looper?.stopRecording(track)
                if track == 0 { looperState.loopLengthTicks = newElapsed }
                state.looper?.startPlayback(track)
                looperState.tracks[track].phase = .playing
                clockPhase = .idle
            } else {
                clockPhase = .recording(track: track, elapsed: newElapsed, stopAt: stopAt)
            }
        }
    }
}
