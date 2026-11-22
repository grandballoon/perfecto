// The grid the timeline's times are snapped to.

#ifndef PERFECTO_DESK_BEAT_GRID_HPP
#define PERFECTO_DESK_BEAT_GRID_HPP

#include <array>
#include <optional>
#include <string>

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

/// How far a cursor moves at a step: a line of the grid, or with none a
/// sixteenth.
double move(BeatGrid grid);

/// `beats` on the nearest line of the grid.
double nearest(BeatGrid grid, double beats);

/// A length on the grid at least `beats` long (but for a hair under a
/// line, which a finger let go of a moment early means as that line),
/// and never shorter than `shortest`.
double length(BeatGrid grid, double beats);

} // namespace perfecto::desk

#endif
