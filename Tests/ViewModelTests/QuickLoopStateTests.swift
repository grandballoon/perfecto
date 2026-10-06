import Foundation
import Testing
@testable import Perfecto

@Suite("QuickLoopState")
@MainActor
struct QuickLoopStateTests {

    // MARK: – Helpers

    /// Returns a state that is currently recording (one tap in).
    private func stateInRecording() -> QuickLoopState {
        let state = QuickLoopState()
        state.triggerTapped()
        return state
    }

    /// Returns a state with `n` completed loop entries and phase == .idle.
    private func stateWithLoops(_ n: Int) -> QuickLoopState {
        let state = QuickLoopState()
        for _ in 0..<n {
            state.triggerTapped()  // → recording
            state.triggerTapped()  // → idle (adds loop)
        }
        return state
    }

    // MARK: – Initial state

    @Test func initialPhaseIsIdle() {
        #expect(QuickLoopState().phase == .idle)
    }

    @Test func initialLoopsIsEmpty() {
        #expect(QuickLoopState().loops.isEmpty)
    }

    @Test func canStartNewIsTrueInitially() {
        #expect(QuickLoopState().canStartNew)
    }

    // MARK: – Recording initiation

    @Test func triggerFromIdleEntersRecording() {
        let state = QuickLoopState()
        state.triggerTapped()
        #expect(state.phase == .recording)
    }

    @Test func triggerFromIdleDoesNotImmediatelyAddLoop() {
        let state = QuickLoopState()
        state.triggerTapped()
        #expect(state.loops.isEmpty)
    }

    // MARK: – Stop recording

    @Test func triggerDuringRecordingAddsOneLoop() {
        let state = stateInRecording()
        state.triggerTapped()
        #expect(state.loops.count == 1)
    }

    @Test func triggerDuringRecordingReturnsToIdle() {
        let state = stateInRecording()
        state.triggerTapped()
        #expect(state.phase == .idle)
    }

    @Test func eachRecordingCycleAddsOneLoop() {
        let state = stateWithLoops(3)
        #expect(state.loops.count == 3)
    }

    // MARK: – Max loop cap

    @Test func allowsExactlyMaxLoops() {
        let state = stateWithLoops(QuickLoopState.maxLoops)
        #expect(state.loops.count == QuickLoopState.maxLoops)
    }

    @Test func canStartNewIsFalseAtMaxLoops() {
        let state = stateWithLoops(QuickLoopState.maxLoops)
        #expect(!state.canStartNew)
    }

    @Test func triggerAtMaxLoopsDoesNotStartRecording() {
        let state = stateWithLoops(QuickLoopState.maxLoops)
        state.triggerTapped()
        #expect(state.phase == .idle)
    }

    @Test func triggerAtMaxLoopsDoesNotAddAnExtraLoop() {
        let state = stateWithLoops(QuickLoopState.maxLoops)
        state.triggerTapped()
        #expect(state.loops.count == QuickLoopState.maxLoops)
    }

    // MARK: – removeLoop

    @Test func removeLoopDecrementsCount() {
        let state = stateWithLoops(1)
        let id = state.loops[0].id
        state.removeLoop(id: id)
        #expect(state.loops.isEmpty)
    }

    @Test func removeLoopDeletesCorrectEntryById() {
        let state = stateWithLoops(2)
        let firstId = state.loops[0].id
        state.removeLoop(id: firstId)
        #expect(state.loops.count == 1)
        #expect(state.loops[0].id != firstId)
    }

    @Test func removeLoopWithUnknownIdIsNoOp() {
        let state = stateWithLoops(1)
        state.removeLoop(id: UUID())
        #expect(state.loops.count == 1)
    }

    @Test func removingLoopFromFullStateRestoresCapacity() {
        let state = stateWithLoops(QuickLoopState.maxLoops)
        state.removeLoop(id: state.loops[0].id)
        #expect(state.canStartNew)
    }

    @Test func removingLoopFromFullStateAllowsNewRecording() {
        let state = stateWithLoops(QuickLoopState.maxLoops)
        state.removeLoop(id: state.loops[0].id)
        state.triggerTapped()
        #expect(state.phase == .recording)
    }

    // MARK: – With a looper

    /// A looper double that records the calls it gets.
    private final class RecordingLoopTracks: LoopTracks {
        var keepsTakes = true
        private(set) var calls: [String] = []

        func startRecording(_ track: Int) throws { calls.append("record \(track)") }
        func stopRecording(_ track: Int) -> Bool {
            calls.append("close \(track)")
            return keepsTakes
        }
        func startPlayback(_ track: Int) { calls.append("play \(track)") }
        func stopPlayback(_ track: Int) { calls.append("stop \(track)") }
        func clearTrack(_ track: Int) { calls.append("clear \(track)") }
    }

    @Test func closingATakeStartsItLoopingWithoutASeparatePlay() {
        let tracks = RecordingLoopTracks()
        let state = QuickLoopState(looper: tracks)
        state.triggerTapped()
        state.triggerTapped()
        #expect(tracks.calls == ["record 0", "close 0"])
        #expect(state.loops.map(\.isPlaying) == [true])
    }

    @Test func aDroppedTakeLeavesNoLoop() {
        let tracks = RecordingLoopTracks()
        tracks.keepsTakes = false
        let state = QuickLoopState(looper: tracks)
        state.triggerTapped()
        state.triggerTapped()
        #expect(state.loops.isEmpty)
        #expect(state.phase == .idle)
    }

    @Test func heldNotesAreReleasedBeforeTheTakeCloses() {
        let tracks = RecordingLoopTracks()
        let state = QuickLoopState(looper: tracks)
        var callsWhenReleased: [String]?
        state.onWillStopRecording = { callsWhenReleased = tracks.calls }
        state.triggerTapped()
        state.triggerTapped()
        #expect(callsWhenReleased == ["record 0"])
    }

    @Test func eachLayerRecordsOnItsOwnTrackAndAFreedTrackIsReused() {
        let tracks = RecordingLoopTracks()
        let state = QuickLoopState(looper: tracks)
        for _ in 0..<3 { state.triggerTapped(); state.triggerTapped() }
        #expect(state.loops.map(\.trackIndex) == [0, 1, 2])
        state.removeLoop(id: state.loops[1].id)
        state.triggerTapped()
        state.triggerTapped()
        #expect(state.loops.map(\.trackIndex) == [0, 2, 1])
    }

    @Test func togglingALayerStopsAndRestartsItsTrack() {
        let tracks = RecordingLoopTracks()
        let state = QuickLoopState(looper: tracks)
        state.triggerTapped()
        state.triggerTapped()
        let id = state.loops[0].id
        state.togglePlayback(id: id)
        #expect(state.loops[0].isPlaying == false)
        state.togglePlayback(id: id)
        #expect(state.loops[0].isPlaying)
        #expect(tracks.calls.suffix(2) == ["stop 0", "play 0"])
    }

    @Test func clearAllRemovesEveryLoopAndTheTakeInProgress() {
        let tracks = RecordingLoopTracks()
        let state = QuickLoopState(looper: tracks)
        state.triggerTapped()
        state.triggerTapped()
        state.triggerTapped()
        state.clearAll()
        #expect(state.loops.isEmpty)
        #expect(state.phase == .idle)
        #expect(tracks.calls.suffix(2) == ["clear 1", "clear 0"])
    }
}
