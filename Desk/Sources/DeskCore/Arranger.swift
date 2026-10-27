import MusicTheoryCore

/// Model 5, the couch arranger: the other layouts play, this one writes. The
/// two sticks aim a chord as Twin rings does, and it is placed in four bars
/// of time, each chord as long as it is held:
///
/// - Stopped, RT held at the cursor writes the chord for as long as it is
///   held, at the tempo: the chord sounds and grows on the screen, a tick is
///   felt on each beat, and the length is snapped to the grid on letting go.
/// - Playing, RT writes at the playhead, live: the chord starts where it was
///   struck and is as long as it was held.
/// - LB and RB shorten and lengthen the chord at the cursor: a tap by a line
///   of the grid, a hold smoothly for as long as it is held.
///
/// Y plays the bars round, through the same sound and MIDI as everything
/// else, and the menu saves them as a MIDI file.
public struct Arranger: Layout {
    /// A chord being written by RT.
    public struct Writing: Equatable, Sendable {
        public let start: Double
        /// When RT struck, and how long it has been held, in beats.
        let since: Double
        public internal(set) var length: Double
        /// Written at the playhead while playing, not at the cursor.
        public let isLive: Bool
    }

    /// A chord being made longer or shorter by a bumper.
    struct Stretch: Equatable, Sendable {
        let start: Double
        let from: Double
        let direction: Double
        let since: Double
    }

    /// How fast a bumper held stretches a chord, in beats a second.
    public static let stretchRate = 2.0
    /// How long a bumper is held before it stretches smoothly.
    public static let stretchDelay = 0.3

    public private(set) var arrangement = Arrangement()
    /// Where the next chord is written, in beats.
    public private(set) var cursor = 0.0
    public private(set) var degree = Degree.I
    private var degreeSector: Int? = DegreePie.sector(of: .I)
    public private(set) var aim: RingCell?
    private var ringSector: Int?
    private var band: Int?
    public private(set) var writing: Writing?
    private var stretch: Stretch?
    /// When playing began, and the beat it began from; nil while stopped.
    public private(set) var playing: (since: Double, from: Double)?
    /// Where the playing is, in beats, while it plays.
    public private(set) var playhead: Double?
    /// The chord heard from the arrangement, by its start, and the time
    /// round the loop it is heard in.
    private var heard: (start: Double, round: Int)?
    public private(set) var line = ChordLine()
    private var undo: [Arrangement] = []
    private var commit = TriggerStrike()
    private var isAuditioning = false
    /// The beat a write or a stretch last ticked on.
    private var ticked = 0

    public init() {}

    public static func == (a: Arranger, b: Arranger) -> Bool {
        a.arrangement == b.arrangement && a.cursor == b.cursor && a.degree == b.degree && a.aim == b.aim
            && a.writing == b.writing && a.stretch == b.stretch && a.playing?.since == b.playing?.since
            && a.playing?.from == b.playing?.from && a.playhead == b.playhead && a.heard?.start == b.heard?.start
            && a.heard?.round == b.heard?.round && a.line == b.line && a.undo == b.undo && a.commit == b.commit
            && a.isAuditioning == b.isAuditioning && a.ringSector == b.ringSector && a.band == b.band
            && a.degreeSector == b.degreeSector && a.ticked == b.ticked
    }

