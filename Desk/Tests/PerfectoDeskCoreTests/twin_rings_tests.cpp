// Ported from Tests/DeskCoreTests: the suite "Twin rings" of LayoutTests.swift
// and "Twin rings' voices" of VoiceLeadingTests.swift, and the tests of other
// suites that play `TwinRings`, each in a suite named as its own:
// `blockedTargetsAreDimmedWhereTheyAre` (ConsonanceTests.swift);
// `yAPinsAndYHeldPlaysTheFavorites`, `aTapOfYStillHolds` and
// `yXUnpinsTheFavoriteAimedAt` (FavoritesTests.swift);
// `theStickFindsTheModeWhereTheArrangementPutsIt`,
// `l3TurnsTheRingAndTheKeptColorStays` and `aStickCannotReachAFilteredSector`
// (RingTests.swift).

#include <doctest.h>

#include "perfecto/desk/gates.hpp"
#include "perfecto/desk/music.hpp"
#include "perfecto/desk/pad.hpp"
#include "perfecto/desk/ring_pie.hpp"
#include "perfecto/desk/twin_rings.hpp"
#include "rig.hpp"

#include <algorithm>
#include <optional>
#include <string>
#include <variant>
#include <vector>

using namespace perfecto::desk;
using namespace perfecto::desk::testing;
using namespace perfecto::theory;

namespace {

constexpr double span = RingPie::sectorSpan;

using Frame = GamepadFrame;

bool contains(const std::vector<DeskEffect> &effects, const DeskEffect &effect) {
    return std::find(effects.begin(), effects.end(), effect) != effects.end();
}

std::string chordName(const Rig<TwinRings> &rig) { return rig.layout.chord(rig.settings).name(); }

} // namespace

