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
    /// How long after its time on the clock a layer is heard (see
    /// `NotePlayer`): what is played along to a layer is that much later
    /// on the clock than the place in the layer it was played to.
    var layerLead: Double { get }
    /// Everything a chord the keys play now is played with: what a loop keeps.
    var playedNow: NotePlaying { get }
    /// Ends the chord the keys are holding.
    func endChord()
}

/// A line of chords a loop is recorded from. Each is one chord at a time, as
/// a layer is, so what each played in a take becomes layers of its own.
enum LoopLine: CaseIterable {
    case keys
    /// The Tonnetz's triads.
    case tonnetzTriads
    /// The notes of the Tonnetz played by themselves.
    case tonnetzNotes
}

/// One layer of the timeline, as the loop bar shows it.
struct QuickLoopEntry: Identifiable, Equatable {
    let id: Layer.ID
    /// Whether the layer is heard (not muted).
    var isPlaying: Bool
}

/// Play mode's loop: one button records what is played as new layers of the
/// timeline, the same one the sequencer edits. What the keys play is one
/// layer, and so is each line of the Tonnetz that was played (`LoopLine`).
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
    static let maxLoops = Timeline.maxLayers

    /// The shortest take that becomes a loop, in seconds. Anything shorter
    /// is an accidental double tap.
    static let minimumSeconds = 0.5

    weak var host: (any LoopHost)?
    private let logger: (any Logger)?

    /// The take being recorded: when it began on the clock, in beats, and
    /// what each line has played in it.
    private var take: (start: Double, lines: [LoopLine: LoopTake])?
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

    // MARK: – What is played, while a take is being recorded

    /// `line` started a chord, played with `playing`.
    func chordStarted(_ event: ChordEvent, pitch: NotePitch, playing: NotePlaying, on line: LoopLine = .keys) {
        guard let host, let start = take?.start else { return }
        take?.lines[line, default: LoopTake(start: start)]
            .chordStarted(event, pitch: pitch, playing: playing, at: host.clockBeats)
    }

    func chordEnded(on line: LoopLine = .keys) {
        guard let host else { return }
        take?.lines[line]?.chordEnded(at: host.clockBeats)
    }

    /// The effects the keys are played with changed (a slide, a zone, a setting).
    func effectsChanged() {
        guard let host, let effects = host.playedNow.effects else { return }
        take?.lines[.keys]?.effectsChanged(to: effects, at: host.clockBeats)
    }

    // MARK: – Private

    private func beginRecording() {
        guard let host, let sequencer else { return }
        // Over what is already there, the take is played along to it.
        if !sequencer.timeline.isEmpty, !sequencer.isPlaying { sequencer.isPlaying = true }
        // The place in the timeline that is being heard as the take starts:
        // a little behind where the clock has it, by the layers' lead.
        let length = sequencer.timeline.length
        let lead = Int((host.layerLead * host.bpm / 60 * Double(TimelineTime.ticksPerBeat)).rounded())
        takeOffset = sequencer.timeline.isEmpty ? 0 : (((sequencer.position ?? 0) - lead) % length + length) % length
        take = (host.clockBeats, [:])
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

        // The lines that played, the keys' first.
        let lines = LoopLine.allCases.compactMap { take.lines[$0] }
        guard !lines.isEmpty else {
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
            let layers = lines.map { $0.notes(closedAt: end, ticksPerBeat: ticksPerBeat) }.filter { !$0.isEmpty }
            sequencer.startLoop(Array(layers.prefix(Self.maxLoops)), bars: fit.bars)
            host.setBPM(fit.bpm)
            sequencer.isPlaying = true
            logger?.log(.loop_recorded(track: track, seconds: seconds, setsLength: true))
        } else {
            let rounds = lines.flatMap { line in
                sequencer.timeline.folded(line.notes(closedAt: end, ticksPerBeat: Double(TimelineTime.ticksPerBeat)),
                                          from: takeOffset)
            }
            let room = Self.maxLoops - loops.count
            if rounds.count > room {
                logger?.log(.loop_take_discarded(track: track + room, reason: "no layers left"))
            }
            sequencer.addLayers(Array(rounds.prefix(room)))
            logger?.log(.loop_recorded(track: track, seconds: seconds, setsLength: false))
        }
    }
}
