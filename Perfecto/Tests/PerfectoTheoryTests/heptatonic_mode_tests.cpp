// Ported from Tests/MusicTheoryCoreTests/HeptatonicModeTests.swift.

#include <doctest.h>

#include "perfecto/theory/modes.hpp"

#include <algorithm>
#include <numeric>
#include <set>
#include <string>
#include <vector>

using namespace perfecto::theory;
using Ints = std::vector<int>;
using Modes = std::vector<HeptatonicMode>;

namespace {

// Swift prints an enum as its case name.
std::string swiftName(ScaleType s) {
    switch (s) {
    case ScaleType::major: return "major";
    case ScaleType::naturalMinor: return "naturalMinor";
    case ScaleType::harmonicMinor: return "harmonicMinor";
    case ScaleType::melodicMinor: return "melodicMinor";
    case ScaleType::majorPentatonic: return "majorPentatonic";
    case ScaleType::minorPentatonic: return "minorPentatonic";
    case ScaleType::blues: return "blues";
    case ScaleType::dorian: return "dorian";
    case ScaleType::mixolydian: return "mixolydian";
    case ScaleType::lydian: return "lydian";
    }
    return "?";
}

std::string swiftName(Degree d) {
    switch (d) {
    case Degree::I: return "I";
    case Degree::ii: return "ii";
    case Degree::iii: return "iii";
    case Degree::IV: return "IV";
    case Degree::V: return "V";
    case Degree::vi: return "vi";
    case Degree::viiDim: return "viiDim";
    }
    return "?";
}

std::string swiftName(HeptatonicMode m) {
    switch (m) {
    case HeptatonicMode::ionian: return "ionian";
    case HeptatonicMode::dorian: return "dorian";
    case HeptatonicMode::phrygian: return "phrygian";
    case HeptatonicMode::lydian: return "lydian";
    case HeptatonicMode::mixolydian: return "mixolydian";
    case HeptatonicMode::aeolian: return "aeolian";
    case HeptatonicMode::locrian: return "locrian";
    case HeptatonicMode::melodicMinor: return "melodicMinor";
    case HeptatonicMode::dorianFlat2: return "dorianFlat2";
    case HeptatonicMode::lydianAugmented: return "lydianAugmented";
    case HeptatonicMode::lydianDominant: return "lydianDominant";
    case HeptatonicMode::mixolydianFlat6: return "mixolydianFlat6";
    case HeptatonicMode::locrianNatural2: return "locrianNatural2";
    case HeptatonicMode::altered: return "altered";
    case HeptatonicMode::harmonicMinor: return "harmonicMinor";
    case HeptatonicMode::locrianNatural6: return "locrianNatural6";
    case HeptatonicMode::ionianSharp5: return "ionianSharp5";
    case HeptatonicMode::dorianSharp4: return "dorianSharp4";
    case HeptatonicMode::phrygianDominant: return "phrygianDominant";
    case HeptatonicMode::lydianSharp2: return "lydianSharp2";
    case HeptatonicMode::ultralocrian: return "ultralocrian";
    }
    return "?";
}

} // namespace

