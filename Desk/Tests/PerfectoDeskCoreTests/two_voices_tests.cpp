// Ported from the "Two voices" suite of Tests/DeskCoreTests/LayoutTests.swift.

#include <doctest.h>

#include "perfecto/desk/two_voices.hpp"
#include "rig.hpp"

#include <algorithm>
#include <optional>
#include <vector>

using namespace perfecto::desk;
using namespace perfecto::desk::testing;
using namespace perfecto::theory;

TEST_SUITE("Two voices") {

TEST_CASE("LT swells the chord") {
    Rig rig{TwoVoices()};
    rig.at(1, [](GamepadFrame &f) { f.leftTrigger = 0.2; });
    const auto out = rig.at(1.02, [](GamepadFrame &f) { f.leftTrigger = 0.2; });
    CHECK(sounded(out) == std::vector<std::vector<int>>{{60, 64, 67}});
    const auto result11 = rig.at(1.5, [](GamepadFrame &f) { f.leftTrigger = 1; });
    CHECK(std::ranges::find(result11, DeskEffect::shape(Line::chord, 1, 1, 0)) != result11.end());
}

TEST_CASE("RT plays the note pointed at and slides") {
    Rig rig{TwoVoices()};
    rig.at(1, [](GamepadFrame &f) { f.right = lean(0, 0.7); });
    const auto struck = rig.at(1.1, [](GamepadFrame &f) { f.rightTrigger = 1; });
    CHECK(sounded(struck, Line::melody) == std::vector<std::vector<int>>{{72}});
    // E is two petals clockwise: the held note slides up four semitones.
    const auto slid = rig.at(1.3, [](GamepadFrame &f) { f.right = lean(2 * 360.0 / 7, 0.7); });
    CHECK(std::ranges::any_of(slid, [](const DeskEffect &effect) {
        const auto *shape = std::get_if<DeskEffect::Shape>(&effect.value());
        return shape && shape->line == Line::melody && shape->bend == 4;
    }));
}

TEST_CASE("chord tones only leaves out the rest") {
    Rig rig{TwoVoices()};
    rig.at(1, [](GamepadFrame &f) { f.buttons = {PadButton::y}; });
    std::vector<int> reachable;
    for (const auto &petal : rig.layout.petals(rig.settings))
        if (petal.isReachable) reachable.push_back(petal.note);
    CHECK(reachable == std::vector<int>{72, 76, 79});
}

TEST_CASE("the bar comes to rest in tune") {
    Rig rig{TwoVoices()};
    rig.at(1, [](GamepadFrame &f) {
        f.buttons = {PadButton::rb};
        f.right = Stick{0, 0.03};
    });
    rig.at(1.01, [](GamepadFrame &f) { f.rightTrigger = 1; });
    rig.at(1.05, [](GamepadFrame &f) { f.rightTrigger = 1; });
    rig.at(1.3, [](GamepadFrame &f) { f.rightTrigger = 1; });
    CHECK(rig.layout.melody().pitch() == std::optional<double>(84));
}

}
