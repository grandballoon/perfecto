// Ported to Tests/DeskCoreTests/FaceChordsTests.swift: Face Chords, the key's
// chords by number on the face buttons.

#include <doctest.h>

#include "perfecto/desk/desk.hpp"
#include "perfecto/desk/face_chords.hpp"
#include "rig.hpp"

#include <algorithm>
#include <vector>

using namespace perfecto::desk;
using namespace perfecto::desk::testing;
using namespace perfecto::theory;

using Notes = std::vector<std::vector<int>>;

namespace {

bool silences(const std::vector<DeskEffect> &effects) {
    return std::find(effects.begin(), effects.end(), DeskEffect::silence(Line::chord)) != effects.end();
}

void hold(GamepadFrame &frame, std::set<PadButton> buttons, double leftTrigger = 0) {
    frame.buttons = std::move(buttons);
    frame.leftTrigger = leftTrigger;
}

bool silencesOver(const std::vector<DeskEffect> &effects) {
    return std::find(effects.begin(), effects.end(), DeskEffect::silence(Line::melody)) != effects.end();
}

/// A rig with the second voice added (R3) at time 0.1.
Rig<FaceChords> withSecond() {
    Rig rig(FaceChords{});
    rig.at(0.1, [](GamepadFrame &f) { hold(f, {PadButton::r3}); });
    rig.at(0.2, [](GamepadFrame &f) { hold(f, {}); });
    return rig;
}

/// The second voice added and LB double-clicked: both voices on.
Rig<FaceChords> together() {
    Rig rig = withSecond();
    rig.at(0.3, [](GamepadFrame &f) { hold(f, {PadButton::lb}); });
    rig.at(0.35, [](GamepadFrame &f) { hold(f, {}); });
    rig.at(0.4, [](GamepadFrame &f) { hold(f, {PadButton::lb}); });
    rig.at(0.45, [](GamepadFrame &f) { hold(f, {}); });
    return rig;
}

} // namespace

