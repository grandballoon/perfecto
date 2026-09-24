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
