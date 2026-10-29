import MusicTheoryCore
import PerfectoTheoryProbe
import Testing

/// The C++ theory core (PerfectoTheory, through `PerfectoTheoryProbe`)
/// against the Swift one it was ported from, over whole spaces of inputs:
/// every key, degree and color the space holds gives the same notes, names
/// and steps from both. The Swift core is the reference.
///
/// The whole of each space is swept in an optimized build (`swift test -c
/// release`, about 8 seconds); a debug build, twenty times slower here,
/// sweeps a fixed sample of the larger ones, so a plain `swift test` still
/// runs every comparison.
@Suite("Theory parity")
struct ParityTests {

    // MARK: – The inputs

    /// A color, as the Swift core has it and as the probe is given it.
    struct Color {
        let swift: ChordColor
        let probe: ptp_color
    }

    static func probe(kind: Int32, _ a: Int32 = 0, _ b: Int32 = 0, moves: [Int32] = Array(repeating: 0, count: 6),
                      skips: Int32 = 0, tones: Int32 = 0) -> ptp_color {
        ptp_color(kind: kind, a: a, b: b, moves: (moves[0], moves[1], moves[2], moves[3], moves[4], moves[5]),
                  skips: skips, tones: tones)
    }

    static func index<T: CaseIterable & Equatable>(_ value: T) -> Int32 {
        Int32(T.allCases.firstIndex(of: value)! as! Int)
    }

    static func mask(_ pitchClasses: [Int]) -> Int32 {
        pitchClasses.reduce(0) { $0 | 1 << $1 }
    }

    static func pitchClasses(_ mask: Int32) -> [Int] {
        (0..<12).filter { mask & 1 << $0 != 0 }
    }

    static let joystickColors: [Color] = JoystickMode.allCases.flatMap { mode in
        JoystickDirection.allCases.map { direction in
            Color(swift: .joystick(mode, direction),
                  probe: probe(kind: Int32(PTP_JOYSTICK), index(mode), index(direction)))
        }
    }

    static let gridColors: [Color] = StackHeight.allCases.flatMap { height in
        ([nil] + HeptatonicMode.allCases).map { mode in
            Color(swift: .grid(height, mode),
                  probe: probe(kind: Int32(PTP_GRID), index(height), mode.map(index) ?? -1))
        }
    }

    /// Every stack with one mark on it, through the degree's own mode and
    /// three others.
    static let markedColors: [Color] = StackHeight.allCases.flatMap { height in
        ([nil, .dorian, .altered, .phrygianDominant] as [HeptatonicMode?]).flatMap { mode in
            ChordTone.allCases.enumerated().flatMap { i, tone in
                var up = ToneMarks(), down = ToneMarks(), skip = ToneMarks()
                up.setMove(tone, to: 1)
                down.setMove(tone, to: -1)
                skip.setSkip(tone, true)
                var moves = Array(repeating: Int32(0), count: 6)
                return [(up, 1), (down, -1), (skip, 0)].map { marks, offset in
                    moves[i] = Int32(offset)
                    let p = probe(kind: Int32(PTP_MARKED), index(height), mode.map(index) ?? -1, moves: moves,
                                  skips: offset == 0 ? 1 << i : 0)
                    return Color(swift: .marked(height, mode, marks), probe: p)
                }
            }
        }
    }

    static let builtColors: [Color] = ([nil] + ChordType.allCases).flatMap { type in
        (0..<16).map { extensionMask in
            let extensions = Set(ChordExtension.allCases.enumerated().filter { extensionMask & 1 << $0.offset != 0 }
                .map(\.element))
            return Color(swift: .built(ChordBuild(type: type, extensions: extensions)),
                         probe: probe(kind: Int32(PTP_BUILT), type.map(index) ?? -1, Int32(extensionMask)))
        }
    }

