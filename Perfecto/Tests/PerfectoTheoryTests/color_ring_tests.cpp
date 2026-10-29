// Ported from Tests/MusicTheoryCoreTests/ColorRingTests.swift.

#include <doctest.h>

#include "perfecto/theory/color_ring.hpp"
#include "perfecto/theory/grid.hpp"

#include <algorithm>
#include <array>
#include <optional>
#include <vector>

using namespace perfecto::theory;

namespace {

const Key cMajor{PitchClass::C, ScaleType::major};
const Key aMinor{PitchClass::A, ScaleType::naturalMinor};

} // namespace

TEST_SUITE("ColorRing") {

TEST_CASE("the sectors go from darkest to brightest") {
    CHECK(ColorRing::modes() ==
          std::vector<HeptatonicMode>{HeptatonicMode::locrian, HeptatonicMode::phrygian, HeptatonicMode::aeolian,
                                      HeptatonicMode::dorian, HeptatonicMode::mixolydian, HeptatonicMode::ionian,
                                      HeptatonicMode::lydian});
    CHECK(ColorRing::modes()[ColorRing::topSector] == HeptatonicMode::dorian);
}

TEST_CASE("each sector is one note from the next") {
    const auto &modes = ColorRing::modes();
    for (std::size_t i = 0; i + 1 < modes.size(); ++i) {
        const auto &a = intervals(modes[i]);
        const auto &b = intervals(modes[i + 1]);
        int differing = 0;
        for (std::size_t k = 0; k < std::min(a.size(), b.size()); ++k)
            if (a[k] != b[k]) ++differing;
        CHECK(differing == 1);
    }
}

TEST_CASE("a fixed ring is never turned") {
    for (Degree degree : allDegrees) {
        CHECK(ColorRing::turn(ColorRingArrangement::fixed, cMajor, degree) == 0);
    }
}

TEST_CASE("a home ring has the own mode at the top") {
    const auto &modes = ColorRing::modes();
    for (const Key &key : {cMajor, aMinor}) {
        for (Degree degree : allDegrees) {
            const HeptatonicMode own = ChordGrid::ownMode(key, degree);
            const auto found = std::find(modes.begin(), modes.end(), own);
            REQUIRE(found != modes.end());
            const int sector = static_cast<int>(found - modes.begin());
            CHECK(sector + ColorRing::turn(ColorRingArrangement::home, key, degree) == ColorRing::topSector);
        }
    }
}

TEST_CASE("a home ring is not turned for a mode off the ring") {
    const Key harmonic{PitchClass::A, ScaleType::harmonicMinor};
    CHECK(ColorRing::turn(ColorRingArrangement::home, harmonic, Degree::I) == 0);
}

TEST_CASE("positions and sectors invert each other") {
    for (ColorRingArrangement arrangement : {ColorRingArrangement::fixed, ColorRingArrangement::home}) {
        for (const Key &key : {cMajor, aMinor}) {
            for (Degree degree : allDegrees) {
                for (int sector = 0; sector < static_cast<int>(ColorRing::modes().size()); ++sector) {
                    const ColorRingPosition position =
                        ColorRing::position(StackHeight::ninth, sector, arrangement, key, degree);
                    CHECK(ColorRing::sector(position, key, degree) == sector);
                }
            }
        }
    }
}

/// The own mode's cell on a home ring follows the degree; on a fixed
/// ring a sector stays its mode.
TEST_CASE("the home ring's own cell follows the degree") {
    const auto home = ColorRing::position(StackHeight::seventh, 5, ColorRingArrangement::home, cMajor, Degree::I);
    CHECK(home.mode == std::nullopt);
    CHECK(ColorRing::mode(home, cMajor, Degree::ii) == HeptatonicMode::dorian);
    const auto fixed = ColorRing::position(StackHeight::seventh, 5, ColorRingArrangement::fixed, cMajor, Degree::I);
    CHECK(ColorRing::mode(fixed, cMajor, Degree::ii) == HeptatonicMode::ionian);
}

TEST_CASE("the own mode's cell plays the grid's own color") {
    const ColorRingPosition fixed{StackHeight::seventh, HeptatonicMode::ionian};
    CHECK(ColorRing::color(fixed, ToneMarks{}, cMajor, Degree::I) == ChordColor::grid(StackHeight::seventh, std::nullopt));
    CHECK(ColorRing::color(fixed, ToneMarks{}, cMajor, Degree::V) ==
          ChordColor::grid(StackHeight::seventh, HeptatonicMode::ionian));
}

} // TEST_SUITE
