import Foundation

// What the Dissonance Lab sounds, as plain values: its settings, the levels
// that set them all at once, and what two keyed notes become under them
// (`LabSounding`). `DissonanceLabState` keeps the notes and the settings;
// everything heard and shown is worked out here, from them alone.

/// Where the two notes are played.
enum LabVoicing: CaseIterable, Sendable {
    /// Within one octave, the lower note between 200 and 400 Hz, where the
    /// beating of partials is easiest to hear.
    case close
    /// As keyed.
    case original
}

/// What the spotlighted pair's beat is made to be, by moving the upper
/// note's partial of it alone.
enum BeatShaping: CaseIterable, Sendable {
    /// As the notes make it.
    case natural
    /// A slow beat, heard as a wobble.
    case wobble
    /// A fast one, heard as grit.
    case grit

    /// The beats a second it is made to be; nil leaves it.
    var rate: Double? {
        switch self {
        case .natural: return nil
        case .wobble:  return 5
        case .grit:    return 45
        }
    }

    var displayName: String {
        switch self {
        case .natural: return "Natural"
        case .wobble:  return "Wobble 5 Hz"
        case .grit:    return "Grit 45 Hz"
        }
    }
}

/// How the upper note is tuned to the lower.
enum LabTuning: CaseIterable, Sendable {
    case equal
    /// The simple ratio nearest the interval (`Interval.justRatio`).
    case just
    /// Just for a consonance, equal for the rest: a consonance can be
    /// tuned to beat not at all, and a dissonance cannot.
    case justForConsonant

    var displayName: String {
        switch self {
        case .equal:            return "12-TET"
        case .just:             return "Just"
        case .justForConsonant: return "Just if consonant"
        }
    }
}

/// A crutch that makes the spotlighted pair's beat plain, beyond the beat
/// itself.
enum BeatCrutch: CaseIterable, Sendable {
    case off
    /// The pair's partials swung in strength at the beat rate.
    case modulation
    /// A quiet sine at the beat rate.
    case differenceTone

    var displayName: String {
        switch self {
        case .off:            return "Off"
        case .modulation:     return "Swing"
        case .differenceTone: return "Difference tone"
        }
    }
}

/// Every control of the Dissonance Lab, each its own switch, so any one can
/// be heard with and without.
struct LabSettings: Equatable, Sendable {
    var voicing = LabVoicing.close
    /// How many partials each note has.
    var partialCount = 10
    /// The partials fall away as 1/n^brightness: 1 is a sawtooth's.
    var brightness = 1.0
    /// A piano's envelope, struck and dying away, and not an organ's.
    var isStruck = false
    /// The pairs most heard as partials meeting are louder, and every other
    /// partial quieter.
    var spotlight = true
    var spotlightCount = 1
    /// In decibels.
    var spotlightBoost = 12.0
    var spotlightCut = -18.0
    var beatShaping = BeatShaping.natural
    var tuning = LabTuning.equal
    var crutch = BeatCrutch.off
    /// How deep the crutch is, 0...1.
    var crutchDepth = 0.6
    /// A quiet sine at the root the notes imply.
    var rootTone = false
    /// The lower note in the left ear and the upper in the right, so their
    /// partials never meet in the air: whatever beats is heard in the head.
    /// No spotlight and no swing, which would put a beat there.
    var isDichotic = false

    static let partialRange = 1...16
    static let brightnessRange = 0.5...3.0
    static let spotlightRange = 1...3
    static let boostRange = 0.0...24.0
    static let cutRange = -36.0...0.0
}

/// A level: the controls set all at once for a stage of learning to hear,
/// from every crutch on to none, and the piano's sound at the last. Any one
/// can be changed after.
enum LabLevel: Int, CaseIterable, Sendable {
    case one = 1, two, three, four, five

    var settings: LabSettings {
        var settings = LabSettings()
        switch self {
        case .one:
            settings.partialCount = 12
            settings.beatShaping = .wobble
            settings.crutch = .modulation
            settings.rootTone = true
            settings.tuning = .justForConsonant
        case .two:
            settings.partialCount = 12
            settings.beatShaping = .grit
            settings.crutch = .modulation
            settings.rootTone = true
        case .three:
            settings.partialCount = 10
            settings.rootTone = true
        case .four:
            settings.partialCount = 8
            settings.spotlight = false
        case .five:
            settings.voicing = .original
            settings.partialCount = 8
            settings.brightness = 1.5
            settings.isStruck = true
            settings.spotlight = false
        }
        return settings
    }
}

/// A pair of partials as the lab sounds it: the analysis's pair, how fast
/// it beats as heard (after any shaping), and how strong each partial
/// sounds (after the spotlight).
struct LabPair: Equatable, Sendable {
    let pair: CollidingPair
    let beatRate: Double
    let lowStrength: Double
    let highStrength: Double
    /// How deep the swing on it is, 0 for none.
    let swing: Double