TEST_SUITE("Twin rings") {

TEST_CASE("a strikes the tonic's chord") {
    Rig rig{TwinRings()};
    const auto out = rig.at(1, [](Frame &f) { f.buttons = {PadButton::a}; });
    CHECK(out == std::vector<DeskEffect>{DeskEffect::sound(Line::chord, {60, 64, 67}, "electricPiano", 0.8, 1, false)});
}

TEST_CASE("the left stick chooses the degree and keeps it") {
    Rig rig{TwinRings()};
    // iii is two sectors clockwise of I, in scale order.
    rig.at(1, [](Frame &f) { f.left = lean(2 * 360.0 / 7); });
    rig.at(2, [](Frame &f) { f.left = Stick::rest(); });
    const auto result1 = rig.at(3, [](Frame &f) { f.buttons = {PadButton::a}; });
    CHECK(sounded(result1) == std::vector<std::vector<int>>{{64, 67, 71}});
}

TEST_CASE("a lean on the ring recolors the chord held") {
    Rig rig{TwinRings()};
    rig.at(1, [](Frame &f) { f.buttons = {PadButton::a}; });
    // A sector darker than I's own Ionian is Mixolydian; the inner ring is the 7th.
    const auto out = rig.at(2, [](Frame &f) { f.right = lean(-RingPie::sectorSpan, 0.6); });
    CHECK(out ==
          std::vector<DeskEffect>{DeskEffect::sound(Line::chord, {60, 64, 67, 70}, "electricPiano", 0.8, 1, true)});
    CHECK(chordName(rig) == "C 7");
}

TEST_CASE("a flick keeps the color and a hold does not") {
    Rig flick{TwinRings()};
    flick.at(1, [](Frame &f) { f.right = lean(0, 0.8); });
    flick.at(1.1, [](Frame &f) { f.right = Stick::rest(); });
    CHECK(chordName(flick) == "C maj9");

    Rig hold{TwinRings()};
    hold.at(1, [](Frame &f) { f.right = lean(0, 0.8); });
    hold.at(1.5, [](Frame &f) { f.right = lean(0, 0.8); });
    hold.at(1.6, [](Frame &f) { f.right = Stick::rest(); });
    CHECK(chordName(hold) == "C maj");
}

TEST_CASE("the right trigger strikes by how fast it is pulled") {
    Rig rig{TwinRings()};
    rig.at(1, [](Frame &f) { f.rightTrigger = 0.1; });
    const auto out = rig.at(1.02, [](Frame &f) { f.rightTrigger = 0.7; });
    REQUIRE_MESSAGE(!out.empty(), "a strike");
    const auto *sound = std::get_if<DeskEffect::Sound>(&out.front().value());
    REQUIRE_MESSAGE(sound != nullptr, "a strike");
    CHECK(sound->notes == std::vector<int>{60, 64, 67});
    CHECK(sound->level == 1);
    const auto result2 = rig.at(1.5, [](Frame &f) { f.rightTrigger = 0; });
    CHECK(contains(result2, DeskEffect::silence(Line::chord)));
}

TEST_CASE("a bumper tapped moves the key a fifth") {
    Rig rig{TwinRings()};
    rig.at(1, [](Frame &f) { f.buttons = {PadButton::rb}; });
    rig.at(1.1, [](Frame &f) { f.buttons = {}; });
    CHECK(rig.settings.key == Key{PitchClass::G, ScaleType::major});
    rig.at(2, [](Frame &f) { f.buttons = {PadButton::lb}; });
    rig.at(2.1, [](Frame &f) { f.buttons = {}; });
    rig.at(3, [](Frame &f) { f.buttons = {PadButton::lb}; });
    rig.at(3.1, [](Frame &f) { f.buttons = {}; });
    CHECK(rig.settings.key == Key{PitchClass::F, ScaleType::major});
}

TEST_CASE("lb puts the step compass on the right stick") {
    Rig rig{TwinRings()};
    rig.at(1, [](Frame &f) { f.buttons = {PadButton::lb}; });
    // Up adds the degree's next tone: its 7th.
    rig.at(1.2, [](Frame &f) { f.right = lean(0); });
    CHECK(chordName(rig) == "C maj7");
    // Let go of the bumper after using it: no tap.
    rig.at(1.3, [](Frame &f) {
        f.right = Stick::rest();
        f.buttons = {};
    });
    CHECK(rig.settings.key == Key{PitchClass::C, ScaleType::major});
}

TEST_CASE("a long press of lb leaves the compass on") {
    Rig rig{TwinRings()};
    rig.at(1, [](Frame &f) { f.buttons = {PadButton::lb}; });
    const auto latched = rig.at(1 + TapOrHold::tapTime, [](Frame &f) { f.buttons = {PadButton::lb}; });
    CHECK(contains(latched, DeskEffect::rumble(Rumble::bump)));
    rig.at(1.5, [](Frame &f) { f.buttons = {}; });
    // Let go, the compass is still on the right stick, and the key has not moved.
    CHECK(rig.layout.isOnCompass());
    CHECK(rig.settings.key == Key{PitchClass::C, ScaleType::major});
    rig.at(2, [](Frame &f) { f.right = lean(0); });
    CHECK(chordName(rig) == "C maj7");
    rig.at(2.1, [](Frame &f) { f.right = Stick::rest(); });
    // Another long-press turns it off.
    rig.at(3, [](Frame &f) { f.buttons = {PadButton::lb}; });
    rig.at(3 + TapOrHold::tapTime, [](Frame &f) { f.buttons = {PadButton::lb}; });
    rig.at(3.5, [](Frame &f) { f.buttons = {}; });
    CHECK(!rig.layout.isOnCompass());
}

TEST_CASE("a tap of lb still moves the key with the compass on") {
    Rig rig{TwinRings()};
    rig.at(1, [](Frame &f) { f.buttons = {PadButton::lb}; });
    rig.at(1.5, [](Frame &f) { f.buttons = {PadButton::lb}; });
    rig.at(1.6, [](Frame &f) { f.buttons = {}; });
    rig.at(2, [](Frame &f) { f.buttons = {PadButton::lb}; });
    rig.at(2.1, [](Frame &f) { f.buttons = {}; });
    CHECK(rig.settings.key == Key{PitchClass::F, ScaleType::major});
    CHECK(rig.layout.isOnCompass());
}

TEST_CASE("r3 at rest takes the compass back and then the color") {
    Rig rig{TwinRings()};
    // A Mixolydian 7th kept on the ring, and the compass's first add kept on it.
    rig.at(1, [](Frame &f) { f.right = lean(-RingPie::sectorSpan, 0.6); });
    rig.at(1.1, [](Frame &f) { f.right = Stick::rest(); });
    rig.at(2, [](Frame &f) { f.buttons = {PadButton::lb}; });
    rig.at(2.05, [](Frame &f) { f.right = lean(0); });
    rig.at(2.1, [](Frame &f) { f.right = Stick::rest(); });
    rig.at(2.2, [](Frame &f) { f.buttons = {}; });
    CHECK(chordName(rig) != "C 7");
    const auto back = rig.layout.resetsTo(rig.settings);
    REQUIRE(back.has_value());
    CHECK(back->name() == "C 7");
    rig.at(3, [](Frame &f) { f.buttons = {PadButton::r3}; });
    rig.at(3.1, [](Frame &f) { f.buttons = {}; });
    CHECK(chordName(rig) == "C 7");
    rig.at(4, [](Frame &f) { f.buttons = {PadButton::r3}; });
    rig.at(4.1, [](Frame &f) { f.buttons = {}; });
    CHECK(chordName(rig) == "C maj");
    CHECK(!rig.layout.resetsTo(rig.settings).has_value());
}

TEST_CASE("the left trigger arpeggiates") {
    Rig rig{TwinRings()};
    rig.at(1, [](Frame &f) { f.buttons = {PadButton::a}; });
    // Pulled to the first step: quarter notes at 96 bpm.
    const auto out = rig.at(1, [](Frame &f) { f.leftTrigger = 0.3; });
    CHECK(sounded(out) == std::vector<std::vector<int>>{{60}});
    const auto result3 = rig.at(1 + 60.0 / 96);
    CHECK(sounded(result3) == std::vector<std::vector<int>>{{64}});
    const auto result4 = rig.at(1 + 2 * 60.0 / 96);
    CHECK(sounded(result4) == std::vector<std::vector<int>>{{67}});
}

TEST_CASE("the d-pad voices the chord held") {
    Rig rig{TwinRings()};
    rig.at(1, [](Frame &f) { f.buttons = {PadButton::a}; });
    const auto out = rig.at(2, [](Frame &f) { f.buttons = {PadButton::a, PadButton::right}; });
    CHECK(sounded(out) == std::vector<std::vector<int>>{{64, 67, 72}});
    CHECK(rig.settings.inversion == Inversion::first());
}

} // TEST_SUITE

