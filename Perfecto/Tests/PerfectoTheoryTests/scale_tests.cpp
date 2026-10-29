// Ported from Tests/MusicTheoryCoreTests/ScaleTests.swift.

#include <doctest.h>

#include "perfecto/theory/key.hpp"
#include "perfecto/theory/voicing.hpp"

#include <string>
#include <utility>
#include <vector>

using namespace perfecto::theory;
using Ints = std::vector<int>;

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

Ints voice(const Key &key, Degree degree) {
    return computeVoicing(key, ChordSpec{degree, ChordColor::joystick(JoystickMode::default_, JoystickDirection::center)},
                          Inversion::root(), 4, false, std::nullopt)
        .notes();
}

} // namespace

TEST_SUITE("Scale") {

// MARK: – Scale intervals

TEST_CASE("major intervals") { CHECK(intervals(ScaleType::major) == Ints{0, 2, 4, 5, 7, 9, 11}); }

TEST_CASE("natural minor intervals") { CHECK(intervals(ScaleType::naturalMinor) == Ints{0, 2, 3, 5, 7, 8, 10}); }

TEST_CASE("harmonic minor intervals") { CHECK(intervals(ScaleType::harmonicMinor) == Ints{0, 2, 3, 5, 7, 8, 11}); }

TEST_CASE("melodic minor intervals") { CHECK(intervals(ScaleType::melodicMinor) == Ints{0, 2, 3, 5, 7, 9, 11}); }

TEST_CASE("major pentatonic intervals") { CHECK(intervals(ScaleType::majorPentatonic) == Ints{0, 2, 4, 7, 9}); }

TEST_CASE("minor pentatonic intervals") { CHECK(intervals(ScaleType::minorPentatonic) == Ints{0, 3, 5, 7, 10}); }

TEST_CASE("blues intervals") { CHECK(intervals(ScaleType::blues) == Ints{0, 3, 5, 6, 7, 10}); }

TEST_CASE("heptatonic scales") {
    std::vector<ScaleType> heptatonic;
    for (ScaleType s : allScaleTypes)
        if (isHeptatonic(s)) heptatonic.push_back(s);
    CHECK(heptatonic == std::vector<ScaleType>{ScaleType::major, ScaleType::naturalMinor, ScaleType::harmonicMinor,
                                               ScaleType::melodicMinor, ScaleType::dorian, ScaleType::mixolydian,
                                               ScaleType::lydian});
}

TEST_CASE("steps continue into higher octaves") {
    Ints steps;
    for (int i = 0; i < 9; ++i) steps.push_back(semitones(ScaleType::major, i));
    CHECK(steps == Ints{0, 2, 4, 5, 7, 9, 11, 12, 14});
}

TEST_CASE("degree offset is the degree's step") {
    Ints offsets;
    for (Degree d : allDegrees) offsets.push_back(offset(ScaleType::naturalMinor, d));
    CHECK(offsets == Ints{0, 2, 3, 5, 7, 8, 10});
}

TEST_CASE("dorian intervals") { CHECK(intervals(ScaleType::dorian) == Ints{0, 2, 3, 5, 7, 9, 10}); }

TEST_CASE("mixolydian intervals") { CHECK(intervals(ScaleType::mixolydian) == Ints{0, 2, 4, 5, 7, 9, 10}); }

TEST_CASE("lydian intervals") { CHECK(intervals(ScaleType::lydian) == Ints{0, 2, 4, 6, 7, 9, 11}); }

// Every scale must start at 0, be strictly ascending, and end below 12
TEST_CASE("all scales are ascending and in range") {
    for (ScaleType scale : allScaleTypes) {
        const Ints &ivls = intervals(scale);
        CHECK_MESSAGE(!ivls.empty(), swiftName(scale), " has empty intervals");
        CHECK_MESSAGE((!ivls.empty() && ivls.front() == 0), swiftName(scale), " must start at 0");
        for (std::size_t i = 0; i + 1 < ivls.size(); ++i) {
            CHECK_MESSAGE(ivls[i] < ivls[i + 1], swiftName(scale), " intervals not strictly ascending at index ", i);
        }
        CHECK_MESSAGE((ivls.empty() ? 12 : ivls.back()) < 12, swiftName(scale), " last interval must be < 12");
    }
}

// MARK: – Base triads for all degrees of C major

// C major: I=C, ii=Dm, iii=Em, IV=F, V=G, vi=Am, vii°=Bdim
// MARK: – The notes of a key

TEST_CASE("a key has its scale's notes in every octave") {
    const Key key{PitchClass::D, ScaleType::major};
    Ints inKey;
    for (int note = 60; note <= 72; ++note)
        if (key.has(note)) inKey.push_back(note);
    CHECK(inKey == Ints{61, 62, 64, 66, 67, 69, 71});
    CHECK((key.has(2) && key.has(0) == false));
}

TEST_CASE("the pitch nearest is a note of the key and the lower of two as near") {
    const Key key{PitchClass::C, ScaleType::major};
    CHECK(key.noteNearest(60.4) == 60);
    CHECK(key.noteNearest(61.2) == 62);
    CHECK(key.noteNearest(61) == 60);   // as near C as D
    CHECK(key.noteNearest(64.6) == 65); // a semitone apart
    CHECK(key.noteNearest(59.9) == 60);
    // The widest gap a scale has.
    const Key pentatonic{PitchClass::A, ScaleType::minorPentatonic};
    CHECK(pentatonic.noteNearest(58.4) == 57);
    CHECK(pentatonic.noteNearest(58.6) == 60);
}

TEST_CASE("C major base triads") {
    const Key key{PitchClass::C, ScaleType::major};
    const std::vector<std::pair<Degree, Ints>> cases = {
        {Degree::I, {60, 64, 67}},      // C-E-G
        {Degree::ii, {62, 65, 69}},     // D-F-A
        {Degree::iii, {64, 67, 71}},    // E-G-B
        {Degree::IV, {65, 69, 72}},     // F-A-C
        {Degree::V, {67, 71, 74}},      // G-B-D
        {Degree::vi, {69, 72, 76}},     // A-C-E
        {Degree::viiDim, {71, 74, 77}}, // B-D-F
    };
    for (const auto &[degree, expected] : cases) {
        CHECK_MESSAGE(voice(key, degree) == expected, "C major ", swiftName(degree), " base triad mismatch");
    }
}

// A natural minor: I=Am, ii°=Bdim, III=C, iv=Dm, v=Em, VI=F, VII=G
TEST_CASE("A natural minor base triads") {
    const Key key{PitchClass::A, ScaleType::naturalMinor};
    const std::vector<std::pair<Degree, Ints>> cases = {
        {Degree::I, {69, 72, 76}},      // A-C-E  (Am)
        {Degree::ii, {71, 74, 77}},     // B-D-F  (Bdim)
        {Degree::iii, {72, 76, 79}},    // C-E-G  (C)
        {Degree::IV, {74, 77, 81}},     // D-F-A  (Dm)
        {Degree::V, {76, 79, 83}},      // E-G-B  (Em)
        {Degree::vi, {77, 81, 84}},     // F-A-C  (F)
        {Degree::viiDim, {79, 83, 86}}, // G-B-D  (G)
    };
    for (const auto &[degree, expected] : cases) {
        CHECK_MESSAGE(voice(key, degree) == expected, "A natural minor ", swiftName(degree), " mismatch");
    }
}

} // TEST_SUITE
