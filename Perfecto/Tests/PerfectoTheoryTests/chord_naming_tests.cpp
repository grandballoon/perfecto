// Ported from Tests/MusicTheoryCoreTests/ChordNamingTests.swift.

#include <doctest.h>

#include "perfecto/theory/joystick.hpp"
#include "perfecto/theory/naming.hpp"
#include "perfecto/theory/voicing.hpp"

#include <algorithm>
#include <cctype>
#include <set>
#include <string>
#include <vector>

using namespace perfecto::theory;

namespace {

const Key cMajor{PitchClass::C, ScaleType::major};
const Key cMinor{PitchClass::C, ScaleType::naturalMinor};

bool hasPrefix(const std::string &s, const std::string &p) { return s.compare(0, p.size(), p) == 0; }
bool hasSuffix(const std::string &s, const std::string &p) {
    return s.size() >= p.size() && s.compare(s.size() - p.size(), p.size(), p) == 0;
}
std::string uppercased(std::string s) {
    for (char &c : s) c = static_cast<char>(std::toupper(static_cast<unsigned char>(c)));
    return s;
}
std::string lowercased(std::string s) {
    for (char &c : s) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    return s;
}

std::string label(const Key &key, Degree degree, JoystickMode mode, JoystickDirection direction) {
    return chordLabel(key, ChordSpec{degree, ChordColor::joystick(mode, direction)});
}

std::vector<std::string> numerals(const Key &key) {
    std::vector<std::string> out;
    for (Degree d : allDegrees) out.push_back(degreeNumeral(key, d));
    return out;
}

} // namespace

