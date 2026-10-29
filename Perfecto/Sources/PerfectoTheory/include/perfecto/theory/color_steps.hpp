// How far apart two chord colors are, in steps: a step adds a note, takes
// one away, or moves one a semitone. Counted between pitch classes above the
// root, so a 9th is its 2nd. The color ring's touching cells are one step
// apart, and so is every tone mark.

#ifndef PERFECTO_THEORY_COLOR_STEPS_HPP
#define PERFECTO_THEORY_COLOR_STEPS_HPP

#include "perfecto/theory/chord_color.hpp"
#include "perfecto/theory/key.hpp"

#include <vector>

namespace perfecto::theory {

/// The steps between two sets of pitch classes: the cheapest pairing of the
/// notes only one of them has, a pair costing the semitones between its two
/// (at most 2, which is as much as taking one away and adding the other)
/// and a note left over costing 1.
int colorSteps(const std::vector<int> &a, const std::vector<int> &b);

/// The steps between the chords two colors make on `degree` in `key`.
int colorSteps(const ChordColor &a, const ChordColor &b, const Key &key, Degree degree);

} // namespace perfecto::theory

#endif
