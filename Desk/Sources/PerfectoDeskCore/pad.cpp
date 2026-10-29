#include "perfecto/desk/pad.hpp"

#include <algorithm>
#include <cmath>
#include <iterator>
#include <numbers>

namespace perfecto::desk {

std::string name(PadButton button) {
    switch (button) {
    case PadButton::a: return "A";
    case PadButton::b: return "B";
    case PadButton::x: return "X";
    case PadButton::y: return "Y";
    case PadButton::lb: return "LB";
    case PadButton::rb: return "RB";
    case PadButton::back: return "Back";
    case PadButton::start: return "Start";
    case PadButton::l3: return "L3";
    case PadButton::r3: return "R3";
    case PadButton::up: return "↑";
    case PadButton::down: return "↓";
    case PadButton::left: return "←";
    case PadButton::right: return "→";
    }
    return {};
}

double Stick::radius() const { return std::min(1.0, std::sqrt(x * x + y * y)); }

double Stick::bearing() const {
    const double degrees = std::atan2(x, y) * 180 / std::numbers::pi;
    return degrees < 0 ? degrees + 360 : degrees;
}

GamepadFrame GamepadFrame::untimed() const {
    GamepadFrame frame = *this;
    frame.time = 0;
    return frame;
}

GamepadFrame GamepadFrame::shown() const {
    const auto round = [](double value) { return std::round(value * 100) / 100; };
    return GamepadFrame{0, Stick{round(left.x), round(left.y)}, Stick{round(right.x), round(right.y)},
                        round(leftTrigger), round(rightTrigger), buttons};
}

GamepadFrame GamepadFrame::merged(const GamepadFrame &other) const {
    const auto further = [](const Stick &a, const Stick &b) { return a.radius() >= b.radius() ? a : b; };
    std::set<PadButton> both = buttons;
    both.insert(other.buttons.begin(), other.buttons.end());
    return GamepadFrame{std::max(time, other.time), further(left, other.left), further(right, other.right),
                        std::max(leftTrigger, other.leftTrigger), std::max(rightTrigger, other.rightTrigger),
                        std::move(both)};
}

PadEdges::PadEdges(std::set<PadButton> pressed, std::set<PadButton> released)
    : pressed(std::move(pressed)), released(std::move(released)) {}

PadEdges::PadEdges(const GamepadFrame &previous, const GamepadFrame &frame) {
    std::set_difference(frame.buttons.begin(), frame.buttons.end(), previous.buttons.begin(), previous.buttons.end(),
                        std::inserter(pressed, pressed.end()));
    std::set_difference(previous.buttons.begin(), previous.buttons.end(), frame.buttons.begin(), frame.buttons.end(),
                        std::inserter(released, released.end()));
}

PadInput::PadInput(const GamepadFrame &frame, const GamepadFrame &previous)
    : frame(frame), previous(previous), edges(previous, frame) {}

std::string name(const PadControl &control) {
    const auto &value = control.value();
    if (const auto *button = std::get_if<PadControl::Button>(&value)) return name(button->button);
    if (std::holds_alternative<PadControl::LeftStick>(value)) return "Left stick";
    if (std::holds_alternative<PadControl::RightStick>(value)) return "Right stick";
    if (std::holds_alternative<PadControl::LeftTrigger>(value)) return "LT";
    return "RT";
}

} // namespace perfecto::desk
