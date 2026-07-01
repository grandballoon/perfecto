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
}
