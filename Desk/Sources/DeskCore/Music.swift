import MusicTheoryCore

// What the layouts play, as values: a chord in a key, the settings every
// layout shares, and the effects the shell is asked to perform.

/// Where notes go: the kernel's own sound, MIDI, or both.
public enum DeskOutput: String, CaseIterable, Codable, Sendable {
    case synth, midi, both

    public var name: String {
        switch self {
        case .synth: "Synth"
        case .midi: "MIDI"
        case .both: "Synth + MIDI"
        }
    }

    public var sounds: Bool { self != .midi }
    public var sendsMIDI: Bool { self != .synth }
}

/// What every layout shares: the key, the voicing, the sounds and where they
/// go. A sound is named by its preset's id (`SynthPreset.rawValue`), so the
/// core needs nothing of the audio.
public struct DeskSettings: Equatable, Codable, Sendable {
    public var key = Key(root: .C, scale: .major)
    /// The chord's octave, as `computeVoicing` takes it: 4 puts C's chord on
    /// middle C.
    public var octave = 4
    public var inversion = Inversion.root
    /// Whether each chord is voiced as near the last as it can be.
    public var voiceLeading = false
    public var chordSound = "electricPiano"
    public var lineSound = "soloLead"
    public var tempo = 96.0
    public var output = DeskOutput.both
    /// The order of the step compass's choices, where a layout uses it.
    public var ranking = ColorStepRanking.theory
    /// How the color ring is laid round the stick.
    public var ringArrangement = RingArrangement.home

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case key, octave, inversion, voiceLeading, chordSound, lineSound, tempo, output, ranking, ringArrangement
    }

    /// Each setting as it was kept, and any kept before it existed as it
    /// starts: settings saved by an older desk still load.
    public init(from decoder: any Decoder) throws {
        let saved = try decoder.container(keyedBy: CodingKeys.self)
        func read<T: Decodable>(_ key: CodingKeys, _ value: inout T) {
            if let kept = try? saved.decodeIfPresent(T.self, forKey: key) { value = kept }
        }
        read(.key, &key)
        read(.octave, &octave)
        read(.inversion, &inversion)
        read(.voiceLeading, &voiceLeading)
        read(.chordSound, &chordSound)
        read(.lineSound, &lineSound)
        read(.tempo, &tempo)
        read(.output, &output)
        read(.ranking, &ranking)
        read(.ringArrangement, &ringArrangement)
    }

    /// The ring laid the next way round (`steps` < 0, the way before).
    public mutating func moveRingArrangement(by steps: Int) {
        let all = RingArrangement.allCases
        let at = all.firstIndex(of: ringArrangement)!
        ringArrangement = all[((at + steps) % all.count + all.count) % all.count]
    }

    public static let octaves = 1...6
    public static let tempos = 40.0...220.0
    /// The scales a key can be in: the heptatonic ones, where every degree
    /// stacks thirds.
    public static let scales: [ScaleType] = [.major, .naturalMinor, .harmonicMinor, .melodicMinor, .dorian,
                                             .mixolydian, .lydian]

    /// The octave `steps` up (down, below 0), within reach.
    public mutating func moveOctave(by steps: Int) {
        octave = min(Self.octaves.upperBound, max(Self.octaves.lowerBound, octave + steps))
    }

    /// The inversion `steps` further, within two octaves of root position
    /// either way.
    public mutating func roll(by steps: Int) {
        inversion = Inversion(steps: min(6, max(-6, inversion.steps + steps)))
    }

    /// The key a fifth up (`steps` > 0) or down, round the circle of fifths.
    public mutating func moveKey(byFifths steps: Int) {
        let root = ((key.root.rawValue + 7 * steps) % 12 + 12) % 12
        key = Key(root: PitchClass(rawValue: root)!, scale: key.scale)
    }

    /// The next scale of `scales` (`steps` < 0, the one before).
    public mutating func moveScale(by steps: Int) {
        let at = Self.scales.firstIndex(of: key.scale) ?? 0
        let next = ((at + steps) % Self.scales.count + Self.scales.count) % Self.scales.count
        key = Key(root: key.root, scale: Self.scales[next])
    }

    /// "C Major · 4 / root".
    public var summary: String {
        "\(key.root.name) \(key.scale.displayName)"
    }

    public var voicingName: String {
        let roll = inversion.steps == 0 ? "root" : inversion.steps > 0 ? "+\(inversion.steps)" : "\(inversion.steps)"
        return "oct \(octave) · \(roll)"
    }
}

/// A chord as played: a spec in a key. A borrowed chord is a degree of the
/// key it is borrowed from, as the octave layout plays one (`KeyDegree`).
public struct DeskChord: Hashable, Sendable {
    public let key: Key
    public let spec: ChordSpec

    public init(key: Key, spec: ChordSpec) {
        self.key = key
        self.spec = spec
    }

    public init(key: Key, degree: Degree, color: ChordColor = .base) {
        self.init(key: key, spec: ChordSpec(degree: degree, color: color))
    }