TEST_SUITE("The consonance guard") {

TEST_CASE("blocked targets are dimmed where they are") {
    DeskSettings settings;
    settings.consonance.mode = GuardMode::run;
    settings.consonance.hear({DeskEffect::sound(Line::chord, {60, 64, 67}, "", 1, 1, false)});
    const auto targets = TwinRings().degreeTargets(settings);
    CHECK(targets.size() == 7);
    const auto named = [&](const std::string &name) {
        return std::find_if(targets.begin(), targets.end(), [&](const Target &target) { return target.name == name; });
    };
    REQUIRE(named("G maj") != targets.end());
    CHECK(named("G maj")->isHidden == true);
    REQUIRE(named("E min") != targets.end());
    CHECK(named("E min")->isHidden == false);
}

} // TEST_SUITE

TEST_SUITE("Favorites") {

TEST_CASE("y a pins and y held plays the favorites") {
    Rig rig{TwinRings()};
    // Flick to keep the Mixolydian 7th (the right thumb cannot lean and
    // press Y at once), then pin it with Y + A.
    rig.at(1, [](Frame &f) { f.right = lean(-span, 0.6); });
    rig.at(1.1, [](Frame &f) { f.right = Stick::rest(); });
    rig.at(1.5, [](Frame &f) { f.buttons = {PadButton::y}; });
    rig.at(1.6, [](Frame &f) { f.buttons = {PadButton::y, PadButton::a}; });
    CHECK(rig.settings.favorites.colors(rig.settings.key, Degree::I) ==
          std::vector<ChordColor>{ChordColor::grid(StackHeight::seventh, HeptatonicMode::mixolydian)});
    // Pinning was no tap: hold has not changed.
    rig.at(1.7, [](Frame &f) { f.buttons = {}; });
    CHECK(!rig.layout.holds());
    // Back to the plain color.
    rig.at(1.8, [](Frame &f) { f.buttons = {PadButton::r3}; });
    rig.at(1.9, [](Frame &f) { f.buttons = {}; });
    CHECK(chordName(rig) == "C maj");
    // Y held, the right stick up is the first favorite; a flick keeps it.
    rig.at(2, [](Frame &f) { f.buttons = {PadButton::y}; });
    rig.at(2.1, [](Frame &f) { f.right = lean(0); });
    rig.at(2.2, [](Frame &f) { f.right = Stick::rest(); });
    rig.at(2.3, [](Frame &f) { f.buttons = {}; });
    CHECK(chordName(rig) == "C 7");
}

TEST_CASE("a tap of y still holds") {
    Rig rig{TwinRings()};
    rig.at(1, [](Frame &f) { f.buttons = {PadButton::y}; });
    rig.at(1.1, [](Frame &f) { f.buttons = {}; });
    CHECK(rig.layout.holds());
}

TEST_CASE("y x unpins the favorite aimed at") {
    Rig rig{TwinRings()};
    rig.settings.favorites.pin(DeskChord(rig.settings.key, Degree::I, ChordColor::grid(StackHeight::ninth)),
                               rig.settings.key);
    rig.at(1, [](Frame &f) { f.buttons = {PadButton::y}; });
    rig.at(1.1, [](Frame &f) { f.right = lean(0); });
    rig.at(1.2, [](Frame &f) { f.buttons = {PadButton::y, PadButton::x}; });
    CHECK(rig.settings.favorites.colors(rig.settings.key, Degree::I).empty());
}

} // TEST_SUITE

