import MusicTheoryCore

/// Model 5, the couch arranger: the other layouts play, this one writes. A
/// cursor moves over four bars of beats with the d-pad, the two sticks aim a
/// chord as Twin rings does, and RT writes it at the cursor, held as long as
/// RT was pulled deep. Y plays the bars round in a loop, through the same
/// sound and MIDI as everything else, and the menu saves them as a MIDI file.
public struct Arranger: Layout {
    /// Beats in a bar, and bars in the arrangement.
    public static let beatsPerBar = 4
    public static let bars = 4
    public static var length: Int { beatsPerBar * bars }

    /// A chord on each beat it starts on; nil holds the chord before.
    public private(set) var beats: [DeskChord?] = Array(repeating: nil, count: Arranger.length)
    public private(set) var cursor = 0
    public private(set) var degree = Degree.I
    private var degreeSector: Int? = DegreePie.sector(of: .I)
    public private(set) var aim: RingCell?
    private var ringSector: Int?
    private var band: Int?
    /// How many beats a write is held for, from RT's depth while writing.
    public private(set) var writing: Int?
    /// When playing began, and the beat it began on; nil while stopped.
    public private(set) var playing: (since: Double, from: Int)?
    /// The beat heard now, while playing.
    public private(set) var playhead: Int?
    public private(set) var line = ChordLine()
    private var undo: [[DeskChord?]] = []
    private var commit = TriggerStrike()
    private var isAuditioning = false

    public init() {}

    public static func == (a: Arranger, b: Arranger) -> Bool {
        a.beats == b.beats && a.cursor == b.cursor && a.degree == b.degree && a.aim == b.aim
            && a.writing == b.writing && a.playing?.since == b.playing?.since && a.playing?.from == b.playing?.from
            && a.playhead == b.playhead && a.line == b.line && a.undo == b.undo && a.commit == b.commit
            && a.isAuditioning == b.isAuditioning && a.ringSector == b.ringSector && a.band == b.band
            && a.degreeSector == b.degreeSector
    }

    public mutating func step(_ input: PadInput, settings: inout DeskSettings) -> [DeskEffect] {
        var out: [DeskEffect] = []
        let time = input.time

        // The cursor, a beat or a bar at a time.
        if input.pressed(.left) { cursor = (cursor + Self.length - 1) % Self.length }
        if input.pressed(.right) { cursor = (cursor + 1) % Self.length }
        if input.pressed(.up) { cursor = (cursor + Self.length - Self.beatsPerBar) % Self.length }
        if input.pressed(.down) { cursor = (cursor + Self.beatsPerBar) % Self.length }
        if input.pressed(.lb) { settings.tempo = max(DeskSettings.tempos.lowerBound, settings.tempo - 4) }
        if input.pressed(.rb) { settings.tempo = min(DeskSettings.tempos.upperBound, settings.tempo + 4) }

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

        // Writing: A a beat, RT as long as it is pulled deep.
        if input.pressed(.a) { write(aimed(settings), beats: 1) }
        for event in commit.step(input.frame.rightTrigger, at: time) {
            switch event {
            case .strike: writing = 1
            case .depth(let depth): writing = max(writing ?? 1, depth < 0.5 ? 1 : depth < 0.85 ? 2 : 4)
            case .release:
                write(aimed(settings), beats: writing ?? 1)
                writing = nil
                out.append(.rumble(.tick))
            }
        }
        if input.pressed(.x) { write(nil, beats: 1) }
        if input.pressed(.b), let last = undo.popLast() { beats = last }

        // LT listens to the chord aimed, while nothing plays.
        let listening = input.frame.leftTrigger > 0.1 && playing == nil
        if listening {
            out += isAuditioning ? line.change(to: aimed(settings), settings: settings)
                : line.strike(aimed(settings), level: 0.3 + 0.6 * input.frame.leftTrigger, settings: settings, at: time)
        } else if isAuditioning {
            out += line.release()
        }
        isAuditioning = listening

        // Playing: Y starts and stops; each beat that starts a chord strikes it.
        if input.pressed(.y) {
            if playing == nil {
                playing = (time, cursor)
                playhead = nil
            } else {
                playing = nil
                playhead = nil
                out += line.release()
            }
        }
        if let playing {
            let elapsed = Int(((time - playing.since) * settings.tempo / 60).rounded(.down))
            let beat = (playing.from + elapsed) % Self.length
            if beat != playhead {
                playhead = beat
                if let chord = beats[beat] {
                    out += line.strike(chord, level: 0.8, settings: settings, at: time)
                } else if !line.isSounding, let held = chord(at: beat) {
                    out += line.strike(held, level: 0.8, settings: settings, at: time)
                }
            }
        }
        return out
    }

