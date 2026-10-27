import Foundation
import Observation

/// What the loop controls need from whatever plays the keys and the timeline.
@MainActor
protocol LoopHost: AnyObject {
    /// The sequencer whose timeline loops are layers of.
    var loopSequencer: SequencerState? { get }
    /// The clock that times the count-in and the take, and whose beats a
    /// take is recorded in.
    var loopClock: any ClockTickable { get }
    var bpm: Double { get }
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
/// a layer is, so what each played in a take becomes layers of its own. The
/// keys are the only line for now.
enum LoopLine: CaseIterable {
    case keys
}

/// One layer of the timeline, as the loop bar shows it.
struct QuickLoopEntry: Identifiable, Equatable {
    let id: Layer.ID
    /// Whether the layer is heard (not paused).
    var isPlaying: Bool
}

/// A moment in recording a loop that is felt as well as seen: what the
/// loop bar plays as haptics. Each is set as it happens, and cleared when a
/// take is called off, so the same moment twice in a row is felt twice.
enum LoopCue: Equatable {
    /// A second of the count-in, with the seconds left in it.
    case count(Int)
    /// Recording began.
    case go
    /// The take became a loop.
    case done
    /// The take ended with nothing in it to keep.
    case dropped
}

/// Play mode's loop: what is played for a chosen number of bars becomes new
/// layers of the timeline. What the keys play is one layer (`LoopLine`).
///
/// The LOOP button offers the lengths (`lengths`); choosing one counts in
/// for three seconds, then records for that many bars at the tempo set, and
/// the take plays from the moment it ends. The first loop sets the
/// timeline's length. A later take is laid on at the point in the loop
/// where it was played, and a take and the timeline of different lengths
/// are each repeated until they come round together (`Timeline.layering`).
/// What the loops play is never recorded into a take: a take is the chords
/// the keys play, not sound.
@Observable
@MainActor
final class QuickLoopState {
    enum Phase: Equatable {
        case idle
        /// The lengths are on offer.
        case choosing
        /// Counting in to the take: `remaining` seconds before it begins.
        case countingIn(remaining: Int)
        /// Recording, from `start` to `end` on the clock, in beats.
        case recording(start: Double, end: Double)
    }

    private(set) var phase: Phase = .idle

    /// The most layers there can be.
    static let maxLoops = Timeline.maxLayers

    /// The lengths a loop can be, in bars. Each is a whole number of the
    /// shorter ones, so layers of any of them come round together.
    static let lengths = [1, 2, 4, 8]

    /// The seconds counted in before a take.
    static let countIn = 3

    /// The length of the next take, in bars: the one chosen last.
    private(set) var bars = 2

    /// While on, tapping a loop's chit deletes it.
    private(set) var isDeleting = false

    /// The last moment to be felt (`LoopCue`).
    private(set) var cue: LoopCue?

    weak var host: (any LoopHost)?
    private let logger: (any Logger)?

    /// The take being recorded: when it began on the clock, in beats, and
    /// what each line has played in it.
    private var take: (start: Double, lines: [LoopLine: LoopTake])?
    /// Where in the timeline the take began, in ticks.
    private var takeOffset = 0
    /// The chord the keys started during the count-in, while it sounds: a
    /// take begins with it, so a chord struck on the last count, or a
    /// moment early, is in the loop.
    private var countedInChord: (event: ChordEvent, pitch: NotePitch, playing: NotePlaying)?
    /// The clock's call for the next second of the count-in, or the end of
    /// the take.
    private var next: ClockCall?

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

    /// Whether a take is counting in or recording.
    var isTaking: Bool {
        switch phase {
        case .countingIn, .recording: true
        case .idle, .choosing: false
        }
    }

    /// How long a take of `bars` bars lasts at the tempo set, in seconds.
    func seconds(ofBars bars: Int) -> Double {
        guard let host, let sequencer else { return 0 }
        return Double(bars) * sequencer.timeline.signature.quarterBeatsPerBar * 60 / host.bpm
    }

