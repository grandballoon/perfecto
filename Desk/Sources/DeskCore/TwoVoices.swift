import MusicTheoryCore

/// Model 4, two hands, two voices: each hand an instrument, each with its
/// trigger as pressure. The left hand plays the chords, LT their swell, an
/// organ's expression pedal; the right hand plays a line over them, the
/// stick a pie of the key's notes and RT the pressure a phone cannot sense.
/// With RB held the right stick is a Trautonium's bar: the line's pitch
/// follows the stick, and comes to rest on the key's nearest note.
public struct TwoVoices: Layout {
    public private(set) var degree = Degree.I
    private var degreeSector: Int? = DegreePie.sector(of: .I)
    public private(set) var height = StackHeight.triad
    public private(set) var chords = ChordLine()
    /// Whether the chord sounds whether or not LT is pulled.
    public private(set) var drones = false
    public private(set) var melody = MelodyVoice()
    /// The note petal pointed at, and whether in the outer ring.
    public private(set) var petal: Int?
    private var band: Int?
    /// The line's octave above the chords'.
    public private(set) var lineOctave = 1
    /// Whether only the chord's own notes can be pointed at.
    public private(set) var chordTonesOnly = false
    public private(set) var isOnBar = false
    /// The bar's pitch, and when it last moved.
    public private(set) var barPitch: Double?
    private var barMoved = 0.0
    private var swell = TriggerStrike()
    private var pressure = TriggerStrike()

    public static let lineOctaves = 0...3
    /// The bar's range, in semitones above the tonic.
    public static let barSpan = 24.0
    /// How long the bar's pitch has to stay put to come to rest on a note.
    public static let restTime = 0.12

    public init() {}

    public mutating func step(_ input: PadInput, settings: inout DeskSettings) -> [DeskEffect] {
        var out: [DeskEffect] = []
        let time = input.time

        if input.pressed(.b) {
            drones = false
            out += chords.release() + melody.release()
        }
        if input.pressed(.a) {
            drones.toggle()
            if drones, !chords.isSounding, let why = settings.consonance.refusal(of: chord(settings), in: settings.key) {
                drones = false
                out.append(.refuse(why))
            } else if drones, !chords.isSounding {
                out += chords.strike(chord(settings), level: 0.7, settings: settings, at: time)
            } else if !drones, !swell.isHeld {
                out += chords.release()
            }
        }
        if input.pressed(.x) {
            out += chords.arpeggiate(chords.arpeggio == nil ? .eighth : nil, settings: settings, at: time)
        }
        if input.pressed(.y) { chordTonesOnly.toggle() }
        if input.pressed(.lb) {
            let heights: [StackHeight] = [.triad, .seventh, .ninth]
            height = heights[((heights.firstIndex(of: height) ?? 0) + 1) % heights.count]
            out.append(.rumble(.tick))
        }
        if input.pressed(.l3) { height = .triad }
        if input.pressed(.up) { lineOctave = min(Self.lineOctaves.upperBound, lineOctave + 1) }
        if input.pressed(.down) { lineOctave = max(Self.lineOctaves.lowerBound, lineOctave - 1) }
        if input.pressed(.left) || input.pressed(.right) {
            settings.roll(by: input.pressed(.left) ? -1 : 1)
            out += chords.revoice(settings)
        }

        // The left hand: the degree, and LT's swell.
        degreeSector = DegreePie.gate.select(input.frame.left, from: degreeSector)
        if let degreeSector, input.frame.left.radius >= PieGate.rest {
            // A degree whose chord the guard will not play is not chosen.
            var chosen = self
            chosen.degree = DegreePie.degree(at: degreeSector)
            if settings.playable(chosen.chord(settings)) { degree = chosen.degree }
        }
        for event in swell.step(input.frame.leftTrigger, at: time) {
            switch event {
            case .strike:
                if let why = settings.consonance.refusal(of: chord(settings), in: settings.key), !chords.isSounding {
                    out.append(.refuse(why))
                } else if !chords.isSounding {
                    out += chords.strike(chord(settings), level: 0.15, brightness: 0.5, settings: settings, at: time)
                }
            case .depth(let depth):
                out += chords.shape(level: 0.15 + 0.85 * depth, brightness: 0.5 + 0.5 * depth)
            case .release:
                if !drones { out += chords.release() }
            }
        }
        if settings.playable(chord(settings)) { out += chords.change(to: chord(settings), settings: settings) }

        // The right hand: a petal or the bar, and RT's pressure.
        isOnBar = input.isDown(.rb)
        let pitch = isOnBar ? barPitch(input, settings) : petalPitch(input.frame.right, settings)
        for event in pressure.step(input.frame.rightTrigger, at: time) {
            switch event {
            case .strike(let level):
                if let pitch {
                    let note = settings.key.note(nearest: pitch)
                    if let why = settings.consonance.refusal(ofNote: note, in: settings.key) {
                        out.append(.refuse(why))
                        continue
                    }
                    out += melody.strike(note, level: level, sound: settings.lineSound)
                    out += melody.glide(to: pitch)
                }
            case .depth(let depth):
                out += melody.shape(level: 0.25 + 0.75 * depth, brightness: 0.4 + 0.6 * depth)
            case .release:
                out += melody.release()
            }
        }
        if pressure.isHeld, let pitch { out += melody.glide(to: pitch) }
        out += chords.tick(settings, at: time)
        return out
    }

