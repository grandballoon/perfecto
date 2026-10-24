// How far apart two chord colors are, in steps: a step adds a note, takes
// one away, or moves one a semitone. Counted between pitch classes above the
// root, so a 9th is its 2nd. The color ring's touching cells are one step
// apart, and so is every tone mark.

/// The steps between two sets of pitch classes: the cheapest pairing of the
/// notes only one of them has, a pair costing the semitones between its two
/// (at most 2, which is as much as taking one away and adding the other)
/// and a note left over costing 1.
public func colorSteps(_ a: [Int], _ b: [Int]) -> Int {
    let a = Set(a.map(pitchClass)), b = Set(b.map(pitchClass))
    return cheapest(gone: Array(a.subtracting(b)).sorted(), come: Array(b.subtracting(a)).sorted())
}

/// The steps between the chords two colors make on `degree` in `key`.
public func colorSteps(_ a: ChordColor, _ b: ChordColor, key: Key, degree: Degree) -> Int {
    colorSteps(chordShape(key: key, spec: ChordSpec(degree: degree, color: a)).intervals,
               chordShape(key: key, spec: ChordSpec(degree: degree, color: b)).intervals)
}

private func pitchClass(_ semitones: Int) -> Int { ((semitones % 12) + 12) % 12 }

/// A chord has at most seven notes, so every pairing can be tried.
private func cheapest(gone: [Int], come: [Int]) -> Int {
    guard let first = gone.first else { return come.count }
    guard !come.isEmpty else { return gone.count }
    let rest = Array(gone.dropFirst())
    var best = 1 + cheapest(gone: rest, come: come)
    for (i, note) in come.enumerated() {
        let apart = abs(first - note)
        let move = min(min(apart, 12 - apart), 2)
        var others = come
        others.remove(at: i)
        best = min(best, move + cheapest(gone: rest, come: others))
    }
    return best
}
