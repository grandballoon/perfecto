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

}
