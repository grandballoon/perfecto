// The ways a frame is made, as pure functions of what the hardware says:
// a wired Xbox 360 controller's USB report, and the computer keyboard
// standing in for a controller. The shell reads the hardware and asks these
// what it means.

#ifndef PERFECTO_DESK_INPUTS_HPP
#define PERFECTO_DESK_INPUTS_HPP

#include "perfecto/desk/pad.hpp"

#include <cstdint>
#include <map>
#include <optional>
#include <set>
#include <string>
#include <vector>

namespace perfecto::desk {

/// A wired Xbox 360 controller, read from its USB reports. macOS has no
/// driver for it (GameController sees Xbox One and Series controllers, not
/// the 360), so the shell reads its interrupt endpoint itself and these
/// bytes are what it reads.
namespace Xbox360 {

inline constexpr int vendor = 0x045E;
/// The wired controller. The wireless one comes through a receiver that
/// speaks another protocol.
inline constexpr int product = 0x028E;

/// How far a 360's stick wanders from the middle at rest, of its reach.
inline constexpr double deadZone = 0.24;

/// The frame a 20-byte input report says, at `time`; none for a report of
/// another kind (the controller also reports its LEDs and headset).
std::optional<GamepadFrame> frame(const std::vector<std::uint8_t> &report, double time);

/// A stick with its loose middle taken out: nothing inside the dead
/// zone, and the rest stretched to the whole reach.
Stick stick(double x, double y);

/// The output report that spins the motors: the heavy low one on the
/// left, the light high one on the right, each 0 to 1.
std::vector<std::uint8_t> rumble(double low, double high);

/// The output report that lights the ring's first quarter: player one.
inline const std::vector<std::uint8_t> playerOne = {0x01, 0x03, 0x06};

} // namespace Xbox360

/// The computer keyboard as a controller, so every layout can be tried
/// without one: WASD the left stick, IJKL the right (Shift holds it half
/// out, for the inner ring), the arrows the d-pad, Space A.
namespace KeyboardPad {

/// The four keys that lean a stick.
struct StickKeys {
    std::string up;
    std::string left;
    std::string down;
    std::string right;
};

/// Each key's control, by the character it types (lowercased) or its
/// name for keys that type none.
const std::map<std::string, PadButton> &buttons();
inline const std::string leftTrigger = "z";
inline const std::string rightTrigger = "c";
inline const StickKeys leftStick = {"w", "a", "s", "d"};
inline const StickKeys rightStick = {"i", "j", "k", "l"};

/// Every key the map reads.
std::set<std::string> keys();

/// What the keys held mean at `time`.
GamepadFrame frame(const std::set<std::string> &keys, bool shift, double time);

/// The key that stands for each control, for the screen's legend.
std::string key(const PadControl &control);

} // namespace KeyboardPad

} // namespace perfecto::desk

#endif
