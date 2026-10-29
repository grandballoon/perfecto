// Ported from Tests/MusicTheoryCoreTests/VoicingTests.swift.

#include <doctest.h>

#include "perfecto/theory/voicing.hpp"

#include <set>

using namespace perfecto::theory;

namespace {

bool inMidiRange(int note) { return note >= Voicing::midiLow && note <= Voicing::midiHigh; }

} // namespace

TEST_SUITE("Voicing") {

TEST_CASE("notes are sorted and unique") {
    CHECK(Voicing({67, 60, 64, 60}).notes() == std::vector<int>{60, 64, 67});
}

TEST_CASE("notes above the MIDI range fold down by octaves") {
    // B major vii add9 at octave 7: A♯ C♯ E♯ and B♯ an octave above the top.
    CHECK(Voicing({118, 122, 125, 132}).notes() == std::vector<int>{118, 120, 122, 125});
}

TEST_CASE("notes below the MIDI range fold up by octaves") {
    CHECK(Voicing({-3, 0, 4}).notes() == std::vector<int>{0, 4, 9});
}

TEST_CASE("folding keeps pitch classes") {
    const std::vector<int> raw = {100, 115, 129, 140, 151};
    const auto folded = Voicing(raw).notes();
    std::set<int> foldedClasses, rawClasses;
    for (int note : folded) {
        CHECK(inMidiRange(note));
        foldedClasses.insert(note % 12);
    }
    for (int note : raw) rawClasses.insert(note % 12);
    CHECK(foldedClasses == rawClasses);
}

TEST_CASE("the bass note is folded too") {
    CHECK(Voicing({60}, 130).bassNote() == 118);
}

TEST_CASE("every computed voicing is in range") {
    for (ScaleType scale : allScaleTypes) {
        if (!isHeptatonic(scale)) continue;
        for (Degree degree : allDegrees) {
            for (int octave : {0, 7, 9}) {
                const Voicing v = computeVoicing(
                    Key{PitchClass::B, scale},
                    ChordSpec{degree, ChordColor::joystick(JoystickMode::chromatic, JoystickDirection::down)},
                    Inversion::second(), octave, false, std::nullopt);
                for (int note : v.notes()) CHECK_MESSAGE(inMidiRange(note), displayName(scale), " ", index(degree), " oct ", octave);
            }
        }
    }
}

}
