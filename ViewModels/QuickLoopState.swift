import Foundation
import Observation

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

    private let looper: Looper?
    private var recordingTrackIndex: Int?

    /// Called immediately before recording stops so the caller can release held notes.
    var onWillStopRecording: (() -> Void)? = nil

    static let maxLoops = 6

    /// Production: pass the quickLooper from AudioSink. Tests: omit looper (nil → no audio).
    init(looper: Looper? = nil) {
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
        looper?.stopPlayback(entry.trackIndex)
        looper?.clearTrack(entry.trackIndex)
        loops.removeAll { $0.id == id }
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
        looper?.stopRecording(trackIdx)
        recordingTrackIndex = nil
        phase = .idle
        loops.append(QuickLoopEntry(trackIndex: trackIdx))
        looper?.startPlayback(trackIdx)
    }
}