    /// The chord `tones` on `root`, read in `home`: its own degree there, or
    /// borrowed from the parallel mode nearest it.
    public init(root: PitchClass, tones: ChordTones, in home: Key) {
        let chord = KeyDegree(root: root, in: home)
        self.init(key: chord.key, spec: ChordSpec(degree: chord.degree, color: .tones(tones)))
    }

    public var root: PitchClass { chordRootPitchClass(key: key, degree: spec.degree) }
    public var tones: ChordTones { ChordTones(key: key, spec: spec) }
    /// "G 7", "C/E".
    public var name: String { chordLabel(key: key, spec: spec) }

    /// The notes it sounds with `settings`' octave and inversion, voice-led
    /// from `previous` if they say so.
    public func notes(_ settings: DeskSettings, octaveShift: Int = 0, roll: Int = 0, after previous: [Int]? = nil) -> [Int] {
        computeVoicing(key: key, spec: spec, inversion: settings.inversion.rolled(by: roll),
                       octave: settings.octave + octaveShift, voiceLeading: settings.voiceLeading,
                       previousVoicing: previous.map { Voicing(notes: $0) }).notes
    }

    /// How it sits in `key`: every note in it, or not.
    public func fit(in home: Key) -> ChordFit {
        let pitches = tones.pitchClasses.map { ($0 + root.rawValue) % 12 }
        let inKey = pitches.allSatisfy { home.has($0) }
        guard inKey else { return .borrowed }
        // A tone a semitone over another is the clash jazz calls an avoid note.
        let clashes = pitches.contains { p in pitches.contains { ($0 + 1) % 12 == p } && p != root.rawValue }
        return clashes ? .tense : .inKey
    }
}

/// How a chord sits in the key: the consonance a target is drawn with.
public enum ChordFit: Equatable, Sendable {
    case inKey
    /// In the key, with a tone a semitone over another.
    case tense
    /// A note from outside the key.
    case borrowed
}

/// A line of notes the shell keeps: the chords, and a single line over them.
/// Each has its own sound and, over MIDI, its own channel.
public enum Line: String, CaseIterable, Hashable, Sendable {
    case chord, melody
}

/// A felt event: the controller's motors say what the ear might miss, and
/// the screen says it too ("Rumble is information, never decoration").
public enum Rumble: Equatable, Sendable {
    /// A step crossed: a detent, a band, a rate.
    case tick
    /// A move made: a chord changed by a flick, a key changed.
    case bump
}

/// What a layout asks the shell to do.
public enum DeskEffect: Equatable, Sendable {
    /// Sound `notes` on `line` in `sound`, in place of what it sounds. Tied,
    /// a note it is sounding already is held over, not struck again.
    case sound(Line, notes: [Int], sound: String, level: Double, brightness: Double, tie: Bool)
    /// Glide what `line` sounds to a new level and brightness, and a bend in
    /// semitones from its pitch.
    case shape(Line, level: Double, brightness: Double, bend: Double)
    /// Let go of everything on `line`.
    case silence(Line)
    case rumble(Rumble)
    /// Play a short chord in `sound`, to hear it while choosing it.
    case preview(sound: String, notes: [Int])
    /// Save `file`'s bytes as a Standard MIDI File called `name`.
    case saveMIDI(bytes: [UInt8], name: String)
}

/// The rates an arpeggio can step at, in beats a note.
public enum ArpeggioRate: Int, CaseIterable, Sendable {
    case quarter = 1, eighth, sixteenth

    public var beats: Double {
        switch self {
        case .quarter: 1
        case .eighth: 0.5
        case .sixteenth: 0.25
        }
    }

    public var name: String {
        switch self {
        case .quarter: "♩"
        case .eighth: "♪"
        case .sixteenth: "♬"
        }
    }
}

/// A line of chords: what it is sounding, how loud and bright, and an
/// arpeggio that plays the chord a note at a time when one is on. Every
/// layout plays its chords through one, so they all strike, tie, swell and
/// arpeggiate alike.
public struct ChordLine: Equatable, Sendable {
    public private(set) var chord: DeskChord?
    /// The notes of the chord sounding (all of them, when arpeggiated).
    public private(set) var notes: [Int] = []
    public private(set) var isSounding = false
    public private(set) var level = 0.8
    public private(set) var brightness = 1.0
    /// The arpeggio's rate; nil plays the chord whole.
    public private(set) var arpeggio: ArpeggioRate?
    /// When the arpeggio started, and the note of it sounding.
    private var arpeggioStart = 0.0
    private var arpeggioStep = -1
    /// Where the chord is moved from the settings' voicing.
    private var octaveShift = 0
    private var roll = 0

    public let line: Line

    public init(_ line: Line = .chord) {
        self.line = line
    }

    /// The note of the arpeggio sounding, if one is.
    public var arpeggioNote: Int? {
        guard arpeggio != nil, isSounding, !notes.isEmpty, arpeggioStep >= 0 else { return nil }
        return notes[arpeggioStep % notes.count]
    }

