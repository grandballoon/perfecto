#include "perfecto/desk/inputs.hpp"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <tuple>

namespace perfecto::desk {

namespace Xbox360 {

std::optional<GamepadFrame> frame(const std::vector<std::uint8_t> &report, double time) {
    if (report.size() < 14 || report[0] != 0x00 || report[1] < 0x14) return std::nullopt;
    static const std::tuple<int, std::uint8_t, PadButton> bits[] = {
        {2, 0x01, PadButton::up},    {2, 0x02, PadButton::down}, {2, 0x04, PadButton::left}, {2, 0x08, PadButton::right},
        {2, 0x10, PadButton::start}, {2, 0x20, PadButton::back}, {2, 0x40, PadButton::l3},   {2, 0x80, PadButton::r3},
        {3, 0x01, PadButton::lb},    {3, 0x02, PadButton::rb},
        {3, 0x10, PadButton::a},     {3, 0x20, PadButton::b},    {3, 0x40, PadButton::x},    {3, 0x80, PadButton::y},
    };
    std::set<PadButton> buttons;
    for (const auto &[byte, mask, button] : bits)
        if ((report[static_cast<size_t>(byte)] & mask) != 0) buttons.insert(button);
    const auto axis = [&](size_t at) {
        const auto raw = static_cast<std::int16_t>(static_cast<std::uint16_t>(report[at] | (report[at + 1] << 8)));
        return std::max(-1.0, static_cast<double>(raw) / 32767);
    };
    return GamepadFrame{time,
                        stick(axis(6), axis(8)),
                        stick(axis(10), axis(12)),
                        static_cast<double>(report[4]) / 255,
                        static_cast<double>(report[5]) / 255,
                        std::move(buttons)};
}

Stick stick(double x, double y) {
    const double radius = std::sqrt(x * x + y * y);
    if (!(radius > deadZone)) return Stick::rest();
    const double scale = std::min(1.0, (radius - deadZone) / (1 - deadZone)) / radius;
    return Stick{x * scale, y * scale};
}

std::vector<std::uint8_t> rumble(double low, double high) {
    const auto level = [](double value) {
        return static_cast<std::uint8_t>(std::max(0.0, std::min(1.0, value)) * 255);
    };
    return {0x00, 0x08, 0x00, level(low), level(high), 0x00, 0x00, 0x00};
}

} // namespace Xbox360

namespace KeyboardPad {

const std::map<std::string, PadButton> &buttons() {
    static const std::map<std::string, PadButton> map = {
        {" ", PadButton::a},        {"b", PadButton::b},        {"x", PadButton::x},         {"y", PadButton::y},
        {"q", PadButton::lb},       {"e", PadButton::rb},       {"r", PadButton::l3},        {"o", PadButton::r3},
        {"up", PadButton::up},      {"down", PadButton::down},  {"left", PadButton::left},   {"right", PadButton::right},
        {"return", PadButton::start}, {"tab", PadButton::back},
    };
    return map;
}

std::set<std::string> keys() {
    std::set<std::string> all;
    for (const auto &[key, button] : buttons()) all.insert(key);
    all.insert({leftTrigger, rightTrigger, leftStick.up, leftStick.left, leftStick.down, leftStick.right, rightStick.up,
                rightStick.left, rightStick.down, rightStick.right});
    return all;
}

GamepadFrame frame(const std::set<std::string> &keys, bool shift, double time) {
    const auto stick = [&](const StickKeys &map, double reach) {
        const double x = (keys.contains(map.right) ? 1.0 : 0) - (keys.contains(map.left) ? 1 : 0);
        const double y = (keys.contains(map.up) ? 1.0 : 0) - (keys.contains(map.down) ? 1 : 0);
        const double length = std::sqrt(x * x + y * y);
        return length == 0 ? Stick::rest() : Stick{x / length * reach, y / length * reach};
    };
    std::set<PadButton> held;
    for (const std::string &key : keys) {
        const auto found = buttons().find(key);
        if (found != buttons().end()) held.insert(found->second);
    }
    return GamepadFrame{time,
                        stick(leftStick, 1),
                        stick(rightStick, shift ? 0.62 : 1),
                        keys.contains(leftTrigger) ? 1.0 : 0,
                        keys.contains(rightTrigger) ? 1.0 : 0,
                        std::move(held)};
}

std::string key(const PadControl &control) {
    const auto &value = control.value();
    if (std::holds_alternative<PadControl::LeftStick>(value)) return "WASD";
    if (std::holds_alternative<PadControl::RightStick>(value)) return "IJKL";
    if (std::holds_alternative<PadControl::LeftTrigger>(value)) return "Z";
    if (std::holds_alternative<PadControl::RightTrigger>(value)) return "C";
    const PadButton button = std::get<PadControl::Button>(value).button;
    static const std::map<std::string, std::string> names = {
        {"up", "↑"}, {"down", "↓"}, {"left", "←"}, {"right", "→"}, {"return", "⏎"}, {"tab", "⇥"}, {" ", "Space"},
    };
    // Every button has one key, so which of the map's keys is found first
    // does not matter.
    const auto found = std::find_if(buttons().begin(), buttons().end(),
                                    [&](const auto &entry) { return entry.second == button; });
    const std::string &key = found->first;
    const auto named = names.find(key);
    if (named != names.end()) return named->second;
    std::string upper = key;
    for (char &c : upper) c = static_cast<char>(std::toupper(static_cast<unsigned char>(c)));
    return upper;
}

} // namespace KeyboardPad

} // namespace perfecto::desk
