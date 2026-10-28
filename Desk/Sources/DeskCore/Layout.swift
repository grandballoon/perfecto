import MusicTheoryCore

// A layout is one way of laying the instrument out on the controller
// (docs/gamepad-desk-ui.md's models). Each is a value stepped by frames:
// input and state in, new state and effects out, so the shell only feeds it
// frames and performs what it returns.

public enum LayoutKind: String, CaseIterable, Codable, Sendable {
    case twinRings, petals, neighbourhood, twoVoices, arranger

    public var name: String {
        switch self {
        case .twinRings: "Twin Rings"
        case .petals: "Petals & Depth"
        case .neighbourhood: "Neighbourhood"
        case .twoVoices: "Two Voices"
        case .arranger: "Arranger"
        }
    }

    /// What it is for, in a line.
    public var summary: String {
        switch self {
        case .twinRings: "Left stick the degree, right stick the color ring, RT strikes: 154 chords in one gesture."
        case .petals: "Left stick the degree, the face buttons strike at four heights, the triggers bend darker and brighter."
        case .neighbourhood: "Only the chords one step from where you are: flick to move there, hold to listen."
        case .twoVoices: "The left hand swells the chords, the right plays a line over them with RT as pressure."
        case .arranger: "Aim a chord with both sticks and write it into four bars; play them back in a loop."
        }
    }
}

public protocol Layout: Equatable, Sendable {
    /// One frame: what the controller does now, against the settings every
    /// layout shares, which it may change.
    mutating func step(_ input: PadInput, settings: inout DeskSettings) -> [DeskEffect]
    /// Lets go of everything sounding and held: the layout is left, or the
    /// menu opens over it.
    mutating func releaseAll() -> [DeskEffect]
    /// What every control does now.
    func legend(_ settings: DeskSettings) -> Legend
}

/// What every playing layout does with the d-pad unless it needs it for
/// something else: left and right roll the inversion, up and down the octave.
/// Returns whether the voicing changed.
func voicingPad(_ input: PadInput, settings: inout DeskSettings) -> Bool {
    let before = (settings.octave, settings.inversion)
    if input.pressed(.left) { settings.roll(by: -1) }
    if input.pressed(.right) { settings.roll(by: 1) }
    if input.pressed(.up) { settings.moveOctave(by: 1) }
    if input.pressed(.down) { settings.moveOctave(by: -1) }
    return before != (settings.octave, settings.inversion)
}

/// The legend's entries every layout shares.
func commonLegend(_ settings: DeskSettings, voicing: Bool = true) -> Legend {
    var legend: Legend = [.button(.back): "Next layout", .button(.start): "Menu"]
    if voicing {
        legend[.button(.left)] = "Inversion down"
        legend[.button(.right)] = "Inversion up"
        legend[.button(.up)] = "Octave up"
        legend[.button(.down)] = "Octave down"
    }
    return legend
}

/// A target a stick can reach, as the screen draws it: named by what it
/// would sound ("V · G7"), with how it sits in the key and whether it is
/// one step from what sounds.
public struct Target: Equatable, Sendable {
    public var bearing: Double
    /// The chord's name.
    public var name: String
    /// What it is besides its name: a numeral, a mode, a step.
    public var detail: String
    public var fit: ChordFit
    /// One step from the chord sounding: the gentle moves.
    public var isNear: Bool
    public var isAimed: Bool
    public var isKept: Bool
    /// Left out by a filter: drawn in its place, but not reached.
    public var isHidden: Bool

    public init(bearing: Double, name: String, detail: String, fit: ChordFit = .inKey, isNear: Bool = false,
                isAimed: Bool = false, isKept: Bool = false, isHidden: Bool = false) {
        self.bearing = bearing
        self.name = name
        self.detail = detail
        self.fit = fit
        self.isNear = isNear
        self.isAimed = isAimed
        self.isKept = isKept
        self.isHidden = isHidden
    }
}

extension DeskChord {
    /// Whether `other` is one step from this: a note added, taken away or
    /// moved a semitone, the root kept.
    func isOneStep(from other: DeskChord?) -> Bool {
        guard let other, other.root == root else { return false }
        return colorSteps(tones.pitchClasses, other.tones.pitchClasses) == 1
    }

    /// The pitch classes it sounds, as notes of the octave.
    var pitchClasses: Set<Int> { Set(tones.pitchClasses.map { ($0 + root.rawValue) % 12 }) }

    /// Whether it shares two notes with `other`: the smooth moves between
    /// degrees.
    func sharesTwo(with other: DeskChord?) -> Bool {
        guard let other, other != self else { return false }
        return pitchClasses.intersection(other.pitchClasses).count >= 2
    }
}

/// The degree's numeral in `key`: "V", "ii", "vii°".
public func numeral(_ degree: Degree, in key: Key) -> String {
    degreeNumeral(key: key, degree: degree)
}

/// The key's degrees round the left stick, as targets.
func degreeTargets(chosen: Degree, sounding: DeskChord?, settings: DeskSettings) -> [Target] {
    DiatonicCycle.thirds.enumerated().map { sector, degree in
        let chord = DeskChord(key: settings.key, degree: degree)
        return Target(bearing: DegreePie.gate.bearings[sector], name: chord.name,
                      detail: numeral(degree, in: settings.key), fit: .inKey,
                      isNear: chord.sharesTwo(with: sounding.map { DeskChord(key: $0.key, degree: $0.spec.degree) }),
                      isAimed: degree == chosen)
    }
}
