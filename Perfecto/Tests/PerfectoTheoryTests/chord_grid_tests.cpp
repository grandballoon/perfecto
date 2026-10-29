// Ported from Tests/MusicTheoryCoreTests/ChordGridTests.swift.

#include <doctest.h>

#include "perfecto/theory/grid.hpp"
#include "perfecto/theory/voicing.hpp"

#include <algorithm>
#include <optional>
#include <vector>

using namespace perfecto::theory;

namespace {

const Key cMajor{PitchClass::C, ScaleType::major};

} // namespace

TEST_SUITE("ChordGrid") {

TEST_CASE("rows are a window around the degree's own mode") {
    CHECK(ChordGrid::rows(cMajor, Degree::I) == rowsAround(HeptatonicMode::ionian, 7));
    const auto rows = ChordGrid::rows(cMajor, Degree::ii);
    CHECK(std::find(rows.begin(), rows.end(), HeptatonicMode::dorian) != rows.end());
}

TEST_CASE("own row is diatonic and other rows name their mode") {
    const auto rows = ChordGrid::rows(cMajor, Degree::V);
    const auto found = std::find(rows.begin(), rows.end(), HeptatonicMode::mixolydian);
    REQUIRE(found != rows.end());
    const int own = static_cast<int>(found - rows.begin());
    CHECK(ChordGrid::color(GridPosition{StackHeight::seventh, own}, cMajor, Degree::V) ==
          ChordColor::grid(StackHeight::seventh, std::nullopt));
    const int other = own == 0 ? 1 : own - 1;
    CHECK(ChordGrid::color(GridPosition{StackHeight::ninth, other}, cMajor, Degree::V) ==
          ChordColor::grid(StackHeight::ninth, rows[other]));
}

TEST_CASE("the same position resolves per degree") {
    // The middle row is each degree's own mode; the top row is three
    // modes brighter, which differs by degree.
    const GridPosition middle{StackHeight::seventh, 3};
    CHECK(ChordGrid::color(middle, cMajor, Degree::vi) == ChordColor::grid(StackHeight::seventh, std::nullopt));
    const GridPosition top{StackHeight::seventh, 0};
    CHECK(ChordGrid::color(top, cMajor, Degree::ii) == ChordColor::grid(StackHeight::seventh, HeptatonicMode::mixolydian));
    CHECK(ChordGrid::color(top, cMajor, Degree::vi) == ChordColor::grid(StackHeight::seventh, HeptatonicMode::dorian));
}

TEST_CASE("position is the inverse of color") {
    for (ScaleType scale : allScaleTypes) {
        if (!isHeptatonic(scale)) continue;
        const Key key{PitchClass::E, scale};
        for (Degree degree : allDegrees) {
            for (StackHeight height : allStackHeights) {
                for (int row = 0; row < ChordGrid::rowCount; ++row) {
                    const GridPosition position{height, row};
                    const ChordColor color = ChordGrid::color(position, key, degree);
                    CHECK_MESSAGE(ChordGrid::position(color, key, degree) == position,
                                  displayName(scale), " ", index(degree), " ", static_cast<int>(height), " row ", row);
                }
            }
        }
    }
}

TEST_CASE("colors off the grid have no position") {
    CHECK(ChordGrid::position(ChordColor::joystick(JoystickMode::default_, JoystickDirection::right), cMajor,
                              Degree::I) == std::nullopt);
    CHECK(ChordGrid::position(ChordColor::grid(StackHeight::triad, HeptatonicMode::ultralocrian), cMajor,
                              Degree::I) == std::nullopt);
}

TEST_CASE("the base grid color sounds the diatonic triad") {
    for (Degree degree : allDegrees) {
        const Voicing grid = computeVoicing(cMajor, ChordSpec{degree, ChordColor::grid(StackHeight::triad, std::nullopt)},
                                            Inversion::root(), 4, false, std::nullopt);
        const Voicing joystick = computeVoicing(cMajor, ChordSpec{degree, ChordColor::base()}, Inversion::root(), 4,
                                                false, std::nullopt);
        CHECK_MESSAGE(grid == joystick, index(degree));
    }
}

} // TEST_SUITE
