// Ported from Tests/DeskCoreTests/Helpers.swift: what the layouts' tests
// share.

#ifndef PERFECTO_DESK_TESTS_RIG_HPP
#define PERFECTO_DESK_TESTS_RIG_HPP

#include "perfecto/desk/layout.hpp"
#include "perfecto/desk/music.hpp"
#include "perfecto/desk/pad.hpp"

#include <cmath>
#include <functional>
#include <numbers>
#include <utility>
#include <vector>

namespace perfecto::desk::testing {

/// A stick leaning towards `bearing` (degrees clockwise from up), `radius` out.
inline Stick lean(double bearing, double radius = 1) {
    const double radians = bearing * std::numbers::pi / 180;
    return Stick{std::sin(radians) * radius, std::cos(radians) * radius};
}

/// Steps a layout through frames, keeping the frame before.
template <class L> struct Rig {
    L layout;
    DeskSettings settings;
    GamepadFrame last = GamepadFrame{.time = 0};

    explicit Rig(L layout) : layout(std::move(layout)) {}

    std::vector<DeskEffect> step(const GamepadFrame &frame) {
        auto effects = layout.step(PadInput(frame, last), settings);
        last = frame;
        return effects;
    }

    /// The frame before, at `time`, changed by `change`.
    std::vector<DeskEffect> at(double time, const std::function<void(GamepadFrame &)> &change = {}) {
        GamepadFrame frame = last;
        frame.time = time;
        if (change) change(frame);
        return step(frame);
    }
};

/// The notes of the chords `effects` sound on `line`, in order.
inline std::vector<std::vector<int>> sounded(const std::vector<DeskEffect> &effects, Line line = Line::chord) {
    std::vector<std::vector<int>> notes;
    for (const DeskEffect &effect : effects)
        if (const auto *sound = std::get_if<DeskEffect::Sound>(&effect.value()); sound && sound->line == line)
            notes.push_back(sound->notes);
    return notes;
}

} // namespace perfecto::desk::testing

#endif