    public mutating func step(_ input: PadInput, settings: inout DeskSettings) -> [DeskEffect] {
        var out: [DeskEffect] = []
        let time = input.time
        let grid = settings.grid
        let length = Arrangement.length

        // The cursor, a line of the grid or a bar at a time.
        if writing == nil {
            if input.pressed(.left) { cursor = wrap(grid.nearest(cursor - grid.move)) }
            if input.pressed(.right) { cursor = wrap(grid.nearest(cursor + grid.move)) }
            if input.pressed(.up) { cursor = wrap(cursor - Double(Arrangement.beatsPerBar)) }
            if input.pressed(.down) { cursor = wrap(cursor + Double(Arrangement.beatsPerBar)) }
        }
        if input.pressed(.l3) {
            settings.moveGrid(by: 1)
            cursor = wrap(settings.grid.nearest(cursor))
            out.append(.rumble(.tick))
        }

        // The aim: the degree and the ring, as Twin rings has them.
        degreeSector = DegreePie.gate.select(input.frame.left, from: degreeSector)
        if let degreeSector, input.frame.left.radius >= PieGate.rest { degree = DegreePie.degree(at: degreeSector) }
        let pie = settings.ring(degree)
        ringSector = pie.gate.select(input.frame.right, from: ringSector)
        if let ringSector {
            band = RadialBands.three.band(input.frame.right.radius, from: band)
            aim = pie.cell(sector: ringSector, band: band!, extended: false)
        } else {
            band = nil
            aim = nil
        }

        // Playing: Y starts and stops, from the cursor.
        if input.pressed(.y) {
            if playing == nil {
                playing = (time, cursor)
            } else {
                playing = nil
                playhead = nil
                heard = nil
                if writing == nil { out += line.release() }
            }
        }
        var round = 0
        if let playing {
            let beats = playing.from + (time - playing.since) * settings.tempo / 60
            round = Int((beats / length).rounded(.down))
            playhead = beats - Double(round) * length
        }

        // A: a beat's chord at the cursor.
        if input.pressed(.a), writing == nil {
            let chord = aimed(settings), at = cursor
            edit { $0.place(chord, at: at, length: 1) }
            cursor = wrap(cursor + 1)
        }

        // RT: a chord for as long as it is held.
        for event in commit.step(input.frame.rightTrigger, at: time) {
            switch event {
            case .strike(let level):
                let live = playhead != nil
                let start = live ? wrap(grid.nearest(playhead!)) : cursor
                writing = Writing(start: start, since: time, length: 0, isLive: live)
                ticked = 0
                out += line.strike(aimed(settings), level: level, settings: settings, at: time)
                heard = nil
            case .depth:
                break
            case .release:
                guard let done = writing else { break }
                writing = nil
                let held = (time - done.since) * settings.tempo / 60
                let written = min(grid.length(held), length - done.start)
                let chord = aimed(settings)
                edit { $0.place(chord, at: done.start, length: written) }
                out.append(.rumble(.bump))
                if done.isLive {
                    // What sounds is the chord just written: playing carries on from it.
                    heard = (done.start, round)
                } else {
                    cursor = wrap(done.start + written)
                    out += line.release()
                }
            }
        }
        if var held = writing {
            held.length = min(length - held.start, (time - held.since) * settings.tempo / 60)
            writing = held
            let beat = Int(held.length.rounded(.down))
            if beat > ticked {
                ticked = beat
                out.append(.rumble(.tick))
            }
            out += line.change(to: aimed(settings), settings: settings)
        }

        // LB and RB: the chord at the cursor shorter and longer.
        for (button, direction) in [(PadButton.lb, -1.0), (.rb, 1.0)] {
            if input.pressed(button), writing == nil, let placed = arrangement.chord(near: cursor) {
                undo.append(arrangement)
                stretch = Stretch(start: placed.start, from: placed.length, direction: direction, since: time)
                ticked = 0
            }
            if input.released(button), stretch?.direction == direction { stretch = nil }
        }
        if let stretch {
            let held = max(0, time - stretch.since - Self.stretchDelay)
            let by = grid.move + held * Self.stretchRate
            let wanted = grid.nearest(stretch.from + stretch.direction * by)
            let atEnd = arrangement.chord(at: cursor) == nil
            if let made = arrangement.resize(stretch.start, to: wanted, shortest: grid.shortest) {
                if atEnd { cursor = wrap(stretch.start + made) }
                let steps = Int((abs(made - stretch.from) / grid.move).rounded(.down))
                if steps > ticked {
                    ticked = steps
                    out.append(.rumble(.tick))
                }
            }
        }

        if input.pressed(.x), writing == nil {
            let at = cursor
            edit { $0.clear(at: at) }
        }
        if input.pressed(.b), writing == nil, let last = undo.popLast() { arrangement = last }

        // LT listens to the chord aimed, while nothing plays or is written.
        let listening = input.frame.leftTrigger > 0.1 && playing == nil && writing == nil
        if listening {
            out += isAuditioning ? line.change(to: aimed(settings), settings: settings)
                : line.strike(aimed(settings), level: 0.3 + 0.6 * input.frame.leftTrigger, settings: settings, at: time)
        } else if isAuditioning, writing == nil {
            out += line.release()
        }
        isAuditioning = listening

        // What plays: the chord under the playhead, struck as it starts.
        if let playhead, writing == nil {
            let placed = arrangement.chord(at: playhead)
            if placed?.start != heard?.start || (placed != nil && round != heard?.round) {
                if let placed {
                    heard = (placed.start, round)
                    out += line.strike(placed.chord, level: 0.8, settings: settings, at: time)
                } else {
                    heard = nil
                    out += line.release()
                }
            }
        }
        out += line.tick(settings, at: time)
        return out
    }

