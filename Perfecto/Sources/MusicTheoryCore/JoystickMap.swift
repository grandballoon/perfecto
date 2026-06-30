// Chord intervals (semitones from chord root) for each joystick direction.
// Three variants per entry: major base chord, minor base chord, diminished base chord.
struct JoystickOutcome: Sendable {
    let major: [Int]
    let minor: [Int]
    let dim: [Int]
}

enum JoystickMap {
    static func outcome(mode: JoystickMode, direction: JoystickDirection) -> JoystickOutcome {
        switch mode {
        case .default:   return defaultTable[direction]!
        case .extended:  return extendedTable[direction]!
        case .chromatic: return chromaticTable[direction]!
        }
    }

    // Base triad — center always returns the unmodified chord
    private static let base = JoystickOutcome(major: [0,4,7], minor: [0,3,7], dim: [0,3,6])

    // Default mode: pop, rock, soul staples
    private static let defaultTable: [JoystickDirection: JoystickOutcome] = [
        .center:    base,
        // ↑ Flip major↔minor (invert the 3rd)
        .up:        JoystickOutcome(major: [0,3,7],    minor: [0,4,7],    dim: [0,4,7]),
        // ↗ Dom7 — flat 7th added
        .upRight:   JoystickOutcome(major: [0,4,7,10], minor: [0,3,7,10], dim: [0,3,6,10]),
        // → Maj7 (major) / min7 (minor) — natural vs. flat 7th per context
        .right:     JoystickOutcome(major: [0,4,7,11], minor: [0,3,7,10], dim: [0,3,6,10]),
        // ↘ Add9 — 9th added without 7th
        .downRight: JoystickOutcome(major: [0,4,7,14], minor: [0,3,7,14], dim: [0,3,6,14]),
        // ↓ Sus4 — 3rd replaced by 4th
        .down:      JoystickOutcome(major: [0,5,7],    minor: [0,5,7],    dim: [0,5,7]),
        // ↙ 6th (major) / Sus2 (minor) — adds 6th or replaces 3rd with 2nd
        .downLeft:  JoystickOutcome(major: [0,4,7,9],  minor: [0,2,7],    dim: [0,2,6]),
        // ← Dim/Min — lower 3rd one step; minor becomes diminished
        .left:      JoystickOutcome(major: [0,3,7],    minor: [0,3,6],    dim: [0,3,6]),
        // ↖ Aug — raise 5th by one semitone
        .upLeft:    JoystickOutcome(major: [0,4,8],    minor: [0,3,8],    dim: [0,3,7]),
    ]

    // Extended mode: jazz and R&B colors
    private static let extendedTable: [JoystickDirection: JoystickOutcome] = [
        .center:    base,
        // ↑ Flip major↔minor (same as default)
        .up:        JoystickOutcome(major: [0,3,7],        minor: [0,4,7],        dim: [0,4,7]),
        // ↗ Dom9 — flat 7th + 9th
        .upRight:   JoystickOutcome(major: [0,4,7,10,14],  minor: [0,3,7,10,14],  dim: [0,3,6,10,14]),
        // → Add11 — 11th added (4th + octave), no notes removed
        .right:     JoystickOutcome(major: [0,4,7,17],     minor: [0,3,7,17],     dim: [0,3,6,17]),
        // ↘ Min11 — minor + flat 7th + 11th; forces minor quality
        .downRight: JoystickOutcome(major: [0,3,7,10,17],  minor: [0,3,7,10,17],  dim: [0,3,7,10,17]),
        // ↓ Dom7#9 — "Hendrix chord": flat 7th + sharp 9th
        .down:      JoystickOutcome(major: [0,4,7,10,15],  minor: [0,3,7,10,15],  dim: [0,3,6,10,15]),
        // ↙ Add9 — 9th without 7th (simpler than dom9)
        .downLeft:  JoystickOutcome(major: [0,4,7,14],     minor: [0,3,7,14],     dim: [0,3,6,14]),
        // ← Sus4+7 — 3rd replaced by 4th, flat 7th added
        .left:      JoystickOutcome(major: [0,5,7,10],     minor: [0,5,7,10],     dim: [0,5,7,10]),
        // ↖ Half-dim7 — minor 3rd, dim 5th, flat 7th
        .upLeft:    JoystickOutcome(major: [0,3,6,10],     minor: [0,3,6,10],     dim: [0,3,6,10]),
    ]

    // Chromatic mode: advanced jazz voicings and altered dominants
    private static let chromaticTable: [JoystickDirection: JoystickOutcome] = [
        .center:    base,
        // ↑ MinMaj7 — "James Bond chord": minor + natural 7th; forces minor quality
        .up:        JoystickOutcome(major: [0,3,7,11],       minor: [0,3,7,11],       dim: [0,3,7,11]),
        // ↗ Dom13 — flat 7th + 9th + 13th
        .upRight:   JoystickOutcome(major: [0,4,7,10,14,21], minor: [0,4,7,10,14,21], dim: [0,4,7,10,14,21]),
        // → 6/9 — adds 6th and 9th; classic jazz ending voicing
        .right:     JoystickOutcome(major: [0,4,7,9,14],     minor: [0,3,7,9,14],     dim: [0,3,6,9,14]),
        // ↘ Dom7alt — flat 7th + aug 5th + sharp 9th; maximum dissonance
        .downRight: JoystickOutcome(major: [0,4,8,10,15],    minor: [0,4,8,10,15],    dim: [0,4,8,10,15]),
        // ↓ Maj13 — stacks nat 7th + 9th + 13th; forces major quality
        .down:      JoystickOutcome(major: [0,4,7,11,14,21], minor: [0,4,7,11,14,21], dim: [0,4,7,11,14,21]),
        // ↙ Dom7b9 — flat 7th + flat 9th; "Spanish" darkness
        .downLeft:  JoystickOutcome(major: [0,4,7,10,13],    minor: [0,3,7,10,13],    dim: [0,3,6,10,13]),
        // ← Half-dim7 (same as extended ↖)
        .left:      JoystickOutcome(major: [0,3,6,10],       minor: [0,3,6,10],       dim: [0,3,6,10]),
        // ↖ Maj7#11 — Lydian flavor: natural 7th + raised 11th
        .upLeft:    JoystickOutcome(major: [0,4,7,11,18],    minor: [0,4,7,11,18],    dim: [0,4,7,11,18]),
    ]
}
