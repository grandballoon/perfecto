// What the arranger writes: chords placed in time, each with its own start
// and length in beats, and silence between them where nothing is placed. A
// value with its edits, so the arranger only decides when to make them.

#ifndef PERFECTO_DESK_ARRANGEMENT_HPP
#define PERFECTO_DESK_ARRANGEMENT_HPP

#include "perfecto/desk/music.hpp"

#include <array>
#include <optional>
#include <string>
#include <vector>

namespace perfecto::desk {

/// The grid times are snapped to, or none.
enum class BeatGrid : int { free, sixteenth, eighth, quarter, half };

inline constexpr std::array<BeatGrid, 5> allBeatGrids = {BeatGrid::free, BeatGrid::sixteenth, BeatGrid::eighth,
                                                         BeatGrid::quarter, BeatGrid::half};

/// Beats from one line of the grid to the next; none with no grid.
std::optional<double> step(BeatGrid grid);

/// "Free", "1/16".
std::string name(BeatGrid grid);

/// The shortest a chord can be: a line of the grid, or with none a
/// thirty-second note.
double shortest(BeatGrid grid);

/// How far the cursor moves at a step: a line of the grid, or with none
/// a sixteenth.
double move(BeatGrid grid);

/// `beats` on the nearest line of the grid.
double nearest(BeatGrid grid, double beats);

/// A length on the grid at least `beats` long (but for a hair under a
/// line, which a finger let go of a moment early means as that line),
/// and never shorter than `shortest`.
double length(BeatGrid grid, double beats);

/// A chord placed in time.
struct Placed {
    /// In beats from the start of the arrangement.
    double start;
    double length;
    DeskChord chord;

    bool operator==(const Placed &) const = default;
    auto operator<=>(const Placed &) const = default;

    double end() const { return start + length; }

    bool covers(double beats) const { return start <= beats && beats < end(); }
};

/// Chords placed in a loop of bars: never two at once, so one line plays them.
class Arrangement {
public:
    static constexpr int beatsPerBar = 4;
    static constexpr int bars = 4;
    static constexpr double length = static_cast<double>(beatsPerBar * bars);

    Arrangement() = default;
    explicit Arrangement(const std::vector<Placed> &chords);

    bool operator==(const Arrangement &) const = default;

    /// In order of their starts, none overlapping, all within the loop.
    const std::vector<Placed> &chords() const { return chords_; }

    bool isEmpty() const { return chords_.empty(); }

    /// Places `chord` from `start` for `length` beats, ending at the loop's
    /// end at the latest. What was there gives way: a chord that started
    /// before it ends where it starts, and one that starts under it is gone.
    void place(const DeskChord &chord, double start, double length);

    /// The chord sounding at `beats`, if any. (Swift's `chord(at:)`.)
    std::optional<Placed> chordAt(double beats) const;

    /// The chord a cursor at `beats` is on: the one sounding there, or else
    /// the one that has just ended there (where the cursor is left after
    /// writing it). (Swift's `chord(near:)`.)
    std::optional<Placed> chordNear(double beats) const;

    /// Takes away the chord sounding at `beats`, leaving silence.
    void clear(double beats);

    /// Makes the chord starting at `start` `length` beats long, as far as
    /// the next chord or the loop's end, and no shorter than `shortest`.
    /// Returns the length it now has.
    std::optional<double> resize(double start, double length, double shortest);

private:
    std::vector<Placed> chords_;
};

} // namespace perfecto::desk

#endif
