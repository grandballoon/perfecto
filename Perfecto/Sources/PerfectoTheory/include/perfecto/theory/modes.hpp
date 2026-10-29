// The modes the chord grid's rows stack thirds through: every mode of the
// major, melodic minor and harmonic minor scales. Every seven-note scale the
// app offers is one of these read from some degree, so a degree's own
// diatonic mode is always in the catalog.

#ifndef PERFECTO_THEORY_MODES_HPP
#define PERFECTO_THEORY_MODES_HPP

#include "perfecto/theory/key.hpp"

#include <array>
#include <optional>
#include <string>
#include <vector>

namespace perfecto::theory {

/// A seven-note mode, named by the scale it is a rotation of.
enum class HeptatonicMode {
    // Modes of the major scale
    ionian, dorian, phrygian, lydian, mixolydian, aeolian, locrian,
    // Modes of melodic minor
    melodicMinor, dorianFlat2, lydianAugmented, lydianDominant, mixolydianFlat6, locrianNatural2, altered,
    // Modes of harmonic minor
    harmonicMinor, locrianNatural6, ionianSharp5, dorianSharp4, phrygianDominant, lydianSharp2, ultralocrian,
};

inline constexpr std::array<HeptatonicMode, 21> allHeptatonicModes = {
    HeptatonicMode::ionian,          HeptatonicMode::dorian,          HeptatonicMode::phrygian,
    HeptatonicMode::lydian,          HeptatonicMode::mixolydian,      HeptatonicMode::aeolian,
    HeptatonicMode::locrian,         HeptatonicMode::melodicMinor,    HeptatonicMode::dorianFlat2,
    HeptatonicMode::lydianAugmented, HeptatonicMode::lydianDominant,  HeptatonicMode::mixolydianFlat6,
    HeptatonicMode::locrianNatural2, HeptatonicMode::altered,         HeptatonicMode::harmonicMinor,
    HeptatonicMode::locrianNatural6, HeptatonicMode::ionianSharp5,    HeptatonicMode::dorianSharp4,
    HeptatonicMode::phrygianDominant, HeptatonicMode::lydianSharp2,   HeptatonicMode::ultralocrian,
};

/// The three scales the modes are rotations of.
enum class ScaleFamily { major, harmonicMinor, melodicMinor };

inline constexpr std::array<ScaleFamily, 3> allScaleFamilies = {
    ScaleFamily::major, ScaleFamily::harmonicMinor, ScaleFamily::melodicMinor,
};

std::string displayName(HeptatonicMode m);
std::string displayName(ScaleFamily f);

/// The scale the mode is a rotation of.
ScaleFamily family(HeptatonicMode m);

/// Which mode of its family it is, from 1: the step of the family's scale
/// it is read from, counted from the first.
int number(HeptatonicMode m);

/// Seven ascending semitone offsets from 0. Lydian → [0, 2, 4, 6, 7, 9, 11].
const std::vector<int> &intervals(HeptatonicMode m);

/// The mode with exactly these seven intervals, if it is in the catalog.
std::optional<HeptatonicMode> modeWith(const std::vector<int> &intervals);

/// `degree`'s own mode in `key` (C major ii → Dorian); none for scales
/// without seven notes.
std::optional<HeptatonicMode> ownModeOf(const Key &key, Degree degree);

/// Every mode from brightest to darkest: the grid's rows, top to bottom.
///
/// Brightness is the sum of the intervals, so each raised note brightens by
/// one: along the major modes this is the familiar Lydian → Locrian order.
/// Several modes share each sum; within a sum, each next row is the mode
/// that changes the fewest notes from the row above (ties go to the higher
/// intervals, the brighter-sounding low notes), so every step down the grid
/// moves one or two notes.
const std::vector<HeptatonicMode> &byBrightness();

/// `count` consecutive rows of `byBrightness` centred on `center`, shifted
/// inward at the brightest and darkest ends so there are always `count`.
std::vector<HeptatonicMode> rowsAround(HeptatonicMode center, int count);

/// The family's seven modes, first to seventh.
std::vector<HeptatonicMode> modes(ScaleFamily f);

/// Every mode, family by family in the order above, each family's first to
/// seventh.
const std::vector<HeptatonicMode> &allModesByFamily();

} // namespace perfecto::theory

#endif