TEST_SUITE("ChordNaming") {

// MARK: – Base quality is scale-driven (not a hardcoded I/IV/V = maj table)

TEST_CASE("major scale triad qualities") {
    CHECK(triadBase(cMajor, Degree::I) == TriadBase::major);
    CHECK(triadBase(cMajor, Degree::ii) == TriadBase::minor);
    CHECK(triadBase(cMajor, Degree::iii) == TriadBase::minor);
    CHECK(triadBase(cMajor, Degree::IV) == TriadBase::major);
    CHECK(triadBase(cMajor, Degree::V) == TriadBase::major);
    CHECK(triadBase(cMajor, Degree::vi) == TriadBase::minor);
    CHECK(triadBase(cMajor, Degree::viiDim) == TriadBase::dim);
}

TEST_CASE("natural minor scale triad qualities") {
    // i, ii°, III, iv, v, VI, VII — the diatonic triads of natural minor.
    // The old label table assumed major-scale qualities and got these wrong.
    CHECK(triadBase(cMinor, Degree::I) == TriadBase::minor);
    CHECK(triadBase(cMinor, Degree::ii) == TriadBase::dim);
    CHECK(triadBase(cMinor, Degree::iii) == TriadBase::major);
    CHECK(triadBase(cMinor, Degree::IV) == TriadBase::minor);
    CHECK(triadBase(cMinor, Degree::V) == TriadBase::minor);
    CHECK(triadBase(cMinor, Degree::vi) == TriadBase::major);
    CHECK(triadBase(cMinor, Degree::viiDim) == TriadBase::major);
}

// MARK: – Regressions the old duplicated label table produced

TEST_CASE("right on a minor degree is min7 not maj7") {
    // ii of C major is D minor; ↗right yields Dm7. The old label said "maj7".
    CHECK(label(cMajor, Degree::ii, JoystickMode::default_, JoystickDirection::right) == "D min7");
}

TEST_CASE("left on a major degree is min not dim") {
    // ↖left lowers the 3rd: I major → C minor. The old label said "dim".
    CHECK(label(cMajor, Degree::I, JoystickMode::default_, JoystickDirection::left) == "C min");
}

TEST_CASE("label is correct on a non-major scale") {
    // The old center label keyed off degree number, so a natural-minor I read
    // "maj". It is actually minor.
    CHECK(label(cMinor, Degree::I, JoystickMode::default_, JoystickDirection::center) == "C min");
    CHECK(label(cMinor, Degree::ii, JoystickMode::default_, JoystickDirection::center) == "D dim");
}

// MARK: – Representative labels

TEST_CASE("default labels") {
    CHECK(label(cMajor, Degree::I, JoystickMode::default_, JoystickDirection::center) == "C maj");
    CHECK(label(cMajor, Degree::I, JoystickMode::default_, JoystickDirection::right) == "C maj7");
    CHECK(label(cMajor, Degree::viiDim, JoystickMode::default_, JoystickDirection::center) == "B dim");
    // vi (Am) flipped to major
    CHECK(label(cMajor, Degree::vi, JoystickMode::default_, JoystickDirection::up) == "A maj");
}

// MARK: – The label never disagrees with the notes

TEST_CASE("a minor flag in the name implies a minor third in the voicing") {
    // For every mode/direction, if the quality name for a minor-base degree
    // starts with "min", the sounding voicing must actually contain a minor
    // (not major) third — the label and the notes come from one source, so
    // this holds by construction; the test guards against future drift.
    for (JoystickMode mode : {JoystickMode::default_, JoystickMode::extended, JoystickMode::chromatic}) {
        for (JoystickDirection dir : allJoystickDirections) {
            const ChordSpec spec{Degree::ii, ChordColor::joystick(mode, dir)}; // ii = minor base
            const std::string name = chordQualityName(cMajor, spec);
            if (!hasPrefix(name, "min")) continue;
            const auto notes =
                computeVoicing(cMajor, spec, Inversion::root(), 4, false, std::nullopt).notes();
            const int root = *std::min_element(notes.begin(), notes.end());
            std::set<int> intervals;
            for (int n : notes) intervals.insert((n - root) % 12);
            CHECK_MESSAGE(intervals.count(3) > 0, static_cast<int>(mode), "/", static_cast<int>(dir), " named ",
                          name, " but has no minor third");
            CHECK_MESSAGE(intervals.count(4) == 0, static_cast<int>(mode), "/", static_cast<int>(dir), " named ",
                          name, " but has a major third");
        }
    }
}

// MARK: – Degree numerals follow the key's triad qualities

TEST_CASE("major key numerals") {
    CHECK(numerals(cMajor) == std::vector<std::string>{"I", "ii", "iii", "IV", "V", "vi", "vii°"});
}

TEST_CASE("natural minor numerals agree with chord labels") {
    // The buttons used to read "ii" and "vii°" here while the display said
    // "D dim" and "B♭ maj".
    CHECK(numerals(cMinor) == std::vector<std::string>{"i", "ii°", "III", "iv", "v", "VI", "VII"});
}

TEST_CASE("numeral case matches the sounding triad") {
    for (ScaleType scale : allScaleTypes) {
        if (!isHeptatonic(scale)) continue;
        const Key key{PitchClass::C, scale};
        for (Degree degree : allDegrees) {
            const std::string numeral = degreeNumeral(key, degree);
            const std::string lab = chordLabel(key, ChordSpec{degree, ChordColor::base()});
            if (hasSuffix(lab, " maj")) {
                CHECK_MESSAGE(numeral == uppercased(numeral), displayName(scale), " ", index(degree), ": ", numeral,
                              " vs ", lab);
            } else {
                CHECK_MESSAGE(numeral == lowercased(numeral), displayName(scale), " ", index(degree), ": ", numeral,
                              " vs ", lab);
                CHECK_MESSAGE(hasSuffix(numeral, "°") == hasSuffix(lab, " dim"), displayName(scale), " ",
                              index(degree), ": ", numeral, " vs ", lab);
            }
        }
    }
}

// MARK: – Key quality

TEST_CASE("key quality") {
    const std::set<ScaleType> minor = {ScaleType::naturalMinor, ScaleType::harmonicMinor, ScaleType::melodicMinor,
                                       ScaleType::dorian,       ScaleType::minorPentatonic, ScaleType::blues};
    for (ScaleType scale : allScaleTypes) {
        const Key key{PitchClass::D, scale};
        CHECK_MESSAGE(key.isMinor() == (minor.count(scale) > 0), displayName(scale));
    }
}

TEST_CASE("key quality matches the tonic triad on seven-note scales") {
    for (ScaleType scale : allScaleTypes) {
        if (!isHeptatonic(scale)) continue;
        const Key key{PitchClass::D, scale};
        CHECK_MESSAGE(key.isMinor() == (triadBase(key, Degree::I) != TriadBase::major), displayName(scale));
    }
}

// MARK: – Ring action legend

TEST_CASE("action labels are base independent") {
    CHECK(joystickActionLabel(JoystickMode::default_, JoystickDirection::upRight) == "Dom 7");
    CHECK(joystickActionLabel(JoystickMode::default_, JoystickDirection::center) == "Base");
    CHECK(joystickActionLabel(JoystickMode::chromatic, JoystickDirection::upLeft) == "Maj7♯11");
}

// MARK: – Every entry is populated (no missing names)

TEST_CASE("every direction has names") {
    for (JoystickMode mode : {JoystickMode::default_, JoystickMode::extended, JoystickMode::chromatic}) {
        for (JoystickDirection dir : allJoystickDirections) {
            const JoystickOutcome &outcome = joystickOutcome(mode, dir);
            CHECK(!outcome.action.empty());
            for (TriadBase base : {TriadBase::major, TriadBase::minor, TriadBase::dim}) {
                const ChordShape &shape = outcome.shape(base);
                CHECK(!shape.name.empty());
                CHECK(!shape.intervals.empty());
            }
        }
    }
}

} // TEST_SUITE
