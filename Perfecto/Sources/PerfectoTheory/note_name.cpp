#include "perfecto/theory/note_name.hpp"

#include "perfecto/theory/require.hpp"

#include <cstdlib>

namespace perfecto::theory {

namespace {

/// The pitch classes of the natural notes, C to B.
constexpr int naturals[] = {0, 2, 4, 5, 7, 9, 11};
constexpr const char *letters[] = {"C", "D", "E", "F", "G", "A", "B"};

} // namespace

NoteName::NoteName(int letter, int accidental) : letter(letter), accidental(accidental) {
    PERFECTO_REQUIRE(letter >= 0 && letter < 7, "a letter is 0...6");
}

PitchClass NoteName::pitchClass() const { return theory::pitchClass(naturals[letter] + accidental); }

std::string NoteName::name() const {
    std::string mark;
    switch (accidental) {
    case -2: mark = "𝄫"; break;
    case -1: mark = "♭"; break;
    case 1: mark = "♯"; break;
    case 2: mark = "𝄪"; break;
    default: break;
    }
    return letters[letter] + mark;
}

NoteName NoteName::spelled(int interval, int letterSteps) const {
    const int to = (letter + letterSteps) % 7;
    const int target = (raw(pitchClass()) + interval) % 12;
    int mark = ((target - naturals[to]) % 12 + 12) % 12;
    if (mark > 6) mark -= 12;
    return NoteName(to, mark);
}

const std::array<NoteName, 12> &NoteName::roots() {
    static const std::array<NoteName, 12> all = {
        NoteName(0, 0), NoteName(1, -1), NoteName(1, 0), NoteName(2, -1), NoteName(2, 0),  NoteName(3, 0),
        NoteName(3, 1), NoteName(4, 0),  NoteName(5, -1), NoteName(5, 0), NoteName(6, -1), NoteName(6, 0),
    };
    return all;
}

NoteName NoteName::asRoot() const { return std::abs(accidental) >= 2 ? roots()[raw(pitchClass())] : *this; }

} // namespace perfecto::theory
