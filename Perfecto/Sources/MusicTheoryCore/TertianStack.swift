// Chords built by stacking thirds through a seven-note mode — the rule the
// chord grid computes instead of looking shapes up in a table. The grid's X
// axis is the stack's `StackHeight`; its Y axis chooses which mode to stack
// through, starting from the degree's own diatonic mode.

/// How many thirds a chord stacks above its root.
public enum StackHeight: Int, CaseIterable, Codable, Sendable {
    case triad = 3, seventh = 4, ninth = 5, eleventh = 6, thirteenth = 7
}

/// The degree's diatonic mode: the seven intervals (semitones above the
/// degree's root, ascending from 0) of `key`'s scale read from `degree`.
/// C major ii → D Dorian `[0, 2, 3, 5, 7, 9, 10]`.
/// Nil for scales without seven notes, where stacking thirds is undefined.
public func diatonicMode(key: Key, degree: Degree) -> [Int]? {
    guard key.scale.isHeptatonic else { return nil }
    let root = key.scale.offset(of: degree)
    return (0..<7).map { key.scale.semitones(atStep: degree.index + $0) - root }
}

/// The chord that stacks `height` thirds through `mode` (seven ascending
/// intervals from 0): chord tone k is mode step 2k, so the ninth, eleventh
/// and thirteenth land an octave above the second, fourth and sixth.
///
/// A perfect eleventh over a major third clashes (it sits a minor ninth above
/// the third), so it is voiced the standard way:
/// - an eleventh chord drops the third (C11 = C G B♭ D F), and
/// - a thirteenth chord drops the eleventh (C13 = C E G B♭ D A).
/// Every column therefore stays distinct from its neighbours.
public func stackThirds(_ mode: [Int], height: StackHeight) -> [Int] {
    precondition(mode.count == 7 && mode.first == 0, "a mode is seven intervals from 0")
    var tones: [Int] = []
    for k in 0..<height.rawValue {
        let step = 2 * k
        tones.append(mode[step % 7] + (step / 7) * 12)
    }
    let majorThird = tones[1] == 4
    let perfectEleventh = tones.count > 5 && tones[5] == 17
    if majorThird && perfectEleventh {
        tones.remove(at: height == .eleventh ? 1 : 5)
    }
    return tones
}

extension StackHeight {
    /// Column heading: "Triad", "7th", "9th", "11th", "13th".
    public var displayName: String {
        switch self {
        case .triad:      return "Triad"
        case .seventh:    return "7th"
        case .ninth:      return "9th"
        case .eleventh:   return "11th"
        case .thirteenth: return "13th"
        }
    }
}

/// The name of `stackThirds(mode.intervals, height:)`, read from the same
/// stacked tones, e.g. "min9", "13♯11", "7♭9♭13", "min(maj7)".
///
/// Standard lead-sheet form: a quality prefix from the third and seventh, the
/// highest natural extension as the number (lower natural ones are implied),
/// then an altered fifth, then every altered extension in ascending order.
/// A dominant "13" implies the dropped eleventh, as usual; an eleventh that
/// was dropped never becomes the number.
public func tertianChordName(_ mode: HeptatonicMode, height: StackHeight) -> String {
    let m = mode.intervals
    let (third, fifth, seventh) = (m[2], m[4], m[6])

    if height == .triad {
        switch (third, fifth) {
        case (4, 7): return "maj"
        case (3, 7): return "min"
        case (3, 6): return "dim"
        case (4, 8): return "aug"
        default:     return (third == 4 ? "maj" : "min") + accidental(fifth - 7) + "5"
        }
    }

    // Extensions stacked at this height: the 9th, 11th and 13th sit an octave
    // above mode steps 1, 3 and 5; natural means 14, 17 and 21 semitones.
    let elevenDropped = height == .thirteenth && third == 4 && m[3] == 5
    let extensions = [(9, m[1] + 12 - 14), (11, m[3] + 12 - 17), (13, m[5] + 12 - 21)]
        .prefix(height.rawValue - 4)
        .filter { !(elevenDropped && $0.0 == 11) }
    let number = extensions.last(where: { $0.1 == 0 })?.0 ?? 7
    let alterations = extensions
        .filter { $0.1 != 0 }
        .map { accidental($0.1) + String($0.0) }
        .joined()

    let fifthMark = fifth == 7 ? "" : accidental(fifth - 7) + "5"
    switch (third, seventh) {
    case (4, 11): return "maj\(number)" + fifthMark + alterations
    case (4, 10): return "\(number)" + fifthMark + alterations
    case (3, 10): return "min\(number)" + fifthMark + alterations
    case (3, 11): return "min(maj\(number))" + fifthMark + alterations
    case (3, 9) where fifth == 6:
        return "dim\(number)" + alterations
    default:
        preconditionFailure("\(mode) has no tertian seventh chord name")
    }
}

/// "♭" or "♯" for a one-semitone alteration.
private func accidental(_ semitones: Int) -> String {
    switch semitones {
    case -1: return "♭"
    case 1:  return "♯"
    default: preconditionFailure("alteration of \(semitones) semitones")
    }
}