    /// How far the take has got, 0 to 1, and the seconds left in it; nil
    /// while none is recording. It moves with the clock, so a view showing
    /// it redraws on its own schedule.
    var recordingProgress: (share: Double, secondsLeft: Double)? {
        guard case let .recording(start, end) = phase, let host else { return nil }
        let beats = host.loopClock.beats
        let share = ((beats - start) / (end - start)).clamped(to: 0...1)
        return (share, max(end - beats, 0) * 60 / host.bpm)
    }

    // MARK: – The controls

    /// The LOOP button: offers the lengths, or takes them away again, or
    /// calls off the take counting in or recording.
    func triggerTapped() {
        switch phase {
        case .idle where canStartNew:
            isDeleting = false
            phase = .choosing
        case .idle:
            break
        case .choosing:
            phase = .idle
        case .countingIn, .recording:
            cancelTake()
        }
    }

    /// The LOOP button's key on the keyboard, which has no way to point at a
    /// length: it counts in to a take of the length chosen last, and
    /// otherwise does what the button does.
    func hotkeyTapped() {
        switch phase {
        case .idle where canStartNew, .choosing:
            countIn()
        default:
            triggerTapped()
        }
    }

    /// A length was chosen: counts in to a take of `bars` bars.
    func choose(bars: Int) {
        guard phase == .choosing, Self.lengths.contains(bars) else { return }
        self.bars = bars
        countIn()
    }

    /// The trash chit: switches deleting on or off. Not while a take is
    /// being made, which the layers it is laid on must stay for.
    func toggleDeleting() {
        guard !isTaking else { return }
        if phase == .choosing { phase = .idle }
        isDeleting.toggle()
    }

    /// A tap anywhere but the loop bar: puts away the lengths, and stops
    /// deleting.
    func dismiss() {
        isDeleting = false
        if phase == .choosing { phase = .idle }
    }

    /// A loop's chit: deletes the loop while deleting is on, and otherwise
    /// pauses it, or resumes it in time.
    func loopTapped(id: Layer.ID) {
        if isDeleting { removeLoop(id: id) } else { togglePlayback(id: id) }
    }

    /// Starts everything playing from the top, or stops it.
    func toggleRunning() {
        guard let sequencer, !loops.isEmpty else { return }
        if isTaking { cancelTake() }
        if phase == .choosing { phase = .idle }
        sequencer.isPlaying.toggle()
    }

    /// Pauses a layer, or resumes it; it rejoins in time.
    func togglePlayback(id: Layer.ID) {
        guard let sequencer, let layer = sequencer.timeline.layer(id) else { return }
        sequencer.setLayer(id, muted: !layer.isMuted)
    }

    func removeLoop(id: Layer.ID) {
        guard let sequencer, let index = sequencer.timeline.layers.firstIndex(where: { $0.id == id }) else { return }
        sequencer.removeLayer(id)
        logger?.log(.loop_cleared(track: index))
        if sequencer.timeline.isEmpty {
            sequencer.isPlaying = false
            isDeleting = false
        }
    }

    /// Removes every loop, and drops the take being made if there is one.
    func clearAll() {
        cancelTake()
        isDeleting = false
        guard let sequencer else { return }
        sequencer.isPlaying = false
        sequencer.removeAllLayers()
    }

    // MARK: – What is played, while a take is being made

    /// `line` started a chord, played with `playing`.
    func chordStarted(_ event: ChordEvent, pitch: NotePitch, playing: NotePlaying, on line: LoopLine = .keys) {
        if case .countingIn = phase, line == .keys {
            countedInChord = (event, pitch, playing)
        }
        guard let host, let start = take?.start else { return }
        take?.lines[line, default: LoopTake(start: start)]
            .chordStarted(event, pitch: pitch, playing: playing, at: host.loopClock.beats)
    }

