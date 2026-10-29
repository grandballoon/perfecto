// Ported from Tests/DeskCoreTests/ConsonanceTests.swift.
//
// Not here: `onlyTheModeIsKept` tests the settings' Codable form, which the
// C++ core has not (persistence is the shell's); `aDegreeOutsideTheRunIsNotChosen`,
// `aStrikeOutsideTheRunIsRefusedAndSaysWhy` and `blockedTargetsAreDimmedWhereTheyAre`
// play `Desk` and `TwinRings`, and are ported with them.

#include <doctest.h>

#include "perfecto/desk/consonance.hpp"
#include "perfecto/desk/music.hpp"

#include <set>
#include <vector>

using namespace perfecto::desk;
using namespace perfecto::theory;

namespace {

const Key c{PitchClass::C, ScaleType::major};

DeskChord chord(PitchClass root, const std::vector<int> &tones) { return DeskChord::onRoot(root, ChordTones(tones), c); }

ConsonanceGuard guarded(GuardMode mode, const std::vector<std::vector<int>> &chords = {}) {
    ConsonanceGuard consonance;
    consonance.mode = mode;
    std::vector<DeskEffect> heard;
    for (const auto &notes : chords) heard.push_back(DeskEffect::sound(Line::chord, notes, "", 1, 1, false));
    consonance.hear(heard);
    return consonance;
}

} // namespace

TEST_SUITE("The consonance guard") {

TEST_CASE("off plays everything") { CHECK(guarded(GuardMode::off).allows(chord(PitchClass::C, {0, 1, 4}), c)); }

TEST_CASE("always plays the consonant qualities only") {
    const ConsonanceGuard always = guarded(GuardMode::always);
    CHECK(always.allows(chord(PitchClass::C, {0, 4, 7}), c));
    CHECK(always.allows(chord(PitchClass::G, {0, 4, 7, 10, 2}), c));
    CHECK(always.refusal(chord(PitchClass::C, {0, 1, 4}), c) != std::nullopt);
    // A borrowed chord is consonant, unless the key's notes alone are asked for.
    CHECK(always.allows(chord(PitchClass::C, {0, 3, 7}), c));
    ConsonanceGuard inKey = always;
    inKey.inKey = true;
    CHECK(inKey.refusal(chord(PitchClass::C, {0, 3, 7}), c) == "C min is outside the key");
    // A line's note must be the key's.
    CHECK(always.allowsNote(62, c));
    CHECK(!always.allowsNote(61, c));
}

TEST_CASE("with what is sounding a chord must share a note and a note must sit in the chord") {
    const ConsonanceGuard sounding = guarded(GuardMode::sounding, {{60, 64, 67}});
    CHECK(sounding.allows(chord(PitchClass::A, {0, 3, 7}), c));
    CHECK(sounding.refusal(chord(PitchClass::Fs, {0, 4, 7}), c) == "F# maj shares no note with what is sounding");
    // D over C major is an added 9th; C♯ is a clash.
    CHECK(sounding.allowsNote(62, c));
    CHECK(sounding.refusalOfNote(61, c) == "C# clashes with the chord");
    // With nothing sounding, nothing is near or far.
    ConsonanceGuard silent = sounding;
    silent.hear({DeskEffect::silence(Line::chord)});
    CHECK(silent.allows(chord(PitchClass::Fs, {0, 4, 7}), c));
}

TEST_CASE("with the run a chord brings one new note at most") {
    const ConsonanceGuard run = guarded(GuardMode::run, {{60, 64, 67}, {65, 69, 72}, {67, 71, 74}});
    CHECK(run.pool() == std::set<int>{0, 2, 4, 5, 7, 9, 11});
    CHECK(run.allows(chord(PitchClass::G, {0, 4, 7, 10}), c));
    // B♭ alone is one step out; E♭ major brings E♭ and B♭.
    CHECK(run.allows(chord(PitchClass::C, {0, 4, 7, 10}), c));
    CHECK(run.refusal(chord(PitchClass::Ds, {0, 4, 7}), c) == "D# maj is outside the run");
    CHECK(!run.allowsNote(63, c));
    // Nothing heard, nothing is outside.
    CHECK(guarded(GuardMode::run).allows(chord(PitchClass::Ds, {0, 4, 7}), c));
}

TEST_CASE("the run remembers the last few chords") {
    std::vector<std::vector<int>> chords;
    for (int i = 0; i < 8; ++i) chords.push_back({48 + i, 52 + i, 55 + i});
    const ConsonanceGuard run = guarded(GuardMode::run, chords);
    CHECK(static_cast<int>(run.recent().size()) == ConsonanceGuard::window);
    // The first two are forgotten: the oldest remembered is the third, D major.
    CHECK(run.recent().front() == std::set<int>{2, 6, 9});
}

}