    /// The chord the sticks aim at.
    public func aimed(_ settings: DeskSettings) -> DeskChord {
        DeskChord(key: settings.key, degree: degree,
                  color: aim.map { settings.ring(degree).color(of: $0) } ?? .base)
    }

    /// Writes `chord` at the cursor, held for `count` beats, and moves the
    /// cursor past it. Nil clears the beat, so the chord before holds over it.
    private mutating func write(_ chord: DeskChord?, beats count: Int) {
        undo.append(beats)
        if undo.count > 64 { undo.removeFirst() }
        beats[cursor] = chord
        for held in 1..<max(1, count) { beats[(cursor + held) % Self.length] = nil }
        cursor = (cursor + max(1, count)) % Self.length
    }

    /// The chord sounding on `beat`: its own, or the last one before it,
    /// round the loop.
    public func chord(at beat: Int) -> DeskChord? {
        for back in 0..<Self.length {
            if let chord = beats[(beat - back + Self.length) % Self.length] { return chord }
        }
        return nil
    }

    public mutating func releaseAll() -> [DeskEffect] {
        playing = nil
        playhead = nil
        isAuditioning = false
        writing = nil
        commit = TriggerStrike()
        return line.release()
    }

    /// The arrangement as a Standard MIDI File: one track of its chords,
    /// each held to the next, at the tempo and in the key set.
    public func midiFile(_ settings: DeskSettings) -> MidiFile? {
        let ticks = 480
        let starts = beats.indices.filter { beats[$0] != nil }
        guard !starts.isEmpty else { return nil }
        var events: [MidiEvent] = [
            MidiEvent(tick: 0, .trackName("Perfecto Desk")),
            MidiEvent(tick: 0, .tempo(bpm: settings.tempo)),
            MidiEvent(tick: 0, .timeSignature(numerator: Self.beatsPerBar, denominator: 4)),
            MidiEvent(tick: 0, .keySignature(settings.key.midiKeySignature)),
        ]
        var previous: [Int]?
        for (index, start) in starts.enumerated() {
            let end = index + 1 < starts.count ? starts[index + 1] : Self.length
            let chord = beats[start]!
            let notes = chord.notes(settings, after: previous)
            previous = notes
            events.append(MidiEvent(tick: start * ticks, .marker(chord.name)))
            for note in notes {
                events.append(MidiEvent(tick: start * ticks, .noteOn(channel: 0, note: note, velocity: 100)))
                events.append(MidiEvent(tick: end * ticks, .noteOff(channel: 0, note: note)))
            }
        }
        return MidiFile(ticksPerQuarter: ticks, tracks: [MidiTrack(events: events, length: Self.length * ticks)])
    }

    // MARK: – What the screen shows

    public func degreeTargets(_ settings: DeskSettings) -> [Target] {
        DeskCore.degreeTargets(chosen: degree, sounding: nil, settings: settings)
    }

    public func legend(_ settings: DeskSettings) -> Legend {
        var legend = commonLegend(settings, voicing: false)
        legend[.button(.left)] = "Cursor back a beat"
        legend[.button(.right)] = "Cursor on a beat"
        legend[.button(.up)] = "Cursor up a bar"
        legend[.button(.down)] = "Cursor down a bar"
        legend[.leftStick] = "Degree · \(numeral(degree, in: settings.key))"
        legend[.rightStick] = "Color ring"
        legend[.rightTrigger] = "Write: deeper holds longer (1, 2, 4 beats)"
        legend[.leftTrigger] = "Listen to the aimed chord"
        legend[.button(.a)] = "Write a beat"
        legend[.button(.x)] = "Clear the beat"
        legend[.button(.y)] = playing == nil ? "Play from the cursor" : "Stop"
        legend[.button(.b)] = "Undo"
        legend[.button(.lb)] = "Tempo −4"
        legend[.button(.rb)] = "Tempo +4"
        return legend
    }
}