TEST_SUITE("HeptatonicMode") {

TEST_CASE("intervals read the parent scale from the mode's step") {
    CHECK(intervals(HeptatonicMode::lydian) == Ints{0, 2, 4, 6, 7, 9, 11});
    CHECK(intervals(HeptatonicMode::lydianDominant) == Ints{0, 2, 4, 6, 7, 9, 10});
    CHECK(intervals(HeptatonicMode::altered) == Ints{0, 1, 3, 4, 6, 8, 10});
    CHECK(intervals(HeptatonicMode::phrygianDominant) == Ints{0, 1, 4, 5, 7, 8, 10});
    CHECK(intervals(HeptatonicMode::ultralocrian) == Ints{0, 1, 3, 4, 6, 8, 9});
}

TEST_CASE("every mode is distinct") {
    std::set<Ints> distinct;
    for (HeptatonicMode m : allHeptatonicModes) distinct.insert(intervals(m));
    CHECK(distinct.size() == 21);
}

TEST_CASE("every degree of every offered scale has its mode") {
    for (ScaleType scale : allScaleTypes) {
        if (!isHeptatonic(scale)) continue;
        for (Degree degree : allDegrees) {
            CHECK_MESSAGE(ownModeOf(Key{PitchClass::D, scale}, degree) != std::nullopt, swiftName(scale), " ",
                          swiftName(degree));
        }
    }
    CHECK(ownModeOf(Key{PitchClass::C, ScaleType::major}, Degree::V) == HeptatonicMode::mixolydian);
    CHECK(ownModeOf(Key{PitchClass::C, ScaleType::harmonicMinor}, Degree::V) == HeptatonicMode::phrygianDominant);
    CHECK(ownModeOf(Key{PitchClass::C, ScaleType::blues}, Degree::I) == std::nullopt);
}

// MARK: – Brightness

TEST_CASE("brightness order") {
    using M = HeptatonicMode;
    CHECK(byBrightness() == Modes{
                                M::lydianSharp2, M::lydianAugmented, M::lydian, M::ionianSharp5, M::ionian,
                                M::lydianDominant, M::mixolydian, M::dorianSharp4, M::melodicMinor, M::dorian,
                                M::mixolydianFlat6, M::harmonicMinor, M::aeolian, M::phrygianDominant, M::dorianFlat2,
                                M::phrygian, M::locrianNatural2, M::locrianNatural6, M::locrian, M::altered,
                                M::ultralocrian,
                            });
}

TEST_CASE("major modes keep their familiar order") {
    using M = HeptatonicMode;
    const Modes major = {M::lydian, M::ionian, M::mixolydian, M::dorian, M::aeolian, M::phrygian, M::locrian};
    Modes filtered;
    for (HeptatonicMode m : byBrightness())
        if (std::find(major.begin(), major.end(), m) != major.end()) filtered.push_back(m);
    CHECK(filtered == major);
}

TEST_CASE("neighbouring rows differ by at most two notes") {
    const Modes &rows = byBrightness();
    for (std::size_t i = 0; i + 1 < rows.size(); ++i) {
        const HeptatonicMode upper = rows[i], lower = rows[i + 1];
        const Ints &a = intervals(upper), &b = intervals(lower);
        int changed = 0;
        for (std::size_t k = 0; k < a.size() && k < b.size(); ++k)
            if (a[k] != b[k]) ++changed;
        CHECK_MESSAGE((changed >= 1 && changed <= 2), swiftName(upper), " → ", swiftName(lower));
    }
}

TEST_CASE("brightness never increases down the rows") {
    Ints sums;
    for (HeptatonicMode m : byBrightness()) {
        const Ints &iv = intervals(m);
        sums.push_back(std::accumulate(iv.begin(), iv.end(), 0));
    }
    Ints sorted = sums;
    std::stable_sort(sorted.begin(), sorted.end(), std::greater<int>());
    CHECK(sums == sorted);
}

TEST_CASE("rows centre on the mode and stay in range") {
    using M = HeptatonicMode;
    const Modes &all = byBrightness();
    CHECK(rowsAround(M::ionian, 7) ==
          Modes{M::lydianAugmented, M::lydian, M::ionianSharp5, M::ionian, M::lydianDominant, M::mixolydian,
                M::dorianSharp4});
    CHECK(rowsAround(M::lydianSharp2, 7) == Modes(all.begin(), all.begin() + 7));
    CHECK(rowsAround(M::altered, 7) == Modes(all.end() - 7, all.end()));
    for (HeptatonicMode mode : allHeptatonicModes) {
        const Modes rows = rowsAround(mode, 7);
        CHECK_MESSAGE((rows.size() == 7 && std::find(rows.begin(), rows.end(), mode) != rows.end()), swiftName(mode));
    }
}

} // TEST_SUITE
