// Chord intervals (semitones from chord root) for each joystick direction,
// paired with the quality name the player sees. Intervals and name live in the
// same literal so a change to one forces a look at the other — the on-screen
// chord label can never silently drift from the notes that actually sound.
// (See design-reviews.md H3/D3: the label used to be a separate table.)

/// One chord shape: the intervals that sound plus the quality name shown for it.
struct ChordShape: Sendable {
    let intervals: [Int]
    let name: String
    init(_ intervals: [Int], _ name: String) {
        self.intervals = intervals
        self.name = name
    }
}

// Chord intervals for one joystick direction. Three base-quality variants
// (major/minor/dim base chord) plus the base-independent `action` label shown
// on the joystick ring legend.
struct JoystickOutcome: Sendable {
    let major: ChordShape
    let minor: ChordShape
    let dim: ChordShape
    /// Gesture legend for the ring — describes what the direction does,
    /// independent of the held degree (e.g. "Dom 7", "Flip 3rd").
    let action: String

    func shape(for base: TriadBase) -> ChordShape {
        switch base {
        case .major: return major
        case .minor: return minor
        case .dim:   return dim
        }
    }
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
    private static let base = JoystickOutcome(
        major: ChordShape([0,4,7], "maj"),
        minor: ChordShape([0,3,7], "min"),
        dim:   ChordShape([0,3,6], "dim"),
        action: "Base")

    // Default mode: pop, rock, soul staples
    private static let defaultTable: [JoystickDirection: JoystickOutcome] = [
        .center:    base,
        // ↑ Flip major↔minor (invert the 3rd)
        .up:        JoystickOutcome(major: ChordShape([0,3,7], "min"),
                                    minor: ChordShape([0,4,7], "maj"),
                                    dim:   ChordShape([0,4,7], "maj"),
                                    action: "Flip 3rd"),
        // ↗ Dom7 — flat 7th added
        .upRight:   JoystickOutcome(major: ChordShape([0,4,7,10], "7"),
                                    minor: ChordShape([0,3,7,10], "min7"),
                                    dim:   ChordShape([0,3,6,10], "min7♭5"),
                                    action: "Dom 7"),
        // → Maj7 (major) / min7 (minor) — natural vs. flat 7th per context
        .right:     JoystickOutcome(major: ChordShape([0,4,7,11], "maj7"),
                                    minor: ChordShape([0,3,7,10], "min7"),
                                    dim:   ChordShape([0,3,6,10], "min7♭5"),
                                    action: "Maj 7"),
        // ↘ Add9 — 9th added without 7th
        .downRight: JoystickOutcome(major: ChordShape([0,4,7,14], "add9"),
                                    minor: ChordShape([0,3,7,14], "min add9"),
                                    dim:   ChordShape([0,3,6,14], "dim add9"),
                                    action: "Add 9"),
        // ↓ Sus4 — 3rd replaced by 4th
        .down:      JoystickOutcome(major: ChordShape([0,5,7], "sus4"),
                                    minor: ChordShape([0,5,7], "sus4"),
                                    dim:   ChordShape([0,5,7], "sus4"),
                                    action: "Sus 4"),
        // ↙ 6th (major) / Sus2 (minor) — adds 6th or replaces 3rd with 2nd
        .downLeft:  JoystickOutcome(major: ChordShape([0,4,7,9], "6"),
                                    minor: ChordShape([0,2,7], "sus2"),
                                    dim:   ChordShape([0,2,6], "sus2♭5"),
                                    action: "6/Sus2"),
        // ← Dim/Min — lower 3rd one step; minor becomes diminished
        .left:      JoystickOutcome(major: ChordShape([0,3,7], "min"),
                                    minor: ChordShape([0,3,6], "dim"),
                                    dim:   ChordShape([0,3,6], "dim"),
                                    action: "Dim"),
        // ↖ Aug — raise 5th by one semitone
        .upLeft:    JoystickOutcome(major: ChordShape([0,4,8], "aug"),
                                    minor: ChordShape([0,3,8], "min♯5"),
                                    dim:   ChordShape([0,3,7], "min"),
                                    action: "Aug"),
    ]