    /// How loud the pair is together `seconds` into a beat: the beating of
    /// the two, and the swing over it, which starts at its loudest too.
    func envelope(at seconds: Double) -> Double {
        let angle = 2 * Double.pi * beatRate * seconds
        let squared = lowStrength * lowStrength + highStrength * highStrength
            + 2 * lowStrength * highStrength * cos(angle)
        return max(squared, 0).squareRoot() * (1 - swing * (0.5 - 0.5 * cos(angle)))
    }
}

/// Two keyed notes as the lab sounds and shows them under its settings.
struct LabSounding: Equatable, Sendable {
    /// The notes as keyed, the lower first.
    let keyed: (low: Int, high: Int)
    let interval: Interval
    /// The pitches sounded, in Hz.
    let lowHz: Double
    let highHz: Double
    /// Whether the upper note is tuned to the interval's just ratio.
    let isJust: Bool
    /// What the analysis finds of the two as sounded.
    let analysis: IntervalAnalysis
    /// How rough the two are beside a minor second over the lower: 1 is as
    /// rough as that.
    let roughness: Double
    /// The pairs spotlighted, or that would be with the spotlight on.
    let spotlit: [LabPair]
    /// Each partial's setting, the fundamental first, in each note.
    let lowPartials: [PartialSetting]
    let highPartials: [PartialSetting]
    /// The pitch of the root tone, in Hz, if it sounds.
    let rootToneHz: Double?
    /// The pitch and strength of the difference tone, if it sounds.
    let differenceTone: (hz: Double, strength: Double)?
    let settings: LabSettings

    /// A beat slower than this is no beat: the pair is in tune.
    static let beatless = 0.05
    /// The lower note's register under close voicing, in Hz.
    static let closeRegister = 200.0..<400.0
    /// The root tone is raised by octaves to be at least this, in Hz, so it
    /// is heard.
    static let lowestRootTone = 40.0
    /// How strong the root tone and the difference tone are, beside the
    /// fundamental of a note.
    static let rootToneStrength: Float = 0.35
    static let differenceToneStrength = 0.5

    static func hz(ofMidi pitch: Double) -> Double { 440 * pow(2, (pitch - 69) / 12) }
    static func midi(ofHz hz: Double) -> Double { 69 + 12 * log2(hz / 440) }

    /// Everything else follows from the notes and the settings.
    static func == (a: LabSounding, b: LabSounding) -> Bool {
        a.keyed == b.keyed && a.lowHz == b.lowHz && a.highHz == b.highHz && a.settings == b.settings
    }

