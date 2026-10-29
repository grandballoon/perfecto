// Ported from Tests/MusicTheoryCoreTests/TertianStackTests.swift.

#include <doctest.h>

#include "perfecto/theory/chord_color.hpp"
#include "perfecto/theory/naming.hpp"
#include "perfecto/theory/tertian.hpp"
#include "perfecto/theory/voicing.hpp"

#include <algorithm>
#include <map>
#include <optional>
#include <set>
#include <string>
#include <utility>
#include <vector>

using namespace perfecto::theory;

namespace {

using V = std::vector<int>;

const Key cMajor{PitchClass::C, ScaleType::major};
const V dorian = {0, 2, 3, 5, 7, 9, 10};
const V ionian = {0, 2, 4, 5, 7, 9, 11};
const V mixolydian = {0, 2, 4, 5, 7, 9, 10};
const V lydian = {0, 2, 4, 6, 7, 9, 11};

std::string name(HeptatonicMode mode, StackHeight height) { return tertianChordName(mode, height); }

std::pair<V, std::string> grid(const Key &key, Degree degree, StackHeight height,
                               std::optional<HeptatonicMode> mode = std::nullopt) {
    const ChordSpec spec{degree, ChordColor::grid(height, mode)};
    const V notes = computeVoicing(key, spec, Inversion::root(), 4, false, std::nullopt).notes();
    return {notes, chordLabel(key, spec)};
}

bool contains(const V &v, int x) { return std::find(v.begin(), v.end(), x) != v.end(); }

} // namespace

