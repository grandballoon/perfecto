// Chords built by stacking thirds through a seven-note mode: the rule the
// chord grid computes instead of looking shapes up in a table. The grid's X
// axis is the stack's `StackHeight`; its Y axis chooses which mode to stack
// through, starting from the degree's own diatonic mode.

#ifndef PERFECTO_THEORY_TERTIAN_HPP
#define PERFECTO_THEORY_TERTIAN_HPP

#include "perfecto/theory/key.hpp"
#include "perfecto/theory/modes.hpp"

#include <array>
#include <optional>
#include <string>
#include <vector>

namespace perfecto::theory {

/// How many thirds a chord stacks above its root.
enum class StackHeight { triad = 3, seventh = 4, ninth = 5, eleventh = 6, thirteenth = 7 };

inline constexpr std::array<StackHeight, 5> allStackHeights = {
    StackHeight::triad, StackHeight::seventh, StackHeight::ninth, StackHeight::eleventh, StackHeight::thirteenth,
};

inline int raw(StackHeight h) { return static_cast<int>(h); }

/// Column heading: "Triad", "7th", "9th", "11th", "13th".
std::string displayName(StackHeight h);

/// The degree's diatonic mode: the seven intervals (semitones above the
/// degree's root, ascending from 0) of `key`'s scale read from `degree`.
/// C major ii → D Dorian [0, 2, 3, 5, 7, 9, 10]. None for scales without
/// seven notes, where stacking thirds is undefined.
std::optional<std::vector<int>> diatonicMode(const Key &key, Degree degree);

/// The chord that stacks `height` thirds through `mode` (seven ascending
/// intervals from 0): chord tone k is mode step 2k, so the ninth, eleventh
/// and thirteenth land an octave above the second, fourth and sixth.
///
/// A perfect eleventh over a major third clashes (it sits a minor ninth
/// above the third), so it is voiced the standard way: an eleventh chord
/// drops the third (C11 = C G B♭ D F), and a thirteenth chord drops the
/// eleventh (C13 = C E G B♭ D A). Every column therefore stays distinct
/// from its neighbours.
std::vector<int> stackThirds(const std::vector<int> &mode, StackHeight height);

/// The name of `stackThirds(intervals(mode), height)`, read from the same
/// stacked tones, e.g. "min9", "13♯11", "7♭9♭13", "min(maj7)".
///
/// Standard lead-sheet form: a quality prefix from the third and seventh,
/// the highest natural extension as the number (lower natural ones are
/// implied), then an altered fifth, then every altered extension in
/// ascending order. A dominant "13" implies the dropped eleventh, as usual;
/// an eleventh that was dropped never becomes the number.
std::string tertianChordName(HeptatonicMode mode, StackHeight height);

} // namespace perfecto::theory

#endif
