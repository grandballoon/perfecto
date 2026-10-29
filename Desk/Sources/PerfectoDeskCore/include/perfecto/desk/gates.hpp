// The controller's analog surfaces read as choices: a stick as a pie of
// targets and rings of radius, a trigger as a strike or as steps. Every one
// holds on to what it chose a little past its edges, so a resting thumb or
// finger cannot flicker between two.

#ifndef PERFECTO_DESK_GATES_HPP
#define PERFECTO_DESK_GATES_HPP

#include "perfecto/desk/pad.hpp"

#include <optional>
#include <variant>
#include <vector>

namespace perfecto::desk {

/// A stick read as a pie: targets at bearings round the middle, the one the
/// stick leans towards chosen.
struct PieGate {
    /// Each target's bearing, degrees clockwise from up.
    std::vector<double> bearings;
    /// How far either side of its bearing a target reaches, in degrees.
    /// Past every target's reach is a gap, which chooses nothing.
    double width;

    /// How far out the stick has to lean to choose, of its whole reach, and
    /// how far in it comes before it lets go.
    static constexpr double reach = 0.5;
    static constexpr double rest = 0.35;
    /// How far past the line between two targets the stick has to turn to
    /// leave the one it is on, in degrees.
    static constexpr double hold = 6.0;

    /// With no width, each target reaches half way round (all the way, for
    /// one alone).
    explicit PieGate(std::vector<double> bearings, std::optional<double> width = std::nullopt);

    bool operator==(const PieGate &) const = default;

    /// `count` targets evenly round the whole circle, the first at `first`.
    static PieGate even(int count, double first = 0);

    /// The target `stick` chooses, given the one it was on; none in the
    /// middle or in a gap.
    std::optional<int> select(const Stick &stick, std::optional<int> last) const;

    /// Degrees between two bearings, the short way round.
    static double turn(double a, double b);

private:
    /// How far a target reaches before the next one's is nearer.
    double sideOf(int index) const;
};

/// A stick's radius read as rings: ring 0 from `PieGate::reach` out to the
/// first edge, and so on outwards.
struct RadialBands {
    /// Where each ring after the first starts.
    std::vector<double> edges;
    /// How far back over an edge the stick has to come to leave a ring.
    static constexpr double hold = 0.06;

    bool operator==(const RadialBands &) const = default;

    /// Three rings: as many as a moving thumb holds on a 360's stick.
    static const RadialBands &three();
    /// Two: inside and out.
    static const RadialBands &two();

    int count() const { return static_cast<int>(edges.size()) + 1; }

    int band(double radius, std::optional<int> last) const;
};

/// The right trigger as a strike: it sounds as it crosses a threshold,
/// with a level from how fast it was pulled, its depth afterwards is a
/// continuous control, and it lets go below a lower threshold.
class TriggerStrike {
public:
    struct Strike {
        double level;
        bool operator==(const Strike &) const = default;
    };
    struct Depth {
        double value;
        bool operator==(const Depth &) const = default;
    };
    struct Release {
        bool operator==(const Release &) const = default;
    };
    using Event = std::variant<Strike, Depth, Release>;

    /// Pulled past this, it sounds.
    static constexpr double threshold = 0.08;
    /// Let back past this, it lets go.
    static constexpr double letGo = 0.05;
    /// How long after crossing the threshold the level is read: a pull that
    /// gets further in that time is faster, and louder.
    static constexpr double window = 0.016;
    /// The softest strike, and how far a pull has to get in the window for
    /// the loudest.
    static constexpr double softest = 0.3;
    static constexpr double fullPull = 0.6;

    bool operator==(const TriggerStrike &) const = default;

    bool isHeld() const { return std::holds_alternative<Held>(phase_); }

    std::vector<Event> step(double value, double time);

private:
    struct Resting {
        bool operator==(const Resting &) const = default;
    };
    struct Crossing {
        double since;
        bool operator==(const Crossing &) const = default;
    };
    struct Held {
        bool operator==(const Held &) const = default;
    };
    using Phase = std::variant<Resting, Crossing, Held>;

    Phase phase_ = Resting{};

    std::vector<Event> strike(double value);
};

/// A trigger read as steps: 0 at rest, then 1, 2, … as it is pulled past
/// each edge.
struct TriggerSteps {
    std::vector<double> edges;
    static constexpr double hold = 0.05;

    bool operator==(const TriggerSteps &) const = default;

    /// Off and three steps.
    static const TriggerSteps &three();

    int count() const { return static_cast<int>(edges.size()) + 1; }

    int step(double value, int last) const;
};

/// A stick leaned and let go, read in time: a flick (out and back quickly)
/// keeps what it pointed at; a lean held is played while it is held.
class StickGesture {
public:
    /// The stick points at a target (each time it changes).
    struct Aim {
        int target;
        bool operator==(const Aim &) const = default;
    };
    /// Out and back within `flickTime`: keep `target`.
    struct Flick {
        int target;
        bool operator==(const Flick &) const = default;
    };
    /// Back to the middle after a lean held: let go of `target`.
    struct Lift {
        int target;
        bool operator==(const Lift &) const = default;
    };
    using Event = std::variant<Aim, Flick, Lift>;

    /// Out and back within this many seconds is a flick.
    static constexpr double flickTime = 0.2;

    bool operator==(const StickGesture &) const = default;

    std::optional<int> target() const { return target_; }
    bool isAiming() const { return target_.has_value(); }

    std::vector<Event> step(const Stick &stick, const PieGate &gate, double time);

    /// Forgets the lean, as if the stick were at rest: what it was on is let
    /// go of without being kept.
    void reset() { target_ = std::nullopt; }

private:
    std::optional<int> target_;
    double since_ = 0;
};

/// A button told apart by how long it is held: let go quickly with nothing
/// else done meanwhile, it was tapped.
class TapOrHold {
public:
    static constexpr double tapTime = 0.35;

    bool operator==(const TapOrHold &) const = default;

    /// The button went down at `time`.
    void press(double time);

    /// Something was done while it was held, so letting it go is no tap.
    void use() { wasUsed_ = true; }

    /// The button came up at `time`: whether that was a tap.
    bool release(double time);

private:
    std::optional<double> pressedAt_;
    bool wasUsed_ = false;
};

} // namespace perfecto::desk

#endif