    /// The chord the left hand is on.
    public func chord(_ settings: DeskSettings) -> DeskChord {
        DeskChord(key: settings.key, degree: degree, color: height == .triad ? .base : .grid(height, nil))
    }

    public func degreeTargets(_ settings: DeskSettings) -> [Target] {
        DeskCore.degreeTargets(chosen: degree, sounding: chords.isSounding ? chords.chord : nil, settings: settings)
    }

    /// The pitch of the tonic the line starts from.
    func lineTonic(_ settings: DeskSettings) -> Int {
        (settings.octave + 1 + lineOctave) * 12 + settings.key.root.rawValue
    }

    /// The petals: the key's notes clockwise from the tonic at the top,
    /// those the chord has marked.
    public func petals(_ settings: DeskSettings) -> [(note: Int, isChordTone: Bool, isReachable: Bool)] {
        let chordPitches = chord(settings).pitchClasses
        return settings.key.scale.intervals.map { interval in
            let note = lineTonic(settings) + interval
            let isChordTone = chordPitches.contains(note % 12)
            let isAllowed = settings.consonance.allows(note: note, in: settings.key)
            return (note, isChordTone, (isChordTone || !chordTonesOnly) && isAllowed)
        }
    }

    private mutating func petalPitch(_ stick: Stick, _ settings: DeskSettings) -> Double? {
        barPitch = nil
        let petals = petals(settings)
        let reachable = petals.indices.filter { petals[$0].isReachable }
        let step = 360 / Double(petals.count)
        let gate = PieGate(bearings: reachable.map { Double($0) * step }, width: 180)
        let last = petal.flatMap { reachable.firstIndex(of: $0) }
        guard let chosen = gate.select(stick, from: last) else {
            petal = nil
            band = nil
            // A note held stays where it was while the stick comes back.
            return pressure.isHeld ? melody.pitch : nil
        }
        petal = reachable[chosen]
        band = RadialBands.two.band(stick.radius, from: band)
        return Double(petals[reachable[chosen]].note + 12 * band!)
    }

    private mutating func barPitch(_ input: PadInput, _ settings: DeskSettings) -> Double {
        petal = nil
        let raw = Double(lineTonic(settings)) + (input.frame.right.y + 1) / 2 * Self.barSpan
        if let barPitch, abs(raw - barPitch) > 0.08 { barMoved = input.time }
        if barPitch == nil { barMoved = input.time }
        barPitch = raw
        // At rest, the bar is in tune: on the key's nearest note.
        return input.time - barMoved >= Self.restTime ? Double(settings.key.note(nearest: raw)) : raw
    }

    public mutating func releaseAll() -> [DeskEffect] {
        drones = false
        swell = TriggerStrike()
        pressure = TriggerStrike()
        return chords.release() + melody.release()
    }

    public func legend(_ settings: DeskSettings) -> Legend {
        var legend = commonLegend(settings, voicing: false)
        legend[.leftStick] = "Degree · \(numeral(degree, in: settings.key))"
        legend[.leftTrigger] = "Chord swell"
        legend[.rightStick] = isOnBar ? "The bar: pitch follows, rests in tune" : "Line: the key's notes, outer ring an octave up"
        legend[.rightTrigger] = "Line pressure"
        legend[.button(.lb)] = "Color: \(height.displayName)"
        legend[.button(.rb)] = "Hold: the bar"
        legend[.button(.a)] = "Drone " + (drones ? "on" : "off")
        legend[.button(.b)] = "Let go"
        legend[.button(.x)] = "Arpeggio " + (chords.arpeggio == nil ? "off" : "on")
        legend[.button(.y)] = chordTonesOnly ? "Chord tones only" : "Every note of the key"
        legend[.button(.up)] = "Line octave up"
        legend[.button(.down)] = "Line octave down"
        legend[.button(.left)] = "Inversion down"
        legend[.button(.right)] = "Inversion up"
        legend[.button(.l3)] = "Plain triad"
        return legend
    }
}

/// One note at a time: struck, then shaped and bent while it is held, which
/// is heard as a slide.
public struct MelodyVoice: Equatable, Sendable {
    /// The note struck, sounding.
    public private(set) var note: Int?
    /// How far it is bent from its pitch, in semitones.
    public private(set) var bend = 0.0
    public private(set) var level = 0.8
    public private(set) var brightness = 1.0

    public init() {}

    /// The pitch it sounds at, bend and all.
    public var pitch: Double? { note.map { Double($0) + bend } }

    public mutating func strike(_ note: Int, level: Double, sound: String) -> [DeskEffect] {
        self.note = note
        self.level = level
        bend = 0
        return [.sound(.melody, notes: [note], sound: sound, level: level, brightness: brightness, tie: false)]
    }

    /// Slides what sounds to `pitch`.
    public mutating func glide(to pitch: Double) -> [DeskEffect] {
        guard let note, abs(pitch - Double(note) - bend) > 0.01 else { return [] }
        bend = pitch - Double(note)
        return [.shape(.melody, level: level, brightness: brightness, bend: bend)]
    }

    public mutating func shape(level: Double, brightness: Double) -> [DeskEffect] {
        guard abs(level - self.level) > 0.01 || abs(brightness - self.brightness) > 0.01 else { return [] }
        self.level = level
        self.brightness = brightness
        return note == nil ? [] : [.shape(.melody, level: level, brightness: brightness, bend: bend)]
    }

    public mutating func release() -> [DeskEffect] {
        guard note != nil else { return [] }
        note = nil
        bend = 0
        return [.silence(.melody)]
    }
}
