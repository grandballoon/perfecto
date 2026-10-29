// Ported from Tests/MusicTheoryCoreTests/ColorStepsTests.swift.

#include <doctest.h>

#include "perfecto/theory/color_ring.hpp"
#include "perfecto/theory/color_steps.hpp"
#include "perfecto/theory/tone_marks.hpp"

#include <set>
#include <string>
#include <utility>
#include <vector>

using namespace perfecto::theory;

namespace {

const Key cMajor{PitchClass::C, ScaleType::major};

using Ints = std::vector<int>;

/// The Swift case name of a mode, as Swift prints it in an expectation.
std::string swiftName(HeptatonicMode mode) {
    switch (mode) {
    case HeptatonicMode::ionian: return "ionian";
    case HeptatonicMode::dorian: return "dorian";
    case HeptatonicMode::phrygian: return "phrygian";
    case HeptatonicMode::lydian: return "lydian";
    case HeptatonicMode::mixolydian: return "mixolydian";
    case HeptatonicMode::aeolian: return "aeolian";
    case HeptatonicMode::locrian: return "locrian";
    default: return "other";
    }
}

/// The Swift case name of a stack height.
std::string swiftName(StackHeight height) {
    switch (height) {
    case StackHeight::triad: return "triad";
    case StackHeight::seventh: return "seventh";
    case StackHeight::ninth: return "ninth";
    case StackHeight::eleventh: return "eleventh";
    case StackHeight::thirteenth: return "thirteenth";
    }
    return "";
}

} // namespace

TEST_SUITE("ColorSteps") {

TEST_CASE("each kind of step") {
    CHECK(colorSteps(Ints{0, 4, 7}, Ints{0, 4, 7}) == 0);
    CHECK(colorSteps(Ints{0, 4, 7}, Ints{0, 3, 7}) == 1);          // a note moved a semitone
    CHECK(colorSteps(Ints{0, 4, 7}, Ints{0, 4, 7, 10}) == 1);      // one added
    CHECK(colorSteps(Ints{0, 4, 7, 10}, Ints{0, 4, 7}) == 1);      // one taken away
    CHECK(colorSteps(Ints{0, 4, 7, 11}, Ints{0, 4, 7, 10}) == 1);  // maj7 to 7
    CHECK(colorSteps(Ints{0, 4, 7}, Ints{0, 3, 7, 10}) == 2);      // maj to min7
    CHECK(colorSteps(Ints{0, 4, 7, 14}, Ints{0, 4, 7, 2}) == 0);   // a 9th is its 2nd
}

TEST_CASE("a move further than a tone") {
    // Moving a note more than a tone costs as much as taking it away
    // and adding the other.
    CHECK(colorSteps(Ints{0, 4, 7}, Ints{0, 4, 11}) == 2);
}

/// Touching cells on the ring: the same height in the next sector, or
/// the next height in the same sector. The four that are more than a
/// step apart are where the stack leaves out a clashing tone.
TEST_CASE("touching cells are one step apart") {
    int oneStep = 0, pairs = 0;
    std::set<std::string> further;
    const auto &modes = ColorRing::modes();
    const auto &heights = allStackHeights;
    const int modeCount = static_cast<int>(modes.size());
    const int heightCount = static_cast<int>(heights.size());
    auto color = [&](int s, int h) { return ChordColor::grid(heights[h], modes[s]); };
    auto check = [&](std::pair<int, int> a, std::pair<int, int> b) {
        pairs += 1;
        if (colorSteps(color(a.first, a.second), color(b.first, b.second), cMajor, Degree::I) <= 1) {
            oneStep += 1;
        } else {
            further.insert(swiftName(modes[a.first]) + " " + swiftName(heights[a.second]) + " – " +
                           swiftName(modes[b.first]) + " " + swiftName(heights[b.second]));
        }
    };
    for (int s = 0; s < modeCount; ++s) {
        for (int h = 0; h < heightCount; ++h) {
            if (s + 1 < modeCount) check({s, h}, {s + 1, h});
            if (h + 1 < heightCount) check({s, h}, {s, h + 1});
        }
    }
    CHECK(pairs == 58);
    CHECK(oneStep == 54);
    CHECK(further == std::set<std::string>{
                         "dorian thirteenth – mixolydian thirteenth",
                         "mixolydian eleventh – mixolydian thirteenth",
                         "ionian eleventh – ionian thirteenth",
                         "ionian eleventh – lydian eleventh",
                     });
}

TEST_CASE("every mark is one step") {
    for (HeptatonicMode mode : ColorRing::modes()) {
        for (StackHeight height : allStackHeights) {
            const Ints plain = markedStack(intervals(mode), height, ToneMarks{});
            for (ChordTone tone : allChordTones) {
                for (int offset : {1, -1}) {
                    ToneMarks marks;
                    marks.toggleMove(tone, offset);
                    const Ints moved = markedStack(intervals(mode), height, marks);
                    CHECK((moved == plain || colorSteps(plain, moved) == 1));
                }
                ToneMarks skip;
                skip.toggleSkip(tone);
                const Ints skipped = markedStack(intervals(mode), height, skip);
                CHECK((skipped == plain || colorSteps(plain, skipped) == 1));
            }
        }
    }
}

} // TEST_SUITE