TEST_SUITE("The ring's arrangements") {

TEST_CASE("the stick finds the mode where the arrangement puts it") {
    Rig rig{TwinRings()};
    rig.settings.ringArrangement = RingArrangement::fixed;
    // Fixed: Mixolydian is one sector clockwise of Dorian.
    rig.at(1, [](Frame &f) { f.right = lean(span, 0.6); });
    CHECK(chordName(rig) == "C 7");
}

TEST_CASE("l3 turns the ring and the kept color stays") {
    Rig rig{TwinRings()};
    rig.at(1, [](Frame &f) { f.right = lean(-span, 0.6); });
    rig.at(1.1, [](Frame &f) { f.right = Stick::rest(); });
    CHECK(chordName(rig) == "C 7");
    rig.at(2, [](Frame &f) { f.buttons = {PadButton::l3}; });
    CHECK(rig.settings.ringArrangement == RingArrangement::fixed);
    CHECK(chordName(rig) == "C 7");
    rig.at(2.1, [](Frame &f) { f.buttons = {}; });
    rig.at(3, [](Frame &f) { f.buttons = {PadButton::l3}; });
    rig.at(3.1, [](Frame &f) { f.buttons = {}; });
    rig.at(4, [](Frame &f) { f.buttons = {PadButton::l3}; });
    CHECK(rig.settings.ringArrangement == RingArrangement::home);
}

} // TEST_SUITE

TEST_SUITE("The ring's orders and filters") {

TEST_CASE("a stick cannot reach a filtered sector") {
    Rig rig{TwinRings()};
    rig.settings.ringFilter = RingFilter::inKey;
    // Where Mixolydian is, darker than Ionian: out of reach, so the chord stays plain.
    rig.at(1, [](Frame &f) { f.right = lean(-RingPie::sectorSpan, 0.6); });
    CHECK(chordName(rig) == "C maj");
    rig.at(2, [](Frame &f) { f.right = lean(RingPie::sectorSpan, 0.6); });
    CHECK(chordName(rig) == "C maj7");
}

} // TEST_SUITE

