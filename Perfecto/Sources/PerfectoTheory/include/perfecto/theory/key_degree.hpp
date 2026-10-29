// A chord named by its root. The chord keys name a chord by its degree, so
// the key says what it is; an octave of roots names it by its note, and the
// key still says what it is: a note of the key plays its own degree's chord,
// and a note outside it a chord borrowed from the scale nearest the key's.

#ifndef PERFECTO_THEORY_KEY_DEGREE_HPP
#define PERFECTO_THEORY_KEY_DEGREE_HPP

#include "perfecto/theory/key.hpp"
#include "perfecto/theory/modes.hpp"

#include <array>

namespace perfecto::theory {

/// A degree of a key: the triad a chord is built on, with the scale its
/// colors are read through.
struct KeyDegree {
    Key key;
    Degree degree;

    bool operator==(const KeyDegree &) const = default;
    auto operator<=>(const KeyDegree &) const = default;

    /// The chord on `root` as `key` has it.
    ///
    /// A note of the key is its own degree there. A note outside the key is
    /// borrowed from a parallel mode: of the modes of the major scale on the
    /// key's tonic that have the note, the one that changes the fewest of the
    /// key's notes (of two as near, the brighter). So C major has B♭ major
    /// from Mixolydian, E♭ and A♭ major from Dorian and Aeolian, D♭ major
    /// from Phrygian and F♯ diminished from Lydian.
    ///
    /// The mode is given as a key on the same tonic where there is a scale
    /// for it (C Mixolydian), and as its relative major where there is not
    /// (C Phrygian is A♭ major, read from its third).
    static KeyDegree onRoot(PitchClass root, const Key &key);

    /// The modes a note outside the key is borrowed from, brightest first.
    static const std::array<HeptatonicMode, 7> parallelModes;

    /// The note the chord is built on.
    PitchClass root() const;
};

} // namespace perfecto::theory

#endif
