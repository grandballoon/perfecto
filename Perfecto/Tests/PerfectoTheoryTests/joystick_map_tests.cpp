// Ported from Tests/MusicTheoryCoreTests/JoystickMapTests.swift.

#include <doctest.h>

#include "perfecto/theory/voicing.hpp"

#include <vector>

using namespace perfecto::theory;
using Ints = std::vector<int>;

namespace {

using JM = JoystickMode;
using JD = JoystickDirection;

Ints notes(JoystickMode mode, JoystickDirection dir, Degree degree = Degree::I,
           Key key = Key{PitchClass::C, ScaleType::major}) {
    return computeVoicing(key, ChordSpec{degree, ChordColor::joystick(mode, dir)}, Inversion::root(), 4, false,
                          std::nullopt)
        .notes();
}

} // namespace

TEST_SUITE("JoystickMap") {

// MARK: – Default mode

TEST_CASE("default center") {
    CHECK(notes(JM::default_, JD::center) == Ints{60, 64, 67}); // C major
}

TEST_CASE("default up flips major to minor") {
    CHECK(notes(JM::default_, JD::up) == Ints{60, 63, 67}); // Cm
}

TEST_CASE("default up flips minor to major") {
    // vi of C major = Am; up should flip to A major
    CHECK(notes(JM::default_, JD::up, Degree::vi) == Ints{69, 73, 76}); // A-C#-E
}

TEST_CASE("default up right dom7") {
    CHECK(notes(JM::default_, JD::upRight) == Ints{60, 64, 67, 70}); // C7
}

TEST_CASE("default right maj7") {
    // Spec example §4.4: C-E-G-B = Cmaj7
    CHECK(notes(JM::default_, JD::right) == Ints{60, 64, 67, 71});
}

TEST_CASE("default right min7 on minor") {
    // vi = Am; right should give Am7 = A-C-E-G
    CHECK(notes(JM::default_, JD::right, Degree::vi) == Ints{69, 72, 76, 79});
}

TEST_CASE("default down right add9") {
    // Cadd9 = C-E-G-D(+oct)
    CHECK(notes(JM::default_, JD::downRight) == Ints{60, 64, 67, 74});
}

TEST_CASE("default down sus4") {
    // Csus4 = C-F-G
    CHECK(notes(JM::default_, JD::down) == Ints{60, 65, 67});
}

TEST_CASE("default down left sixth on major") {
    // C6 = C-E-G-A
    CHECK(notes(JM::default_, JD::downLeft) == Ints{60, 64, 67, 69});
}

TEST_CASE("default down left sus2 on minor") {
    // ii = Dm; downLeft should give Dsus2 = D-E-A
    CHECK(notes(JM::default_, JD::downLeft, Degree::ii) == Ints{62, 64, 69});
}

TEST_CASE("default left makes minor from major") {
    CHECK(notes(JM::default_, JD::left) == Ints{60, 63, 67}); // Cm
}

TEST_CASE("default left makes dim from minor") {
    // ii = Dm; left should give Ddim = D-F-Ab
    CHECK(notes(JM::default_, JD::left, Degree::ii) == Ints{62, 65, 68});
}

TEST_CASE("default up left aug") {
    // Caug = C-E-G#
    CHECK(notes(JM::default_, JD::upLeft) == Ints{60, 64, 68});
}

TEST_CASE("default center on diminished") {
    // vii° of C major = Bdim = B-D-F
    CHECK(notes(JM::default_, JD::center, Degree::viiDim) == Ints{71, 74, 77});
}

// MARK: – Extended mode

TEST_CASE("extended up right dom9") {
    // C9 = C-E-G-Bb-D
    CHECK(notes(JM::extended, JD::upRight) == Ints{60, 64, 67, 70, 74});
}

TEST_CASE("extended right add11") {
    // Cadd11 = C-E-G-F(+oct)
    CHECK(notes(JM::extended, JD::right) == Ints{60, 64, 67, 77});
}

TEST_CASE("extended down hendrix") {
    // C7#9 = C-E-G-Bb-D#
    CHECK(notes(JM::extended, JD::down) == Ints{60, 64, 67, 70, 75});
}

TEST_CASE("extended up left half dim7") {
    // Cø7 = C-Eb-Gb-Bb
    CHECK(notes(JM::extended, JD::upLeft) == Ints{60, 63, 66, 70});
}

TEST_CASE("extended down right min11 forces minor") {
    // Even on degree I (major), min11 forces minor quality
    CHECK(notes(JM::extended, JD::downRight) == Ints{60, 63, 67, 70, 77});
}

TEST_CASE("extended left sus4 plus 7") {
    // Csus4+7 = C-F-G-Bb
    CHECK(notes(JM::extended, JD::left) == Ints{60, 65, 67, 70});
}

// MARK: – Chromatic mode

TEST_CASE("chromatic up minMaj7") {
    // CminMaj7 = C-Eb-G-B; forces minor regardless of major base chord
    CHECK(notes(JM::chromatic, JD::up) == Ints{60, 63, 67, 71});
}

TEST_CASE("chromatic right six nine") {
    // C6/9 = C-E-G-A-D
    CHECK(notes(JM::chromatic, JD::right) == Ints{60, 64, 67, 69, 74});
}

TEST_CASE("chromatic up left maj7 sharp 11") {
    // Cmaj7#11 = C-E-G-B-F#(+oct)
    CHECK(notes(JM::chromatic, JD::upLeft) == Ints{60, 64, 67, 71, 78});
}

TEST_CASE("chromatic down left dom7b9") {
    // C7b9 = C-E-G-Bb-Db
    CHECK(notes(JM::chromatic, JD::downLeft) == Ints{60, 64, 67, 70, 73});
}

TEST_CASE("chromatic left half dim7") {
    // Cø7 = C-Eb-Gb-Bb
    CHECK(notes(JM::chromatic, JD::left) == Ints{60, 63, 66, 70});
}

// MARK: – A color's place on the joystick

TEST_CASE("a joystick color has its direction in its own mode only") {
    const ChordColor color = ChordColor::joystick(JM::extended, JD::upRight);
    CHECK(color.direction(JM::extended) == JD::upRight);
    CHECK(color.direction(JM::default_) == std::nullopt);
}

TEST_CASE("the plain chord and a grid color have no direction") {
    CHECK(ChordColor::base().direction(JM::default_) == std::nullopt);
    CHECK(ChordColor::joystick(JM::chromatic, JD::center).direction(JM::chromatic) == std::nullopt);
    CHECK(ChordColor::grid(StackHeight::seventh, std::nullopt).direction(JM::default_) == std::nullopt);
}

} // TEST_SUITE