    /// Every chord of three and four notes on a root.
    static let toneColors: [Color] = (0..<2048).compactMap { above in
        let tones = [0] + (1..<12).filter { above & 1 << ($0 - 1) != 0 }
        guard (3...4).contains(tones.count) else { return nil }
        return Color(swift: .tones(ChordTones(tones)), probe: probe(kind: Int32(PTP_TONES), tones: mask(tones)))
    }

    static let allColors = joystickColors + gridColors + markedColors + builtColors + toneColors

    static let keys: [Key] = PitchClass.allCases.flatMap { root in ScaleType.allCases.map { Key(root: root, scale: $0) } }

    #if DEBUG
    static let thorough = false
    #else
    static let thorough = true
    #endif

    /// Every `n`th of `all` in a debug build, all of it otherwise.
    static func sample<T>(_ all: [T], every n: Int) -> [T] {
        thorough ? all : all.enumerated().filter { $0.offset % n == 0 }.map(\.element)
    }

    /// The keys the larger spaces are swept over: in a debug build every
    /// seventh, which still has every root and every scale among them.
    static let sweptKeys = sample(keys, every: 7)

    static func text(_ fill: (UnsafeMutablePointer<CChar>, Int32) -> Void) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        fill(&buffer, Int32(buffer.count))
        return string(buffer)
    }

    /// `#expect` without its cost, which the millions of comparisons here
    /// cannot afford: an issue only when `condition` fails.
    static func check(_ condition: Bool, _ context: @autoclosure () -> String = "",
                      sourceLocation: SourceLocation = #_sourceLocation) {
        if !condition { Issue.record(Comment(rawValue: context()), sourceLocation: sourceLocation) }
    }

    /// The NUL-terminated UTF-8 in `buffer`.
    static func string(_ buffer: [CChar]) -> String {
        String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    static func probeVoicing(_ key: Key, _ degree: Degree, _ color: Color, inversion: Int, octave: Int,
                             voiceLeading: Bool = false, previous: Voicing? = nil) -> [Int] {
        var notes = [Int32](repeating: 0, count: 32)
        var probeColor = color.probe
        let prior = previous?.notes.map(Int32.init)
        let count = prior.withOptionalBuffer { previousNotes, previousCount in
            ptp_voicing(Int32(key.root.rawValue), index(key.scale), index(degree), &probeColor, Int32(inversion),
                        Int32(octave), voiceLeading ? 1 : 0, previousNotes, previousCount, &notes)
        }
        return notes.prefix(Int(count)).map(Int.init)
    }

    // MARK: – Chords

    @Test func everyColorOnEveryDegreeOfEveryKeyHasTheSameNotesAndLabel() {
        var checked = 0
        for key in Self.sweptKeys { for degree in Degree.allCases { for color in Self.allColors {
            let spec = ChordSpec(degree: degree, color: color.swift)
            let notes = computeVoicing(key: key, spec: spec, inversion: .root, octave: 4, voiceLeading: false,
                                       previousVoicing: nil).notes
            let probeNotes = Self.probeVoicing(key, degree, color, inversion: 0, octave: 4)
            guard notes == probeNotes else {
                Issue.record("\(key) \(degree) \(color.swift): \(notes) ≠ \(probeNotes)")
                continue
            }
            var probeColor = color.probe
            let label = Self.text { ptp_chord_label(Int32(key.root.rawValue), Self.index(key.scale),
                                                    Self.index(degree), &probeColor, $0, $1) }
            Self.check(chordLabel(key: key, spec: spec) == label, "\(key) \(degree) \(color.swift)")
            checked += 1
        } } }
        Self.check(checked == Self.sweptKeys.count * 7 * Self.allColors.count)
    }

    @Test func everyInversionAndOctave() {
        let colors = Self.joystickColors + Self.gridColors + Self.toneColors.filter { $0.probe.tones % 3 == 0 }
        for root in Self.sample([PitchClass.Fs, .C, .B], every: 3) { for scale in ScaleType.allCases {
            let key = Key(root: root, scale: scale)
            for degree in Degree.allCases { for color in colors {
                let spec = ChordSpec(degree: degree, color: color.swift)
                for inversion in -4...4 { for octave in [-1, 4, 9] {
                    let notes = computeVoicing(key: key, spec: spec, inversion: Inversion(steps: inversion),
                                               octave: octave, voiceLeading: false, previousVoicing: nil).notes
                    Self.check(notes == Self.probeVoicing(key, degree, color, inversion: inversion, octave: octave),
                            "\(key) \(degree) \(color.swift) inversion \(inversion) octave \(octave)")
                } }
            } }
        } }
    }

    /// Long runs of chords, each led from the last, from a seeded chance.
    @Test func voiceLeadingFollowsTheSameRuns() {
        var random = SeededRandom(seed: 7)
        let colors = Self.joystickColors + Self.gridColors
        for _ in 0..<200 {
            let key = Self.keys.randomElement(using: &random)!
            var previous: Voicing? = nil
            for _ in 0..<30 {
                let degree = Degree.allCases.randomElement(using: &random)!
                let color = colors.randomElement(using: &random)!
                let inversion = Int.random(in: -2...3, using: &random)
                let octave = Int.random(in: 2...6, using: &random)
                let voicing = computeVoicing(key: key, spec: ChordSpec(degree: degree, color: color.swift),
                                             inversion: Inversion(steps: inversion), octave: octave,
                                             voiceLeading: true, previousVoicing: previous)
                Self.check(voicing.notes == Self.probeVoicing(key, degree, color, inversion: inversion, octave: octave,
                                                           voiceLeading: true, previous: previous))
                previous = voicing
            }
        }
    }

    @Test func everyColorHasTheSameActionLabel() {
        for color in Self.allColors {
            var probeColor = color.probe
            Self.check(colorActionLabel(color.swift) == Self.text { ptp_color_action_label(&probeColor, $0, $1) },
                    "\(color.swift)")
        }
    }

    @Test func everyDegreeHasTheSameNumeral() {
        for key in Self.keys { for degree in Degree.allCases {
            let numeral = Self.text { ptp_degree_numeral(Int32(key.root.rawValue), Self.index(key.scale),
                                                         Self.index(degree), $0, $1) }
            Self.check(degreeNumeral(key: key, degree: degree) == numeral, "\(key) \(degree)")
        } }
    }

    /// Every chord there is on a root: all 2,048 sets of tones above it.
    @Test func everyChordHasTheSameNameAndSlash() {
        for above in 0..<2048 {
            let tones = [0] + (1..<12).filter { above & 1 << ($0 - 1) != 0 }
            let chord = ChordTones(tones)
            var slashRoot: Int32 = 0
            var quality = [CChar](repeating: 0, count: 256)
            var isSlash: Int32 = 0
            let name = Self.text { name, capacity in
                isSlash = ptp_chord_tones(Self.mask(tones), name, capacity, &slashRoot, &quality, 256)
            }
            Self.check(chord.name == name, "\(tones)")
            if let slash = chord.slash {
                Self.check(isSlash == 1 && Int(slashRoot) == slash.root && Self.string(quality) == slash.quality,
                        "\(tones)")
            } else {
                Self.check(isSlash == 0, "\(tones)")
            }
        }
    }

    // MARK: – The step compass

    /// Every place from every chord of three and four notes, on every degree
    /// of a major and a harmonic minor key, by both rankings.
    @Test func everyStepFromEveryChord() {
        let tones = Self.sample(Self.toneColors.map { Self.pitchClasses($0.probe.tones) }, every: 5)
        for key in [Key(root: .C, scale: .major), Key(root: .A, scale: .harmonicMinor)] {
            for degree in Degree.allCases { for ranking in ColorStepRanking.allCases { for chord in tones {
                let steps = StepCompass.steps(from: ChordTones(chord), key: key, degree: degree, ranking: ranking)
                for place in CompassPlace.all {
                    let choices = steps[place.kind] ?? []
                    let step = choices.indices.contains(place.rank - 1) ? choices[place.rank - 1] : nil
                    var made: Int32 = 0, from: Int32 = 0, to: Int32 = 0, fit: Int32 = 0
                    var found: Int32 = 0
                    let editName = Self.text { name, capacity in
                        found = ptp_step(Int32(key.root.rawValue), Self.index(key.scale), Self.index(degree),
                                         Self.mask(chord), Self.index(ranking), Self.index(place.kind),
                                         Int32(place.rank), &made, &from, &to, &fit, name, capacity)
                    }
                    let context = "\(key) \(degree) \(ranking) \(chord) \(place)"
                    guard let step else {
                        Self.check(found == 0, "\(context)")
                        continue
                    }
                    Self.check(found == 1, "\(context)")
                    Self.check(Self.pitchClasses(made) == step.tones.pitchClasses, "\(context)")
                    Self.check(Int(from) == (step.from ?? -1) && Int(to) == (step.to ?? -1), "\(context)")
                    Self.check(Int(fit) == step.fit.rawValue, "\(context)")
                    Self.check(editName == step.editName, "\(context)")
                }
            } } }
        }
    }

    /// Every walk of up to two places, and long walks from a seeded chance,
    /// on every degree of a few keys. Each step of a walk is checked by
    /// `everyStepFromEveryChord`; this checks that they are taken in turn.
    @Test func walksOfPlaces() {
        let places = CompassPlace.all
        var random = SeededRandom(seed: 11)
        let short = [[]] + places.map { [$0] } + places.flatMap { a in places.map { [a, $0] } }
        let long = (0..<(Self.thorough ? 200 : 20)).map { _ in
            (0..<Int.random(in: 3...8, using: &random)).map { _ in places.randomElement(using: &random)! }
        }
        let keys = [Key(root: .C, scale: .major), Key(root: .E, scale: .dorian), Key(root: .G, scale: .melodicMinor)]
        for key in Self.sample(keys, every: 3) {
            for degree in Degree.allCases { for ranking in ColorStepRanking.allCases { for walk in short + long {
                let codes = walk.map { Self.index($0.kind) * 2 + Int32($0.rank - 1) }
                let probe = ptp_walk(Int32(key.root.rawValue), Self.index(key.scale), Self.index(degree),
                                     Self.index(ranking), codes, Int32(codes.count))
                let swift = StepCompass.walk(walk, key: key, degree: degree, ranking: ranking)
                Self.check(Self.pitchClasses(probe) == swift.pitchClasses, "\(key) \(degree) \(ranking) \(walk)")
            } } }
        }
    }

    // MARK: – Keys, grids and steps

    @Test func everyRootInEveryKey() {
        for key in Self.keys { for note in PitchClass.allCases {
            let degree = KeyDegree(root: note, in: key)
            var root: Int32 = 0, scale: Int32 = 0, probeDegree: Int32 = 0
            ptp_key_degree(Int32(key.root.rawValue), Self.index(key.scale), Int32(note.rawValue), &root, &scale,
                           &probeDegree)
            Self.check(Int(root) == degree.key.root.rawValue && scale == Self.index(degree.key.scale)
                    && probeDegree == Self.index(degree.degree), "\(note) in \(key)")
        } }
    }

    @Test func everyGridAndRing() {
        for key in Self.keys { for degree in Degree.allCases {
            var rows = [Int32](repeating: 0, count: 7)
            let count = ptp_grid_rows(Int32(key.root.rawValue), Self.index(key.scale), Self.index(degree), &rows)
            Self.check(rows.prefix(Int(count)).map { HeptatonicMode.allCases[Int($0)] }
                    == ChordGrid.rows(key: key, degree: degree), "\(key) \(degree)")
            for arrangement in ColorRingArrangement.allCases {
                Self.check(Int(ptp_ring_turn(Self.index(arrangement), Int32(key.root.rawValue), Self.index(key.scale),
                                          Self.index(degree)))
                        == ColorRing.turn(arrangement, key: key, degree: degree), "\(key) \(degree) \(arrangement)")
            }
        } }
    }

    @Test func colorStepsBetweenEveryPairOfTriadsAndSevenths() {
        let chords = Self.toneColors.map { Self.pitchClasses($0.probe.tones) }
        for a in chords { for b in chords {
            let probe = ptp_color_steps(a.map(Int32.init), Int32(a.count), b.map(Int32.init), Int32(b.count))
            Self.check(Int(probe) == colorSteps(a, b), "\(a) \(b)")
        } }
    }

    // MARK: – What goes out

    @Test func chordLinkFramesAndStatedInversions() {
        let colors = Self.joystickColors
        for key in Self.sweptKeys { for degree in Degree.allCases { for color in colors {
            guard case let .joystick(mode, direction) = color.swift else { continue }
            let spec = ChordSpec(degree: degree, color: color.swift)
            for inversion in -4...4 {
                var statedInversion: Int32 = 0, statedOctave: Int32 = 0
                var probeColor = color.probe
                let found = ptp_stated(Int32(inversion), 4, Int32(key.root.rawValue), Self.index(key.scale),
                                       Self.index(degree), &probeColor, &statedInversion, &statedOctave)
                let stated = ChordWire.stated(Inversion(steps: inversion), octave: 4, key: key, spec: spec)
                Self.check((found == 1) == (stated != nil), "\(key) \(degree) \(color.swift) \(inversion)")
                guard let stated else { continue }
                Self.check(Int(statedInversion) == stated.inversion.steps && Int(statedOctave) == stated.octave)

                let voicing = computeVoicing(key: key, spec: spec, inversion: stated.inversion,
                                             octave: stated.octave, voiceLeading: false, previousVoicing: nil)
                let bass = voicing.notes.first.map { $0 - 12 }
                let announced = Voicing(notes: voicing.notes, bassNote: bass)
                let frame = ChordWire.encodeChord(ChordAnnouncement(
                    key: key, degree: degree, joystickMode: mode, joystickDirection: direction,
                    inversion: stated.inversion, octave: stated.octave, voiceLeading: inversion % 2 == 0,
                    voicing: announced))
                var bytes = [UInt8](repeating: 0, count: 64)
                let notes = announced.notes.map(Int32.init)
                let count = ptp_chord_wire(Int32(key.root.rawValue), Self.index(key.scale), Self.index(degree),
                                           Self.index(mode), Self.index(direction), Int32(stated.inversion.steps),
                                           Int32(stated.octave), inversion % 2 == 0 ? 1 : 0, notes,
                                           Int32(notes.count), Int32(bass ?? -1), &bytes)
                Self.check(Array(bytes.prefix(Int(count))) == frame)
            }
        } } }
    }

    @Test func everyKeysMidiSignature() {
        for key in Self.keys {
            var sharps: Int32 = 0, isMinor: Int32 = 0
            ptp_midi_key_signature(Int32(key.root.rawValue), Self.index(key.scale), &sharps, &isMinor)
            Self.check(Int(sharps) == key.midiKeySignature.sharps && (isMinor == 1) == key.midiKeySignature.isMinor,
                    "\(key)")
        }
    }
}

/// A chance that starts from the same place each run (SplitMix64).
struct SeededRandom: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

private extension Optional where Wrapped == [Int32] {
    /// The array's storage and count, or no pointer and 0.
    func withOptionalBuffer<R>(_ body: (UnsafePointer<Int32>?, Int32) -> R) -> R {
        guard let array = self else { return body(nil, 0) }
        return array.withUnsafeBufferPointer { body($0.baseAddress, Int32($0.count)) }
    }
}
