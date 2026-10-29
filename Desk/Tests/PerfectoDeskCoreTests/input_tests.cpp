// Ported from Tests/DeskCoreTests/InputTests.swift.

#include <doctest.h>

#include "perfecto/desk/inputs.hpp"

#include <cmath>
#include <cstdint>
#include <utility>
#include <vector>

using namespace perfecto::desk;

namespace {

std::vector<std::uint8_t> report(std::pair<std::uint8_t, std::uint8_t> buttons = {0, 0}, std::uint8_t lt = 0,
                                 std::uint8_t rt = 0, std::int16_t lx = 0, std::int16_t ly = 0, std::int16_t rx = 0,
                                 std::int16_t ry = 0) {
    std::vector<std::uint8_t> out = {0x00, 0x14, buttons.first, buttons.second, lt, rt};
    for (std::int16_t v : {lx, ly, rx, ry}) {
        out.push_back(static_cast<std::uint8_t>(v & 0xFF));
        out.push_back(static_cast<std::uint8_t>((v >> 8) & 0xFF));
    }
    out.insert(out.end(), 6, 0);
    return out;
}

} // namespace

TEST_SUITE("Inputs") {

TEST_CASE("a report's buttons are read") {
    const auto frame = Xbox360::frame(report({0x11, 0x92}), 1);
    REQUIRE(frame);
    CHECK(frame->buttons ==
          std::set<PadButton>{PadButton::up, PadButton::start, PadButton::rb, PadButton::a, PadButton::y});
    CHECK(frame->time == 1);
}

TEST_CASE("a report's sticks and triggers are read") {
    const auto frame = *Xbox360::frame(report({0, 0}, 255, 0, 32767, 0, 0, -32768), 0);
    CHECK(frame.leftTrigger == 1);
    CHECK(frame.rightTrigger == 0);
    CHECK(std::abs(frame.left.x - 1) < 0.001);
    CHECK(std::abs(frame.right.y + 1) < 0.001);
}

TEST_CASE("a stick's loose middle is rest") {
    const auto frame = *Xbox360::frame(report({0, 0}, 0, 0, 6000, -5000), 0);
    CHECK(frame.left == Stick::rest());
}

TEST_CASE("other reports are not frames") {
    CHECK(Xbox360::frame({0x01, 0x03, 0x06}, 0) == std::nullopt);
    std::vector<std::uint8_t> leds = {0x08, 0x03, 0x00};
    leds.insert(leds.end(), 17, 0);
    CHECK(Xbox360::frame(leds, 0) == std::nullopt);
}

TEST_CASE("the keyboard is a controller") {
    const auto frame = KeyboardPad::frame({"w", "d", "l", " ", "c", "up"}, true, 2);
    CHECK(frame.buttons == std::set<PadButton>{PadButton::a, PadButton::up});
    CHECK(frame.rightTrigger == 1);
    CHECK(std::abs(frame.left.bearing() - 45) < 0.001);
    CHECK(std::abs(frame.right.radius() - 0.62) < 0.001);
    CHECK(KeyboardPad::key(PadControl::button(PadButton::a)) == "Space");
}

}
