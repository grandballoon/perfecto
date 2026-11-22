#include "perfecto/desk/beat_grid.hpp"

#include "perfecto/desk/music.hpp"

#include <algorithm>
#include <cmath>

namespace perfecto::desk {

std::optional<double> step(BeatGrid grid) {
    switch (grid) {
    case BeatGrid::free: return std::nullopt;
    case BeatGrid::sixteenth: return 0.25;
    case BeatGrid::eighth: return 0.5;
    case BeatGrid::quarter: return 1;
    case BeatGrid::half: return 2;
    }
    return std::nullopt;
}

std::string name(BeatGrid grid) {
    switch (grid) {
    case BeatGrid::free: return "Free";
    case BeatGrid::sixteenth: return "1/16";
    case BeatGrid::eighth: return "1/8";
    case BeatGrid::quarter: return "1/4";
    case BeatGrid::half: return "1/2";
    }
    return {};
}

double shortest(BeatGrid grid) { return step(grid).value_or(0.125); }

double move(BeatGrid grid) { return step(grid).value_or(0.25); }

double nearest(BeatGrid grid, double beats) {
    const auto line = step(grid);
    if (!line) return beats;
    return std::round(beats / *line) * *line;
}

double length(BeatGrid grid, double beats) {
    const auto line = step(grid);
    if (!line) return std::max(shortest(grid), beats);
    return std::max(*line, std::ceil((beats - *line * 0.15) / *line) * *line);
}

void DeskSettings::moveGrid(int steps) {
    const int count = static_cast<int>(allBeatGrids.size());
    const int at = static_cast<int>(std::find(allBeatGrids.begin(), allBeatGrids.end(), grid) - allBeatGrids.begin());
    grid = allBeatGrids[static_cast<size_t>(((at + steps) % count + count) % count)];
}

} // namespace perfecto::desk
