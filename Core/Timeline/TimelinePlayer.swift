/// What a layer's chords are played on: one for each layer, so layers
/// overlap freely. `play` replaces whatever the voice is sounding.
@MainActor
protocol TimelineVoice: AnyObject {
    func play(_ chord: TimedChord)
    func stop()
}

/// Plays a timeline against the clock, round and round, under whatever else
/// is being played. It is not a performance mode: like the arpeggiator it
/// runs beneath all of them.
///
/// Every chord starts and ends on its own tick: the player asks the clock
/// for one call at the next moment anything happens, and inside that call
/// time is the moment itself, so playback neither drifts nor depends on how
/// promptly the clock got round to it. A change of tempo moves the pending
/// call with it.
///
/// The timeline can be changed while it plays. A chord that is sounding
/// carries on if its note is still there unchanged, and stops if not; new
/// and changed notes are heard from their next start.
@MainActor
final class TimelinePlayer {

    /// The timeline being played. Setting it while playing takes effect at
    /// once, from wherever the playhead is.
    var timeline: Timeline {
        didSet {
            guard timeline != oldValue, isPlaying else { return }
            replan()
        }
    }

    /// What notes follow where they have no settings of their own. Changing
    /// it is heard from each layer's next chord.
    var live: LiveSettings {
        didSet {
            guard live != oldValue, isPlaying else { return }
            replan()
        }
    }

    private(set) var isPlaying = false

    /// Called as the playhead enters each step (counted from the start of
    /// the timeline), and with nil when playback stops.
    var onStep: ((Int?) -> Void)?

    private let clock: any ClockTickable
    private let makeVoice: () -> any TimelineVoice

    private struct Playing {
        let voice: any TimelineVoice
        var chords: [TimedChord] = []
        /// The chord the voice is sounding.
        var sounding: TimedChord?
    }

    private var layers: [Layer.ID: Playing] = [:]
    /// The tick the playhead was at when the clock last called, and the
    /// clock's position then.
    private var cursor = 0
    private var cursorBeats = 0.0
    private var next: ClockCall?

    init(timeline: Timeline = Timeline(), live: LiveSettings,
         clock: any ClockTickable, makeVoice: @escaping () -> any TimelineVoice) {
        self.timeline = timeline
        self.live = live
        self.clock = clock
        self.makeVoice = makeVoice
    }

    /// Where the playhead is, in ticks from the start of the timeline; nil
    /// while stopped.
    var position: Int? {
        guard isPlaying else { return nil }
        let range = timeline.playedRange
        let moved = Int(((clock.beats - cursorBeats) * Double(TimelineTime.ticksPerBeat)).rounded(.down))
        // Between calls the playhead is short of the next one, so short of
        // the end of the stretch while it is inside it.
        let here = cursor + max(moved, 0)
        return range.contains(cursor) ? min(here, range.upperBound - 1) : here
    }

    /// Starts from the beginning of the stretch that repeats. Does nothing
    /// if already playing.
    func start() {
        guard !isPlaying else { return }
        isPlaying = true
        compile()
        arrive(at: timeline.playedRange.lowerBound)
    }

    func stop() {
        guard isPlaying else { return }
        isPlaying = false
        next?.cancel()
        next = nil
        for id in layers.keys { silence(id) }
        layers = [:]
        onStep?(nil)
    }

    // MARK: – Private

    /// Reads the timeline again, keeping a voice for each layer that is
    /// still there and stopping the voices of layers that are gone.
    private func compile() {
        var compiled: [Layer.ID: Playing] = [:]
        for layer in timeline.layers {
            var playing = layers[layer.id] ?? Playing(voice: makeVoice())
            playing.chords = layer.isMuted ? [] : timeline.compile(layer: layer.id, live: live)
            compiled[layer.id] = playing
        }
        for id in layers.keys where compiled[id] == nil { silence(id) }
        layers = compiled
    }

    /// The timeline or the live settings changed under the playhead.
    private func replan() {
        let here = position ?? timeline.playedRange.lowerBound
        compile()
        for id in layers.keys {
            guard let sounding = layers[id]?.sounding else { continue }
            // A chord carries on only as the same chord of the same note;
            // its end may have moved.
            if let same = layers[id]?.chords.first(where: { $0.start == sounding.start && $0.event == sounding.event }),
               same.end > here {
                layers[id]?.sounding = same
            } else {
                silence(id)
            }
        }
        cursor = here
        cursorBeats = clock.beats
        schedule()
    }

    /// The playhead has reached `tick`: starts what starts there, ends what
    /// has ended, and asks for the next call. A playhead at the end of the
    /// stretch that repeats, or left outside it by a change of loop, goes to
    /// its beginning.
    private func arrive(at tick: Int) {
        let range = timeline.playedRange
        let wrapped = !range.contains(tick)
        cursor = wrapped ? range.lowerBound : tick
        cursorBeats = clock.beats
        for id in layers.keys {
            if let chord = layers[id]?.chords.first(where: { $0.start == cursor }) {
                // Playing replaces what the voice was sounding, so a chord
                // that ends where the next begins needs no stop between.
                layers[id]?.sounding = chord
                layers[id]?.voice.play(chord)
            } else if wrapped || (layers[id]?.sounding?.end ?? .max) <= tick {
                silence(id)
            }
        }
        if TimelineTime.isOnGrid(cursor) { onStep?(TimelineTime.step(at: cursor)) }
        schedule()
    }

    /// Asks the clock for a call at the next tick anything happens on: a
    /// chord's start or end, a step line, or the end of the stretch. The
    /// call goes ahead of others due at the same moment, so a chord that
    /// starts there replaces the old one before anything plays on from it.
    private func schedule() {
        next?.cancel()
        let range = timeline.playedRange
        let stepLine = (TimelineTime.step(at: cursor) + 1) * TimelineTime.ticksPerStep
        var due = stepLine
        // A playhead outside the stretch keeps the pulse: it joins at the
        // next step line.
        if range.contains(cursor) {
            due = min(due, range.upperBound)
            for playing in layers.values {
                if let end = playing.sounding?.end, end > cursor { due = min(due, end) }
                if let start = playing.chords.first(where: { $0.start > cursor })?.start { due = min(due, start) }
            }
        }
        let beats = Double(due - cursor) / Double(TimelineTime.ticksPerBeat)
        next = clock.after(beats: beats, first: true) { [weak self] in self?.arrive(at: due) }
    }

    private func silence(_ id: Layer.ID) {
        guard layers[id]?.sounding != nil else { return }
        layers[id]?.sounding = nil
        layers[id]?.voice.stop()
    }
}
