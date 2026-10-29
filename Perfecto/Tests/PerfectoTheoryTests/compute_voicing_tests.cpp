// Ported from Tests/MusicTheoryCoreTests/ComputeVoicingTests.swift.

#include <doctest.h>

#include "perfecto/theory/naming.hpp"
#include "perfecto/theory/voicing.hpp"

#include <algorithm>
#include <set>
#include <string>
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

std::string swiftName(JoystickDirection d) {
    switch (d) {
    case JoystickDirection::center: return "center";
    case JoystickDirection::up: return "up";
    case JoystickDirection::upRight: return "upRight";
    case JoystickDirection::right: return "right";
    case JoystickDirection::downRight: return "downRight";
    case JoystickDirection::down: return "down";
    case JoystickDirection::downLeft: return "downLeft";
    case JoystickDirection::left: return "left";
    case JoystickDirection::upLeft: return "upLeft";
    }
    return "?";
}

using JM = JoystickMode;
using JD = JoystickDirection;

Ints voice(const Key &key, Degree degree, ChordColor color, Inversion inversion, int octave, bool voiceLeading = false,
           const std::optional<Voicing> &previous = std::nullopt) {
    return computeVoicing(key, ChordSpec{degree, color}, inversion, octave, voiceLeading, previous).notes();
}

Ints cMajor(Inversion inversion, ChordColor color = ChordColor::joystick(JM::default_, JD::center)) {
    return voice(Key{PitchClass::C, ScaleType::major}, Degree::I, color, inversion, 4);
}

Ints plus(Ints notes, int by) {
    for (int &n : notes) n += by;
    return notes;
}

// C9: C E G B♭ D
const ChordColor ninth = ChordColor::joystick(JM::extended, JD::upRight);

} // namespace

