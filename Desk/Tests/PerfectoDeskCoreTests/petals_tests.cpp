// Ported from Tests/DeskCoreTests/LayoutTests.swift ("Petals and depth"),
// and from Tests/DeskCoreTests/RingTests.swift ("The ring's arrangements"):
// `petalsDepthFollowsTheArrangement` and
// `petalsStepsByBrightnessWhateverTheOrder`, which play `Petals`.

#include <doctest.h>

#include "perfecto/desk/music.hpp"
#include "perfecto/desk/petals.hpp"
#include "perfecto/desk/ring_pie.hpp"
#include "rig.hpp"

#include <algorithm>
#include <numeric>
#include <vector>

using namespace perfecto::desk;
using namespace perfecto::desk::testing;
using namespace perfecto::theory;

using Notes = std::vector<std::vector<int>>;

TEST_SUITE("Petals and depth") {

TEST_CASE("the face buttons strike four heights") {
    Rig rig(Petals{});
    const auto result5 = rig.at(1, [](GamepadFrame &f) { f.buttons = {PadButton::a}; });
    CHECK(sounded(result5) == Notes{{60, 64, 67}});
    const auto result6 = rig.at(2, [](GamepadFrame &f) { f.buttons = {PadButton::a, PadButton::x}; });
    CHECK(sounded(result6) == Notes{{60, 64, 67, 71}});
    // Letting go of X hands the chord back to A, beneath it.
    const auto result7 = rig.at(3, [](GamepadFrame &f) { f.buttons = {PadButton::a}; });
    CHECK(sounded(result7) == Notes{{60, 64, 67}});
    const auto result8 = rig.at(4, [](GamepadFrame &f) { f.buttons = {}; });
    CHECK(std::find(result8.begin(), result8.end(), DeskEffect::silence(Line::chord)) != result8.end());
}

TEST_CASE("the triggers bend the mode") {
    Rig rig(Petals{});
    rig.at(1, [](GamepadFrame &f) { f.leftTrigger = 0.3; });
    CHECK(rig.layout.chord(Petals::Petal::height(StackHeight::seventh), rig.settings).name() == "C 7");
    rig.at(2, [](GamepadFrame &f) {
        f.leftTrigger = 0;
        f.rightTrigger = 0.3;
    });
    CHECK(rig.layout.chord(Petals::Petal::height(StackHeight::eleventh), rig.settings).name() == "C maj9♯11");
}

TEST_CASE("LB puts marks on the buttons") {
    Rig rig(Petals{});
    rig.at(1, [](GamepadFrame &f) { f.buttons = {PadButton::lb}; });
    rig.at(2, [](GamepadFrame &f) { f.buttons = {PadButton::lb, PadButton::a}; });
    REQUIRE(rig.layout.line().chord());
    CHECK(rig.layout.line().chord()->name() == "C sus4");
}

TEST_CASE("the right stick bends the voicing and R3 keeps it") {
    Rig rig(Petals{});
    rig.at(1, [](GamepadFrame &f) { f.buttons = {PadButton::a}; });
    const auto result9 = rig.at(2, [](GamepadFrame &f) { f.right = lean(90, 0.6); });
    CHECK(sounded(result9) == Notes{{64, 67, 72}});
    rig.at(3, [](GamepadFrame &f) { f.buttons = {PadButton::a, PadButton::r3}; });
    CHECK(rig.settings.inversion == Inversion::first());
    // Back to the middle, nothing more is bent.
    const auto result10 = rig.at(4, [](GamepadFrame &f) {
        f.right = Stick::rest();
        f.buttons = {PadButton::a};
    });
    CHECK(sounded(result10) == Notes{});
}

}

TEST_SUITE("The ring's arrangements") {

TEST_CASE("Petals' depth follows the arrangement") {
    Rig rig(Petals{});
    rig.settings.ringArrangement = RingArrangement::centred;
    // Pulled all the way, RT is three brighter: past Lydian, centred borrows.
    rig.at(1, [](GamepadFrame &f) { f.rightTrigger = 1; });
    const HeptatonicMode mode = rig.settings.ring(Degree::I).mode(rig.layout.shift());
    CHECK(mode != HeptatonicMode::lydian);
    const auto sum = [](HeptatonicMode m) {
        const auto &steps = intervals(m);
        return std::accumulate(steps.begin(), steps.end(), 0);
    };
    CHECK(sum(mode) >= sum(HeptatonicMode::lydian));
}

TEST_CASE("Petals steps by brightness whatever the order") {
    Rig rig(Petals{});
    rig.settings.ringOrder = RingOrder::common;
    rig.at(1, [](GamepadFrame &f) { f.leftTrigger = 0.3; });
    CHECK(rig.layout.chord(Petals::Petal::height(StackHeight::seventh), rig.settings).name() == "C 7");
}

}
