#include "perfecto/theory/joystick.hpp"

namespace perfecto::theory {

const ChordShape &JoystickOutcome::shape(TriadBase base) const {
    switch (base) {
    case TriadBase::major: return major;
    case TriadBase::minor: return minor;
    case TriadBase::dim: return dim;
    }
    return major;
}

namespace {

using O = JoystickOutcome;

// Base triad: the center always returns the unmodified chord.
const O base = {{{0, 4, 7}, "maj"}, {{0, 3, 7}, "min"}, {{0, 3, 6}, "dim"}, "Base"};

// In `allJoystickDirections` order: center, up, upRight, right, downRight,
// down, downLeft, left, upLeft.

// Default mode: pop, rock, soul staples.
const std::array<O, 9> defaultTable = {
    base,
    // ↑ Flip major↔minor (invert the 3rd)
    O{{{0, 3, 7}, "min"}, {{0, 4, 7}, "maj"}, {{0, 4, 7}, "maj"}, "Flip 3rd"},
    // ↗ Dom7: flat 7th added
    O{{{0, 4, 7, 10}, "7"}, {{0, 3, 7, 10}, "min7"}, {{0, 3, 6, 10}, "min7♭5"}, "Dom 7"},
    // → Maj7 (major) / min7 (minor): natural vs. flat 7th per context
    O{{{0, 4, 7, 11}, "maj7"}, {{0, 3, 7, 10}, "min7"}, {{0, 3, 6, 10}, "min7♭5"}, "Maj 7"},
    // ↘ Add9: 9th added without 7th
    O{{{0, 4, 7, 14}, "add9"}, {{0, 3, 7, 14}, "min add9"}, {{0, 3, 6, 14}, "dim add9"}, "Add 9"},
    // ↓ Sus4: 3rd replaced by 4th
    O{{{0, 5, 7}, "sus4"}, {{0, 5, 7}, "sus4"}, {{0, 5, 7}, "sus4"}, "Sus 4"},
    // ↙ 6th (major) / Sus2 (minor): adds 6th or replaces 3rd with 2nd
    O{{{0, 4, 7, 9}, "6"}, {{0, 2, 7}, "sus2"}, {{0, 2, 6}, "sus2♭5"}, "6/Sus2"},
    // ← Dim/Min: lower 3rd one step; minor becomes diminished
    O{{{0, 3, 7}, "min"}, {{0, 3, 6}, "dim"}, {{0, 3, 6}, "dim"}, "Dim"},
    // ↖ Aug: raise 5th by one semitone
    O{{{0, 4, 8}, "aug"}, {{0, 3, 8}, "min♯5"}, {{0, 3, 7}, "min"}, "Aug"},
};

// Extended mode: jazz and R&B colors.
const std::array<O, 9> extendedTable = {
    base,
    // ↑ Flip major↔minor (same as default)
    O{{{0, 3, 7}, "min"}, {{0, 4, 7}, "maj"}, {{0, 4, 7}, "maj"}, "Flip 3rd"},
    // ↗ Dom9: flat 7th + 9th
    O{{{0, 4, 7, 10, 14}, "9"}, {{0, 3, 7, 10, 14}, "min9"}, {{0, 3, 6, 10, 14}, "min9♭5"}, "Dom 9"},
    // → Add11: 11th added (4th + octave), no notes removed
    O{{{0, 4, 7, 17}, "add11"}, {{0, 3, 7, 17}, "min add11"}, {{0, 3, 6, 17}, "dim add11"}, "Add 11"},
    // ↘ Min11: minor + flat 7th + 11th; forces minor quality
    O{{{0, 3, 7, 10, 17}, "min11"}, {{0, 3, 7, 10, 17}, "min11"}, {{0, 3, 7, 10, 17}, "min11"}, "Min 11"},
    // ↓ Dom7#9, the "Hendrix chord": flat 7th + sharp 9th
    O{{{0, 4, 7, 10, 15}, "7♯9"}, {{0, 3, 7, 10, 15}, "min7♯9"}, {{0, 3, 6, 10, 15}, "min7♭5♯9"}, "7♯9"},
    // ↙ Add9: 9th without 7th (simpler than dom9)
    O{{{0, 4, 7, 14}, "add9"}, {{0, 3, 7, 14}, "min add9"}, {{0, 3, 6, 14}, "dim add9"}, "Add 9"},
    // ← Sus4+7: 3rd replaced by 4th, flat 7th added
    O{{{0, 5, 7, 10}, "7sus4"}, {{0, 5, 7, 10}, "7sus4"}, {{0, 5, 7, 10}, "7sus4"}, "Sus4 7"},
    // ↖ Half-dim7: minor 3rd, dim 5th, flat 7th
    O{{{0, 3, 6, 10}, "min7♭5"}, {{0, 3, 6, 10}, "min7♭5"}, {{0, 3, 6, 10}, "min7♭5"}, "½dim 7"},
};

// Chromatic mode: advanced jazz voicings and altered dominants.
const std::array<O, 9> chromaticTable = {
    base,
    // ↑ MinMaj7, the "James Bond chord": minor + natural 7th; forces minor quality
    O{{{0, 3, 7, 11}, "min(maj7)"}, {{0, 3, 7, 11}, "min(maj7)"}, {{0, 3, 7, 11}, "min(maj7)"}, "MinMaj 7"},
    // ↗ Dom13: flat 7th + 9th + 13th
    O{{{0, 4, 7, 10, 14, 21}, "13"}, {{0, 4, 7, 10, 14, 21}, "13"}, {{0, 4, 7, 10, 14, 21}, "13"}, "Dom 13"},
    // → 6/9: adds 6th and 9th; classic jazz ending voicing
    O{{{0, 4, 7, 9, 14}, "6/9"}, {{0, 3, 7, 9, 14}, "min6/9"}, {{0, 3, 6, 9, 14}, "dim6/9"}, "6/9"},
    // ↘ Dom7alt: flat 7th + aug 5th + sharp 9th; maximum dissonance
    O{{{0, 4, 8, 10, 15}, "7alt"}, {{0, 4, 8, 10, 15}, "7alt"}, {{0, 4, 8, 10, 15}, "7alt"}, "7alt"},
    // ↓ Maj13: stacks nat 7th + 9th + 13th; forces major quality
    O{{{0, 4, 7, 11, 14, 21}, "maj13"}, {{0, 4, 7, 11, 14, 21}, "maj13"}, {{0, 4, 7, 11, 14, 21}, "maj13"}, "Maj 13"},
    // ↙ Dom7b9: flat 7th + flat 9th; "Spanish" darkness
    O{{{0, 4, 7, 10, 13}, "7♭9"}, {{0, 3, 7, 10, 13}, "min7♭9"}, {{0, 3, 6, 10, 13}, "min7♭5♭9"}, "7♭9"},
    // ← Half-dim7 (same as extended ↖)
    O{{{0, 3, 6, 10}, "min7♭5"}, {{0, 3, 6, 10}, "min7♭5"}, {{0, 3, 6, 10}, "min7♭5"}, "½dim 7"},
    // ↖ Maj7#11: Lydian flavor, natural 7th + raised 11th
    O{{{0, 4, 7, 11, 18}, "maj7♯11"}, {{0, 4, 7, 11, 18}, "maj7♯11"}, {{0, 4, 7, 11, 18}, "maj7♯11"}, "Maj7♯11"},
};

} // namespace

const JoystickOutcome &joystickOutcome(JoystickMode mode, JoystickDirection direction) {
    const int d = static_cast<int>(direction);
    switch (mode) {
    case JoystickMode::default_: return defaultTable[d];
    case JoystickMode::extended: return extendedTable[d];
    case JoystickMode::chromatic: return chromaticTable[d];
    }
    return defaultTable[d];
}

} // namespace perfecto::theory