TEST_SUITE("Face Chords") {

TEST_CASE("each button strikes its numbered chord, the minor ones with LT") {
    Rig rig(FaceChords{});
    const std::vector<std::pair<PadButton, std::vector<int>>> plain = {
        {PadButton::a, {60, 64, 67}}, {PadButton::b, {65, 69, 72}}, {PadButton::x, {67, 71, 74}}, {PadButton::y, {71, 74, 77}}};
    const std::vector<std::pair<PadButton, std::vector<int>>> layered = {
        {PadButton::a, {60, 64, 67}}, {PadButton::b, {62, 65, 69}}, {PadButton::x, {64, 67, 71}}, {PadButton::y, {69, 72, 76}}};
    double time = 1;
    for (const auto &[layer, trigger] : {std::pair(&plain, 0.0), std::pair(&layered, 1.0)}) {
        for (const auto &[button, notes] : *layer) {
            CHECK(sounded(rig.at(time, [&](GamepadFrame &f) { hold(f, {button}, trigger); })) == Notes{notes});
            CHECK(silences(rig.at(time + 0.5, [&](GamepadFrame &f) { hold(f, {}, trigger); })));
            time += 1;
        }
    }
}

TEST_CASE("pulling LT while a button is held changes the chord, and letting go changes it back") {
    Rig rig(FaceChords{});
    CHECK(sounded(rig.at(1, [](GamepadFrame &f) { hold(f, {PadButton::b}); })) == Notes{{65, 69, 72}});
    CHECK(sounded(rig.at(2, [](GamepadFrame &f) { hold(f, {PadButton::b}, 1); })) == Notes{{62, 65, 69}});
    CHECK(rig.layout.heard() == std::pair(PadButton::b, Degree::ii));
    CHECK(sounded(rig.at(3, [](GamepadFrame &f) { hold(f, {PadButton::b}, 0); })) == Notes{{65, 69, 72}});
    CHECK(rig.layout.heard() == std::pair(PadButton::b, Degree::IV));
}

TEST_CASE("LT on A, the tonic in both layers, strikes nothing again") {
    Rig rig(FaceChords{});
    rig.at(1, [](GamepadFrame &f) { hold(f, {PadButton::a}); });
    CHECK(sounded(rig.at(2, [](GamepadFrame &f) { hold(f, {PadButton::a}, 1); })).empty());
    CHECK(rig.layout.line().isSounding());
}

TEST_CASE("LT alone sounds nothing") {
    Rig rig(FaceChords{});
    CHECK(sounded(rig.at(1, [](GamepadFrame &f) { hold(f, {}, 1); })).empty());
    CHECK(sounded(rig.at(2, [](GamepadFrame &f) { hold(f, {}, 0); })).empty());
    CHECK(!rig.layout.line().isSounding());
}

TEST_CASE("LT is held a little either side of halfway") {
    Rig rig(FaceChords{});
    rig.at(1, [](GamepadFrame &f) { hold(f, {PadButton::x}, 0.52); });
    CHECK_FALSE(rig.layout.isLayered());
    rig.at(1.5, [](GamepadFrame &f) { hold(f, {PadButton::x}, 0.6); });
    CHECK(rig.layout.isLayered());
    CHECK(sounded(rig.at(2, [](GamepadFrame &f) { hold(f, {PadButton::x}, 0.47); })).empty());
    CHECK(rig.layout.isLayered());
    CHECK(sounded(rig.at(3, [](GamepadFrame &f) { hold(f, {PadButton::x}, 0.4); })) == Notes{{67, 71, 74}});
}

TEST_CASE("the latest button is heard, and letting it go hands back to the one beneath") {
    Rig rig(FaceChords{});
    rig.at(1, [](GamepadFrame &f) { hold(f, {PadButton::a}); });
    CHECK(sounded(rig.at(2, [](GamepadFrame &f) { hold(f, {PadButton::a, PadButton::x}); })) == Notes{{67, 71, 74}});
    CHECK(sounded(rig.at(3, [](GamepadFrame &f) { hold(f, {PadButton::a}); })) == Notes{{60, 64, 67}});
    const auto out = rig.at(4, [](GamepadFrame &f) { hold(f, {}); });
    CHECK(silences(out));
    CHECK(!rig.layout.line().isSounding());
    CHECK(!rig.layout.heard());
}

TEST_CASE("a layer that leaves a button out plays the press beneath it, or nothing") {
    FaceChords::Map map = FaceChords::Map::standard();
    map.layered.erase(PadButton::y);
    Rig rig(FaceChords{map});
    rig.at(1, [](GamepadFrame &f) { hold(f, {PadButton::a}); });
    rig.at(2, [](GamepadFrame &f) { hold(f, {PadButton::a, PadButton::y}); });
    CHECK(rig.layout.heard() == std::pair(PadButton::y, Degree::viiDim));
    CHECK(sounded(rig.at(3, [](GamepadFrame &f) { hold(f, {PadButton::a, PadButton::y}, 1); })) == Notes{{60, 64, 67}});
    rig.at(4, [](GamepadFrame &f) { hold(f, {PadButton::y}, 1); });
    CHECK(!rig.layout.line().isSounding());
    CHECK(sounded(rig.at(5, [](GamepadFrame &f) { hold(f, {PadButton::y}, 0); })) == Notes{{71, 74, 77}});
}

TEST_CASE("the d-pad revoices the chord held") {
    Rig rig(FaceChords{});
    rig.at(1, [](GamepadFrame &f) { hold(f, {PadButton::a}); });
    CHECK(sounded(rig.at(2, [](GamepadFrame &f) { hold(f, {PadButton::a, PadButton::up}); })) == Notes{{72, 76, 79}});
}

TEST_CASE("the menu lets go, and a button still down when it closes strikes nothing") {
    Desk desk(SoundCatalog({{"Keys", {{"electricPiano", "Electric Piano"}}}}), DeskSettings(), LayoutKind::faceChords);
    desk.step(GamepadFrame{.time = 1, .buttons = {PadButton::a}});
    CHECK(desk.faceChords().line().isSounding());
    CHECK(silences(desk.step(GamepadFrame{.time = 2, .buttons = {PadButton::a, PadButton::start}})));
    desk.step(GamepadFrame{.time = 3, .buttons = {PadButton::a}});
    desk.step(GamepadFrame{.time = 4, .buttons = {PadButton::a, PadButton::start}});
    CHECK(!desk.menu());
    CHECK(sounded(desk.step(GamepadFrame{.time = 5, .leftTrigger = 1, .buttons = {PadButton::a}})).empty());
    CHECK(!desk.faceChords().line().isSounding());
    CHECK(sounded(desk.step(GamepadFrame{.time = 6})).empty());
    CHECK(!desk.faceChords().line().isSounding());
}

TEST_CASE("Back leaves it silent") {
    Desk desk(SoundCatalog({{"Keys", {{"electricPiano", "Electric Piano"}}}}), DeskSettings(), LayoutKind::faceChords);
    desk.step(GamepadFrame{.time = 1, .buttons = {PadButton::b}});
    CHECK(silences(desk.step(GamepadFrame{.time = 2, .buttons = {PadButton::b, PadButton::back}})));
    CHECK(desk.layout() == LayoutKind::twinRings);
    CHECK(!desk.faceChords().line().isSounding());
}

TEST_CASE("the legend names each chord by number and name, and what LT brings") {
    Rig rig(FaceChords{});
    auto legend = rig.layout.legend(rig.settings);
    CHECK(legend[PadControl::button(PadButton::b)] == "IV · F maj");
    CHECK(legend[PadControl::button(PadButton::y)] == "vii° · B dim");
    CHECK(legend[PadControl::leftTrigger()] == "Hold: ii iii vi");
    rig.at(1, [](GamepadFrame &f) { hold(f, {}, 1); });
    legend = rig.layout.legend(rig.settings);
    CHECK(legend[PadControl::button(PadButton::b)] == "ii · D min");
    CHECK(legend[PadControl::leftTrigger()] == "Let go: IV V vii°");
}

TEST_CASE("with one voice, LB and R3's absence change nothing: LB and a face button play the first voice") {
    Rig rig(FaceChords{});
    const auto out = rig.at(1, [](GamepadFrame &f) { hold(f, {PadButton::lb, PadButton::x}); });
    CHECK(sounded(out) == Notes{{67, 71, 74}});
    CHECK(sounded(out, Line::melody).empty());
}

TEST_CASE("R3 adds a second voice, and LB held plays it alone, an octave over, on the line") {
    Rig rig = withSecond();
    CHECK(rig.layout.hasSecond());
    CHECK(sounded(rig.at(1, [](GamepadFrame &f) { hold(f, {PadButton::a}); })) == Notes{{60, 64, 67}});
    const auto out = rig.at(2, [](GamepadFrame &f) { hold(f, {PadButton::a, PadButton::lb, PadButton::x}); });
    CHECK(sounded(out).empty());
    CHECK(sounded(out, Line::melody) == Notes{{79, 83, 86}});
    CHECK(rig.layout.heard() == std::pair(PadButton::a, Degree::I));
    CHECK(rig.layout.voices()[1].heard() == std::pair(PadButton::x, Degree::V));
    // Letting LB go leaves the press where it went.
    CHECK(rig.at(3, [](GamepadFrame &f) { hold(f, {PadButton::a, PadButton::x}); }).empty());
    const auto up = rig.at(4, [](GamepadFrame &f) { hold(f, {PadButton::a}); });
    CHECK(silencesOver(up));
    CHECK(!silences(up));
}

TEST_CASE("without LB, a press with the second voice added is the first's") {
    Rig rig = withSecond();
    const auto out = rig.at(1, [](GamepadFrame &f) { hold(f, {PadButton::b}); });
    CHECK(sounded(out) == Notes{{65, 69, 72}});
    CHECK(sounded(out, Line::melody).empty());
}

TEST_CASE("a double-click of LB plays both voices on every press, and another goes back to one") {
    Rig rig = together();
    CHECK(rig.layout.isTogether());
    auto out = rig.at(1, [](GamepadFrame &f) { hold(f, {PadButton::b}); });
    CHECK(sounded(out) == Notes{{65, 69, 72}});
    CHECK(sounded(out, Line::melody) == Notes{{77, 81, 84}});
    out = rig.at(1.5, [](GamepadFrame &f) { hold(f, {}); });
    CHECK(silences(out));
    CHECK(silencesOver(out));
    rig.at(2, [](GamepadFrame &f) { hold(f, {PadButton::lb}); });
    rig.at(2.1, [](GamepadFrame &f) { hold(f, {}); });
    rig.at(2.2, [](GamepadFrame &f) { hold(f, {PadButton::lb}); });
    rig.at(2.3, [](GamepadFrame &f) { hold(f, {}); });
    CHECK_FALSE(rig.layout.isTogether());
    CHECK(sounded(rig.at(3, [](GamepadFrame &f) { hold(f, {PadButton::b}); }), Line::melody).empty());
}

TEST_CASE("two presses of LB too far apart are no double-click") {
    Rig rig = withSecond();
    rig.at(1, [](GamepadFrame &f) { hold(f, {PadButton::lb}); });
    rig.at(1.1, [](GamepadFrame &f) { hold(f, {}); });
    rig.at(1.1 + FaceChords::doubleClick + 0.05, [](GamepadFrame &f) { hold(f, {PadButton::lb}); });
    CHECK_FALSE(rig.layout.isTogether());
}

TEST_CASE("with both on, LB and a face button play the second voice over the first") {
    Rig rig = together();
    rig.at(1, [](GamepadFrame &f) { hold(f, {PadButton::a}); });
    const auto out = rig.at(2, [](GamepadFrame &f) { hold(f, {PadButton::a, PadButton::lb, PadButton::x}); });
    CHECK(sounded(out).empty());
    CHECK(sounded(out, Line::melody) == Notes{{79, 83, 86}});
    // Letting X go hands the second voice back to A beneath it.
    CHECK(sounded(rig.at(3, [](GamepadFrame &f) { hold(f, {PadButton::a}); }), Line::melody) == Notes{{72, 76, 79}});
}

TEST_CASE("with both on, LT and a face button together play that button's LT chord over the first, which keeps its own") {
    Rig rig = together();
    rig.at(1, [](GamepadFrame &f) { hold(f, {PadButton::b}); });
    // LT a moment before Y: the pull moves the first voice at first, as a
    // pull alone does, and then Y with it makes the pull the second voice's.
    auto out = rig.at(2, [](GamepadFrame &f) { hold(f, {PadButton::b}, 1); });
    CHECK(sounded(out) == Notes{{62, 65, 69}});
    out = rig.at(2.04, [](GamepadFrame &f) { hold(f, {PadButton::b, PadButton::y}, 1); });
    CHECK(rig.layout.isOverPull());
    CHECK(sounded(out) == Notes{{65, 69, 72}});
    CHECK(sounded(out, Line::melody) == Notes{{81, 84, 88}});
    CHECK(rig.layout.heard() == std::pair(PadButton::b, Degree::IV));
    CHECK(rig.layout.voices()[1].heard() == std::pair(PadButton::y, Degree::vi));
    // Letting LT go ends the pull: the second voice is Y without it.
    out = rig.at(3, [](GamepadFrame &f) { hold(f, {PadButton::b, PadButton::y}); });
    CHECK_FALSE(rig.layout.isOverPull());
    CHECK(sounded(out).empty());
    CHECK(sounded(out, Line::melody) == Notes{{83, 86, 89}});
}

TEST_CASE("with both on, a face button and LT just after are struck together, the first voice going back") {
    Rig rig = together();
    rig.at(1, [](GamepadFrame &f) { hold(f, {PadButton::b}); });
    auto out = rig.at(2, [](GamepadFrame &f) { hold(f, {PadButton::b, PadButton::y}); });
    CHECK(sounded(out) == Notes{{71, 74, 77}});
    out = rig.at(2 + FaceChords::together - 0.01, [](GamepadFrame &f) { hold(f, {PadButton::b, PadButton::y}, 1); });
    CHECK(sounded(out) == Notes{{65, 69, 72}});
    CHECK(sounded(out, Line::melody) == Notes{{81, 84, 88}});
    CHECK(rig.layout.voices()[0].held == std::vector<PadButton>{PadButton::b});
}

TEST_CASE("with both on, LT pulled later while a button is held switches both voices' chord") {
    Rig rig = together();
    rig.at(1, [](GamepadFrame &f) { hold(f, {PadButton::b}); });
    const auto out = rig.at(1 + FaceChords::together + 0.1, [](GamepadFrame &f) { hold(f, {PadButton::b}, 1); });
    CHECK_FALSE(rig.layout.isOverPull());
    CHECK(sounded(out) == Notes{{62, 65, 69}});
    CHECK(sounded(out, Line::melody) == Notes{{74, 77, 81}});
}

TEST_CASE("with both on, a press with LT held from before plays both voices in its layer") {
    Rig rig = together();
    rig.at(1, [](GamepadFrame &f) { hold(f, {}, 1); });
    const auto out = rig.at(2, [](GamepadFrame &f) { hold(f, {PadButton::x}, 1); });
    CHECK(sounded(out) == Notes{{64, 67, 71}});
    CHECK(sounded(out, Line::melody) == Notes{{76, 79, 83}});
}

TEST_CASE("with one voice, LT and a face button together play the first voice's LT chord, as before") {
    Rig rig = withSecond();
    rig.at(1, [](GamepadFrame &f) { hold(f, {}, 1); });
    const auto out = rig.at(1.02, [](GamepadFrame &f) { hold(f, {PadButton::x}, 1); });
    CHECK(sounded(out) == Notes{{64, 67, 71}});
    CHECK(sounded(out, Line::melody).empty());
}

TEST_CASE("R3 again takes the second voice away, silencing it") {
    Rig rig = together();
    rig.at(1, [](GamepadFrame &f) { hold(f, {PadButton::a}); });
    const auto out = rig.at(2, [](GamepadFrame &f) { hold(f, {PadButton::a, PadButton::r3}); });
    CHECK(silencesOver(out));
    CHECK(!silences(out));
    CHECK_FALSE(rig.layout.hasSecond());
    CHECK_FALSE(rig.layout.isTogether());
    CHECK(rig.layout.line().isSounding());
}

TEST_CASE("the d-pad revoices both voices") {
    Rig rig = together();
    rig.at(1, [](GamepadFrame &f) { hold(f, {PadButton::a}); });
    const auto out = rig.at(2, [](GamepadFrame &f) { hold(f, {PadButton::a, PadButton::up}); });
    CHECK(sounded(out) == Notes{{72, 76, 79}});
    CHECK(sounded(out, Line::melody) == Notes{{84, 88, 91}});
}

TEST_CASE("the menu lets go of both voices") {
    Desk desk(SoundCatalog({{"Keys", {{"electricPiano", "Electric Piano"}}}}), DeskSettings(), LayoutKind::faceChords);
    desk.step(GamepadFrame{.time = 0.1, .buttons = {PadButton::r3}});
    desk.step(GamepadFrame{.time = 0.2});
    desk.step(GamepadFrame{.time = 1, .buttons = {PadButton::a}});
    desk.step(GamepadFrame{.time = 2, .buttons = {PadButton::a, PadButton::lb, PadButton::x}});
    CHECK(desk.pinnable() == DeskChord(Key{PitchClass::C, ScaleType::major}, Degree::I));
    const auto out = desk.step(GamepadFrame{.time = 3, .buttons = {PadButton::a, PadButton::x, PadButton::start}});
    CHECK(silences(out));
    CHECK(silencesOver(out));
    CHECK(desk.faceChords().hasSecond());
}

TEST_CASE("the legend says what R3 and LB do for the voices") {
    Rig rig(FaceChords{});
    auto legend = rig.layout.legend(rig.settings);
    CHECK(legend[PadControl::button(PadButton::r3)] == "Add a second voice");
    CHECK(!legend.contains(PadControl::button(PadButton::lb)));
    rig = withSecond();
    legend = rig.layout.legend(rig.settings);
    CHECK(legend[PadControl::button(PadButton::r3)] == "Take away voice 2");
    CHECK(legend[PadControl::button(PadButton::lb)] == "Hold: voice 2 · double-click: both");
    rig = together();
    legend = rig.layout.legend(rig.settings);
    CHECK(legend[PadControl::button(PadButton::lb)] == "Hold: voice 2 over · double-click: voice 1");
    CHECK(legend[PadControl::leftTrigger()] == "Hold: ii iii vi · with a face: voice 2");
}


TEST_CASE("a degree's color strikes its chord colored, and a new color is heard tied") {
    Rig rig(FaceChords{});
    rig.layout.setColors({{Degree::I, ChordColor::joystick(JoystickMode::default_, JoystickDirection::right)}});
    CHECK(sounded(rig.at(1, [](GamepadFrame &f) { hold(f, {PadButton::a}); })) == Notes{{60, 64, 67, 71}});
    rig.layout.setColors({{Degree::I, ChordColor::joystick(JoystickMode::default_, JoystickDirection::upRight)}});
    const auto out = rig.at(2);
    REQUIRE(out.size() == 1);
    CHECK(out[0] == DeskEffect::sound(Line::chord, {60, 64, 67, 70}, "electricPiano", 0.8, 1, true));
    // Another degree's color leaves this one plain.
    rig.layout.setColors({{Degree::IV, ChordColor::joystick(JoystickMode::default_, JoystickDirection::right)}});
    CHECK(sounded(rig.at(3)) == Notes{{60, 64, 67}});
    CHECK(rig.at(4).empty());
}

}
