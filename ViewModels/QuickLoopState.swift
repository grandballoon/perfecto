import Foundation
import Observation

/// What the loop controls need from whatever plays the keys and the timeline.
@MainActor
protocol LoopHost: AnyObject {
    /// The sequencer whose timeline loops are layers of.
    var loopSequencer: SequencerState? { get }
    var bpm: Double { get }
    func setBPM(_ value: Double)
    /// How far the clock has got, in beats.
    var clockBeats: Double { get }
    /// Everything a chord played now is played with: what a loop keeps.
    var playedNow: NotePlaying { get }
    /// Ends the chord the keys are holding.
    func endChord()
}

/// One layer of the timeline, as the loop bar shows it.
struct QuickLoopEntry: Identifiable, Equatable {
    let id: Layer.ID
    /// Whether the layer is heard (not muted).
    var isPlaying: Bool
}

/// Play mode's loop: one button records what the keys play as a new layer of
/// the timeline, the same one the sequencer edits.
///
/// The first loop, recorded onto an empty timeline, sets its length and the
/// tempo (`Timeline.fit`): it is taken to be whole bars, and loops from the
/// moment it is closed. Every later take is folded onto that length at the
/// point in the loop where it was played, so layers stay in time with each
/// other; a take longer than the loop becomes a layer for each time round.
@Observable
@MainActor
final class QuickLoopState {
    enum Phase: Equatable {
        case idle
        case recording
    }

    private(set) var phase: Phase = .idle

    /// The most layers there can be.
    static let maxLoops = 6

    /// The shortest take that becomes a loop, in seconds. Anything shorter
    /// is an accidental double tap.
    static let minimumSeconds = 0.5

    weak var host: (any LoopHost)?
    private let logger: (any Logger)?

    private var take: LoopTake?
    /// Where in the timeline the take began, in ticks.
    private var takeOffset = 0

    init(logger: (any Logger)? = nil) {
        self.logger = logger
    }

    private var sequencer: SequencerState? { host?.loopSequencer }

    /// The layers that have something in them, in order.
    var loops: [QuickLoopEntry] {
        (sequencer?.timeline.layers ?? [])
            .filter { !$0.notes.isEmpty }
            .map { QuickLoopEntry(id: $0.id, isPlaying: !$0.isMuted) }
    }

    var canStartNew: Bool { loops.count < Self.maxLoops }

    /// Whether the timeline is playing.
    var isRunning: Bool { sequencer?.isPlaying ?? false }

    /// The LOOP button: starts a take, or closes the one being recorded.
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

    /// Starts everything playing from the top, or stops it.
    func toggleRunning() {
        guard let sequencer, !loops.isEmpty else { return }
        if phase == .recording { cancelTake() }
        sequencer.isPlaying.toggle()
    }

    /// Silences a layer, or brings it back; it rejoins in time.
    func togglePlayback(id: Layer.ID) {
        guard let sequencer, let layer = sequencer.timeline.layer(id) else { return }
        sequencer.setLayer(id, muted: !layer.isMuted)
    }

    func removeLoop(id: Layer.ID) {
        guard let sequencer, let index = sequencer.timeline.layers.firstIndex(where: { $0.id == id }) else { return }
        sequencer.removeLayer(id)
        logger?.log(.loop_cleared(track: index))
        if sequencer.timeline.isEmpty { sequencer.isPlaying = false }
    }

    /// Removes every loop, and drops the take being recorded if there is one.
    func clearAll() {
        cancelTake()
        guard let sequencer else { return }
        sequencer.isPlaying = false
        sequencer.removeAllLayers()
    }

    // MARK: – What the keys play, while a take is being recorded

    func chordStarted(_ event: ChordEvent, pitch: NotePitch) {
        guard let host else { return }
        take?.chordStarted(event, pitch: pitch, playing: host.playedNow, at: host.clockBeats)
    }

    func chordEnded() {
        guard let host else { return }
        take?.chordEnded(at: host.clockBeats)
    }

    /// The effects being played changed (a slide, a zone, a setting).
    func effectsChanged() {
        guard let host, let effects = host.playedNow.effects else { return }
        take?.effectsChanged(to: effects, at: host.clockBeats)
    }

    // MARK: – Private

    private func beginRecording() {
        guard let host, let sequencer else { return }
        // Over what is already there, the take is played along to it.
        if !sequencer.timeline.isEmpty, !sequencer.isPlaying { sequencer.isPlaying = true }
        takeOffset = sequencer.timeline.isEmpty ? 0 : (sequencer.position ?? 0)
        take = LoopTake(start: host.clockBeats)
        phase = .recording
        logger?.log(.loop_record_started(track: loops.count))
    }

    private func cancelTake() {
        take = nil
        phase = .idle
    }

    private func finishRecording() {
        guard let host, let sequencer, let take else { return cancelTake() }
        host.endChord()
        cancelTake()
        let end = host.clockBeats
        let beats = end - take.start
        let seconds = beats * 60 / host.bpm
        let track = loops.count

        guard !take.isEmpty else {
            logger?.log(.loop_take_discarded(track: track, reason: "nothing played"))
            return
        }
        guard seconds >= Self.minimumSeconds else {
            logger?.log(.loop_take_discarded(track: track, reason: "too short"))
            return
        }

        if sequencer.timeline.isEmpty {
            // The first loop: it is whole bars, and the tempo is what makes it so.
            let signature = sequencer.timeline.signature
            let fit = Timeline.fit(loopOf: beats, at: host.bpm, signature: signature)
            let ticksPerBeat = Double(fit.bars * signature.ticksPerBar) / beats
            sequencer.isPlaying = false
            sequencer.startLoop(take.notes(closedAt: end, ticksPerBeat: ticksPerBeat), bars: fit.bars)
            host.setBPM(fit.bpm)
            sequencer.isPlaying = true
            logger?.log(.loop_recorded(track: track, seconds: seconds, setsLength: true))
        } else {
            let notes = take.notes(closedAt: end, ticksPerBeat: Double(TimelineTime.ticksPerBeat))
            let rounds = sequencer.timeline.folded(notes, from: takeOffset)
            let room = Self.maxLoops - loops.count
            if rounds.count > room {
                logger?.log(.loop_take_discarded(track: track + room, reason: "no layers left"))
            }
            sequencer.addLayers(Array(rounds.prefix(room)))
            logger?.log(.loop_recorded(track: track, seconds: seconds, setsLength: false))
        }
    }
}
