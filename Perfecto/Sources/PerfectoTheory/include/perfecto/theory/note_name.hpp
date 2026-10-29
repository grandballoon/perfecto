// Notes as they are written: a letter and an accidental, not a bare pitch
// class. B Locrian is B C D E F G A, and F♯ major has E♯ and not F, because
// a scale uses each letter once and a chord stacks every other letter.

#ifndef PERFECTO_THEORY_NOTE_NAME_HPP
#define PERFECTO_THEORY_NOTE_NAME_HPP

#include "perfecto/theory/key.hpp"

#include <array>
#include <string>

namespace perfecto::theory {

/// A note's name: one of the seven letters, raised or lowered by up to two
/// semitones.
struct NoteName {
    /// 0...6, C D E F G A B.
    int letter;
    /// Semitones from the letter's natural note: -2 is 𝄫, 2 is 𝄪.
    int accidental;

    NoteName(int letter, int accidental);

    bool operator==(const NoteName &) const = default;
    auto operator<=>(const NoteName &) const = default;

    PitchClass pitchClass() const;

    /// "C", "F♯", "B♭", "D𝄪".
    std::string name() const;

    /// The note `interval` semitones above this one, written `letters`
    /// letters further up: a scale's degree i is `letters` i, and a chord's
    /// tone i is 2i, so each is spelled as the letters fall.
    NoteName spelled(int interval, int letters) const;

    /// The twelve notes as a root is chosen from them: C, D♭, D, E♭, E, F,
    /// F♯, G, A♭, A, B♭, B.
    static const std::array<NoteName, 12> &roots();

    /// The note as a root it can be: a double sharp or flat is written as
    /// `roots` writes its pitch, and any other name is kept (F♭, E♯).
    NoteName asRoot() const;
};

} // namespace perfecto::theory

#endif