    /// Sounds `chord` from silence, or in place of what sounds.
    public mutating func strike(_ chord: DeskChord, level: Double, brightness: Double = 1,
                                settings: DeskSettings, at time: Double) -> [DeskEffect] {
        self.chord = chord
        self.level = level
        self.brightness = brightness
        notes = chord.notes(settings, octaveShift: octaveShift, roll: roll, after: isSounding ? notes : nil)
        isSounding = true
        arpeggioStart = time
        arpeggioStep = -1
        return arpeggio == nil ? [sound(notes, settings, tie: false)] : advance(settings, at: time)
    }

    /// The chord is now `chord`: heard at once, tied, if the line is
    /// sounding, and otherwise kept for the next strike.
    public mutating func change(to chord: DeskChord, settings: DeskSettings) -> [DeskEffect] {
        guard chord != self.chord else { return [] }
        self.chord = chord
        return revoice(settings)
    }

    /// The voicing changed: what sounds moves to it, tied.
    public mutating func revoice(_ settings: DeskSettings) -> [DeskEffect] {
        guard isSounding, let chord else { return [] }
        let next = chord.notes(settings, octaveShift: octaveShift, roll: roll, after: notes)
        guard next != notes else { return [] }
        notes = next
        if arpeggio != nil { return [] }
        return [sound(notes, settings, tie: true)]
    }

    /// Moves the chord from the settings' voicing: a bend held by a stick.
    public mutating func bend(octaves: Int, roll: Int, settings: DeskSettings) -> [DeskEffect] {
        guard octaves != octaveShift || roll != self.roll else { return [] }
        octaveShift = octaves
        self.roll = roll
        return revoice(settings)
    }

    /// Glides what sounds to `level` and `brightness`.
    public mutating func shape(level: Double, brightness: Double) -> [DeskEffect] {
        guard abs(level - self.level) > 0.01 || abs(brightness - self.brightness) > 0.01 else { return [] }
        self.level = level
        self.brightness = brightness
        return isSounding ? [.shape(line, level: level, brightness: brightness, bend: 0)] : []
    }

    public mutating func release() -> [DeskEffect] {
        guard isSounding else { return [] }
        isSounding = false
        arpeggioStep = -1
        return [.silence(line)]
    }

    /// Plays the chord a note at a time at `rate`, or whole with nil.
    public mutating func arpeggiate(_ rate: ArpeggioRate?, settings: DeskSettings, at time: Double) -> [DeskEffect] {
        guard rate != arpeggio else { return [] }
        let wasOn = arpeggio != nil
        arpeggio = rate
        guard isSounding else { return [] }
        if rate == nil { return [sound(notes, settings, tie: false)] }
        if !wasOn {
            arpeggioStart = time
            arpeggioStep = -1
        } else {
            // A new rate carries on from the note sounding.
            arpeggioStart = time - Double(arpeggioStep) * 60 / settings.tempo * rate!.beats
        }
        return advance(settings, at: time)
    }

    /// The arpeggio's next note, when its time has come.
    public mutating func tick(_ settings: DeskSettings, at time: Double) -> [DeskEffect] {
        advance(settings, at: time)
    }

    private mutating func advance(_ settings: DeskSettings, at time: Double) -> [DeskEffect] {
        guard let arpeggio, isSounding, !notes.isEmpty else { return [] }
        let step = Int(((time - arpeggioStart) / (60 / settings.tempo * arpeggio.beats)).rounded(.down))
        guard step != arpeggioStep else { return [] }
        arpeggioStep = max(0, step)
        return [sound([notes[arpeggioStep % notes.count]], settings, tie: false)]
    }

    private func sound(_ notes: [Int], _ settings: DeskSettings, tie: Bool) -> DeskEffect {
        .sound(line, notes: notes, sound: line == .chord ? settings.chordSound : settings.lineSound,
               level: level, brightness: brightness, tie: tie)
    }
}

/// The diatonic cycle of thirds: I iii V vii° ii IV vi. Neighbours share two
/// notes, and it closes (vi back to I shares two), so a thumb rolling round
/// a pie in this order makes the smoothest chain of chords the key has.
public enum DiatonicCycle {
    public static let thirds: [Degree] = [.I, .iii, .V, .viiDim, .ii, .IV, .vi]

    /// The degree `steps` thirds from `degree` round the cycle.
    public static func degree(_ steps: Int, from degree: Degree) -> Degree {
        let at = thirds.firstIndex(of: degree)!
        return thirds[((at + steps) % 7 + 7) % 7]
    }
}

/// The key's seven degrees round a stick, in the cycle of thirds, I at the top.
public enum DegreePie {
    public static let gate = PieGate.even(7)

    public static func degree(at sector: Int) -> Degree { DiatonicCycle.thirds[sector] }
    public static func sector(of degree: Degree) -> Int { DiatonicCycle.thirds.firstIndex(of: degree)! }
}