TEST_SUITE("TertianStack") {

// MARK: – Diatonic modes

TEST_CASE("degree modes of C major") {
    CHECK(diatonicMode(cMajor, Degree::I) == std::optional<V>(ionian));
    CHECK(diatonicMode(cMajor, Degree::ii) == std::optional<V>(dorian));
    CHECK(diatonicMode(cMajor, Degree::V) == std::optional<V>(mixolydian));
    CHECK(diatonicMode(cMajor, Degree::IV) == std::optional<V>(lydian));
}

TEST_CASE("no mode for scales without seven notes") {
    CHECK(!diatonicMode(Key{PitchClass::C, ScaleType::blues}, Degree::I).has_value());
}

// MARK: – Heights

TEST_CASE("each height adds a third") {
    CHECK(stackThirds(mixolydian, StackHeight::triad)      == V{0, 4, 7});
    CHECK(stackThirds(mixolydian, StackHeight::seventh)    == V{0, 4, 7, 10});
    CHECK(stackThirds(mixolydian, StackHeight::ninth)      == V{0, 4, 7, 10, 14});
    CHECK(stackThirds(dorian,     StackHeight::eleventh)   == V{0, 3, 7, 10, 14, 17});
    CHECK(stackThirds(dorian,     StackHeight::thirteenth) == V{0, 3, 7, 10, 14, 17, 21});
}

TEST_CASE("diatonic sevenths of C major") {
    std::vector<V> sevenths;
    for (Degree degree : allDegrees) {
        sevenths.push_back(stackThirds(*diatonicMode(cMajor, degree), StackHeight::seventh));
    }
    CHECK(sevenths == std::vector<V>{
        {0, 4, 7, 11},   // I    maj7
        {0, 3, 7, 10},   // ii   min7
        {0, 3, 7, 10},   // iii  min7
        {0, 4, 7, 11},   // IV   maj7
        {0, 4, 7, 10},   // V    7
        {0, 3, 7, 10},   // vi   min7
        {0, 3, 6, 10},   // vii  min7♭5
    });
}

// MARK: – The eleventh over a major third

TEST_CASE("dominant eleven drops the third") {
    CHECK(stackThirds(mixolydian, StackHeight::eleventh) == V{0, 7, 10, 14, 17});
}

TEST_CASE("thirteenths drop the eleven over a major third") {
    CHECK(stackThirds(mixolydian, StackHeight::thirteenth) == V{0, 4, 7, 10, 14, 21});   // 13
    CHECK(stackThirds(ionian,     StackHeight::thirteenth) == V{0, 4, 7, 11, 14, 21});   // maj13
}

TEST_CASE("raised eleven is kept") {
    CHECK(stackThirds(lydian, StackHeight::eleventh) == V{0, 4, 7, 11, 14, 18});         // maj9♯11
}

// MARK: – Chords the joystick table gets wrong or can't reach

TEST_CASE("harmonic minor third is augmented") {
    // JoystickMap plays E♭–G–B♭ here; B♭ is not in C harmonic minor.
    const auto mode = *diatonicMode(Key{PitchClass::C, ScaleType::harmonicMinor}, Degree::iii);
    CHECK(stackThirds(mode, StackHeight::triad) == V{0, 4, 8});
}

TEST_CASE("harmonic minor seventh degree is fully diminished") {
    const auto mode = *diatonicMode(Key{PitchClass::C, ScaleType::harmonicMinor}, Degree::viiDim);
    CHECK(stackThirds(mode, StackHeight::seventh) == V{0, 3, 6, 9});
}

// MARK: – Structural rules, every heptatonic scale, degree and height

TEST_CASE("stacks ascend and stay in their mode") {
    for (ScaleType scale : allScaleTypes) {
        if (!isHeptatonic(scale)) continue;
        for (Degree degree : allDegrees) {
            const auto mode = *diatonicMode(Key{PitchClass::C, scale}, degree);
            for (StackHeight height : allStackHeights) {
                const V chord = stackThirds(mode, height);
                const std::string label = displayName(scale) + " " + std::to_string(index(degree)) + " " + displayName(height);
                CHECK_MESSAGE(chord.front() == 0, label);
                CHECK_MESSAGE(std::adjacent_find(chord.begin(), chord.end(), [](int a, int b) { return !(a < b); }) == chord.end(), label);
                CHECK_MESSAGE(std::all_of(chord.begin(), chord.end(), [&](int n) { return contains(mode, n % 12); }), label);
                CHECK_MESSAGE(raw(height) - static_cast<int>(chord.size()) <= 1, label, " dropped more than one tone");
            }
        }
    }
}

TEST_CASE("every column differs from its neighbour") {
    for (ScaleType scale : allScaleTypes) {
        if (!isHeptatonic(scale)) continue;
        for (Degree degree : allDegrees) {
            const auto mode = *diatonicMode(Key{PitchClass::C, scale}, degree);
            std::vector<V> column;
            for (StackHeight height : allStackHeights) column.push_back(stackThirds(mode, height));
            CHECK_MESSAGE(std::adjacent_find(column.begin(), column.end()) == column.end(),
                          displayName(scale), " ", index(degree));
        }
    }
}

// MARK: – Names

TEST_CASE("triad and seventh names") {
    CHECK(name(HeptatonicMode::ionian, StackHeight::triad) == "maj");
    CHECK(name(HeptatonicMode::dorian, StackHeight::triad) == "min");
    CHECK(name(HeptatonicMode::locrian, StackHeight::triad) == "dim");
    CHECK(name(HeptatonicMode::lydianAugmented, StackHeight::triad) == "aug");
    CHECK(name(HeptatonicMode::ionian, StackHeight::seventh) == "maj7");
    CHECK(name(HeptatonicMode::mixolydian, StackHeight::seventh) == "7");
    CHECK(name(HeptatonicMode::dorian, StackHeight::seventh) == "min7");
    CHECK(name(HeptatonicMode::melodicMinor, StackHeight::seventh) == "min(maj7)");
    CHECK(name(HeptatonicMode::locrian, StackHeight::seventh) == "min7♭5");
    CHECK(name(HeptatonicMode::ultralocrian, StackHeight::seventh) == "dim7");
    CHECK(name(HeptatonicMode::ionianSharp5, StackHeight::seventh) == "maj7♯5");
}

TEST_CASE("extended names") {
    CHECK(name(HeptatonicMode::ionian, StackHeight::ninth) == "maj9");
    CHECK(name(HeptatonicMode::dorian, StackHeight::thirteenth) == "min13");
    CHECK(name(HeptatonicMode::mixolydian, StackHeight::eleventh) == "11");
    CHECK(name(HeptatonicMode::mixolydian, StackHeight::thirteenth) == "13");
    CHECK(name(HeptatonicMode::lydian, StackHeight::eleventh) == "maj9♯11");
    CHECK(name(HeptatonicMode::lydianDominant, StackHeight::thirteenth) == "13♯11");
    CHECK(name(HeptatonicMode::phrygianDominant, StackHeight::thirteenth) == "7♭9♭13");
    CHECK(name(HeptatonicMode::mixolydianFlat6, StackHeight::thirteenth) == "9♭13");
    CHECK(name(HeptatonicMode::aeolian, StackHeight::thirteenth) == "min11♭13");
    CHECK(name(HeptatonicMode::locrianNatural2, StackHeight::ninth) == "min9♭5");
    CHECK(name(HeptatonicMode::harmonicMinor, StackHeight::ninth) == "min(maj9)");
}

/// Names are read from the stacked tones alone: two cells share a name
/// exactly when they sound the same chord.
TEST_CASE("same name exactly when same chord") {
    for (StackHeight height : allStackHeights) {
        std::map<std::string, V> chordForName;
        for (HeptatonicMode mode : allHeptatonicModes) {
            const V chord = stackThirds(intervals(mode), height);
            const std::string label = name(mode, height);
            if (auto other = chordForName.find(label); other != chordForName.end()) {
                CHECK_MESSAGE(other->second == chord, label, " names two chords at ", displayName(height));
            }
            chordForName[label] = chord;
        }
        std::set<V> chords;
        for (HeptatonicMode mode : allHeptatonicModes) chords.insert(stackThirds(intervals(mode), height));
        CHECK_MESSAGE(chords.size() == chordForName.size(), displayName(height), ": one chord has two names");
    }
}

// MARK: – The grid color

TEST_CASE("diatonic grid chord follows the key") {
    CHECK(grid(cMajor, Degree::ii, StackHeight::seventh) == std::pair<V, std::string>(V{62, 65, 69, 72}, "D min7"));
    CHECK(grid(Key{PitchClass::C, ScaleType::naturalMinor}, Degree::ii, StackHeight::seventh) ==
          std::pair<V, std::string>(V{62, 65, 68, 72}, "D min7♭5"));
}

TEST_CASE("named mode is the same quality in every key") {
    const auto inMajor = grid(cMajor, Degree::V, StackHeight::ninth, HeptatonicMode::altered);
    const auto inMinor = grid(Key{PitchClass::C, ScaleType::harmonicMinor}, Degree::V, StackHeight::ninth,
                              HeptatonicMode::altered);
    CHECK(inMajor == std::pair<V, std::string>(V{67, 70, 73, 77, 80}, "G min7♭5♭9"));
    CHECK(inMinor == inMajor);
}

TEST_CASE("base grid color is the diatonic triad") {
    CHECK(ChordColor::grid(StackHeight::triad, std::nullopt).isBase());
    CHECK(!ChordColor::grid(StackHeight::triad, HeptatonicMode::ionian).isBase());
    CHECK(!ChordColor::grid(StackHeight::seventh, std::nullopt).isBase());
}

}
