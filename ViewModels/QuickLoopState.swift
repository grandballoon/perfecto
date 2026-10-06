import Foundation
import Observation

/// What the play-mode looper needs from the audio layer: tracks that record
/// and loop. `Looper` is the real one; tests substitute their own.
@MainActor
protocol LoopTracks: AnyObject {
    func startRecording(_ track: Int) throws
    /// Ends the take and starts it looping; false if the take was dropped.
    @discardableResult func stopRecording(_ track: Int) -> Bool
    func startPlayback(_ track: Int)
    func stopPlayback(_ track: Int)
    func clearTrack(_ track: Int)
}

struct QuickLoopEntry: Identifiable {
    let id = UUID()
    let trackIndex: Int
    var isPlaying: Bool = true
}

@Observable
@MainActor
final class QuickLoopState {
    enum Phase: Equatable {
        case idle
        case recording
    }

    private(set) var phase: Phase = .idle
    private(set) var loops: [QuickLoopEntry] = []

    private let looper: (any LoopTracks)?
    private var recordingTrackIndex: Int?

    /// Called immediately before recording stops so the caller can release held notes.
    var onWillStopRecording: (() -> Void)? = nil

    static let maxLoops = AudioSink.quickLoopTrackCount

    /// Production: pass the quickLooper from AudioSink. Tests: omit looper (nil → no audio).
    init(looper: (any LoopTracks)? = nil) {
        self.looper = looper
    }

    var canStartNew: Bool { loops.count < Self.maxLoops }

    func triggerTapped() {
        switch phase {
        case .idle where canStartNew:
            beginRecording()
        case .idle:
            break
        case .recording:
            finishRecording()
        }
    }

    func togglePlayback(id: UUID) {
        guard let idx = loops.firstIndex(where: { $0.id == id }) else { return }
        var updated = loops
        updated[idx].isPlaying.toggle()
        loops = updated
        let entry = loops[idx]
        if entry.isPlaying {
            looper?.startPlayback(entry.trackIndex)
        } else {
            looper?.stopPlayback(entry.trackIndex)
        }
    }

    func removeLoop(id: UUID) {
        guard let entry = loops.first(where: { $0.id == id }) else { return }
        looper?.clearTrack(entry.trackIndex)
        loops.removeAll { $0.id == id }
    }

    /// Removes every loop, and drops the take being recorded if there is one.
    func clearAll() {
        if let recordingTrackIndex { looper?.clearTrack(recordingTrackIndex) }
        recordingTrackIndex = nil
        phase = .idle
        for entry in loops { looper?.clearTrack(entry.trackIndex) }
        loops = []
    }

    // MARK: – Private

    private func nextFreeTrackIndex() -> Int {
        let used = Set(loops.map { $0.trackIndex })
        return (0..<Self.maxLoops).first { !used.contains($0) } ?? 0
    }

    private func beginRecording() {
        let nextTrack = nextFreeTrackIndex()
        do {
            try looper?.startRecording(nextTrack)
        } catch {
            return
        }
        recordingTrackIndex = nextTrack
        phase = .recording
    }

    private func finishRecording() {
        guard let trackIdx = recordingTrackIndex else { phase = .idle; return }
        onWillStopRecording?()
        recordingTrackIndex = nil
        phase = .idle
        // A dropped take (too short to loop) leaves no entry behind.
        guard looper?.stopRecording(trackIdx) ?? true else { return }
        loops.append(QuickLoopEntry(trackIndex: trackIdx))
    }
}
