// Ported from Tests/MusicTheoryCoreTests/ChordBuildTests.swift.

#include <doctest.h>

#include "perfecto/theory/naming.hpp"
#include "perfecto/theory/voicing.hpp"

#include <optional>
#include <set>
#include <vector>

using namespace perfecto::theory;

namespace {

const Key cMajor{PitchClass::C, ScaleType::major};

using Type = std::optional<ChordType>;
using Extensions = std::set<ChordExtension>;

ChordSpec spec(Type type, const Extensions &extensions = {}, Degree degree = Degree::I) {
    return ChordSpec{degree, ChordColor::built(ChordBuild(type, extensions))};
}

std::vector<int> notes(Type type, const Extensions &extensions = {}, Degree degree = Degree::I,
                       Inversion inversion = Inversion::root()) {
    return computeVoicing(cMajor, spec(type, extensions, degree), inversion, 4, false, std::nullopt).notes();
}

std::string name(Type type, const Extensions &extensions = {}, Degree degree = Degree::I) {
    return chordLabel(cMajor, spec(type, extensions, degree));
}

using V = std::vector<int>;

} // namespace

TEST_SUITE("ChordBuild") {

// MARK: – Types

TEST_CASE("each type is its triad on any degree") {
    CHECK(notes(ChordType::diminished) == V{60, 63, 66});
    CHECK(notes(ChordType::minor) == V{60, 63, 67});
    CHECK(notes(ChordType::major) == V{60, 64, 67});
    CHECK(notes(ChordType::suspended) == V{60, 65, 67});
    // D is minor in C major, and a major button makes it major.
    CHECK(notes(ChordType::major, {}, Degree::ii) == V{62, 66, 69});
    CHECK(name(ChordType::major, {}, Degree::ii) == "D maj");
}

TEST_CASE("no type is the degree's own triad") {
    CHECK(notes(std::nullopt, {}, Degree::ii) == V{62, 65, 69});
    CHECK(notes(std::nullopt, {ChordExtension::minorSeventh}, Degree::ii) == V{62, 65, 69, 72});
    CHECK(name(std::nullopt, {ChordExtension::minorSeventh}, Degree::ii) == "D min7");
    CHECK(ChordColor::built(ChordBuild(std::nullopt)).isBase());
    CHECK(!ChordColor::built(ChordBuild(ChordType::major)).isBase());
}

TEST_CASE("a note is its root alone and keeps no extensions") {
    CHECK(notes(ChordType::note, {ChordExtension::ninth, ChordExtension::sixth}) == V{60});
    CHECK(name(ChordType::note, {ChordExtension::ninth}) == "C");
    CHECK(ChordBuild(ChordType::note, {ChordExtension::ninth}).extensions().empty());
}

// MARK: – Extensions

TEST_CASE("the extensions are added above the triad") {
    CHECK(notes(ChordType::major, {ChordExtension::sixth}) == V{60, 64, 67, 69});
    CHECK(notes(ChordType::major, {ChordExtension::minorSeventh}) == V{60, 64, 67, 70});
    CHECK(notes(ChordType::major, {ChordExtension::majorSeventh}) == V{60, 64, 67, 71});
    CHECK(notes(ChordType::major, {ChordExtension::ninth}) == V{60, 64, 67, 74});
    CHECK(notes(ChordType::major, {ChordExtension::sixth, ChordExtension::ninth}) == V{60, 64, 67, 69, 74});
}

TEST_CASE("a sixth over a seventh is a thirteenth") {
    CHECK(notes(ChordType::major, {ChordExtension::minorSeventh, ChordExtension::sixth}) ==
          V{60, 64, 67, 70, 81});
    CHECK(notes(ChordType::major, {ChordExtension::minorSeventh, ChordExtension::ninth, ChordExtension::sixth}) ==
          V{60, 64, 67, 70, 74, 81});
}

TEST_CASE("a diminished triad's sixth is a diminished seventh") {
    CHECK(notes(ChordType::diminished, {ChordExtension::sixth}) == V{60, 63, 66, 69});
    CHECK(name(ChordType::diminished, {ChordExtension::sixth}) == "C dim7");
}

TEST_CASE("the two sevenths together are the major one") {
    CHECK(notes(ChordType::minor, {ChordExtension::minorSeventh, ChordExtension::majorSeventh}) ==
          V{60, 63, 67, 71});
}

TEST_CASE("the extensions stay on top as the chord is inverted") {
    // C add9 in first inversion: E G C, with the D above them.
    CHECK(notes(ChordType::major, {ChordExtension::ninth}, Degree::I, Inversion::first()) == V{64, 67, 72, 74});
}

// MARK: – Names

TEST_CASE("the chord is named as the joysticks are") {
    CHECK(name(ChordType::major) == "C maj");
    CHECK(name(ChordType::suspended) == "C sus4");
    CHECK(name(ChordType::major, {ChordExtension::minorSeventh}) == "C 7");
    CHECK(name(ChordType::major, {ChordExtension::majorSeventh}) == "C maj7");
    CHECK(name(ChordType::minor, {ChordExtension::minorSeventh}) == "C min7");
    CHECK(name(ChordType::minor, {ChordExtension::majorSeventh}) == "C min(maj7)");
    CHECK(name(ChordType::diminished, {ChordExtension::minorSeventh}) == "C min7♭5");
    CHECK(name(ChordType::suspended, {ChordExtension::minorSeventh}) == "C 7sus4");
    CHECK(name(ChordType::major, {ChordExtension::ninth}) == "C add9");
    CHECK(name(ChordType::minor, {ChordExtension::ninth}) == "C min add9");
    CHECK(name(ChordType::major, {ChordExtension::sixth}) == "C 6");
    CHECK(name(ChordType::minor, {ChordExtension::sixth}) == "C min6");
    CHECK(name(ChordType::major, {ChordExtension::sixth, ChordExtension::ninth}) == "C 6/9");
    CHECK(name(ChordType::minor, {ChordExtension::sixth, ChordExtension::ninth}) == "C min6/9");
}

TEST_CASE("a ninth over a seventh names the chord") {
    CHECK(name(ChordType::major, {ChordExtension::minorSeventh, ChordExtension::ninth}) == "C 9");
    CHECK(name(ChordType::major, {ChordExtension::majorSeventh, ChordExtension::ninth}) == "C maj9");
    CHECK(name(ChordType::minor, {ChordExtension::minorSeventh, ChordExtension::ninth}) == "C min9");
    CHECK(name(ChordType::diminished, {ChordExtension::minorSeventh, ChordExtension::ninth}) == "C min9♭5");
    CHECK(name(ChordType::suspended, {ChordExtension::minorSeventh, ChordExtension::ninth}) == "C 9sus4");
    CHECK(name(ChordType::major, {ChordExtension::minorSeventh, ChordExtension::ninth, ChordExtension::sixth}) ==
          "C 9(13)");
}

TEST_CASE("the legend is the buttons' marks") {
    CHECK(ChordBuild(ChordType::minor, {ChordExtension::ninth, ChordExtension::minorSeventh}).legend() ==
          "Min · m7 9");
    CHECK(ChordBuild(std::nullopt, {ChordExtension::sixth}).legend() == "6");
    CHECK(ChordBuild(std::nullopt).legend() == "Base");
    CHECK(colorActionLabel(ChordColor::built(ChordBuild(ChordType::major))) == "Maj");
}

TEST_CASE("every build has its notes once and its root lowest") {
    std::vector<Type> types = {std::nullopt};
    for (ChordType t : allChordTypes) types.push_back(t);
    std::vector<Extensions> subsets;
    for (int bits = 0; bits < 16; ++bits) {
        Extensions s;
        for (std::size_t i = 0; i < allChordExtensions.size(); ++i)
            if (bits & (1 << i)) s.insert(allChordExtensions[i]);
        subsets.push_back(s);
    }
    for (const Type &type : types) {
        for (const Extensions &extensions : subsets) {
            const auto played = notes(type, extensions);
            CHECK(!played.empty());
            if (!played.empty()) CHECK(played.front() == 60);
            CHECK(std::set<int>(played.begin(), played.end()).size() == played.size());
            CHECK(!name(type, extensions).empty());
        }
    }
}

} // TEST_SUITE