    // Extended mode: jazz and R&B colors
    private static let extendedTable: [JoystickDirection: JoystickOutcome] = [
        .center:    base,
        // ↑ Flip major↔minor (same as default)
        .up:        JoystickOutcome(major: ChordShape([0,3,7], "min"),
                                    minor: ChordShape([0,4,7], "maj"),
                                    dim:   ChordShape([0,4,7], "maj"),
                                    action: "Flip 3rd"),
        // ↗ Dom9 — flat 7th + 9th
        .upRight:   JoystickOutcome(major: ChordShape([0,4,7,10,14], "9"),
                                    minor: ChordShape([0,3,7,10,14], "min9"),
                                    dim:   ChordShape([0,3,6,10,14], "min9♭5"),
                                    action: "Dom 9"),
        // → Add11 — 11th added (4th + octave), no notes removed
        .right:     JoystickOutcome(major: ChordShape([0,4,7,17], "add11"),
                                    minor: ChordShape([0,3,7,17], "min add11"),
                                    dim:   ChordShape([0,3,6,17], "dim add11"),
                                    action: "Add 11"),
        // ↘ Min11 — minor + flat 7th + 11th; forces minor quality
        .downRight: JoystickOutcome(major: ChordShape([0,3,7,10,17], "min11"),
                                    minor: ChordShape([0,3,7,10,17], "min11"),
                                    dim:   ChordShape([0,3,7,10,17], "min11"),
                                    action: "Min 11"),
        // ↓ Dom7#9 — "Hendrix chord": flat 7th + sharp 9th
        .down:      JoystickOutcome(major: ChordShape([0,4,7,10,15], "7♯9"),
                                    minor: ChordShape([0,3,7,10,15], "min7♯9"),
                                    dim:   ChordShape([0,3,6,10,15], "min7♭5♯9"),
                                    action: "7♯9"),
        // ↙ Add9 — 9th without 7th (simpler than dom9)
        .downLeft:  JoystickOutcome(major: ChordShape([0,4,7,14], "add9"),
                                    minor: ChordShape([0,3,7,14], "min add9"),
                                    dim:   ChordShape([0,3,6,14], "dim add9"),
                                    action: "Add 9"),
        // ← Sus4+7 — 3rd replaced by 4th, flat 7th added
        .left:      JoystickOutcome(major: ChordShape([0,5,7,10], "7sus4"),
                                    minor: ChordShape([0,5,7,10], "7sus4"),
                                    dim:   ChordShape([0,5,7,10], "7sus4"),
                                    action: "Sus4 7"),
        // ↖ Half-dim7 — minor 3rd, dim 5th, flat 7th
        .upLeft:    JoystickOutcome(major: ChordShape([0,3,6,10], "min7♭5"),
                                    minor: ChordShape([0,3,6,10], "min7♭5"),
                                    dim:   ChordShape([0,3,6,10], "min7♭5"),
                                    action: "½dim 7"),
    ]

    // Chromatic mode: advanced jazz voicings and altered dominants
    private static let chromaticTable: [JoystickDirection: JoystickOutcome] = [
        .center:    base,
        // ↑ MinMaj7 — "James Bond chord": minor + natural 7th; forces minor quality
        .up:        JoystickOutcome(major: ChordShape([0,3,7,11], "min(maj7)"),
                                    minor: ChordShape([0,3,7,11], "min(maj7)"),
                                    dim:   ChordShape([0,3,7,11], "min(maj7)"),
                                    action: "MinMaj 7"),
        // ↗ Dom13 — flat 7th + 9th + 13th
        .upRight:   JoystickOutcome(major: ChordShape([0,4,7,10,14,21], "13"),
                                    minor: ChordShape([0,4,7,10,14,21], "13"),
                                    dim:   ChordShape([0,4,7,10,14,21], "13"),
                                    action: "Dom 13"),
        // → 6/9 — adds 6th and 9th; classic jazz ending voicing
        .right:     JoystickOutcome(major: ChordShape([0,4,7,9,14], "6/9"),
                                    minor: ChordShape([0,3,7,9,14], "min6/9"),
                                    dim:   ChordShape([0,3,6,9,14], "dim6/9"),
                                    action: "6/9"),
        // ↘ Dom7alt — flat 7th + aug 5th + sharp 9th; maximum dissonance
        .downRight: JoystickOutcome(major: ChordShape([0,4,8,10,15], "7alt"),
                                    minor: ChordShape([0,4,8,10,15], "7alt"),
                                    dim:   ChordShape([0,4,8,10,15], "7alt"),
                                    action: "7alt"),
        // ↓ Maj13 — stacks nat 7th + 9th + 13th; forces major quality
        .down:      JoystickOutcome(major: ChordShape([0,4,7,11,14,21], "maj13"),
                                    minor: ChordShape([0,4,7,11,14,21], "maj13"),
                                    dim:   ChordShape([0,4,7,11,14,21], "maj13"),
                                    action: "Maj 13"),
        // ↙ Dom7b9 — flat 7th + flat 9th; "Spanish" darkness
        .downLeft:  JoystickOutcome(major: ChordShape([0,4,7,10,13], "7♭9"),
                                    minor: ChordShape([0,3,7,10,13], "min7♭9"),
                                    dim:   ChordShape([0,3,6,10,13], "min7♭5♭9"),
                                    action: "7♭9"),
        // ← Half-dim7 (same as extended ↖)
        .left:      JoystickOutcome(major: ChordShape([0,3,6,10], "min7♭5"),
                                    minor: ChordShape([0,3,6,10], "min7♭5"),
                                    dim:   ChordShape([0,3,6,10], "min7♭5"),
                                    action: "½dim 7"),
        // ↖ Maj7#11 — Lydian flavor: natural 7th + raised 11th
        .upLeft:    JoystickOutcome(major: ChordShape([0,4,7,11,18], "maj7♯11"),
                                    minor: ChordShape([0,4,7,11,18], "maj7♯11"),
                                    dim:   ChordShape([0,4,7,11,18], "maj7♯11"),
                                    action: "Maj7♯11"),
    ]
}
