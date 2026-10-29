// ChordLink wire protocol v1: the semantic chord announcement Perfecto
// broadcasts alongside plain MIDI notes, encoded as a SysEx frame so it
// travels over any MIDI transport and is ignored by receivers that only want
// notes. Both directions live here so the frame layout is testable as a
// round trip. The wire numbering is fixed by explicit tables, never by enum
// declaration order. The full spec (shared with Harmonicland) is in
// chordlink.md.

#ifndef PERFECTO_THEORY_CHORD_WIRE_HPP
#define PERFECTO_THEORY_CHORD_WIRE_HPP

#include "perfecto/theory/chord_color.hpp"
#include "perfecto/theory/joystick.hpp"
#include "perfecto/theory/key.hpp"
#include "perfecto/theory/voicing.hpp"

#include <array>
#include <cstdint>
#include <optional>
#include <variant>
#include <vector>

namespace perfecto::theory {

/// Everything a receiver needs to reconstruct the musical intent of one
/// chord event: the selection context plus the exact voicing that sounded.
struct ChordAnnouncement {
    Key key;
    Degree degree;
    JoystickMode joystickMode;
    JoystickDirection joystickDirection;
    Inversion inversion;
    int octave;
    bool voiceLeading;
    Voicing voicing;

    bool operator==(const ChordAnnouncement &) const = default;
};

namespace ChordWire {

/// A decoded release frame.
struct Release {
    bool operator==(const Release &) const = default;
};

/// A decoded frame: either a chord with full context, or a release.
using Frame = std::variant<ChordAnnouncement, Release>;

inline constexpr std::uint8_t sysExStart = 0xF0;
inline constexpr std::uint8_t sysExEnd = 0xF7;

// Wire numbering tables. Order here IS the protocol; do not reorder.
inline constexpr std::array<ScaleType, 10> scaleOrder = {
    ScaleType::major,           ScaleType::naturalMinor,    ScaleType::harmonicMinor, ScaleType::melodicMinor,
    ScaleType::majorPentatonic, ScaleType::minorPentatonic, ScaleType::blues,         ScaleType::dorian,
    ScaleType::mixolydian,      ScaleType::lydian,
};
inline constexpr std::array<JoystickMode, 3> modeOrder = {JoystickMode::default_, JoystickMode::extended,
                                                         JoystickMode::chromatic};
inline constexpr std::array<JoystickDirection, 9> directionOrder = {
    JoystickDirection::center,   JoystickDirection::up,   JoystickDirection::upRight,
    JoystickDirection::right,    JoystickDirection::downRight, JoystickDirection::down,
    JoystickDirection::downLeft, JoystickDirection::left, JoystickDirection::upLeft,
};
/// The inversions a frame can state. A chord rolled further is restated as
/// one of them (`stated`).
inline constexpr std::array<Inversion, 3> inversionOrder = {Inversion::root(), Inversion::first(),
                                                           Inversion::second()};
/// Wire value = index + 1 (I = 1 … vii° = 7).
inline constexpr std::array<Degree, 7> degreeOrder = {Degree::I, Degree::ii, Degree::iii, Degree::IV,
                                                     Degree::V, Degree::vi, Degree::viiDim};
inline constexpr int octaveLow = 0;
inline constexpr int octaveHigh = 8;

std::vector<std::uint8_t> encodeChord(const ChordAnnouncement &announcement);
std::vector<std::uint8_t> encodeRelease();

struct Stated {
    Inversion inversion;
    int octave;
    bool operator==(const Stated &) const = default;
};

/// The inversion and octave a frame states for the chord `spec` in `key`,
/// rolled to `inversion` in `octave`. A frame has only the inversions of
/// `inversionOrder`, so a chord rolled further is stated as the one of them,
/// in whichever octave, that has the same notes; none when none has, and
/// the chord cannot be announced.
std::optional<Stated> stated(Inversion inversion, int octave, const Key &key, const ChordSpec &spec);

/// None for anything that is not a well-formed ChordLink v1 frame: foreign
/// SysEx, truncated payloads, and out-of-range fields are all rejected
/// rather than partially interpreted.
std::optional<Frame> decode(const std::vector<std::uint8_t> &bytes);

} // namespace ChordWire

} // namespace perfecto::theory

#endif
