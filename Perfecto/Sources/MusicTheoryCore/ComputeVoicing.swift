/// Compute the MIDI notes for the chord `spec` in `key`, voiced by the given settings.
///
/// MIDI convention: middle C = C4 = note 60.
/// Formula: chordRootMIDI = pitchClass.rawValue + (octave + 1) * 12 + degreeOffset
public func computeVoicing(
    key: Key,
    spec: ChordSpec,
    inversion: Inversion,
    octave: Int,
    voiceLeading: Bool,
    previousVoicing: Voicing?
) -> Voicing {
    // Same shape the on-screen label is read from, so the notes and the
    // displayed name can never disagree (see ChordNaming.swift).
    let intervals = chordShape(key: key, spec: spec).intervals

    // MIDI note of the chord root
    let chordRoot = key.root.rawValue + (octave + 1) * 12 + key.scale.offset(of: spec.degree)

    /// The chord rolled to `inversion`, `octaveShift` octaves from its own.
    func build(_ inversion: Inversion, octaveShift: Int) -> [Int] {
        inversion.applied(to: intervals).map { chordRoot + $0 + octaveShift * 12 }
    }

    if voiceLeading, let prev = previousVoicing, !prev.notes.isEmpty {
        var best = build(inversion, octaveShift: 0)
        var bestCost = voiceLeadingCost(best, prev.notes)

        for shift in [-1, 0, 1] {
            for inv in [Inversion.root, .first, .second] {
                let candidate = build(inv, octaveShift: shift)
                let cost = voiceLeadingCost(candidate, prev.notes)
                if cost < bestCost {
                    bestCost = cost
                    best = candidate
                }
            }
        }
        return Voicing(notes: best)
    }

    return Voicing(notes: build(inversion, octaveShift: 0))
}

// Sum of each note's distance to the nearest note in the reference voicing
private func voiceLeadingCost(_ a: [Int], _ b: [Int]) -> Int {
    a.reduce(0) { total, note in
        total + (b.map { abs(note - $0) }.min() ?? 0)
    }
}
