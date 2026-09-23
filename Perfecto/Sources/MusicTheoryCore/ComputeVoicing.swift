/// Compute the MIDI notes for a chord given key, scale degree, joystick state, and voice settings.
///
/// MIDI convention: middle C = C4 = note 60.
/// Formula: chordRootMIDI = pitchClass.rawValue + (octave + 1) * 12 + degreeOffset
public func computeVoicing(
    key: Key,
    degree: Degree,
    joystickMode: JoystickMode,
    joystickDirection: JoystickDirection,
    inversion: Inversion,
    octave: Int,
    voiceLeading: Bool,
    previousVoicing: Voicing?
) -> Voicing {
    let scaleIntervals = key.scale.intervals
    let n = scaleIntervals.count
    let degIdx = degree.index

    // Semitone offset of the chord root above the key root
    let degreeOffset = scaleIntervals[degIdx % n] + (degIdx / n) * 12

    // Base triad quality (major/minor/dim) — shared with the on-screen label so
    // the notes and the displayed name can never disagree (see ChordNaming.swift).
    let base = triadBase(key: key, degree: degree)

    // Resolve chord intervals from the joystick map
    let outcome = JoystickMap.outcome(mode: joystickMode, direction: joystickDirection)
    let intervals: [Int] = outcome.shape(for: base).intervals

    // MIDI note of the chord root
    let chordRoot = key.root.rawValue + (octave + 1) * 12 + degreeOffset

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