namespace {

/// Twin rings with the LB layer left on, showing the voices.
Rig<TwinRings> voices() {
    Rig rig{TwinRings()};
    rig.at(1, [](Frame &f) { f.buttons = {PadButton::lb}; });
    rig.at(1 + TapOrHold::tapTime, [](Frame &f) { f.buttons = {PadButton::lb}; });
    rig.at(1.5, [](Frame &f) { f.buttons = {}; });
    rig.at(2, [](Frame &f) { f.buttons = {PadButton::l3}; });
    rig.at(2.1, [](Frame &f) { f.buttons = {}; });
    return rig;
}

} // namespace

TEST_SUITE("Twin rings' voices") {

TEST_CASE("l3 with the layer on switches to the voices") {
    const auto rig = voices();
    CHECK(rig.settings.lbLayer == LBLayer::voices);
    CHECK(rig.layout.isOnVoices());
    // The ring's arrangement was not turned.
    CHECK(rig.settings.ringArrangement == RingArrangement::home);
}

TEST_CASE("a flick takes a step and r3 takes it back") {
    auto rig = voices();
    rig.at(3, [](Frame &f) { f.right = lean(90, 0.6); });
    CHECK(chordName(rig) == "C sus4");
    rig.at(3.1, [](Frame &f) { f.right = Stick::rest(); });
    REQUIRE(rig.layout.walked().has_value());
    CHECK(rig.layout.walked()->name() == "C sus4");
    // Steps walk on from where they took the voices: the middle down from F to E.
    rig.at(4, [](Frame &f) { f.right = lean(270, 0.6); });
    rig.at(4.1, [](Frame &f) { f.right = Stick::rest(); });
    CHECK(chordName(rig) == "C maj");
    CHECK(rig.layout.chord(rig.settings).notes(rig.settings) == std::vector<int>{60, 64, 67});
    rig.at(5, [](Frame &f) { f.right = lean(0, 0.95); });
    rig.at(5.1, [](Frame &f) { f.right = Stick::rest(); });
    CHECK(chordName(rig) == "A min/C");
    rig.at(6, [](Frame &f) { f.buttons = {PadButton::r3}; });
    rig.at(6.1, [](Frame &f) { f.buttons = {}; });
    CHECK(!rig.layout.walked().has_value());
    CHECK(chordName(rig) == "C maj");
}

TEST_CASE("a hold plays the move and goes back") {
    auto rig = voices();
    rig.at(3, [](Frame &f) { f.buttons = {PadButton::a}; });
    const auto played = rig.at(3.5, [](Frame &f) { f.right = lean(270, 0.6); });
    CHECK(sounded(played) == std::vector<std::vector<int>>{{60, 63, 67}});
    rig.at(4, [](Frame &f) { f.right = lean(270, 0.6); });
    const auto back = rig.at(4.1, [](Frame &f) { f.right = Stick::rest(); });
    CHECK(sounded(back) == std::vector<std::vector<int>>{{60, 64, 67}});
    CHECK(!rig.layout.walked().has_value());
}

TEST_CASE("the left stick moves the bass") {
    auto rig = voices();
    rig.at(3, [](Frame &f) { f.left = lean(180, 0.6); });
    rig.at(3.1, [](Frame &f) { f.left = Stick::rest(); });
    CHECK(chordName(rig) == "E min/B");
    // The degree pie is not played meanwhile.
    CHECK(rig.layout.degree() == Degree::I);
}

TEST_CASE("a move that is not consonant cannot be taken") {
    auto rig = voices();
    rig.at(3, [](Frame &f) { f.right = lean(180, 0.6); });
    CHECK(!rig.layout.voiceAim().has_value());
    rig.at(3.1, [](Frame &f) { f.right = Stick::rest(); });
    CHECK(!rig.layout.walked().has_value());
}

} // TEST_SUITE