    /// The chord the sticks aim at.
    public func aimed(_ settings: DeskSettings) -> DeskChord {
        DeskChord(key: settings.key, degree: degree,
                  color: aim.map { settings.ring(degree).color(of: $0) } ?? .base)
    }

    /// Makes an edit that undo can take back.
    private mutating func edit(_ change: (inout Arrangement) -> Void) {
        undo.append(arrangement)
        if undo.count > 64 { undo.removeFirst() }
        change(&arrangement)
    }

    /// `beats` round the loop.
    private func wrap(_ beats: Double) -> Double {
        let length = Arrangement.length
        let wrapped = beats.truncatingRemainder(dividingBy: length)
        return wrapped < 0 ? wrapped + length : wrapped
    }

    public mutating func releaseAll() -> [DeskEffect] {
        playing = nil
        playhead = nil
        heard = nil
        isAuditioning = false
        writing = nil
        stretch = nil
        commit = TriggerStrike()
        return line.release()
    }

    /// The arrangement as a Standard MIDI File: one track of its chords, each
    /// as long as it was written, at the tempo and in the key set.
    public func midiFile(_ settings: DeskSettings) -> MidiFile? {
        guard !arrangement.isEmpty else { return nil }
        let ticks = 480
        func tick(_ beats: Double) -> Int { Int((beats * Double(ticks)).rounded()) }
        var events: [MidiEvent] = [
            MidiEvent(tick: 0, .trackName("Perfecto Desk")),
            MidiEvent(tick: 0, .tempo(bpm: settings.tempo)),
            MidiEvent(tick: 0, .timeSignature(numerator: Arrangement.beatsPerBar, denominator: 4)),
            MidiEvent(tick: 0, .keySignature(settings.key.midiKeySignature)),
        ]
        var previous: [Int]?
        for placed in arrangement.chords {
            let notes = placed.chord.notes(settings, after: previous)
            previous = notes
            events.append(MidiEvent(tick: tick(placed.start), .marker(placed.chord.name)))
            for note in notes {
                events.append(MidiEvent(tick: tick(placed.start), .noteOn(channel: 0, note: note, velocity: 100)))
                events.append(MidiEvent(tick: tick(placed.end), .noteOff(channel: 0, note: note)))
            }
        }
        return MidiFile(ticksPerQuarter: ticks, tracks: [MidiTrack(events: events, length: tick(Arrangement.length))])
    }

    // MARK: – What the screen shows

    public func degreeTargets(_ settings: DeskSettings) -> [Target] {
        DeskCore.degreeTargets(chosen: degree, sounding: nil, settings: settings)
    }

    public func legend(_ settings: DeskSettings) -> Legend {
        var legend = commonLegend(settings, voicing: false)
        let grid = settings.grid
        legend[.button(.left)] = "Cursor back " + (grid.step == nil ? "a sixteenth" : grid.name)
        legend[.button(.right)] = "Cursor on " + (grid.step == nil ? "a sixteenth" : grid.name)
        legend[.button(.up)] = "Cursor up a bar"
        legend[.button(.down)] = "Cursor down a bar"
        legend[.leftStick] = "Degree · \(numeral(degree, in: settings.key))"
        legend[.rightStick] = "Color ring"
        legend[.rightTrigger] = playing == nil ? "Hold to write: as long as it's held" : "Record live at the playhead"
        legend[.leftTrigger] = "Listen to the aimed chord"
        legend[.button(.a)] = "Write a beat"
        legend[.button(.x)] = "Clear the chord"
        legend[.button(.y)] = playing == nil ? "Play from the cursor" : "Stop"
        legend[.button(.b)] = "Undo"
        legend[.button(.lb)] = "Shorter: tap a step, hold smoothly"
        legend[.button(.rb)] = "Longer: tap a step, hold smoothly"
        legend[.button(.l3)] = "Grid: \(grid.name) → next"
        return legend
    }
}
