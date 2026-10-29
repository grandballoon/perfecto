// The joystick's colors: a table of chord shapes for each direction in each
// of three modes, paired with the quality name the player sees. Intervals
// and name live in the same entry so a change to one forces a look at the
// other.

#ifndef PERFECTO_THEORY_JOYSTICK_HPP
#define PERFECTO_THEORY_JOYSTICK_HPP

#include "perfecto/theory/chord_shape.hpp"

#include <array>
#include <string>

namespace perfecto::theory {

enum class JoystickMode { default_, extended, chromatic };

inline constexpr std::array<JoystickMode, 3> allJoystickModes = {
    JoystickMode::default_, JoystickMode::extended, JoystickMode::chromatic,
};

enum class JoystickDirection { center, up, upRight, right, downRight, down, downLeft, left, upLeft };

inline constexpr std::array<JoystickDirection, 9> allJoystickDirections = {
    JoystickDirection::center,   JoystickDirection::up,   JoystickDirection::upRight,
    JoystickDirection::right,    JoystickDirection::downRight, JoystickDirection::down,
    JoystickDirection::downLeft, JoystickDirection::left, JoystickDirection::upLeft,
};

/// What one direction does: a shape for each base triad, and the legend for
/// the ring that describes it whatever the degree ("Dom 7", "Flip 3rd").
struct JoystickOutcome {
    ChordShape major;
    ChordShape minor;
    ChordShape dim;
    std::string action;

    const ChordShape &shape(TriadBase base) const;
};

const JoystickOutcome &joystickOutcome(JoystickMode mode, JoystickDirection direction);

} // namespace perfecto::theory

#endif
