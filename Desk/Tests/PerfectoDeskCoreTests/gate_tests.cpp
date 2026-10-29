// Ported from Tests/DeskCoreTests/GateTests.swift.

#include <doctest.h>

#include "perfecto/desk/gates.hpp"
#include "rig.hpp"

#include <vector>

using namespace perfecto::desk;
using perfecto::desk::testing::lean;

TEST_SUITE("Gates") {

TEST_CASE("a pie chooses the nearest target") {
    const PieGate pie = PieGate::even(7);
    CHECK(pie.select(lean(0), std::nullopt) == 0);
    CHECK(pie.select(lean(52), std::nullopt) == 1);
    CHECK(pie.select(lean(350), std::nullopt) == 0);
    CHECK((pie.select(lean(180), std::nullopt) == 3 || pie.select(lean(180), std::nullopt) == 4));
}

TEST_CASE("a pie chooses nothing in the middle") {
    const PieGate pie = PieGate::even(4);
    CHECK(pie.select(lean(0, 0.4), std::nullopt) == std::nullopt);
    // Once chosen, it holds until the stick is further in.
    CHECK(pie.select(lean(0, 0.4), 0) == 0);
    CHECK(pie.select(lean(0, 0.3), 0) == std::nullopt);
}

TEST_CASE("a pie holds on past its edge") {
    const PieGate pie = PieGate::even(4);
    // 45° is the edge between up and right.
    CHECK(pie.select(lean(48), 0) == 0);
    CHECK(pie.select(lean(48), std::nullopt) == 1);
    CHECK(pie.select(lean(55), 0) == 1);
}

TEST_CASE("a pie with a gap chooses nothing there") {
    const PieGate pie({-30, 0, 30}, 15);
    CHECK(pie.select(lean(180), std::nullopt) == std::nullopt);
    CHECK(pie.select(lean(40), std::nullopt) == 2);
}

TEST_CASE("bands are read outwards and hold") {
    const RadialBands &bands = RadialBands::three();
    CHECK(bands.band(0.6, std::nullopt) == 0);
    CHECK(bands.band(0.8, std::nullopt) == 1);
    CHECK(bands.band(0.95, std::nullopt) == 2);
    CHECK(bands.band(0.69, 1) == 1);
    CHECK(bands.band(0.6, 1) == 0);
}

TEST_CASE("a fast pull strikes louder than a slow one") {
    TriggerStrike fast;
    const auto result1 = fast.step(0.1, 0);
    CHECK(result1.empty());
    const auto loud = fast.step(0.7, 0.016);
    TriggerStrike slow;
    (void)slow.step(0.1, 0);
    const auto soft = slow.step(0.15, 0.016);
    const auto *high = loud.empty() ? nullptr : std::get_if<TriggerStrike::Strike>(&loud.front());
    const auto *low = soft.empty() ? nullptr : std::get_if<TriggerStrike::Strike>(&soft.front());
    REQUIRE_MESSAGE((high && low), "both strike");
    CHECK(high->level > low->level);
    CHECK(low->level >= TriggerStrike::softest);
}

TEST_CASE("a strike is held and let go") {
    TriggerStrike trigger;
    (void)trigger.step(1, 0);
    CHECK(trigger.isHeld());
    const auto result2 = trigger.step(0.5, 0.1);
    CHECK(result2 == std::vector<TriggerStrike::Event>{TriggerStrike::Depth{0.5}});
    const auto result3 = trigger.step(0.02, 0.2);
    CHECK(result3 == std::vector<TriggerStrike::Event>{TriggerStrike::Release{}});
    CHECK(!trigger.isHeld());
}

TEST_CASE("trigger steps hold at their edges") {
    const TriggerSteps &steps = TriggerSteps::three();
    CHECK(steps.step(0.1, 0) == 0);
    CHECK(steps.step(0.2, 0) == 1);
    CHECK(steps.step(0.12, 1) == 1);
    CHECK(steps.step(0.05, 1) == 0);
    CHECK(steps.step(0.9, 0) == 3);
}

TEST_CASE("a flick keeps and a hold lets go") {
    using Events = std::vector<StickGesture::Event>;
    const PieGate pie = PieGate::even(8);
    StickGesture flick;
    const auto result4 = flick.step(lean(90), pie, 0);
    CHECK(result4 == Events{StickGesture::Aim{2}});
    const auto result5 = flick.step(Stick::rest(), pie, 0.1);
    CHECK(result5 == Events{StickGesture::Flick{2}});

    StickGesture hold;
    (void)hold.step(lean(90), pie, 0);
    const auto result6 = hold.step(lean(90), pie, 0.5);
    CHECK(result6.empty());
    const auto result7 = hold.step(Stick::rest(), pie, 0.6);
    CHECK(result7 == Events{StickGesture::Lift{2}});
}

TEST_CASE("a tap is quick and unused") {
    TapOrHold tap;
    tap.press(0);
    const bool result8 = tap.release(0.2);
    CHECK(result8);
    tap.press(1);
    tap.use();
    const bool result9 = tap.release(1.1);
    CHECK(!result9);
    tap.press(2);
    const bool result10 = tap.release(3);
    CHECK(!result10);
}

}