    /// `first` and `second`, two MIDI notes in either order, under
    /// `settings`; `plain` is the A/B button held: equal temperament and no
    /// enhancement, the partials and the voicing as set.
    init(_ first: Int, _ second: Int, settings given: LabSettings, plain: Bool = false) {
        var settings = given
        if plain {
            settings.tuning = .equal
            settings.spotlight = false
            settings.beatShaping = .natural
            settings.crutch = .off
            settings.rootTone = false
            settings.isDichotic = false
        }
        if settings.isDichotic {
            settings.spotlight = false
            if settings.crutch == .modulation { settings.crutch = .off }
        }
        self.settings = settings

        let (low, high) = (min(first, second), max(first, second))
        keyed = (low, high)
        interval = Interval(from: low, to: high)

        // The pitches.
        var lowHz = Self.hz(ofMidi: Double(low))
        var semitones = high - low
        if settings.voicing == .close {
            while lowHz < Self.closeRegister.lowerBound { lowHz *= 2 }
            while lowHz >= Self.closeRegister.upperBound { lowHz /= 2 }
            semitones = interval.semitones
        }
        let octaves = Double((semitones - interval.semitones) / 12)
        isJust = settings.tuning == .just || (settings.tuning == .justForConsonant && interval.isConsonant)
        let ratio = isJust
            ? Double(interval.justRatio.numerator) / Double(interval.justRatio.denominator) * pow(2, octaves)
            : pow(2, Double(semitones) / 12)
        self.lowHz = lowHz
        highHz = lowHz * ratio

        // What the analysis finds of them.
        let count = settings.partialCount.clamped(to: LabSettings.partialRange)
        let lowTone = Tone(fundamental: lowHz, partials: count, brightness: settings.brightness)
        let highTone = Tone(fundamental: highHz, partials: count, brightness: settings.brightness)
        analysis = IntervalAnalyzer.analyze(low: lowTone, high: highTone)
        roughness = IntervalAnalyzer.roughnessBesideMinorSecond(low: lowTone, high: highTone)

        // The pairs to point the ear at: no two moving one upper partial.
        var candidates: [CollidingPair] = []
        for pair in analysis.spotlight(analysis.pairs.count) where candidates.count < settings.spotlightCount {
            if !candidates.contains(where: { $0.low == pair.low || $0.high == pair.high }) {
                candidates.append(pair)
            }
        }

        // Each partial's strength, with the spotlight's boost and cut.
        let boost = pow(10, settings.spotlightBoost / 20)
        let cut = pow(10, settings.spotlightCut / 20)
        func strength(_ tone: Tone, _ number: Int, lit: Bool) -> Double {
            let base = tone.strengths[number - 1]
            guard settings.spotlight else { return base }
            return base * (lit ? boost : cut)
        }
        var lowPartials = (1...count).map { n in
            PartialSetting(strength: Float(strength(lowTone, n, lit: candidates.contains { $0.low == n })))
        }
        var highPartials = (1...count).map { n in
            PartialSetting(strength: Float(strength(highTone, n, lit: candidates.contains { $0.high == n })))
        }

        // The beat of each spotlighted pair as shaped, and its swing.
        var spotlit: [LabPair] = []
        for pair in candidates {
            var rate = pair.beatRate
            if let shaped = settings.beatShaping.rate, pair.beatRate >= Self.beatless {
                highPartials[pair.high - 1].offset = Float(pair.offset(toBeatAt: shaped))
                rate = shaped
            }
            let swing = settings.crutch == .modulation && rate >= Self.beatless ? settings.crutchDepth : 0
            if swing > 0 {
                lowPartials[pair.low - 1].depth = Float(swing)
                lowPartials[pair.low - 1].rate = Float(rate)
                highPartials[pair.high - 1].depth = Float(swing)
                highPartials[pair.high - 1].rate = Float(rate)
            }
            spotlit.append(LabPair(pair: pair, beatRate: rate,
                                   lowStrength: Double(lowPartials[pair.low - 1].strength),
                                   highStrength: Double(highPartials[pair.high - 1].strength),
                                   swing: swing))
        }
        self.spotlit = spotlit
        self.lowPartials = lowPartials
        self.highPartials = highPartials

        // The tones beside the notes.
        if settings.rootTone, var root = analysis.impliedRoot?.hz {
            while root < Self.lowestRootTone { root *= 2 }
            rootToneHz = root
        } else {
            rootToneHz = nil
        }
        if settings.crutch == .differenceTone, let lit = spotlit.first, lit.beatRate >= Self.beatless {
            differenceTone = (lit.beatRate, Self.differenceToneStrength * settings.crutchDepth
                                * min(lit.lowStrength, lit.highStrength))
        } else {
            differenceTone = nil
        }
    }

    /// The lines the lab sounds for the two notes, each `velocity` strong.
    func lines(velocity: Float) -> [LabLine: PartialNote] {
        let sound: PartialSound = settings.isStruck ? .struck : .held
        let pans: (Float, Float) = settings.isDichotic ? (-1, 1) : (0, 0)
        var lines: [LabLine: PartialNote] = [
            .keyed(keyed.low): PartialNote(sound: sound, pitch: Self.midi(ofHz: lowHz), velocity: velocity,
                                           pan: pans.0, partials: lowPartials),
            .keyed(keyed.high): PartialNote(sound: sound, pitch: Self.midi(ofHz: highHz), velocity: velocity,
                                            pan: pans.1, partials: highPartials),
        ]
        if let rootToneHz {
            lines[.root] = Self.sine(at: rootToneHz, strength: Self.rootToneStrength, velocity: velocity)
        }
        if let differenceTone {
            lines[.difference] = Self.sine(at: differenceTone.hz, strength: Float(differenceTone.strength),
                                           velocity: velocity)
        }
        return lines
    }

    /// The line one note sounds by itself: as keyed, its partials as set
    /// and nothing more.
    static func single(_ note: Int, settings: LabSettings, velocity: Float) -> [LabLine: PartialNote] {
        let tone = Tone(fundamental: hz(ofMidi: Double(note)),
                        partials: settings.partialCount.clamped(to: LabSettings.partialRange),
                        brightness: settings.brightness)
        return [.keyed(note): PartialNote(sound: settings.isStruck ? .struck : .held, pitch: Double(note),
                                          velocity: velocity,
                                          partials: tone.strengths.map { PartialSetting(strength: Float($0)) })]
    }

    private static func sine(at hz: Double, strength: Float, velocity: Float) -> PartialNote {
        PartialNote(sound: .held, pitch: midi(ofHz: hz), velocity: velocity,
                    partials: [PartialSetting(strength: strength)])
    }
}