    func chordEnded(on line: LoopLine = .keys) {
        if line == .keys { countedInChord = nil }
        guard let host else { return }
        take?.lines[line]?.chordEnded(at: host.loopClock.beats)
    }

    /// The effects the keys are played with changed (a slide, a zone, a setting).
    func effectsChanged() {
        guard let host, let effects = host.playedNow.effects else { return }
        take?.lines[.keys]?.effectsChanged(to: effects, at: host.loopClock.beats)
    }

    // MARK: – Private

    /// Counts in to a take of `bars` bars, with whatever is already there
    /// playing to be played along to.
    private func countIn() {
        guard let sequencer else { return }
        isDeleting = false
        if !sequencer.timeline.isEmpty, !sequencer.isPlaying { sequencer.isPlaying = true }
        logger?.log(.loop_count_in_started(track: loops.count, bars: bars))
        count(Self.countIn)
    }

    /// `remaining` seconds of the count-in are left.
    private func count(_ remaining: Int) {
        guard let host else { return }
        phase = .countingIn(remaining: remaining)
        cue = .count(remaining)
        next = host.loopClock.after(seconds: 1) { [weak self] in
            if remaining > 1 { self?.count(remaining - 1) } else { self?.beginRecording() }
        }
    }

    private func beginRecording() {
        guard let host, let sequencer else { return }
        let clock = host.loopClock
        // The place in the timeline that is being heard as the take starts:
        // a little behind where the clock has it, by the layers' lead.
        let length = sequencer.timeline.length
        let lead = Int((host.layerLead * host.bpm / 60 * Double(TimelineTime.ticksPerBeat)).rounded())
        takeOffset = sequencer.timeline.isEmpty ? 0 : (((sequencer.position ?? 0) - lead) % length + length) % length

        let start = clock.beats
        let end = start + Double(bars) * sequencer.timeline.signature.quarterBeatsPerBar
        var lines: [LoopLine: LoopTake] = [:]
        if let chord = countedInChord {
            var keys = LoopTake(start: start)
            keys.chordStarted(chord.event, pitch: chord.pitch, playing: chord.playing, at: start)
            lines[.keys] = keys
        }
        countedInChord = nil
        take = (start, lines)
        phase = .recording(start: start, end: end)
        cue = .go
        next = clock.after(beats: end - start) { [weak self] in self?.finishRecording() }
        logger?.log(.loop_record_started(track: loops.count))
    }

    private func cancelTake() {
        guard isTaking else { return }
        logger?.log(.loop_take_discarded(track: loops.count, reason: "called off"))
        endTake()
        cue = nil
    }

    private func endTake() {
        next?.cancel()
        next = nil
        take = nil
        countedInChord = nil
        phase = .idle
    }

    private func finishRecording() {
        guard let host, let sequencer, let take, case let .recording(_, end) = phase else { return endTake() }
        host.endChord()
        endTake()
        let track = loops.count

        // The lines that played, the keys' first.
        let lines = LoopLine.allCases.compactMap { take.lines[$0] }
            .map { $0.notes(closedAt: end, ticksPerBeat: Double(TimelineTime.ticksPerBeat)) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else {
            logger?.log(.loop_take_discarded(track: track, reason: "nothing played"))
            cue = .dropped
            return
        }
        let room = Self.maxLoops - track
        if lines.count > room {
            logger?.log(.loop_take_discarded(track: track + room, reason: "no layers left"))
        }
        let setsLength = sequencer.timeline.isEmpty
        sequencer.layerTake(Array(lines.prefix(room)), bars: bars, from: takeOffset)
        // A first loop plays from its top the moment it ends.
        if !sequencer.isPlaying { sequencer.isPlaying = true }
        logger?.log(.loop_recorded(track: track, seconds: (end - take.start) * 60 / host.bpm, setsLength: setsLength))
        cue = .done
    }
}
