#include "perfecto/desk/arrangement.hpp"

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

Arrangement::Arrangement(const std::vector<Placed> &chords) {
    for (const Placed &chord : chords) place(chord.chord, chord.start, chord.length);
}

void Arrangement::place(const DeskChord &chord, double start, double length) {
    start = std::max(0.0, std::min(start, Arrangement::length));
    const double end = std::min(Arrangement::length, start + length);
    if (!(end > start)) return;
    std::vector<Placed> kept;
    for (const Placed &placed : chords_) {
        if (placed.start >= start && placed.start < end) continue;
        if (placed.start < start && placed.end() > start) {
            kept.push_back(Placed{placed.start, start - placed.start, placed.chord});
            continue;
        }
        kept.push_back(placed);
    }
    kept.push_back(Placed{start, end - start, chord});
    std::stable_sort(kept.begin(), kept.end(), [](const Placed &a, const Placed &b) { return a.start < b.start; });
    chords_ = std::move(kept);
}

std::optional<Placed> Arrangement::chordAt(double beats) const {
    for (const Placed &placed : chords_)
        if (placed.covers(beats)) return placed;
    return std::nullopt;
}

std::optional<Placed> Arrangement::chordNear(double beats) const {
    if (auto at = chordAt(beats)) return at;
    for (auto placed = chords_.rbegin(); placed != chords_.rend(); ++placed)
        if (std::fabs(placed->end() - beats) < 1e-9) return *placed;
    return std::nullopt;
}

void Arrangement::clear(double beats) {
    std::erase_if(chords_, [&](const Placed &placed) { return placed.covers(beats); });
}

std::optional<double> Arrangement::resize(double start, double length, double shortest) {
    const auto found =
        std::find_if(chords_.begin(), chords_.end(), [&](const Placed &placed) { return placed.start == start; });
    if (found == chords_.end()) return std::nullopt;
    const size_t index = static_cast<size_t>(found - chords_.begin());
    const double limit = index + 1 < chords_.size() ? chords_[index + 1].start : Arrangement::length;
    const double fitted = std::min(limit - start, std::max(shortest, length));
    chords_[index] = Placed{start, fitted, chords_[index].chord};
    return fitted;
}

} // namespace perfecto::desk

// DeskSettings, from Arrangement.swift.

namespace perfecto::desk {

void DeskSettings::moveGrid(int steps) {
    const int count = static_cast<int>(allBeatGrids.size());
    const int at = static_cast<int>(std::find(allBeatGrids.begin(), allBeatGrids.end(), grid) - allBeatGrids.begin());
    grid = allBeatGrids[static_cast<size_t>(((at + steps) % count + count) % count)];
}

} // namespace perfecto::desk
