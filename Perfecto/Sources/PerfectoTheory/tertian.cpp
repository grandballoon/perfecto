#include "perfecto/theory/tertian.hpp"

#include "perfecto/theory/require.hpp"

namespace perfecto::theory {

namespace {

/// "♭" or "♯" for a one-semitone alteration.
std::string accidental(int semitones) {
    PERFECTO_REQUIRE(semitones == -1 || semitones == 1, "an alteration is one semitone");
    return semitones < 0 ? "♭" : "♯";
}

} // namespace

std::string displayName(StackHeight h) {
    switch (h) {
    case StackHeight::triad: return "Triad";
    case StackHeight::seventh: return "7th";
    case StackHeight::ninth: return "9th";
    case StackHeight::eleventh: return "11th";
    case StackHeight::thirteenth: return "13th";
    }
    return "";
}

std::optional<std::vector<int>> diatonicMode(const Key &key, Degree degree) {
    if (!isHeptatonic(key.scale)) return std::nullopt;
    const int root = offset(key.scale, degree);
    std::vector<int> steps;
    for (int i = 0; i < 7; ++i) steps.push_back(semitones(key.scale, index(degree) + i) - root);
    return steps;
}

std::vector<int> stackThirds(const std::vector<int> &mode, StackHeight height) {
    PERFECTO_REQUIRE(mode.size() == 7 && mode.front() == 0, "a mode is seven intervals from 0");
    std::vector<int> tones;
    for (int k = 0; k < raw(height); ++k) {
        const int step = 2 * k;
        tones.push_back(mode[step % 7] + (step / 7) * 12);
    }
    const bool majorThird = tones[1] == 4;
    const bool perfectEleventh = tones.size() > 5 && tones[5] == 17;
    if (majorThird && perfectEleventh) tones.erase(tones.begin() + (height == StackHeight::eleventh ? 1 : 5));
    return tones;
}

std::string tertianChordName(HeptatonicMode mode, StackHeight height) {
    const auto &m = intervals(mode);
    const int third = m[2], fifth = m[4], seventh = m[6];

    if (height == StackHeight::triad) {
        if (third == 4 && fifth == 7) return "maj";
        if (third == 3 && fifth == 7) return "min";
        if (third == 3 && fifth == 6) return "dim";
        if (third == 4 && fifth == 8) return "aug";
        return (third == 4 ? "maj" : "min") + accidental(fifth - 7) + "5";
    }

    // Extensions stacked at this height: the 9th, 11th and 13th sit an
    // octave above mode steps 1, 3 and 5; natural means 14, 17 and 21
    // semitones.
    const bool elevenDropped = height == StackHeight::thirteenth && third == 4 && m[3] == 5;
    struct Extension {
        int number, alteration;
    };
    const Extension all[] = {{9, m[1] + 12 - 14}, {11, m[3] + 12 - 17}, {13, m[5] + 12 - 21}};
    std::vector<Extension> extensions;
    for (int i = 0; i < raw(height) - 4; ++i)
        if (!(elevenDropped && all[i].number == 11)) extensions.push_back(all[i]);
    int number = 7;
    for (const auto &e : extensions)
        if (e.alteration == 0) number = e.number;
    std::string alterations;
    for (const auto &e : extensions)
        if (e.alteration != 0) alterations += accidental(e.alteration) + std::to_string(e.number);

    const std::string fifthMark = fifth == 7 ? "" : accidental(fifth - 7) + "5";
    const std::string n = std::to_string(number);
    if (third == 4 && seventh == 11) return "maj" + n + fifthMark + alterations;
    if (third == 4 && seventh == 10) return n + fifthMark + alterations;
    if (third == 3 && seventh == 10) return "min" + n + fifthMark + alterations;
    if (third == 3 && seventh == 11) return "min(maj" + n + ")" + fifthMark + alterations;
    if (third == 3 && seventh == 9 && fifth == 6) return "dim" + n + alterations;
    PERFECTO_REQUIRE(false, "a mode with no tertian seventh chord name");
    return "";
}

} // namespace perfecto::theory
