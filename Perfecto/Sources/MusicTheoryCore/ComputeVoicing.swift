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

    func build(_ ivls: [Int], octaveShift: Int) -> [Int] {
        ivls.map { chordRoot + $0 + octaveShift * 12 }.sorted()
    }

    func applyInversion(_ notes: [Int], _ inv: Inversion) -> [Int] {
        guard notes.count >= 2 else { return notes }
        var result = notes.sorted()
        switch inv {
        case .root:
            break
        case .first:
            result[0] += 12
            result.sort()
        case .second:
            result[0] += 12
            result[1] += 12
            result.sort()
        }
        return result
    }

    if voiceLeading, let prev = previousVoicing, !prev.notes.isEmpty {
        var best = applyInversion(build(intervals, octaveShift: 0), inversion)
        var bestCost = voiceLeadingCost(best, prev.notes)

        for shift in [-1, 0, 1] {
            for inv in [Inversion.root, .first, .second] {
                let candidate = applyInversion(build(intervals, octaveShift: shift), inv)
                let cost = voiceLeadingCost(candidate, prev.notes)
                if cost < bestCost {
                    bestCost = cost
                    best = candidate
                }
            }
        }
        return Voicing(notes: best)
    }

    return Voicing(notes: applyInversion(build(intervals, octaveShift: 0), inversion))
}

// Sum of each note's distance to the nearest note in the reference voicing
private func voiceLeadingCost(_ a: [Int], _ b: [Int]) -> Int {
    a.reduce(0) { total, note in
        total + (b.map { abs(note - $0) }.min() ?? 0)
    }
}
