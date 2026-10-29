// Which chord to play, independent of key and voicing: a scale degree and
// how its base triad is colored.

#ifndef PERFECTO_THEORY_CHORD_COLOR_HPP
#define PERFECTO_THEORY_CHORD_COLOR_HPP

#include "perfecto/theory/chord_build.hpp"
#include "perfecto/theory/chord_tones.hpp"
#include "perfecto/theory/joystick.hpp"
#include "perfecto/theory/key.hpp"
#include "perfecto/theory/modes.hpp"
#include "perfecto/theory/tertian.hpp"
#include "perfecto/theory/tone_marks.hpp"

#include <optional>
#include <type_traits>
#include <variant>

namespace perfecto::theory {

/// How a degree's base triad is transformed into the chord that sounds.
/// Each input surface contributes a kind, so the rest of the app depends on
/// "a color" rather than on any one surface's coordinates.
class ChordColor {
public:
    /// A direction on the joystick in one of its three modes.
    struct Joystick {
        JoystickMode mode;
        JoystickDirection direction;
        bool operator==(const Joystick &) const = default;
        auto operator<=>(const Joystick &) const = default;
    };
    /// A cell of the chord grid: thirds stacked to `height` through `mode`.
    /// No mode is the degree's own diatonic mode, so the chord follows the
    /// key (C major ii stacks through Dorian, C minor ii through Locrian); a
    /// named mode is the same chord quality in every key.
    struct Grid {
        StackHeight height;
        std::optional<HeptatonicMode> mode;
        bool operator==(const Grid &) const = default;
        auto operator<=>(const Grid &) const = default;
    };
    /// A grid color with marks on its tones: some moved a semitone, some
    /// left out or brought back. With no marks it is the grid color
    /// (`tertian`), so this kind always has some.
    struct Marked {
        StackHeight height;
        std::optional<HeptatonicMode> mode;
        ToneMarks marks;
        bool operator==(const Marked &) const = default;
        auto operator<=>(const Marked &) const = default;
    };
    /// A chord built from buttons: a type and extensions, the same chord on
    /// every root unless it has no type.
    using Built = ChordBuild;
    /// A chord given by its tones above the root: what the step compass
    /// makes, a few steps from the degree's triad. It is the same chord on
    /// every degree.
    using Tones = ChordTones;

    using Value = std::variant<Joystick, Grid, Marked, Built, Tones>;

    template <class Alternative>
        requires std::is_constructible_v<Value, Alternative>
    ChordColor(Alternative alternative) : value_(std::move(alternative)) {}

    static ChordColor joystick(JoystickMode mode, JoystickDirection direction) { return Joystick{mode, direction}; }
    static ChordColor grid(StackHeight height, std::optional<HeptatonicMode> mode = std::nullopt) {
        return Grid{height, mode};
    }
    static ChordColor marked(StackHeight height, std::optional<HeptatonicMode> mode, ToneMarks marks) {
        return Marked{height, mode, std::move(marks)};
    }
    static ChordColor built(ChordBuild build) { return std::move(build); }
    static ChordColor tones(ChordTones tones) { return std::move(tones); }

    /// Thirds stacked to `height` through `mode` with `marks`: a grid color
    /// when there are no marks.
    static ChordColor tertian(StackHeight height, std::optional<HeptatonicMode> mode, const ToneMarks &marks);

    /// The unmodified base triad.
    static ChordColor base() { return joystick(JoystickMode::default_, JoystickDirection::center); }

    const Value &value() const { return value_; }

    bool operator==(const ChordColor &) const = default;
    auto operator<=>(const ChordColor &) const = default;

    /// Whether the color leaves the base triad unchanged.
    bool isBase() const;

    /// The joystick direction that gives the color in `mode`, or none if
    /// none does: the base triad, another mode's color, or a cell of the
    /// grid.
    std::optional<JoystickDirection> direction(JoystickMode mode) const;

private:
    Value value_;
};

/// Which chord to play, independent of key and voicing: a scale degree and
/// how its base triad is colored. The key comes from the performance
/// context; octave, inversion and voice leading are voicing choices applied
/// afterwards by `computeVoicing`.
struct ChordSpec {
    Degree degree;
    ChordColor color;

    bool operator==(const ChordSpec &) const = default;
    auto operator<=>(const ChordSpec &) const = default;
};

} // namespace perfecto::theory

#endif
