// A game controller as values: what every stick, trigger and button is
// doing at one moment. The design reference is the Xbox 360 controller
// (docs/gamepad-desk-ui.md, "The hand, as a budget"); any extended gamepad
// has the same controls under other names.

#ifndef PERFECTO_DESK_PAD_HPP
#define PERFECTO_DESK_PAD_HPP

#include <array>
#include <compare>
#include <map>
#include <set>
#include <string>
#include <type_traits>
#include <utility>
#include <variant>

namespace perfecto::desk {

/// A button of the controller, by where it is.
enum class PadButton {
    a, b, x, y,
    /// The bumpers.
    lb, rb,
    /// The small buttons in the middle: Back (View) and Start (Menu).
    back, start,
    /// The sticks, pressed in.
    l3, r3,
    /// The d-pad. Its diagonals are not reliable on a 360, so nothing asks
    /// for them.
    up, down, left, right,
};

inline constexpr std::array<PadButton, 14> allPadButtons = {
    PadButton::a,     PadButton::b,     PadButton::x,  PadButton::y,  PadButton::lb,   PadButton::rb,   PadButton::back,
    PadButton::start, PadButton::l3,    PadButton::r3, PadButton::up, PadButton::down, PadButton::left, PadButton::right,
};

/// "A", "LB", "Back", "↑".
std::string name(PadButton button);

/// A stick's place, each axis from -1 to 1 with right and up positive.
struct Stick {
    double x = 0;
    double y = 0;

    bool operator==(const Stick &) const = default;

    static constexpr Stick rest() { return {}; }

    /// How far from the middle, 0 to 1 (a corner of a square gate is cut
    /// to 1).
    double radius() const;

    /// Which way it leans, as a compass bearing: degrees clockwise from up,
    /// 0 up to 360.
    double bearing() const;
};

/// Everything the controller is doing at `time` (seconds, on any clock that
/// only goes forward).
struct GamepadFrame {
    double time = 0;
    Stick left = Stick::rest();
    Stick right = Stick::rest();
    /// How far each trigger is pulled, 0 to 1.
    double leftTrigger = 0;
    double rightTrigger = 0;
    std::set<PadButton> buttons;

    bool operator==(const GamepadFrame &) const = default;

    bool isDown(PadButton button) const { return buttons.contains(button); }

    /// The frame as if it came at no time: what the controls are doing,
    /// for telling whether anything changed.
    GamepadFrame untimed() const;

    /// The frame with its sticks and triggers to the nearest hundredth: what
    /// a screen can show of it, so a stick's jitter at rest redraws nothing.
    GamepadFrame shown() const;

    /// Two hands' worth of frames as one: the buttons either holds, each
    /// stick and trigger the one leaning or pulled further. How the
    /// computer keyboard and a controller play at once.
    GamepadFrame merged(const GamepadFrame &other) const;
};

/// What changed between two frames: the buttons pressed and let go.
///
/// (Swift's `pressed(_:)` and `released(_:)` are `pressed.contains(_:)` and
/// `released.contains(_:)` here: C++ cannot name a member and a function
/// alike.)
struct PadEdges {
    std::set<PadButton> pressed;
    std::set<PadButton> released;

    PadEdges() = default;
    PadEdges(std::set<PadButton> pressed, std::set<PadButton> released);
    /// The edges from `previous` to `frame`.
    PadEdges(const GamepadFrame &previous, const GamepadFrame &frame);

    bool operator==(const PadEdges &) const = default;
};

/// One step of input for a layout: the frame, what changed since the last,
/// and the frame before it.
struct PadInput {
    GamepadFrame frame;
    GamepadFrame previous;
    PadEdges edges;

    PadInput(const GamepadFrame &frame, const GamepadFrame &previous);

    bool operator==(const PadInput &) const = default;

    double time() const { return frame.time; }
    bool pressed(PadButton button) const { return edges.pressed.contains(button); }
    bool released(PadButton button) const { return edges.released.contains(button); }
    bool isDown(PadButton button) const { return frame.isDown(button); }
};

/// A control of the controller, for saying what each does: a button, or a
/// stick or trigger as a whole.
class PadControl {
public:
    struct Button {
        PadButton button;
        bool operator==(const Button &) const = default;
        auto operator<=>(const Button &) const = default;
    };
    struct LeftStick {
        bool operator==(const LeftStick &) const = default;
        auto operator<=>(const LeftStick &) const = default;
    };
    struct RightStick {
        bool operator==(const RightStick &) const = default;
        auto operator<=>(const RightStick &) const = default;
    };
    struct LeftTrigger {
        bool operator==(const LeftTrigger &) const = default;
        auto operator<=>(const LeftTrigger &) const = default;
    };
    struct RightTrigger {
        bool operator==(const RightTrigger &) const = default;
        auto operator<=>(const RightTrigger &) const = default;
    };

    using Value = std::variant<Button, LeftStick, RightStick, LeftTrigger, RightTrigger>;

    template <class Alternative>
        requires std::is_constructible_v<Value, Alternative>
    PadControl(Alternative alternative) : value_(std::move(alternative)) {}

    static PadControl button(PadButton button) { return Button{button}; }
    static PadControl leftStick() { return LeftStick{}; }
    static PadControl rightStick() { return RightStick{}; }
    static PadControl leftTrigger() { return LeftTrigger{}; }
    static PadControl rightTrigger() { return RightTrigger{}; }

    const Value &value() const { return value_; }

    bool operator==(const PadControl &) const = default;
    /// An order of its own, so a legend can be a `std::map`: Swift's is a
    /// dictionary, with none.
    auto operator<=>(const PadControl &) const = default;

private:
    Value value_;
};

/// "A", "Left stick", "LT".
std::string name(const PadControl &control);

/// What every control does now, for the screen to show the hand
/// ("The screen shows the hand").
using Legend = std::map<PadControl, std::string>;

} // namespace perfecto::desk

#endif
