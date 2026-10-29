// The drums: a beat that loops under the chords, and drum pads played live.
//
// A beat is a pattern of sixteen steps, one bar of sixteenth notes, played at
// the desk's tempo. Each step is scheduled from the one before at the tempo
// now, so a change of tempo is heard from the next step with no jump, and
// every hit is worked out a little ahead (`DrumMachine::lookahead`) and
// stamped with the moment it sounds, so the shell can place it on its exact
// frame however unevenly the desk is stepped.
//
// It has no Swift original: the drums are the Godot desk's alone, played
// beside the desk (`Studio`) and not inside it, so the desk the parity test
// plays is unchanged.

#ifndef PERFECTO_DESK_DRUMS_HPP
#define PERFECTO_DESK_DRUMS_HPP

#include "perfecto/desk/gates.hpp"
#include "perfecto/desk/music.hpp"
#include "perfecto/desk/pad.hpp"

#include <array>
#include <optional>
#include <set>
#include <string>
#include <type_traits>
#include <utility>
#include <variant>
#include <vector>

namespace perfecto::desk {

/// A drum of the kit.
enum class Drum { kick, snare, closedHat, openHat, clap, lowTom, midTom, highTom };

inline constexpr std::array<Drum, 8> allDrums = {Drum::kick,  Drum::snare,  Drum::closedHat, Drum::openHat,
                                                 Drum::clap,  Drum::lowTom, Drum::midTom,    Drum::highTom};

/// "Kick", "Closed hat".
std::string name(Drum drum);

/// `drum`'s note on General MIDI's drum channel: 36 the kick.
int generalMidi(Drum drum);

/// The drums a hit of `drum` cuts short: a closed hat stops the open one, as
/// one pair of cymbals closing.
std::vector<Drum> chokes(Drum drum);

/// What the drums ask the shell to do. A time is on the frames' clock, and
/// may be a little ahead of the frame that asked.
class DrumEffect {
public:
    /// Strike `drum` at `time`, `level` hard (0 to 1).
    struct Hit {
        Drum drum;
        double level;
        double time;
        bool operator==(const Hit &) const = default;
    };
    /// Stop what `drum` is sounding, at `time`.
    struct Choke {
        Drum drum;
        double time;
        bool operator==(const Choke &) const = default;
    };

    using Value = std::variant<Hit, Choke>;

    template <class Alternative>
        requires std::is_constructible_v<Value, Alternative>
    DrumEffect(Alternative alternative) : value_(std::move(alternative)) {}

    static DrumEffect hit(Drum drum, double level, double time) { return Hit{drum, level, time}; }
    static DrumEffect choke(Drum drum, double time) { return Choke{drum, time}; }

    const Value &value() const { return value_; }

    bool operator==(const DrumEffect &) const = default;

private:
    Value value_;
};

/// `drum` struck at `time`, after what it cuts short.
std::vector<DrumEffect> strike(Drum drum, double level, double time);

/// A bar of sixteen steps: for each drum a line of them, one character a
/// step, '.' a rest, 'o' a ghost note, 'x' a hit and 'X' an accent.
struct DrumPattern {
    static constexpr int steps = 16;

    std::string name;
    std::vector<std::pair<Drum, std::string>> lines;
    /// How late the second sixteenth of each pair is, as a share of the
    /// eighth the pair makes: 0.5 is straight, ⅔ a triplet shuffle.
    double swing = 0.5;

    bool operator==(const DrumPattern &) const = default;

    /// The drums struck on `step` (taken round the bar), with their levels,
    /// in the order of `lines`.
    std::vector<std::pair<Drum, double>> at(int step) const;

    /// Whether anything is struck on `step`.
    bool isStruck(int step) const { return !at(step).empty(); }

    /// How far `step` is moved from its place on the grid by the swing, as
    /// a share of a sixteenth.
    double lateness(int step) const;
};

/// How hard a step's character strikes: none for a rest.
double level(char step);

/// The beats there are to choose from, in the order the d-pad goes through
/// them.
const std::vector<DrumPattern> &drumPatterns();

/// Seconds a sixteenth lasts at `tempo` beats a minute.
double sixteenth(double tempo);

/// A pattern played in time: started, stepped as time goes on, and stopped.
class DrumMachine {
public:
    /// How far ahead hits are given, in seconds: more than the longest
    /// frame the desk is stepped at, so no step is ever found late.
    static constexpr double lookahead = 0.05;

    bool operator==(const DrumMachine &) const = default;

    bool isPlaying() const { return isPlaying_; }
    /// The pattern played, by its place in `drumPatterns()`.
    int pattern() const { return pattern_; }
    const DrumPattern &played() const;

    /// The pattern `steps` along (`steps` < 0, back), round and round,
    /// taken up from the step the bar is at.
    void choose(int steps);

    /// Plays the pattern from its first step, at `time`: what is due up to
    /// the lookahead.
    std::vector<DrumEffect> start(double time, double tempo);

    void stop();

    /// What is due from the last given up to `time` and the lookahead, each
    /// step a sixteenth at `tempo` from the one before.
    std::vector<DrumEffect> advance(double time, double tempo);

    /// The step sounding at `time`, if the beat is playing.
    std::optional<int> step(double time) const;

private:
    bool isPlaying_ = false;
    int pattern_ = 0;
    /// The next step to give, counted from the start, and where it is on
    /// the grid (before the swing moves it).
    int next_ = 0;
    double nextTime_ = 0;
    /// The steps given most recently, and when each sounds, the latest last.
    std::vector<std::pair<int, double>> given_;
};

/// The drums as the hands play them, in Face Chords: L3 starts and stops the
/// beat, and RB held is the drum layer, where the face buttons are pads (A
/// kick, B snare, X closed hat, Y open hat; with LT held too, A low tom, B
/// clap, X mid tom, Y high tom), and the d-pad chooses the pattern (left and
/// right) and the tempo (up and down).
///
/// A button the drums take, they keep until it is let go: the desk is
/// handed the frame without it, so a pad never reaches the chords. While RB
/// is held the desk sees LT where it was when RB was pulled, so the toms'
/// LT leaves the chords' layer alone.
class Drums {
public:
    /// What one frame did: the drums' effects, the desk's (a felt tick), and
    /// the frame left for the desk.
    struct Step {
        std::vector<DrumEffect> drums;
        std::vector<DeskEffect> effects;
        GamepadFrame frame;
    };

    /// The tempo's step on the d-pad, in beats a minute.
    static constexpr double tempoStep = 4;

    bool operator==(const Drums &) const = default;

    const DrumMachine &machine() const { return machine_; }
    /// Whether RB holds the drum layer.
    bool isLayered() const { return claimed_.contains(PadButton::rb); }
    /// Whether LT is held in the drum layer: the toms and the clap.
    bool isShifted() const { return isShifted_; }

    /// The drum `button` strikes in the drum layer, with LT or without.
    static std::optional<Drum> pad(PadButton button, bool shifted);

    /// One frame. `reachable` says whether the hands can play the drums now
    /// (Face Chords, the menu closed); a tempo chosen changes `settings`.
    Step step(const PadInput &input, bool reachable, DeskSettings &settings);

    /// Stops the beat and lets go of what the drums hold.
    void stop();

    /// What the drums' controls do now, over `legend`.
    Legend legend(Legend legend, bool reachable) const;

private:
    DrumMachine machine_;
    /// The buttons the drums have taken, until each is let go.
    std::set<PadButton> claimed_;
    bool isShifted_ = false;
    /// LT as the desk was last given it.
    double deskTrigger_ = 0;
};

} // namespace perfecto::desk

#endif