TEST_SUITE("ComputeVoicing") {

// MARK: – Spec example

TEST_CASE("spec example: C major I, default right, octave 4") {
    // From spec §4.4: C-E-G-B = Cmaj7
    const Ints result = voice(Key{PitchClass::C, ScaleType::major}, Degree::I, ChordColor::joystick(JM::default_, JD::right),
                              Inversion::root(), 4);
    CHECK(result == Ints{60, 64, 67, 71});
}

// MARK: – MIDI root placement

TEST_CASE("octave 3 shifts all notes down 12") {
    const Key key{PitchClass::C, ScaleType::major};
    const ChordColor center = ChordColor::joystick(JM::default_, JD::center);
    const Ints oct4 = voice(key, Degree::I, center, Inversion::root(), 4);
    const Ints oct3 = voice(key, Degree::I, center, Inversion::root(), 3);
    CHECK(oct3 == plus(oct4, -12));
}

TEST_CASE("degree V root is correct for G major key") {
    // G major, degree V = D chord.
    // G.rawValue=7, octave=4, degreeOffset=7 (G major V).
    // chordRoot = 7 + (4+1)*12 + 7 = 74 (D5)
    const Ints result = voice(Key{PitchClass::G, ScaleType::major}, Degree::V, ChordColor::joystick(JM::default_, JD::center),
                              Inversion::root(), 4);
    CHECK(result.front() == 74); // D5 is the chord root
}

// MARK: – Inversions

TEST_CASE("first inversion") {
    // C major [60,64,67] → first inversion: C moves up → [64,67,72]
    CHECK(cMajor(Inversion::first()) == Ints{64, 67, 72});
}

TEST_CASE("second inversion") {
    // C major [60,64,67] → second inversion: C and E move up → [67,72,76]
    CHECK(cMajor(Inversion::second()) == Ints{67, 72, 76});
}

/// Each step up takes the lowest note up an octave, so a triad is an
/// octave higher after three.
TEST_CASE("an inversion goes on up past the second") {
    CHECK(cMajor(Inversion{3}) == Ints{72, 76, 79});
    CHECK(cMajor(Inversion{4}) == Ints{76, 79, 84});
    CHECK(cMajor(Inversion::second().rolled(2)) == cMajor(Inversion{4}));
}

/// Each step down takes the highest note down an octave.
TEST_CASE("an inversion below root position rolls the chord down") {
    CHECK(cMajor(Inversion{-1}) == Ints{55, 60, 64});
    CHECK(cMajor(Inversion{-2}) == Ints{52, 55, 60});
    CHECK(cMajor(Inversion{-3}) == Ints{48, 52, 55});
}

/// A four-note chord takes four steps to the octave, and has a third
/// inversion on the way.
TEST_CASE("a four-note chord has a third inversion") {
    const ChordColor maj7 = ChordColor::joystick(JM::default_, JD::right);
    CHECK(cMajor(Inversion{3}, maj7) == Ints{71, 72, 76, 79});
    CHECK(cMajor(Inversion{4}, maj7) == Ints{72, 76, 79, 83});
}

/// However far a chord is rolled, it is the same notes in other octaves.
TEST_CASE("rolling keeps the chord's pitch classes") {
    const ChordColor ninthGrid = ChordColor::grid(StackHeight::ninth, std::nullopt);
    std::set<int> root;
    for (int n : cMajor(Inversion::root(), ninthGrid)) root.insert(n % 12);
    for (int steps = -8; steps <= 8; ++steps) {
        const Ints rolled = cMajor(Inversion{steps}, ninthGrid);
        std::set<int> classes;
        for (int n : rolled) classes.insert(n % 12);
        CHECK(classes == root);
        CHECK(rolled == [&] { Ints s = rolled; std::sort(s.begin(), s.end()); return s; }());
    }
}

// MARK: – Chords wider than an octave

/// The notes above the octave are not inverted: the 9th stays on top
/// while the four notes under it take turns in the bass.
TEST_CASE("a ninth stays on top while the notes under it are inverted") {
    CHECK(cMajor(Inversion::root(), ninth) == Ints{60, 64, 67, 70, 74});
    CHECK(cMajor(Inversion::first(), ninth) == Ints{64, 67, 70, 72, 74});
    // The E rolled up would pass the 9th, which goes up an octave.
    CHECK(cMajor(Inversion::second(), ninth) == Ints{67, 70, 72, 76, 86});
    CHECK(cMajor(Inversion{3}, ninth) == Ints{70, 72, 76, 79, 86});
}

/// A turn of the notes within the octave is an octave, whatever the
/// chord has above them, up and down.
TEST_CASE("a turn of the inverted notes is an octave for every color") {
    for (JoystickMode mode : allJoystickModes) {
        for (JoystickDirection direction : allJoystickDirections) {
            const ChordColor color = ChordColor::joystick(mode, direction);
            const Ints shape = chordShape(Key{PitchClass::C, ScaleType::major}, ChordSpec{Degree::I, color}).intervals;
            const int turn = static_cast<int>(std::count_if(shape.begin(), shape.end(), [](int i) { return i < 12; }));
            const Ints root = cMajor(Inversion::root(), color);
            CHECK(cMajor(Inversion{turn}, color) == plus(root, 12));
            CHECK(cMajor(Inversion{-2 * turn}, color) == plus(root, -24));
        }
    }
}

/// No note above the octave is ever in the bass or among the inverted
/// notes, so a chord is never rolled into a cluster of its extensions.
TEST_CASE("the notes above the octave are always on top") {
    for (JoystickMode mode : allJoystickModes) {
        for (JoystickDirection direction : allJoystickDirections) {
            const ChordColor color = ChordColor::joystick(mode, direction);
            const Ints shape = chordShape(Key{PitchClass::C, ScaleType::major}, ChordSpec{Degree::I, color}).intervals;
            std::set<int> above;
            for (int i : shape)
                if (i >= 12) above.insert(i % 12);
            const std::size_t below = static_cast<std::size_t>(
                std::count_if(shape.begin(), shape.end(), [](int i) { return i < 12; }));
            for (int steps = -8; steps <= 8; ++steps) {
                const Ints rolled = cMajor(Inversion{steps}, color);
                CHECK(rolled.size() == shape.size());
                std::set<int> top;
                for (std::size_t k = std::min(below, rolled.size()); k < rolled.size(); ++k) top.insert(rolled[k] % 12);
                CHECK(top == above);
            }
        }
    }
}

/// Going down, the 9th comes down with the chord it is over.
TEST_CASE("a ninth rolled down keeps its ninth on top") {
    CHECK(cMajor(Inversion{-1}, ninth) == Ints{58, 60, 64, 67, 74});
    CHECK(cMajor(Inversion{-4}, ninth) == Ints{48, 52, 55, 58, 62});
}

TEST_CASE("second inversion on a four-note chord") {
    // Cmaj7 [60,64,67,71] → second inversion → [67,71,72,76]
    const Ints result = voice(Key{PitchClass::C, ScaleType::major}, Degree::I, ChordColor::joystick(JM::default_, JD::right),
                              Inversion::second(), 4);
    CHECK(result == Ints{67, 71, 72, 76});
}

// MARK: – Voice leading

TEST_CASE("voice leading minimizes movement from the previous chord") {
    // C major (60,64,67) → IV = F major.
    // Best voice leading is F in 2nd inversion [60,65,69] = C-F-A (cost 3),
    // which retains the common tone C. Root position [65,69,72] costs 8.
    const Voicing prev({60, 64, 67});
    const Ints result = voice(Key{PitchClass::C, ScaleType::major}, Degree::IV, ChordColor::joystick(JM::default_, JD::center),
                              Inversion::root(), 4, true, prev);
    CHECK(result == Ints{60, 65, 69});
}

TEST_CASE("voice leading with nil previous matches no voice leading") {
    const Key key{PitchClass::C, ScaleType::major};
    const ChordColor center = ChordColor::joystick(JM::default_, JD::center);
    const Ints a = voice(key, Degree::I, center, Inversion::root(), 4, true, std::nullopt);
    const Ints b = voice(key, Degree::I, center, Inversion::root(), 4, false, std::nullopt);
    CHECK(a == b);
}

// MARK: – Cross-scale quality detection

TEST_CASE("harmonic minor vii is dim") {
    // C harmonic minor vii = B dim triad = B-D-F
    const Ints result = voice(Key{PitchClass::C, ScaleType::harmonicMinor}, Degree::viiDim,
                              ChordColor::joystick(JM::default_, JD::center), Inversion::root(), 4);
    CHECK(result == Ints{71, 74, 77});
}

TEST_CASE("mixolydian I is major and gets maj7") {
    // G Mixolydian I = G major; joystick right → Gmaj7 = G-B-D-F#
    // G=67, B=71, D=74, F#=78
    const Ints result = voice(Key{PitchClass::G, ScaleType::mixolydian}, Degree::I,
                              ChordColor::joystick(JM::default_, JD::right), Inversion::root(), 4);
    CHECK(result == Ints{67, 71, 74, 78});
}

// MARK: – Invariants

TEST_CASE("output is always sorted ascending") {
    for (ScaleType scale : allScaleTypes) {
        for (Degree degree : allDegrees) {
            for (JoystickDirection dir : {JD::center, JD::up, JD::right, JD::down, JD::upLeft}) {
                const Ints result = voice(Key{PitchClass::C, scale}, degree, ChordColor::joystick(JM::default_, dir),
                                          Inversion::root(), 4);
                CHECK_MESSAGE(std::is_sorted(result.begin(), result.end()), swiftName(scale), " ", swiftName(degree), " ",
                              swiftName(dir), " output not sorted");
            }
        }
    }
}

TEST_CASE("output has at least two notes") {
    for (ScaleType scale : allScaleTypes) {
        for (Degree degree : allDegrees) {
            const Ints result = voice(Key{PitchClass::C, scale}, degree, ChordColor::joystick(JM::default_, JD::center),
                                      Inversion::root(), 4);
            CHECK_MESSAGE(result.size() >= 2, swiftName(scale), " ", swiftName(degree), " has too few notes");
        }
    }
}

} // TEST_SUITE
