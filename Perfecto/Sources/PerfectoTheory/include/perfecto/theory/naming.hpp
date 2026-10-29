// Chord labelling: the single source of truth for the text the player sees.
//
// The chord's name is derived from the same inputs that produce the notes:
// the scale-driven base quality (major, minor, diminished) and the shape the
// chord's color resolves to (`chordShape`). Nothing here keeps a parallel
// table, so a label cannot say "maj7" while a min7 sounds, and it stays
// correct across scales rather than assuming the major scale's qualities.

#ifndef PERFECTO_THEORY_NAMING_HPP
#define PERFECTO_THEORY_NAMING_HPP

#include "perfecto/theory/chord_color.hpp"
#include "perfecto/theory/chord_shape.hpp"
#include "perfecto/theory/key.hpp"

#include <string>

namespace perfecto::theory {

/// The natural triad quality of `degree` within `key`'s scale: the exact
/// major, minor or diminished determination the notes are chosen by.
TriadBase triadBase(const Key &key, Degree degree);

/// Pitch class of the chord root for `degree` in `key`.
PitchClass chordRootPitchClass(const Key &key, Degree degree);

/// Roman numeral for `degree` in `key`, cased by the degree's triad
/// quality: uppercase for major, lowercase for minor, lowercase with "°"
/// for diminished. Numerals count scale steps, so C natural minor reads
/// i ii° III iv v VI VII.
std::string degreeNumeral(const Key &key, Degree degree);

/// The intervals and quality name `spec` resolves to in `key`: the one
/// place a chord color is turned into a shape, shared by the notes and the
/// label.
ChordShape chordShape(const Key &key, const ChordSpec &spec);

/// Quality name for `spec` (e.g. "maj7", "min7♭5").
std::string chordQualityName(const Key &key, const ChordSpec &spec);

/// Full chord label, e.g. "D min7"; a note alone is its name, "D". Tones
/// that are another chord over this root are named as that chord over its
/// bass: "C/E", "A min/C".
std::string chordLabel(const Key &key, const ChordSpec &spec);

/// What `color` does to any degree's triad, e.g. "Dom 7": the legend for a
/// color independent of the degree it is applied to.
std::string colorActionLabel(const ChordColor &color);

/// Base-independent gesture legend for the joystick ring, e.g. "Dom 7".
std::string joystickActionLabel(JoystickMode mode, JoystickDirection direction);

} // namespace perfecto::theory

#endif
