// A layout is one way of laying the instrument out on the controller
// (docs/gamepad-desk-ui.md's models). Each is a value stepped by frames:
// input and state in, new state and effects out, so the shell only feeds it
// frames and performs what it returns.
//
// Swift's `Layout` protocol has no base class here: every layout has the
// same three members, and `Desk` chooses the layout by its kind.
//
//     std::vector<DeskEffect> step(const PadInput &input, DeskSettings &settings);
//         One frame: what the controller does now, against the settings
//         every layout shares, which it may change.
//     std::vector<DeskEffect> releaseAll();
//         Lets go of everything sounding and held: the layout is left, or
//         the menu opens over it.
//     Legend legend(const DeskSettings &settings) const;
//         What every control does now.

#ifndef PERFECTO_DESK_LAYOUT_HPP
#define PERFECTO_DESK_LAYOUT_HPP

#include "perfecto/desk/music.hpp"
#include "perfecto/desk/pad.hpp"

#include <perfecto/theory/key.hpp>

#include <array>
#include <optional>
#include <string>
#include <vector>

namespace perfecto::desk {

enum class LayoutKind { twinRings, petals, neighbourhood, twoVoices, arranger };

inline constexpr std::array<LayoutKind, 5> allLayoutKinds = {LayoutKind::twinRings, LayoutKind::petals,
                                                             LayoutKind::neighbourhood, LayoutKind::twoVoices,
                                                             LayoutKind::arranger};

/// "Twin Rings", "Petals & Depth".
std::string name(LayoutKind kind);

/// What it is for, in a line.
std::string summary(LayoutKind kind);

/// What every playing layout does with the d-pad unless it needs it for
/// something else: left and right roll the inversion, up and down the octave.
/// Returns whether the voicing changed.
bool voicingPad(const PadInput &input, DeskSettings &settings);

/// The legend's entries every layout shares.
Legend commonLegend(const DeskSettings &settings, bool voicing = true);

/// A target a stick can reach, as the screen draws it: named by what it
/// would sound ("V · G7"), with how it sits in the key and whether it is
/// one step from what sounds.
struct Target {
    double bearing;
    /// The chord's name.
    std::string name;
    /// What it is besides its name: a numeral, a mode, a step.
    std::string detail;
    ChordFit fit = ChordFit::inKey;
    /// One step from the chord sounding: the gentle moves.
    bool isNear = false;
    bool isAimed = false;
    bool isKept = false;
    /// Left out by a filter: drawn in its place, but not reached.
    bool isHidden = false;

    bool operator==(const Target &) const = default;
};

/// The degree's numeral in `key`: "V", "ii", "vii°".
std::string numeral(theory::Degree degree, const theory::Key &key);

/// The key's degrees round the left stick, as targets.
std::vector<Target> degreeTargets(theory::Degree chosen, const std::optional<DeskChord> &sounding,
                                  const DeskSettings &settings);

} // namespace perfecto::desk

#endif
